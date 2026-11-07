"""Bounded ISA read-before-write audit; no claim of RTL memory-reset coverage."""
import argparse
from dataclasses import asdict
import hashlib
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / 'tools'), str(ROOT / 'vendor/openTPU'), str(ROOT / 'tools/reproduction')]
from recorded import save, sha, utc


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args(); out = a.output.absolute(); out.mkdir(parents=True, exist_ok=False)
    os.environ.update(OPENBLAS_NUM_THREADS='2', OMP_NUM_THREADS='2', OTPU_IMAGE_CACHE='0', OTPU_PROG_CACHE='0', HF_HUB_OFFLINE='1')
    import numpy as np
    from opentpu import isa as I
    from opentpu.compiler import arg_words
    from opentpu.llm.qwen3 import Spec, IsaBackend
    from opentpu.isasim import Config
    from npu_context_programs import ColdContextImage
    from npu_kv_pool import PoolSpec
    profile = json.loads((ROOT / 'configs/npu-vu440-core.json').read_text())
    layout = json.loads((ROOT / 'configs/m1/layout.json').read_text())
    ref = json.loads((ROOT / 'assets/reference/summary.json').read_text())
    cfg = Config(**profile['architecture'])
    image = ColdContextImage(PoolSpec(**asdict(Spec.from_hf(ROOT / 'models/Qwen3-0.6B-hf')), pool_bytes=256<<20), cfg, 1024, lookup=True)
    image.create_cold('context', 256)
    programs = {name: image.compile_operation(name)[0] for name in ('build', 'decode')}
    for name, prog in programs.items():
        assert np.asarray(I.assemble(prog), dtype='<u4').tobytes() == (ROOT / f'assets/reference/{name}.bin').read_bytes()
    cold = ROOT / 'assets/data/dram-input.bin'
    assert sha(cold) == layout['cold_image_sha256']
    report = dict(status='running', started_at=utc(), cases=[], source_sha256=sha(Path(__file__)),
                  layout_sha256=sha(ROOT / 'configs/m1/layout.json'),
                  scope='ISA only; full dimensions/native arithmetic. Decode uses explicit sealed-prefix fixture. Not cold-build or RTL evidence.')
    save(out / 'summary.json', report)

    class Tracked:
        def __init__(self, data, owner, name):
            self.data = data; self.valid = np.zeros(data.shape, dtype=bool)
            self.owner = owner; self.name = name; self.reads = 0; self.early = 0; self.first = None

        def __getitem__(self, index):
            valid = self.valid[index]
            self.reads += int(np.size(valid))
            bad = int(np.count_nonzero(~valid))
            if bad:
                self.early += bad
                if self.first is None: self.first = dict(pc=self.owner.pc, index=str(index)[:250], count=bad)
            return self.data[index]

        def __setitem__(self, index, value):
            self.data[index] = value; self.valid[index] = True

    def poison_and_track(s):
        tracked = {}
        for name in ('tmem', 'act', 'ascale', 'adoff'):
            old = getattr(s, name)
            if isinstance(old, Tracked): old = old.data
            raw = old.copy()
            if name == 'tmem': raw[:] = np.uint32(0x7fc01234)
            elif name == 'ascale': raw[:] = np.nan
            else: raw[:] = 85
            wrapper = Tracked(raw, s, name); setattr(s, name, wrapper); tracked[name] = wrapper
        return tracked

    initial = np.fromfile(cold, dtype=np.uint8)
    backend = IsaBackend(cfg, [initial], adopt=True); s = backend.machine.slices[0]
    reference_prefix = np.fromfile(ROOT / 'assets/reference/reference-prefix.bin', dtype=np.uint8)
    regions = image.regions('context')
    def build_valid(data):
        pieces = []
        for r in regions:
            if r['kind'] != 'prefix': continue
            raw = data[r['address']-layout['kv_base']:r['address']-layout['kv_base']+r['bytes']]
            if r['field'] == 'vt': pieces.append(raw.reshape(128,256)[:, :4].copy().reshape(-1))
            else: pieces.append(raw[:4*(128 if r['field']=='k' else 4)])
        return np.concatenate(pieces)
    expected_build = build_valid(reference_prefix)
    try:
        for phase, count in [('build', 1), ('decode', 3)]:
            if phase == 'decode': s.dram[layout['kv_base']:layout['kv_base']+layout['prefix_bytes']] = reference_prefix
            tokens = [3555, 8429]
            for step in range(count):
                tracked = poison_and_track(s)
                backend.run([programs[phase]], args=arg_words(programs[phase].run_args, image.argument_values(step, tokens)))
                if phase == 'build':
                    actual = build_valid(s.dram[layout['kv_base']:layout['kv_base']+layout['prefix_bytes']])
                    expected = expected_build
                else:
                    actual = s.dram[layout['logits_address']:layout['logits_address']+layout['logits_bytes']]
                    expected = np.load(ROOT / f'assets/reference/native-logits-{step}.npy').view(np.uint8).reshape(-1)
                    tokens = ref['runs']['native']['steps'][step]['output_tokens']
                case = dict(phase=phase, step=step, equal=actual.tobytes()==expected.tobytes(),
                            sha256=hashlib.sha256(actual).hexdigest(),
                            state={name:dict(read_elements=t.reads, read_before_write=t.early, first=t.first) for name,t in tracked.items()})
                report['cases'].append(case); save(out / 'summary.json', report); print(json.dumps(case), flush=True)
                if not case['equal']:
                    actual.tofile(out / f'{phase}-{step}-first-difference.bin')
                    raise AssertionError('poisoned on-chip state changed numerical output')
        report['status'] = 'passed_isa_numeric_and_read_coverage' if all(t['read_before_write']==0 for c in report['cases'] for t in c['state'].values()) else 'numeric_equal_read_coverage_gaps'
    except BaseException as exc:
        report.update(status='failed', error=f'{type(exc).__name__}: {exc}')
        raise
    finally:
        report['finished_at'] = utc(); save(out / 'summary.json', report)


if __name__ == '__main__':
    main()

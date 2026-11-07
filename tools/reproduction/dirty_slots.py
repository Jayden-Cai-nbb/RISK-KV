"""Bounded full-model ISA experiments at explicit dirty-slot restart boundaries.

These are numerical microexperiments, not RTL service support for slot reuse.
Decode starts from a declared sealed-prefix fixture, never a cold-build claim.
"""
import argparse
from dataclasses import asdict
import gc
import hashlib
import json
import os
from pathlib import Path
import sys
import time

from recorded import ROOT, save, sha, utc


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--input', type=Path, default=ROOT/'assets/data/dram-input.bin')
    p.add_argument('--reference', type=Path, default=ROOT/'assets/reference')
    p.add_argument('--cancel-prefix', type=Path, required=True)
    p.add_argument('--phase', choices=('all','build','decode'), default='all')
    p.add_argument('--case', action='append', choices=('clean','finite_old','nan_old','nan_clear_scales','nan_clear_full','cancel_physical_restart'))
    a = p.parse_args()
    out = a.output.resolve(); out.mkdir(parents=True, exist_ok=False)
    os.environ.update(OPENBLAS_NUM_THREADS='2', OMP_NUM_THREADS='2', OTPU_IMAGE_CACHE='0', OTPU_PROG_CACHE='0', HF_HUB_OFFLINE='1')
    sys.path[:0] = [str(ROOT/'tools'), str(ROOT/'vendor/openTPU')]
    import numpy as np
    from opentpu import isa as I
    from opentpu.compiler import arg_words
    from opentpu.llm.qwen3 import Spec, IsaBackend
    from opentpu.isasim import Config
    from npu_context_programs import ColdContextImage
    from npu_core_profile import load
    from npu_kv_pool import PoolSpec
    profile, _ = load(ROOT/'configs/npu-vu440-core.json')
    cfg = Config(**profile['architecture'])
    spec = Spec.from_hf(ROOT/'models/Qwen3-0.6B-hf')
    image = ColdContextImage(PoolSpec(**asdict(spec), pool_bytes=256<<20), cfg, 1024, lookup=True)
    ctx = image.create_cold('context', 256)
    programs = {k: image.compile_operation(k)[0] for k in ('build', 'decode')}
    for k, program in programs.items():
        assert np.asarray(I.assemble(program), dtype='<u4').tobytes() == (a.reference/f'{k}.bin').read_bytes()
    ref = json.loads((a.reference/'summary.json').read_text())
    workload = json.loads((a.reference/'workload.json').read_text())
    assert sha(a.input) == ref['input_sha256']
    prefix = np.fromfile(a.reference/'reference-prefix.bin', dtype=np.uint8)
    canceled = np.fromfile(a.cancel_prefix, dtype=np.uint8)
    assert prefix.size == canceled.size == ref['prefix_bytes']
    regions = image.regions('context')
    report = dict(status='running', started_at=utc(), model='Qwen3-0.6B, all 28 layers, frozen native arithmetic',
        scope='ISA boundary microexperiments; sealed-prefix fixture is explicitly preloaded for decode only; no RTL reuse claim',
        inputs={str(x):sha(x) for x in (a.input,a.reference/'reference-prefix.bin',a.cancel_prefix,Path(__file__))}, cases=[],
        selection=dict(phase=a.phase,cases=a.case),
        cleaning_bytes={kind:{'full':sum(r['bytes'] for r in regions if r['kind']==kind),
            'scales':sum(r['bytes'] for r in regions if r['kind']==kind and r['field'] in ('ks','vs'))} for kind in ('prefix','private')})
    save(out/'summary.json', report)

    def valid_build(mem):
        pieces=[]
        for r in regions:
            if r['kind']!='prefix': continue
            raw=mem[r['address']:r['address']+r['bytes']]
            if r['field']=='k': pieces.append(raw[:4*128])
            elif r['field']=='vt': pieces.append(raw.reshape(128,256)[:,:4].copy().reshape(-1))
            else: pieces.append(raw[:4*4])
        return np.concatenate(pieces)

    clean_build=None
    for phase in ('build','decode'):
        if a.phase!='all' and a.phase!=phase:continue
        cases=[('clean','none','none'),('finite_old','finite','none'),('nan_old','nan','none'),
               ('nan_clear_scales','nan','scales'),('nan_clear_full','nan','full')]
        if phase=='build': cases += [('cancel_physical_restart','cancel','none')]
        if a.case:
            cases=[x for x in cases if x[0] in a.case]
            if phase=='build' and cases and not any(x[0]=='clean' for x in cases):cases.insert(0,('clean','none','none'))
        for name, poison, cleaning in cases:
            began=time.perf_counter(); initial=np.fromfile(a.input,dtype=np.uint8)
            backend=IsaBackend(cfg,[initial],adopt=True); mem=backend.machine.slices[0].dram
            kind='prefix' if phase=='build' else 'private'
            if phase=='decode': mem[ctx['start']:ctx['start']+prefix.size]=prefix
            affected=[r for r in regions if r['kind']==kind]
            if poison in ('finite','nan'):
                for r in affected:
                    raw=mem[r['address']:r['address']+r['bytes']]
                    if r['field'] in ('ks','vs'): raw.view('<f4')[:]=1.25 if poison=='finite' else np.nan
                    else: raw[:]=85
            elif poison=='cancel': mem[ctx['start']:ctx['start']+canceled.size]=canceled
            cleaned=0
            for r in affected:
                if cleaning=='full' or (cleaning=='scales' and r['field'] in ('ks','vs')):
                    mem[r['address']:r['address']+r['bytes']]=0; cleaned+=r['bytes']
            before_prefix=hashlib.sha256(mem[ctx['start']:ctx['start']+prefix.size]).hexdigest()
            immutable=lambda: hashlib.sha256(b''.join(mem[x:x+n].tobytes() for x,n in image.immutable_regions())).hexdigest()
            before_immutable=immutable()
            result=dict(phase=phase,name=name,poison=poison,cleaning=cleaning,cleaned_bytes=cleaned)
            if phase=='build':
                backend.run([programs['build']],args=arg_words(programs['build'].run_args,image.argument_values(0)))
                actual=valid_build(mem)
                if name=='clean': clean_build=actual.copy()
                result.update(valid_written_bytes=len(actual),equal_clean=actual.tobytes()==clean_build.tobytes(),
                    mismatch_bytes=int(np.count_nonzero(actual!=clean_build)),sha256=hashlib.sha256(actual).hexdigest())
                actual.tofile(out/f'{phase}-{name}-written.bin')
            else:
                tokens=workload['seed_tokens'].copy();steps=[]
                for step in range(3):
                    backend.run([programs['decode']],args=arg_words(programs['decode'].run_args,image.argument_values(step,tokens)))
                    logits=backend.read(0,image.io['logits'],2*151936*4).view('<f4').reshape(2,151936)
                    expected=np.load(a.reference/f'native-logits-{step}.npy')
                    nxt=backend.read(0,ref['result_address'],8).view('<f4')
                    np.save(out/f'{phase}-{name}-logits-{step}.npy',logits)
                    steps.append(dict(step=step,finite_logits=int(np.count_nonzero(np.isfinite(logits))),total_logits=logits.size,
                        equal_reference=logits.tobytes()==expected.tobytes(),tokens=nxt.tolist()))
                    # Preserve the frozen inputs for each step to isolate numeric
                    # contamination from a changed token trajectory.
                    tokens=ref['runs']['native']['steps'][step]['output_tokens']
                result.update(steps=steps,equal_clean=all(x['equal_reference'] for x in steps),
                    prefix_unchanged=before_prefix==hashlib.sha256(mem[ctx['start']:ctx['start']+prefix.size]).hexdigest())
                assert result['prefix_unchanged']
            result.update(immutable_unchanged=before_immutable==immutable(),wall_seconds=time.perf_counter()-began)
            assert result['immutable_unchanged']
            if name in ('clean','nan_clear_full'): assert result['equal_clean'], result
            report['cases'].append(result); save(out/'summary.json',report); print(json.dumps(result),flush=True)
            del backend,mem,initial;gc.collect()
    if not report['cases']:raise ValueError('No requested cases apply to selected phase')
    report.update(status='completed',finished_at=utc(),limits=[
        'Only frozen geometry and specified finite/NaN patterns; no arbitrary-bit-pattern or security sanitization proof.',
        'Scale-only clearing is an experiment, not authorization to remove used_slot/ever_bound.',
        'Decode uses the same expected input tokens for each step; divergent output tokens are reported, not fed back.',
        'Canceled-prefix restart tests actual physical bytes after the frozen cancellation run, with no logical commit.'])
    save(out/'summary.json',report)


if __name__=='__main__': main()

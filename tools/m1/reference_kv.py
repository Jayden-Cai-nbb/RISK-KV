"""Independent contiguous-KV tail snapshots, using an explicit proven prefix fixture."""
import argparse
import gc
import hashlib
import json
import os
from pathlib import Path
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / 'tools'), str(ROOT / 'vendor/openTPU'), str(ROOT / 'tools/reproduction')]
from recorded import save, sha, utc


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--prefix-fixture', type=Path, required=True)
    a = p.parse_args(); out = a.output.absolute(); out.mkdir(parents=True, exist_ok=False)
    os.environ.update(HF_HUB_OFFLINE='1', OTPU_IMAGE_CACHE='0', OTPU_PROG_CACHE='0', OPENBLAS_NUM_THREADS='2', OMP_NUM_THREADS='2')
    import numpy as np
    import torch
    from transformers import AutoTokenizer
    from opentpu.compiler import Affine
    from opentpu.llm.qwen3 import Spec, Engine, load_weights
    from opentpu.isasim import Config
    from npu_model_contract import WEIGHT_SHA256
    torch.set_num_threads(2)
    model = ROOT / 'models/Qwen3-0.6B-hf'
    assert sha(model / 'model.safetensors') == WEIGHT_SHA256
    profile = json.loads((ROOT / 'configs/npu-vu440-core.json').read_text())
    workload = json.loads((ROOT / 'assets/reference/workload.json').read_text())
    cfg = Config(**profile['architecture']); spec = Spec.from_hf(model)
    tokenizer = AutoTokenizer.from_pretrained(str(model), local_files_only=True)
    pair2 = [tokenizer.encode(word, add_special_tokens=False) for word in (' How', ' When')]
    assert all(len(x) == 1 for x in pair2)
    seeds = [workload['seed_tokens'], [x[0] for x in pair2]]
    report = dict(status='running', started_at=utc(), seed_pairs=seeds, pairs=[], source_sha256=sha(Path(__file__)),
                  model_sha256=WEIGHT_SHA256, profile_sha256=sha(ROOT / 'configs/npu-vu440-core.json'),
                  workload_sha256=sha(ROOT / 'assets/reference/workload.json'),
                  prefix_fixture_sha256=sha(a.prefix_fixture),
                  scope='complete model native ISA with independent contiguous KV layout and explicit preloaded prefix; not a cold-build experiment; common upstream arithmetic/compiler dependency; no QA quality claim')
    save(out / 'summary.json', report)
    try:
        weights = load_weights(model)
        engine = Engine(spec, weights, cap=1024, cfg=cfg, batch=2, rows=4, backend='isa', resident=True,
                        embed_host=False, wformat='int8', head_format='int8', pipeline=False,
                        prog_cache=False, prompt_runs=False, tile_runs=False)
        del weights; gc.collect()
        begin = time.monotonic()
        fixture = np.fromfile(a.prefix_fixture, dtype=np.uint8)
        assert fixture.tobytes() == (ROOT / 'assets/reference/reference-prefix.bin').read_bytes()
        offset = 0
        for li in range(28):
            kv = engine.image.descriptors(0).layer(li).kvs[0]
            for h in range(8):
                for field, length in [('k',32768), ('ks',1024), ('vt',32768), ('vs',1024)]:
                    engine.backend.write(0, Affine.of(kv.heads[h][field]).static(), fixture[offset:offset+length])
                    offset += length
        def segment(slot, token_offset=0):
            parts = []
            for li in range(28):
                kv = engine.image.descriptors(0).layer(li).kvs[slot]
                for h in range(8):
                    for field, length in [('k',32768), ('ks',1024), ('vt',32768), ('vs',1024)]:
                        base = Affine.of(kv.heads[h][field]).static() + (token_offset // 256) * length
                        parts.append(engine.backend.read(0, base, length))
            return np.concatenate(parts)
        prefix = lambda slot: segment(slot)
        raw = prefix(0)
        assert raw.tobytes() == (ROOT / 'assets/reference/reference-prefix.bin').read_bytes()
        raw.tofile(out / 'reference-prefix.bin')
        offset = 0
        for li in range(28):
            kv = engine.image.descriptors(0).layer(li).kvs[1]
            for h in range(8):
                for field, length in [('k',32768), ('ks',1024), ('vt',32768), ('vs',1024)]:
                    engine.backend.write(0, Affine.of(kv.heads[h][field]).static(), raw[offset:offset+length]); offset += length
        for pair, seed in enumerate(seeds):
            # 原生布局每字段按 256-token 块连续排布；清除前缀后的 768-token 区。
            # 此清理是独立参考构造，不是候选 RTL 的清理成本。
            for li in range(28):
                for slot in range(2):
                    kv = engine.image.descriptors(0).layer(li).kvs[slot]
                    for h in range(8):
                        for field, bytes_per_token in [('k',128), ('ks',4), ('vt',128), ('vs',4)]:
                            base = Affine.of(kv.heads[h][field]).static()
                            engine.backend.write(0, base + 256*bytes_per_token, np.zeros(768*bytes_per_token, dtype=np.uint8))
            assert prefix(0).tobytes() == raw.tobytes() == prefix(1).tobytes()
            tokens = seed.copy(); rows = []
            for step in range(3):
                logits = engine.run_rows([(0,256+step), (1,256+step)], tokens, [0,1])
                assert np.isfinite(logits).all()
                nxt = np.argmax(logits, axis=1).tolist()
                name = f'pair-{pair}-logits-{step}.npy'; np.save(out / name, logits)
                if pair == 0:
                    assert logits.tobytes() == np.load(ROOT / f'assets/reference/native-logits-{step}.npy').tobytes()
                assert prefix(0).tobytes() == raw.tobytes() == prefix(1).tobytes()
                rows.append(dict(step=step, input_tokens=tokens, output_tokens=nxt,
                                 logits_file=name, logits_sha256=sha(out / name)))
                tokens = nxt; print(json.dumps(dict(pair=pair, step=step, tokens=tokens)), flush=True)
            context = np.concatenate([raw, segment(0, 256), segment(1, 256)])
            context_name = f'pair-{pair}-context.bin'; context.tofile(out / context_name)
            if pair == 0:
                frozen = json.loads((ROOT / 'assets/reference/summary.json').read_text())
                h = hashlib.sha256(context)
                h.update(bytes(frozen['pool_bytes'] - len(context)))
                assert h.hexdigest() == frozen['runs']['candidate']['final_pool_sha256']
            report['pairs'].append(dict(pair=pair, seeds=seed, steps=rows,
                                       context_file=context_name, context_sha256=sha(out / context_name)))
            save(out / 'summary.json', report)
        report.update(status='passed_independent_native_reference', prefix_sha256=sha(out / 'reference-prefix.bin'),
                      wall_seconds=time.monotonic()-begin, finished_at=utc())
    except BaseException as exc:
        report.update(status='failed', error=f'{type(exc).__name__}: {exc}')
        raise
    finally:
        save(out / 'summary.json', report)


if __name__ == '__main__':
    main()

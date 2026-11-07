"""Build/run the full-dimensional M1 RTL, preserving every failed run."""
import argparse
import hashlib
import json
import re
import shutil
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/reproduction'))
from recorded import run, save, sha, utc
from lint import source_paths


def sources():
    return source_paths() + [ROOT / f for f in (
        'tb/npu_dpi/otpu_dram_dpi.sv', 'tb/npu_dpi/dram_store.cpp',
        'tb/npu_dpi/observe_logits.cpp', 'tb/npu_dpi/observe_context.cpp', 'tb/m1/full_model/progress.cpp', 'tb/m1/full_model/tb_top.sv')]


def compare(out, data, reference, short):
    import numpy as np
    layout = json.loads((ROOT / 'configs/m1/layout.json').read_text())
    frozen = json.loads((ROOT / 'assets/reference/summary.json').read_text())
    actual = np.fromfile(data / 'prefix-final.bin', dtype=np.uint8)
    gold = np.fromfile(ROOT / 'assets/reference/reference-prefix.bin', dtype=np.uint8)
    memory = np.memmap(data / 'dram_out_0.bin', dtype=np.uint8, mode='r')
    assert memory.size == layout['logical_bytes']
    h = hashlib.sha256()
    for addr, size in layout['immutable_regions']: h.update(memory[addr:addr+size])
    assert h.hexdigest() == frozen['immutable_sha256'], 'immutable bytes changed'
    if short:
        expected = np.zeros_like(gold); cursor = 0
        for _ in range(28*8):
            for field, length in [('k',32768), ('ks',1024), ('vt',32768), ('vs',1024)]:
                if field == 'vt':
                    expected[cursor:cursor+length].reshape(128,256)[:, :4] = gold[cursor:cursor+length].reshape(128,256)[:, :4]
                else:
                    valid = 4*(128 if field == 'k' else 4)
                    expected[cursor:cursor+valid] = gold[cursor:cursor+valid]
                cursor += length
        assert actual.tobytes() == expected.tobytes(), 'four-token prefix mismatch'
        assert not np.any(memory[layout['kv_base']+layout['prefix_bytes']:layout['kv_base']+layout['pool_bytes']])
        return dict(status='passed_four_token_full_model', immutable_equal=True, prefix_sha256=sha(data / 'prefix-final.bin'), valid_kv_bytes=236544)
    ref = json.loads((reference / 'summary.json').read_text())
    assert ref['status'] == 'passed_independent_native_reference' and len(ref['pairs']) == 2
    assert actual.tobytes() == gold.tobytes()
    rows = []
    for pair, group in enumerate(ref['pairs']):
        assert (data / f'prefix-bind-{pair}.bin').read_bytes() == gold.tobytes()
        tail = np.fromfile(data / f'private-bind-{pair}.bin', dtype=np.uint8)
        assert tail.size == 2*layout['prefix_bytes'] and not np.any(tail)
        assert sha(data / f'context-pair-{pair}.bin') == group['context_sha256'], 'full context differs from native KV'
        for step, expected in enumerate(group['steps']):
            got = np.fromfile(data / f'observed-logits-{3*pair+step+1}.bin', dtype='<f4').reshape(2,151936)
            gold_logits = np.load(reference / expected['logits_file'], allow_pickle=False)
            if got.tobytes() != gold_logits.tobytes():
                diff = np.flatnonzero(got.view(np.uint32).reshape(-1) != gold_logits.view(np.uint32).reshape(-1))
                save(out / 'first-difference.json', dict(pair=pair, step=step, element=int(diff[0]), differing_elements=len(diff)))
                raise AssertionError('all-logits comparison failed')
            assert np.isfinite(got).all()
            rows.append(dict(pair=pair, step=step, raw_sha256=hashlib.sha256(got).hexdigest(), tokens=np.argmax(got,axis=1).tolist()))
    assert not np.any(memory[layout['kv_base']+layout['object_bytes']:layout['kv_base']+layout['pool_bytes']])
    # 工作区只读模板和可信程序也必须保持原样。
    cold = np.memmap(ROOT / 'assets/data/dram-input.bin', dtype=np.uint8, mode='r')
    offset = 0
    for addr, size in layout['scratch_restore']:
        start = layout['scratch_template_base'] + offset
        assert memory[start:start+size].tobytes() == cold[addr:addr+size].tobytes(); offset += size
    for program in layout['programs'].values():
        start, size = program['address'], program['bytes']
        assert memory[start:start+size].tobytes() == cold[start:start+size].tobytes()
    return dict(status='passed_continuous_full_model', immutable_equal=True, all_kv_equal=True,
                prefix_sha256=sha(data / 'prefix-final.bin'), steps=rows)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--compile-only', action='store_true')
    p.add_argument('--build', type=Path)
    p.add_argument('--verilator-prefix', type=Path)
    p.add_argument('--firmware', type=Path)
    p.add_argument('--reference', type=Path)
    p.add_argument('--short', action='store_true')
    a = p.parse_args(); out = a.output.absolute(); out.mkdir(parents=True, exist_ok=False)
    paths = sources()
    hashes = {str(path.relative_to(ROOT)): sha(path) for path in paths}
    report = dict(status='running', started_at=utc(), short=a.short, board_execution=False, source_sha256=hashes)
    save(out / 'summary.json', report)
    try:
        if a.compile_only:
            if not a.verilator_prefix: p.error('compile-only requires --verilator-prefix')
            for src in paths:
                dst = out / 'sources' / src.relative_to(ROOT); dst.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(src, dst)
            cmd = [sys.executable, ROOT / 'tools/reproduction/with_verilator.py', '--prefix', a.verilator_prefix,
                   '--', 'verilator', '--binary', '--timing', '-j', '2', '-Wno-fatal', '-Wno-WIDTHEXPAND', '-Wno-WIDTHTRUNC',
                   '-Wno-UNUSEDSIGNAL', '-Wno-UNUSEDPARAM', '-O3', '--x-assign', '0', '--x-initial', '0',
                   '--threads', '4', '--threads-dpi', 'none', '--top-module', 'tb_top', '--Mdir', out / 'obj', *paths]
            assert run(out / 'compile', cmd, timeout=1800, inputs=paths) == 0, 'compile failed'
            report.update(status='compiled_not_simulated', executable=str(out / 'obj/Vtb_top'), executable_sha256=sha(out / 'obj/Vtb_top'))
        else:
            if not a.build or not a.firmware or (not a.short and not a.reference): p.error('simulation requires --build, --firmware and full run --reference')
            build = json.loads((a.build / 'summary.json').read_text())
            assert build['status'] == 'compiled_not_simulated' and build['source_sha256'] == hashes, 'build inputs stale'
            exe = Path(build['executable']); assert sha(exe) == build['executable_sha256']
            fw = json.loads((a.firmware / 'manifest.json').read_text())
            assert fw['mode'] == 'autorun' and fw['build_tasks'] == (1 if a.short else 64)
            assert sha(a.firmware / 'firmware.hex') == fw['hex_sha256']
            for name, h in fw['inputs'].items(): assert sha(ROOT / name) == h, f'firmware inputs stale: {name}'
            if not a.short:
                ref = json.loads((a.reference / 'summary.json').read_text())
                assert fw['second_seeds'] == ref['seed_pairs'][1]
            layout = json.loads((ROOT / 'configs/m1/layout.json').read_text())
            cold = ROOT / 'assets/data/dram-input.bin'; assert sha(cold) == layout['cold_image_sha256']
            import numpy as np
            data = out / 'runtime'; data.mkdir()
            mem = np.memmap(cold, dtype='<u4', mode='r')
            with (data / 'dram_0.bin').open('wb') as dst:
                for at in range(0, len(mem), 1<<20): dst.write(mem[at:at+(1<<20)].astype('>u4').tobytes())
                dst.seek(layout['scratch_template_base'])
                for addr, size in layout['scratch_restore']: dst.write(mem[addr//4:(addr+size)//4].astype('>u4').tobytes())
            del mem
            (data / 'prog_0.hex').write_text('00000000\n'*32768)
            for name in ('build','decode'):
                words = np.fromfile(ROOT / f'assets/reference/{name}.bin', dtype='<u4')
                (data / f'expected_{name}.hex').write_text(''.join(f'{int(w):08x}\n' for w in words))
            report.update(phase='simulate', firmware_sha256=fw['hex_sha256'], executable_sha256=build['executable_sha256'],
                          cold_image_sha256=layout['cold_image_sha256'], timeout_seconds=21600)
            save(out / 'summary.json', report)
            stopped = threading.Event()
            def progress():
                while not stopped.wait(5):
                    live = data / 'live-progress.json'
                    if live.exists():
                        save(out / 'progress.json', json.loads(live.read_text()))
                        continue
                    log = out / 'simulation/stdout.log'
                    if not log.exists(): continue
                    text = log.read_text(errors='replace')
                    commits = re.findall(r'M1_BUILD_COMMIT tokens=(\d+)', text)
                    events = [line for line in text.splitlines() if line.startswith('M1_')]
                    save(out / 'progress.json', dict(status='running', built_tokens=int(commits[-1]) if commits else 0,
                                                   last_event=events[-1] if events else 'started'))
            monitor = threading.Thread(target=progress, daemon=True); monitor.start()
            try:
                cmd = [exe, f'+dir={data}', f'+firmware={a.firmware.absolute()/"firmware.hex"}',
                       f'+short={int(a.short)}', '+max_cycles=500000000']
                assert run(out / 'simulation', cmd, timeout=21600, inputs=paths+[a.firmware / 'firmware.hex']) == 0, 'RTL simulation failed'
            finally:
                stopped.set(); monitor.join(timeout=6)
            log = (out / 'simulation/stdout.log').read_text()
            match = re.search(r'M1_FULL_RESULT (.*)', log); assert match, 'no final self-check marker'
            report['counters'] = {k:int(v) for k,v in (field.split('=') for field in match[1].split())}
            report.update(compare(out, data, a.reference, a.short))
            if not a.short:
                receipts = [[int(x),int(y)] for x,y in re.findall(r'M1_COMPLETE op=6 seq=[0-9a-f]+ token0=(\d+) token1=(\d+)', log)]
                expected_tokens = [step['output_tokens'] for group in ref['pairs'] for step in group['steps']]
                assert receipts == expected_tokens, 'CQ integer tokens differ from independent reference'
                report['cq_tokens_equal'] = True
    except BaseException as exc:
        report.update(status='failed', error=f'{type(exc).__name__}: {exc}')
        raise
    finally:
        report['finished_at'] = utc(); save(out / 'summary.json', report)
        save(out / 'progress.json', dict(status=report['status'], phase=report.get('phase'), error=report.get('error')))
        print(json.dumps({k:v for k,v in report.items() if k != 'source_sha256'}), flush=True)


if __name__ == '__main__':
    main()

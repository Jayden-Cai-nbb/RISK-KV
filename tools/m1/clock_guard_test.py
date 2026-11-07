"""Verify platform clock-fault capture with the actual bridge and retirement monitor."""
import argparse
import json
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/reproduction'))
import recorded


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--verilator-prefix', type=Path, required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    sources = [ROOT / p for p in (
        'platform/m1/rkv_m1_clock_guard.v',
        'platform/m1/rkv_m1_native_axi.sv',
        'rtl/m1/rkv_m1_native_retirement.sv',
        'tb/m1/tb_rkv_m1_clock_guard.sv',
    )]
    inputs = sources + [Path(__file__).resolve(), ROOT / 'tools/reproduction/with_verilator.py']
    for source in inputs:
        target = out / 'sources' / source.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    recorded.save(out / 'inputs.json', {str(p.relative_to(ROOT)): recorded.sha(p) for p in inputs})
    result = dict(status='running', scope='guard + actual bridge and retirement; injected lock/ready states; no MIG/AXI CDC/board')
    recorded.save(out / 'summary.json', result)
    try:
        command = [sys.executable, ROOT / 'tools/reproduction/with_verilator.py', '--prefix',
                   args.verilator_prefix.resolve(), '--', 'verilator', '--binary', '--timing', '--assert',
                   '-j', '2', '-Wno-fatal', '--Mdir', out / 'obj', '--top-module', 'tb_rkv_m1_clock_guard', *sources]
        assert recorded.run(out / 'compile', command, 300, inputs) == 0
        assert recorded.run(out / 'run', [out / 'obj/Vtb_rkv_m1_clock_guard'], 60, inputs) == 0
        assert 'M1_CLOCK_GUARD_PASS' in (out / 'run/stdout.log').read_text()
        result['status'] = 'passed'
    except Exception as exc:
        result.update(status='failed', error=str(exc))
        raise
    finally:
        recorded.save(out / 'summary.json', result)
        print(json.dumps(result))


if __name__ == '__main__':
    main()

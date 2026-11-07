"""Verify the independent native-to-AXI platform candidate, not a board acceptance."""
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
        'platform/m1/rkv_m1_native_axi.sv',
        'rtl/m1/rkv_m1_native_retirement.sv',
        'tb/m1/tb_rkv_m1_native_axi.sv',
    )]
    inputs = sources + [Path(__file__).resolve(), ROOT / 'tools/reproduction/with_verilator.py']
    for p in inputs:
        target = out / 'sources' / p.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(p, target)
    recorded.save(out / 'inputs.json', {str(p.relative_to(ROOT)): recorded.sha(p) for p in inputs})
    result = dict(status='running', scope='bridge + existing retirement supervisor; behavioral AXI memory; no MIG/CDC/board')
    recorded.save(out / 'summary.json', result)
    try:
        cmd = [sys.executable, ROOT / 'tools/reproduction/with_verilator.py', '--prefix',
               args.verilator_prefix.resolve(), '--', 'verilator', '--binary', '--timing', '--assert',
               '-j', '2', '-Wno-fatal', '--Mdir', out / 'obj', '--top-module', 'tb_rkv_m1_native_axi', *sources]
        assert recorded.run(out / 'compile', cmd, timeout=300, inputs=inputs) == 0
        for seed in (1, 17, 12345):
            run_dir = out / f'seed-{seed}'
            assert recorded.run(run_dir, [out / 'obj/Vtb_rkv_m1_native_axi', f'+seed={seed}'],
                                timeout=60, inputs=inputs) == 0
            assert 'M1_NATIVE_AXI_PASS' in (run_dir / 'stdout.log').read_text()
        result['status'] = 'passed'
    except Exception as exc:
        result.update(status='failed', error=str(exc))
        raise
    finally:
        recorded.save(out / 'summary.json', result)
        print(json.dumps(result))


if __name__ == '__main__':
    main()

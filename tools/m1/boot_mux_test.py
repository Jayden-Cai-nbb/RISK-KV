"""Verify the bounded single-configuration DDR ownership transfer; no physical DDR."""
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
        'platform/m1/prodigy/rkv_m1_boot_mux.v',
        'tb/m1/tb_rkv_m1_boot_mux.sv',
    )]
    inputs = sources + [Path(__file__).resolve(), ROOT / 'tools/reproduction/with_verilator.py']
    for p in inputs:
        target = out / 'sources' / p.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(p, target)
    recorded.save(out / 'inputs.json', {str(p.relative_to(ROOT)): recorded.sha(p) for p in inputs})
    result = dict(status='running', scope='boot ownership, in-flight rejection, sticky failure and unbroken service retirement; no physical DDR')
    recorded.save(out / 'summary.json', result)
    try:
        cmd = [sys.executable, ROOT / 'tools/reproduction/with_verilator.py', '--prefix',
               args.verilator_prefix.resolve(), '--', 'verilator', '--binary', '--timing', '--assert',
               '-j', '2', '-Wno-fatal', '--Mdir', out / 'obj', '--top-module', 'tb_rkv_m1_boot_mux', *sources]
        assert recorded.run(out / 'compile', cmd, timeout=300, inputs=inputs) == 0
        for scenario in range(10):
            run_dir = out / f'case-{scenario}'
            assert recorded.run(run_dir, [out / 'obj/Vtb_rkv_m1_boot_mux', f'+case={scenario}'],
                                timeout=30, inputs=inputs) == 0
            assert 'BOOT_MUX_PASS' in (run_dir / 'stdout.log').read_text()
        result['status'] = 'passed'
    except Exception as exc:
        result.update(status='failed', error=str(exc))
        raise
    finally:
        recorded.save(out / 'summary.json', result)
        print(json.dumps(result))


if __name__ == '__main__':
    main()

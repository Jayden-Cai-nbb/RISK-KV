"""Run an explicit M1 quick-test target with immutable per-run evidence."""
import argparse
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/reproduction'))
from recorded import run, save, sha


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('target', choices=['cleaner', 'control', 'executor', 'native_retirement', 'memory_arbiter', 'native_adapter', 'cpu', 'mailbox'])
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--verilator-prefix', type=Path)
    parser.add_argument('--firmware', type=Path)
    args = parser.parse_args()
    out = args.output.absolute()
    out.mkdir(parents=True, exist_ok=False)
    dut_name = {'native_adapter':'memory_arbiter', 'mailbox':'cpu'}.get(args.target, args.target)
    names = ['rtl/m1/rkv_m1_layout_pkg.sv', f'rtl/m1/rkv_m1_{dut_name}.sv',
             f'tb/m1/tb_rkv_m1_{args.target}.sv', 'configs/m1/layout.json',
             'tools/m1/quick.py', 'tools/m1/generate_layout.py', 'docs/m1/contract.md']
    paths = [ROOT / name for name in names]
    rtl_paths = paths[:3]
    if args.target in ('cpu','mailbox'):
        if not args.firmware:
            parser.error('cpu requires --firmware')
        deps = [ROOT / f'rtl/m1/rkv_m1_{n}.sv' for n in ('control', 'executor', 'cleaner', 'service', 'mmio')]
        deps.append(ROOT / 'vendor/picorv32/picorv32.v')
        rtl_paths = paths[:1] + deps + paths[1:3]
        paths += deps + [args.firmware.absolute() / 'firmware.hex', args.firmware.absolute() / 'manifest.json']
    if args.target == 'native_adapter':
        deps = [ROOT / f'rtl/m1/rkv_m1_{n}.sv' for n in ('native_retirement', 'native_memory')]
        deps.append(ROOT / 'vendor/openTPU/rtl/mem/otpu_native_dram.sv')
        deps.append(ROOT / 'vendor/openTPU/rtl/tech/generic/otpu_tech_ram.sv')
        rtl_paths = paths[:1] + deps + paths[1:3]
        paths += deps
    for path in paths:
        dst = out / 'sources' / path.relative_to(ROOT)
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, dst)
    save(out / 'inputs.json', {str(p.relative_to(ROOT)): sha(p) for p in paths})
    result = dict(status='running', target=args.target, scope='standalone protocol simulation; not full NPU or board')
    save(out / 'summary.json', result)
    prefix = []
    if args.verilator_prefix:
        prefix = [sys.executable, ROOT / 'tools/reproduction/with_verilator.py', '--prefix', args.verilator_prefix, '--']
    try:
        assert run(out / 'layout', [sys.executable, ROOT / 'tools/m1/generate_layout.py', '--check'], inputs=paths) == 0, 'layout check failed'
        assert run(out / 'compile', prefix + ['verilator', '--binary', '--timing', '-j', '2', '-Wno-fatal',
            '--Mdir', out / 'obj', '--top-module', f'tb_rkv_m1_{args.target}', *rtl_paths], inputs=paths, timeout=300) == 0, 'compile failed; see compile/stdout.log'
        runtime = [] if not args.firmware else [f'+firmware={args.firmware.absolute() / "firmware.hex"}']
        assert run(out / 'simulation', [out / 'obj' / f'Vtb_rkv_m1_{args.target}', *runtime], inputs=paths, timeout=180) == 0, 'simulation failed; see simulation/stdout.log'
        logs = (out / 'simulation/stdout.log').read_text()
        assert f'M1_{args.target.upper()}_PASS' in logs
        result['status'] = 'passed'
    except Exception as exc:
        result.update(status='failed', error=f'{type(exc).__name__}: {exc}')
        raise
    finally:
        save(out / 'summary.json', result)
        print(json.dumps(result))


if __name__ == '__main__':
    main()

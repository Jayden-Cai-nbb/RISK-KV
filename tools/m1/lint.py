"""Record portable M1 system elaboration; this does not establish FPGA timing."""
import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / 'vendor/openTPU'), str(ROOT / 'tools/reproduction')]
from recorded import run, save, sha


def source_paths():
    from opentpu import rtlsim
    # 可综合计算路径；保留原生 adapter，排除上游仿真顶层与行为 DRAM。
    vendor = [(rtlsim.RTL / name).resolve() for name in rtlsim.RTL_SOURCES
              if name not in ('top/otpu_top.sv', 'mem/otpu_dram.sv') and not name.startswith('../')]
    own = [ROOT / 'rtl/m1/rkv_m1_layout_pkg.sv']
    own += sorted(p for p in (ROOT / 'rtl/m1').glob('*.sv') if p.name != 'rkv_m1_layout_pkg.sv')
    return vendor + own + [ROOT / 'vendor/picorv32/picorv32.v']


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--verilator-prefix', type=Path, required=True)
    a = p.parse_args(); out = a.output.absolute(); out.mkdir(parents=True, exist_ok=False)
    paths = source_paths()
    (ROOT / 'rtl/m1/files.f').write_text('\n'.join(str(path.relative_to(ROOT)) for path in paths) + '\n')
    save(out / 'inputs.json', {str(path.relative_to(ROOT)): sha(path) for path in paths})
    cmd = [sys.executable, ROOT / 'tools/reproduction/with_verilator.py', '--prefix', a.verilator_prefix,
           '--', 'verilator', '--lint-only', '-Wno-fatal', '--top-module', 'rkv_m1_native_system', *paths]
    rc = run(out / 'command', cmd, timeout=300, inputs=paths)
    save(out / 'summary.json', dict(status='passed_elaboration' if rc == 0 else 'failed',
                                   scope='portable native system; no DDR/host IP, no CDC/STA/board claim'))
    raise SystemExit(rc)


if __name__ == '__main__':
    main()

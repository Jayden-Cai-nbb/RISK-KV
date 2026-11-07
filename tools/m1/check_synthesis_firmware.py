"""Exercise the synthesis RAM initialization branch with the real mailbox CPU test."""
import argparse
import json
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/reproduction'))
from recorded import run, save, sha


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--firmware', type=Path, required=True)
    p.add_argument('--verilator-prefix', type=Path, required=True)
    a = p.parse_args()
    out = a.output.absolute(); out.mkdir(parents=True, exist_ok=False)
    source = ROOT / 'tb/m1/tb_rkv_m1_mailbox.sv'
    firmware = out / 'firmware.hex'
    shutil.copy2(a.firmware, firmware)
    body = source.read_text()
    assert body.count('rkv_m1_cpu dut (') == 1
    body = body.replace('rkv_m1_cpu dut (', 'rkv_m1_cpu #(.FIRMWARE(' + json.dumps(str(firmware)) + ')) dut (')
    tb = out / 'tb_rkv_m1_mailbox.sv'; tb.write_text(body)
    paths = [ROOT / 'rtl/m1/rkv_m1_layout_pkg.sv']
    paths += [ROOT / f'rtl/m1/rkv_m1_{name}.sv' for name in ('control', 'executor', 'cleaner', 'service', 'mmio', 'cpu')]
    paths += [ROOT / 'vendor/picorv32/picorv32.v']
    for path in paths:
        dst = out / 'sources' / path.relative_to(ROOT)
        dst.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(path, dst)
    inputs = paths + [source, firmware, tb, Path(__file__)]
    save(out / 'inputs.json', {str(path): sha(path) for path in inputs})
    report = dict(status='running', scope='real PicoRV32 mailbox protocol using SYNTHESIS RAM init; not post-synthesis netlist or board simulation')
    try:
        command = [sys.executable, ROOT / 'tools/reproduction/with_verilator.py', '--prefix', a.verilator_prefix.absolute(), '--',
                   'verilator', '--binary', '--timing', '-DSYNTHESIS', '-j', '2', '-Wno-fatal',
                   '--Mdir', out / 'obj', '--top-module', 'tb_rkv_m1_mailbox', *paths, tb]
        assert run(out / 'compile', command, inputs=inputs, timeout=300) == 0
        assert run(out / 'simulation', [out / 'obj/Vtb_rkv_m1_mailbox'], inputs=inputs, timeout=180) == 0
        assert 'M1_MAILBOX_PASS' in (out / 'simulation/stdout.log').read_text()
        report['status'] = 'passed'
    except BaseException as exc:
        report.update(status='failed', error=f'{type(exc).__name__}: {exc}')
        raise
    finally:
        save(out / 'summary.json', report)
        print(json.dumps(report))


if __name__ == '__main__':
    main()

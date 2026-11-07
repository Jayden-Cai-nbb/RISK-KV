"""Exercise AXI control with actual PicoRV32/mailbox firmware and a protocol NPU fixture."""
import argparse
import json
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/reproduction'))
import recorded

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--verilator-prefix', type=Path, required=True)
    p.add_argument('--firmware', type=Path, required=True)
    a = p.parse_args()
    out = a.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    firmware = a.firmware.resolve()
    names = ['rtl/m1/rkv_m1_layout_pkg.sv']
    names += [f'rtl/m1/rkv_m1_{n}.sv' for n in ('control','executor','cleaner','service','mmio','cpu')]
    names += ['vendor/picorv32/picorv32.v', 'platform/m1/rkv_m1_host_map.v', 'platform/m1/rkv_m1_host_control.v', 'tb/m1/tb_rkv_m1_host_control.sv']
    sources = [ROOT/n for n in names]
    inputs = sources + [ROOT/'configs/m1/host-control.json', ROOT/'configs/m1/layout.json', ROOT/'tools/m1/generate_host_control.py', Path(__file__), ROOT/'tools/reproduction/with_verilator.py', firmware/'firmware.hex', firmware/'manifest.json']
    for source in inputs:
        dst = out/'sources'/source.relative_to(ROOT)
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, dst)
    recorded.save(out/'inputs.json', {str(x.relative_to(ROOT)):recorded.sha(x) for x in inputs})
    result = dict(status='running', scope='AXI64 control, actual CPU/mailbox firmware and service; protocol NPU/cleaner memory fixture; no actual DDR gate/root SmartConnect/JTAG/NPU/board', runs=[], hardware_actions=[])
    try:
        assert recorded.run(out/'map-check', [sys.executable, ROOT/'tools/m1/generate_host_control.py', '--check'], 60, inputs) == 0
        command = [sys.executable, ROOT/'tools/reproduction/with_verilator.py', '--prefix', a.verilator_prefix.resolve(), '--', 'verilator', '--binary', '--timing', '--assert', '-j', '2', '-Wno-fatal', '--Mdir', out/'obj', '--top-module', 'tb_rkv_m1_host_control', *sources]
        assert recorded.run(out/'compile', command, 300, inputs) == 0
        for seed in (1,17,12345):
            stage=out/f'seed-{seed}'
            assert recorded.run(stage, [out/'obj/Vtb_rkv_m1_host_control', f'+firmware={firmware/"firmware.hex"}', f'+seed={seed}', f'+verilator+seed+{seed}'], 180, inputs) == 0
            log=(stage/'stdout.log').read_text()
            assert 'M1_HOST_CONTROL_PASS ' in log
            result['runs'].append(dict(seed=seed, marker=next(x for x in log.splitlines() if x.startswith('M1_HOST_CONTROL_PASS '))))
        result['status']='passed'
    except Exception as e:
        result.update(status='failed', error=repr(e))
        raise
    finally:
        recorded.save(out/'summary.json',result)
        print(json.dumps(result))

if __name__=='__main__':
    main()

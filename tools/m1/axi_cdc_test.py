"""Run the real Vivado 2022.2 AXI Clock Converter with the native bridge and reset guard."""
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
    parser.add_argument('--fixture', type=Path, required=True)
    parser.add_argument('--vivado', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    fixture = args.fixture.resolve()
    bin_dir = args.vivado.resolve().parent
    install = bin_dir.parent
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    fixture_ip = fixture / 'project/axi_cdc_fixture.gen/sources_1/ip/rkv_m1_axi_clock_converter/sim/rkv_m1_axi_clock_converter.v'
    source_names = (
        'platform/m1/rkv_m1_clock_guard.v',
        'platform/m1/rkv_m1_axi_reset.v',
        'platform/m1/rkv_m1_native_axi.sv',
        'platform/m1/rkv_m1_native_axi_cdc.v',
        'rtl/m1/rkv_m1_native_retirement.sv',
        'tb/m1/tb_rkv_m1_native_axi_cdc.sv',
    )
    originals = [ROOT / p for p in source_names]
    snapshots = []
    for source in originals:
        target = out / 'sources' / source.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        snapshots.append(target)
    for source, name in ((fixture_ip, 'ip.v'), (install / 'data/verilog/src/glbl.v', 'glbl.v')):
        target = out / 'sources' / name
        shutil.copy2(source, target)
        originals.append(source)
        snapshots.append(target)
    shutil.copy2(__file__, out / 'axi_cdc_test.py')
    shutil.copy2(fixture / 'cdc-properties.txt', out / 'cdc-properties.txt')
    shutil.copy2(fixture / 'create_axi_cdc.tcl', out / 'create_axi_cdc.tcl')
    recorded.save(out / 'inputs.json', {str(p): recorded.sha(p) for p in originals + [Path(__file__).resolve()]})
    # 使用export_simulation所列出的固定预编译库，不改安装或解密厂商源码。
    libraries = ['axi_infrastructure_v1_1_0', 'fifo_generator_v13_2_7',
                 'axi_clock_converter_v2_1_26', 'xil_defaultlib', 'unisims_ver', 'unimacro_ver', 'secureip', 'xpm']
    libmap = install / 'data/xsim/xsim.ini'
    original_map = libmap.read_text()
    lines = [line for line in original_map.splitlines() if not line.startswith('xil_defaultlib=')]
    (out / 'xsim.ini').write_text('\n'.join(lines + ['xil_defaultlib=xsim.dir/xil_defaultlib']) + '\n')
    recorded.save(out / 'vendor-libraries.json', dict(libraries=libraries, installed_map_sha256=recorded.sha(libmap),
                  generated_wrapper_sha256=recorded.sha(fixture_ip), note='Installed Vivado precompiled libraries; build must match 2022.2/3671981'))
    report = dict(status='running', scope='Real vendor AXI CDC + clock/reset guard + native bridge + retirement; behavioral UI memory, no MIG/PHY/board', runs=[])
    recorded.save(out / 'summary.json', report)
    recorded.ROOT = out
    inputs = snapshots + [out / 'axi_cdc_test.py', out / 'xsim.ini', out / 'vendor-libraries.json']
    try:
        assert recorded.run(out / 'version', [args.vivado.resolve(), '-version'], 60, inputs) == 0
        version = (out / 'version/stdout.log').read_text()
        assert 'v2022.2' in version and '3671981' in version, 'Unverified Vivado version'
        assert recorded.run(out / 'compile', [bin_dir / 'xvlog', '--sv', '--work', 'xil_defaultlib', *snapshots], 300, inputs) == 0
        command = [bin_dir / 'xelab', '--debug', 'typical', '--relax', '--mt', '2']
        for library in libraries:
            command.extend(['-L', library])
        command.extend(['xil_defaultlib.tb_rkv_m1_native_axi_cdc', 'xil_defaultlib.glbl', '-s', 'native_axi_cdc_sim'])
        assert recorded.run(out / 'elaborate', command, 300, inputs) == 0
        for seed, phase in ((1, 3333), (17, 1101), (12345, 1979)):
            stage = out / f'seed-{seed}'
            # 每次仿真有自己的日志、工作目录；只读共享已编译快照。
            stage.mkdir(exist_ok=False)
            (stage / 'xsim.dir').symlink_to('../xsim.dir', target_is_directory=True)
            shutil.copy2(out / 'xsim.ini', stage / 'xsim.ini')
            recorded.ROOT = stage
            command = [bin_dir / 'xsim', 'native_axi_cdc_sim', '-runall',
                       '-testplusarg', f'seed={seed}', '-testplusarg', f'ui_phase_ps={phase}']
            assert recorded.run(stage / 'record', command, 120, inputs) == 0
            log = (stage / 'record/stdout.log').read_text()
            assert f'M1_NATIVE_AXI_CDC_PASS seed={seed} ' in log
            report['runs'].append(dict(seed=seed, core_hz=50000000, ui_half_period_ps=2604, ui_phase_ps=phase, status='passed'))
            recorded.save(out / 'summary.json', report)
        report['status'] = 'passed'
    except Exception as exc:
        report.update(status='failed', error=str(exc))
        raise
    finally:
        recorded.save(out / 'summary.json', report)
        print(json.dumps(report), flush=True)


if __name__ == '__main__':
    main()

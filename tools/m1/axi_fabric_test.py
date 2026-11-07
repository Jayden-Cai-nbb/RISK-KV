"""Exercise actual SmartConnect RTL and AXI CDC with host/native retirement."""
import argparse
import json
from pathlib import Path
import re
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/reproduction'))
import recorded


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixture', type=Path, required=True)
    parser.add_argument('--cdc-fixture', type=Path, required=True)
    parser.add_argument('--vivado', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--source-root', type=Path, default=ROOT)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    fixture = args.fixture.resolve()
    export = fixture / 'simulation-export/rkv_m1_axi_fabric/xsim'
    install = args.vivado.resolve().parent.parent
    bin_dir = install / 'bin'
    originals = []
    snapshots = []

    def copy(source, target):
        source = source.resolve()
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        originals.append(source)
        snapshots.append(target)
        return target

    # Preserve the generated compiler list; no vendor model edits or TLM substitution.
    for name in ('vlog.prj', 'vhdl.prj'):
        source = export / name
        copy(source, out / ('original-' + name))
        text = source.read_text()
        replacements = {}
        for quoted in re.findall(r'"([^"]+)"', text):
            path = (export / quoted).resolve()
            if path.is_file():
                target = out / 'vendor' / path.relative_to(fixture) if path.is_relative_to(fixture) else out / 'vendor-install' / path.relative_to(install)
                copy(path, target)
            else:
                assert path.is_dir(), path
                target = out / 'vendor' / path.relative_to(fixture) if path.is_relative_to(fixture) else out / 'vendor-install' / path.relative_to(install)
                for child in sorted(path.rglob('*')):
                    if child.is_file():
                        copy(child, target / child.relative_to(path))
            replacements[quoted] = str(target)
        for before, after in replacements.items():
            text = text.replace('"' + before + '"', '"' + after + '"')
        (out / name).write_text(text)
        snapshots.append(out / name)
    shell = copy(export / 'rkv_m1_axi_fabric.sh', out / 'vendor-export.sh').read_text()
    libraries = list(dict.fromkeys(re.findall(r'-L (\w+)', shell)))
    libraries += ['fifo_generator_v13_2_7', 'axi_clock_converter_v2_1_26']
    sources = [line for line in (args.source_root / 'platform/m1/shared_axi.f').read_text().splitlines() if line]
    sources.append('tb/m1/tb_rkv_m1_shared_axi.sv')
    rtl = [copy(args.source_root / name, out / 'sources' / name) for name in sources]
    cdc = args.cdc_fixture.resolve() / 'project/axi_cdc_fixture.gen/sources_1/ip/rkv_m1_axi_clock_converter/sim/rkv_m1_axi_clock_converter.v'
    rtl.append(copy(cdc, out / 'sources/cdc.v'))
    copy(Path(__file__), out / 'axi_fabric_test.py')
    for name in ('interface-HOST.txt', 'interface-NATIVE.txt', 'interface-MEMORY.txt', 'jtag-properties.txt', 'fabric-properties.txt'):
        copy(fixture / name, out / name)
    libmap = install / 'data/xsim/xsim.ini'
    lines = [line for line in libmap.read_text().splitlines() if not line.startswith('xil_defaultlib=')]
    (out / 'xsim.ini').write_text('\n'.join(lines + ['xil_defaultlib=xsim.dir/xil_defaultlib']) + '\n')
    snapshots.append(out / 'xsim.ini')
    recorded.save(out / 'inputs.json', {str(p): recorded.sha(p) for p in originals})
    recorded.save(out / 'vendor-libraries.json', dict(libraries=libraries, installed_map_sha256=recorded.sha(libmap),
        model='Generated RTL hierarchy + fixed Vivado 2022.2 precompiled libraries; no C++/TLM compiled'))
    report = dict(status='running', hardware_actions=[], scope='Actual SmartConnect RTL + CDC + host/native bridges; behavioral UI memory; no JTAG transactions, MIG, native cache or full NPU', runs=[])
    recorded.save(out / 'summary.json', report)
    recorded.ROOT = out
    try:
        assert recorded.run(out / 'version', [args.vivado.resolve(), '-version'], 60, snapshots) == 0
        version = (out / 'version/stdout.log').read_text()
        assert 'v2022.2' in version and '3671981' in version
        assert recorded.run(out / 'compile-vendor-v', [bin_dir / 'xvlog', '--relax', '-L', 'uvm', '-L', 'axi_vip_v1_1_13', '-L', 'smartconnect_v1_0', '-L', 'xilinx_vip', '-prj', out / 'vlog.prj'], 300, snapshots) == 0
        assert recorded.run(out / 'compile-vendor-h', [bin_dir / 'xvhdl', '--relax', '-prj', out / 'vhdl.prj'], 300, snapshots) == 0
        assert recorded.run(out / 'compile-project', [bin_dir / 'xvlog', '--sv', '--relax', '--work', 'xil_defaultlib', *rtl], 300, snapshots) == 0
        command = [bin_dir / 'xelab', '--debug', 'typical', '--relax', '--mt', '2']
        for library in libraries:
            command.extend(['-L', library])
        command.extend(['xil_defaultlib.tb_rkv_m1_shared_axi', 'xil_defaultlib.glbl', '-s', 'shared_axi_sim'])
        assert recorded.run(out / 'elaborate', command, 600, snapshots) == 0
        for seed, phase in ((1, 3333), (17, 1101), (12345, 1979)):
            stage = out / f'seed-{seed}'
            stage.mkdir(exist_ok=False)
            (stage / 'xsim.dir').symlink_to('../xsim.dir', target_is_directory=True)
            shutil.copy2(out / 'xsim.ini', stage / 'xsim.ini')
            recorded.ROOT = stage
            command = [bin_dir / 'xsim', 'shared_axi_sim', '-runall', '-testplusarg', f'seed={seed}', '-testplusarg', f'ui_phase_ps={phase}']
            assert recorded.run(stage / 'record', command, 180, snapshots) == 0
            log = (stage / 'record/stdout.log').read_text()
            assert f'M1_SHARED_AXI_PASS seed={seed} ' in log
            marker = next(line for line in log.splitlines() if line.startswith('M1_SHARED_AXI_PASS '))
            metrics = {key: int(value) for key, value in re.findall(r'(\w+)=(\d+)', marker)}
            report['runs'].append(dict(seed=seed, ui_phase_ps=phase, status='passed', metrics=metrics))
            recorded.save(out / 'summary.json', report)
        assert sum(run['metrics']['blocked_next_w'] for run in report['runs']) > 0, 'No next-burst W backpressure coverage across seeds'
        report['status'] = 'passed'
    except Exception as exc:
        report.update(status='failed', error=repr(exc))
        raise
    finally:
        recorded.save(out / 'summary.json', report)
        print(json.dumps(report), flush=True)


if __name__ == '__main__':
    main()

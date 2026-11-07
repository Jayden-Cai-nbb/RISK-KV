"""Exercise complete digital platform with actual native cache/retirement and a protocol compute fixture."""
import argparse
import difflib
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
    parser.add_argument('--router-fixture', type=Path, required=True)
    parser.add_argument('--cdc-fixture', type=Path, required=True)
    parser.add_argument('--vivado', type=Path, required=True)
    parser.add_argument('--firmware', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--source-root', type=Path, default=ROOT)
    parser.add_argument('--scenario', choices=('admission', 'lifecycle', 'clean-success'), default='admission')
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

    # 两套BD按各自根目录快照，保留原编译清单/层级；不修改厂商RTL。
    libraries = []
    for label, fixture_dir, design in [('fabric', fixture, 'rkv_m1_axi_fabric'), ('router', args.router_fixture.resolve(), 'rkv_m1_host_router')]:
        export_dir = fixture_dir / ('simulation-export/' + design + '/xsim')
        for name in ('vlog.prj', 'vhdl.prj'):
            source = export_dir / name
            text = copy(source, out / (label + '-original-' + name)).read_text()
            replacements = {}
            for quoted in re.findall(r'"([^"]+)"', text):
                path = (export_dir / quoted).resolve()
                target = out / label / path.relative_to(fixture_dir) if path.is_relative_to(fixture_dir) else out / 'vendor-install' / path.relative_to(install)
                if path.is_file():
                    if not target.exists(): copy(path, target)
                else:
                    assert path.is_dir(), path
                    for child in sorted(path.rglob('*')):
                        if child.is_file() and not (target / child.relative_to(path)).exists(): copy(child, target / child.relative_to(path))
                replacements[quoted] = str(target)
            for before, after in replacements.items(): text = text.replace('"' + before + '"', '"' + after + '"')
            (out / (label + '-' + name)).write_text(text)
            snapshots.append(out / (label + '-' + name))
        shell = copy(export_dir / (design + '.sh'), out / (label + '-export.sh')).read_text()
        libraries.extend(re.findall(r'-L (\w+)', shell))
    libraries = list(dict.fromkeys(libraries + ['fifo_generator_v13_2_7', 'axi_clock_converter_v2_1_26']))
    sources = [line for line in (args.source_root / 'platform/m1/platform.f').read_text().splitlines() if line and not line.startswith('#')]
    # Exclude actual compute closure only for this explicitly scoped protocol test.
    sources = [name for name in sources if not name.startswith('vendor/openTPU/') or name in ('vendor/openTPU/rtl/mem/otpu_native_dram.sv', 'vendor/openTPU/rtl/tech/generic/otpu_tech_ram.sv')]
    sources.remove('rtl/m1/rkv_m1_compute.sv')
    lifecycle = args.scenario == 'lifecycle'
    clean_success = args.scenario == 'clean-success'
    tb_name = 'tb_rkv_m1_platform_lifecycle' if lifecycle else 'tb_rkv_m1_platform'
    compute_fixture = 'platform_lifecycle_compute_fixture' if lifecycle else 'platform_compute_fixture'
    marker_name = 'M1_PLATFORM_LIFECYCLE_PASS' if lifecycle else 'M1_PLATFORM_PASS'
    if clean_success:
        tb_name = 'tb_rkv_m1_platform_clean'
        compute_fixture = 'platform_clean_compute_fixture'
        marker_name = 'M1_PLATFORM_CLEAN_PASS'
    sources += [f'tb/m1/{compute_fixture}.sv', f'tb/m1/{tb_name}.sv']
    copy(args.source_root / 'platform/m1/platform.f', out / 'platform.f')
    rtl = [copy(args.source_root / name, out / 'sources' / name) for name in sources]
    cdc = args.cdc_fixture.resolve() / 'project/axi_cdc_fixture.gen/sources_1/ip/rkv_m1_axi_clock_converter/sim/rkv_m1_axi_clock_converter.v'
    rtl.append(copy(cdc, out / 'sources/cdc.v'))
    copy(Path(__file__), out / 'platform_test.py')
    if clean_success:
        copy(ROOT / 'tools/m1/platform_clean_check.py', out / 'platform_clean_check.py')
        copy(args.source_root / 'configs/m1/layout.json', out / 'layout.json')
    firmware = copy(args.firmware.resolve() / 'firmware.hex', out / 'sources/firmware.hex')
    copy(args.firmware.resolve() / 'manifest.json', out / 'sources/firmware-manifest.json')
    for name in ('interface-HOST.txt', 'interface-NATIVE.txt', 'interface-MEMORY.txt', 'jtag-properties.txt', 'fabric-properties.txt'):
        copy(fixture / name, out / name)
    libmap = install / 'data/xsim/xsim.ini'
    lines = [line for line in libmap.read_text().splitlines() if not line.startswith('xil_defaultlib=')]
    (out / 'xsim.ini').write_text('\n'.join(lines + ['xil_defaultlib=xsim.dir/xil_defaultlib']) + '\n')
    snapshots.append(out / 'xsim.ini')
    recorded.save(out / 'inputs.json', {str(p): recorded.sha(p) for p in originals})
    recorded.save(out / 'vendor-libraries.json', dict(libraries=libraries, installed_map_sha256=recorded.sha(libmap),
        model='Generated RTL hierarchy + fixed Vivado 2022.2 precompiled libraries; no C++/TLM compiled'))
    report = dict(status='running', hardware_actions=[], scope='Actual platform RTL, CPU/mailbox/arbiter, native cache/prefetch/retirement, two SmartConnects and CDC; explicit protocol compute, behavioral DDR UI, no real NPU/JTAG/MIG/board', runs=[])
    report['scenario'] = args.scenario
    if lifecycle:
        report['limits'] = 'Actual layout retained; cleaning intentionally faulted after initial blocks. No full-clean completion or model numeric validation.'
    if clean_success:
        report['limits'] = 'One fixed seed, full actual cleanup layout, complete physical dumps. Protocol compute and synthetic dirty/template bytes; no model numerical or DDR board validation.'
    recorded.save(out / 'summary.json', report)
    recorded.ROOT = out
    # XSim拒绝上游仿真checker的initial+always_ff双过程初始化。
    # 只在编译副本将该checker改为相同事件的always；保留全部断言和硬件过程。
    native_source = out / 'sources/vendor/openTPU/rtl/mem/otpu_native_dram.sv'
    original = native_source.read_text()
    before = "  always_ff @(posedge clk) begin\n    if (rst) rst_seen <= 1'b1;"
    after = "  always @(posedge clk) begin\n    if (rst) rst_seen <= 1'b1;"
    assert original.count(before) == 1, 'Upstream checker changed; review compatibility export'
    exported = original.replace(before, after)
    compatibility = out / 'simulation-compat'
    compatibility.mkdir()
    native_compiled = compatibility / native_source.name
    native_compiled.write_text(exported)
    rtl[rtl.index(native_source)] = native_compiled
    patch = compatibility / 'checker-only.patch'
    patch.write_text(''.join(difflib.unified_diff(original.splitlines(True), exported.splitlines(True),
                                               fromfile='original/otpu_native_dram.sv', tofile='compiled/otpu_native_dram.sv')))
    recorded.save(compatibility / 'manifest.json', dict(original_sha256=recorded.sha(native_source),
                  exported_sha256=recorded.sha(native_compiled), change='One simulation-only checker always_ff -> always; same posedge, body and assertions. Production source untouched.'))
    snapshots += [native_compiled, patch, compatibility / 'manifest.json']
    # 同一前端也拒绝read-ahead RAM的q/wq/by仿真初值与always_ff共存。
    # 只导出该模块的三个过程关键字；事件、RAM读写、旁路和初值逐字保持。
    ram_source = out / 'sources/vendor/openTPU/rtl/tech/generic/otpu_tech_ram.sv'
    ram_original = ram_source.read_text()
    start = ram_original.index('module otpu_ram_1r1w_ra #(')
    end = ram_original.index('endmodule', start)
    block = ram_original[start:end]
    assert block.count('always_ff @') == 3, 'Read-ahead RAM changed; review compatibility export'
    ram_exported = ram_original[:start] + block.replace('always_ff @', 'always @') + ram_original[end:]
    ram_compiled = compatibility / ram_source.name
    ram_compiled.write_text(ram_exported)
    rtl[rtl.index(ram_source)] = ram_compiled
    ram_patch = compatibility / 'ram-process-keywords.patch'
    ram_patch.write_text(''.join(difflib.unified_diff(ram_original.splitlines(True), ram_exported.splitlines(True),
                                                   fromfile='original/otpu_tech_ram.sv', tofile='compiled/otpu_tech_ram.sv')))
    recorded.save(compatibility / 'ram-manifest.json', dict(original_sha256=recorded.sha(ram_source),
                  exported_sha256=recorded.sha(ram_compiled), change='Only three always_ff -> always keywords inside otpu_ram_1r1w_ra. Same events, bodies, initialization and bypass; production source untouched.'))
    snapshots += [ram_compiled, ram_patch, compatibility / 'ram-manifest.json']
    report['simulation_export'] = 'simulation-compat/: four process keywords only; all events, assignments, initial values and upstream assertions retained'
    try:
        assert recorded.run(out / 'version', [args.vivado.resolve(), '-version'], 60, snapshots) == 0
        version = (out / 'version/stdout.log').read_text()
        assert 'v2022.2' in version and '3671981' in version
        for label in ('fabric', 'router'):
            assert recorded.run(out / ('compile-' + label + '-v'), [bin_dir / 'xvlog', '--relax', '-L', 'uvm', '-L', 'axi_vip_v1_1_13', '-L', 'smartconnect_v1_0', '-L', 'xilinx_vip', '-prj', out / (label + '-vlog.prj')], 300, snapshots) == 0
            assert recorded.run(out / ('compile-' + label + '-h'), [bin_dir / 'xvhdl', '--relax', '-prj', out / (label + '-vhdl.prj')], 300, snapshots) == 0
        assert recorded.run(out / 'compile-project', [bin_dir / 'xvlog', '--sv', '--relax', '--work', 'xil_defaultlib', *rtl], 300, snapshots) == 0
        command = [bin_dir / 'xelab', '--debug', 'typical', '--relax', '--mt', '2']
        for library in libraries:
            command.extend(['-L', library])
        command.extend([f'xil_defaultlib.{tb_name}', 'xil_defaultlib.glbl', '-s', 'platform_sim'])
        assert recorded.run(out / 'elaborate', command, 600, snapshots) == 0
        cases = ((1, 3333),) if clean_success else ((1, 3333), (17, 1101), (12345, 1979))
        for seed, phase in cases:
            stage = out / f'seed-{seed}'
            stage.mkdir(exist_ok=False)
            (stage / 'xsim.dir').symlink_to('../xsim.dir', target_is_directory=True)
            shutil.copy2(out / 'xsim.ini', stage / 'xsim.ini')
            recorded.ROOT = stage
            command = [bin_dir / 'xsim', 'platform_sim', '-runall', '-testplusarg', f'seed={seed}', '-testplusarg', f'ui_phase_ps={phase}', '-testplusarg', f'firmware={firmware}']
            # 新完整清理的实测吞吐需要项目完整集成的7h预算；既有快测/每笔超时不改。
            assert recorded.run(stage / 'record', command, 25200 if clean_success else 180, snapshots) == 0
            log = (stage / 'record/stdout.log').read_text()
            assert f'{marker_name} seed={seed} ' in log
            marker = next(line for line in log.splitlines() if line.startswith(marker_name + ' '))
            metrics = {key: int(value) for key, value in re.findall(r'(\w+)=(\d+)', marker)}
            if clean_success:
                dumps = list(stage.glob('*.bin'))
                assert len(dumps) == 7, dumps
                assert recorded.run(stage / 'compare', [sys.executable, out / 'platform_clean_check.py',
                    '--layout', out / 'layout.json', '--directory', stage], 180, snapshots + dumps) == 0
                report['complete_dump_check'] = json.loads((stage / 'numeric-check.json').read_text())
            report['runs'].append(dict(seed=seed, ui_phase_ps=phase, status='passed', metrics=metrics))
            recorded.save(out / 'summary.json', report)
        report['status'] = 'passed'
    except Exception as exc:
        report.update(status='failed', error=repr(exc))
        raise
    finally:
        recorded.save(out / 'summary.json', report)
        print(json.dumps(report), flush=True)


if __name__ == '__main__':
    main()

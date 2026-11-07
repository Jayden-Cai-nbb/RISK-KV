"""Verify the actual openTPU native adapter, cleaning arbiter and real AXI CDC together."""
import argparse
import difflib
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
    source_names = tuple(p for p in (ROOT / 'platform/m1/memory_axi_cdc.f').read_text().splitlines() if p and not p.startswith('#')) + (
        'rtl/m1/rkv_m1_memory_arbiter.sv',
        'tb/m1/tb_rkv_m1_memory_axi_cdc.sv',
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
    shutil.copy2(__file__, out / 'memory_axi_cdc_test.py')
    shutil.copy2(fixture / 'cdc-properties.txt', out / 'cdc-properties.txt')
    shutil.copy2(fixture / 'create_axi_cdc.tcl', out / 'create_axi_cdc.tcl')
    shutil.copy2(ROOT / 'platform/m1/memory_axi_cdc.f', out / 'memory_axi_cdc.f')
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
    report = dict(status='running', scope='Actual cleaning arbiter + native memory/retirement + unmodified openTPU adapter + real AXI CDC; behavioral UI memory, no MIG/PHY/NPU/board', runs=[])
    recorded.save(out / 'summary.json', report)
    recorded.ROOT = out
    inputs = snapshots + [out / 'memory_axi_cdc.f', out / 'memory_axi_cdc_test.py', out / 'xsim.ini', out / 'vendor-libraries.json']
    # XSim拒绝上游仿真checker的initial+always_ff双过程初始化。
    # 只在编译副本将该checker改为相同事件的always；保留全部断言和硬件过程。
    compiled = list(snapshots)
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
    compiled[compiled.index(native_source)] = native_compiled
    patch = compatibility / 'checker-only.patch'
    patch.write_text(''.join(difflib.unified_diff(original.splitlines(True), exported.splitlines(True),
                                               fromfile='original/otpu_native_dram.sv', tofile='compiled/otpu_native_dram.sv')))
    recorded.save(compatibility / 'manifest.json', dict(original_sha256=recorded.sha(native_source),
                  exported_sha256=recorded.sha(native_compiled), change='One simulation-only checker always_ff -> always; same posedge, body and assertions. Production source untouched.'))
    inputs += [native_compiled, patch, compatibility / 'manifest.json']
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
    compiled[compiled.index(ram_source)] = ram_compiled
    ram_patch = compatibility / 'ram-process-keywords.patch'
    ram_patch.write_text(''.join(difflib.unified_diff(ram_original.splitlines(True), ram_exported.splitlines(True),
                                                   fromfile='original/otpu_tech_ram.sv', tofile='compiled/otpu_tech_ram.sv')))
    recorded.save(compatibility / 'ram-manifest.json', dict(original_sha256=recorded.sha(ram_source),
                  exported_sha256=recorded.sha(ram_compiled), change='Only three always_ff -> always keywords inside otpu_ram_1r1w_ra. Same events, bodies, initialization and bypass; production source untouched.'))
    inputs += [ram_compiled, ram_patch, compatibility / 'ram-manifest.json']
    report['simulation_export'] = 'simulation-compat/: four process keywords only; all events, assignments, initial values and upstream assertions retained'
    try:
        assert recorded.run(out / 'version', [args.vivado.resolve(), '-version'], 60, inputs) == 0
        version = (out / 'version/stdout.log').read_text()
        assert 'v2022.2' in version and '3671981' in version, 'Unverified Vivado version'
        # 固定2022.2提供的语言兼容选项；保留上游声明顺序，不影响综合/DRC检查。
        assert recorded.run(out / 'compile', [bin_dir / 'xvlog', '--sv', '--relax', '--work', 'xil_defaultlib', *compiled], 300, inputs) == 0, 'xvlog compile failed; see compile/stdout.log'
        command = [bin_dir / 'xelab', '--debug', 'typical', '--relax', '--mt', '2']
        for library in libraries:
            command.extend(['-L', library])
        command.extend(['xil_defaultlib.tb_rkv_m1_memory_axi_cdc', 'xil_defaultlib.glbl', '-s', 'memory_axi_cdc_sim'])
        assert recorded.run(out / 'elaborate', command, 300, inputs) == 0, 'xelab failed; see elaborate/stdout.log'
        for seed, phase in ((1, 3333), (17, 1101), (12345, 1979)):
            stage = out / f'seed-{seed}'
            # 每次仿真有自己的日志、工作目录；只读共享已编译快照。
            stage.mkdir(exist_ok=False)
            (stage / 'xsim.dir').symlink_to('../xsim.dir', target_is_directory=True)
            shutil.copy2(out / 'xsim.ini', stage / 'xsim.ini')
            recorded.ROOT = stage
            command = [bin_dir / 'xsim', 'memory_axi_cdc_sim', '-runall',
                       '-testplusarg', f'seed={seed}', '-testplusarg', f'ui_phase_ps={phase}']
            assert recorded.run(stage / 'record', command, 120, inputs) == 0
            log = (stage / 'record/stdout.log').read_text()
            assert f'M1_MEMORY_AXI_CDC_PASS seed={seed} ' in log
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

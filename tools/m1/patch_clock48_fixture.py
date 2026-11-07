"""Patch only an isolated structural fixture; never a Vivado installation or frozen IP."""
import argparse
import difflib
import hashlib
import json
from pathlib import Path
import re


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def patch(root):
    root = root.resolve()
    marker = root / 'user-management-state.tsv'
    if not marker.is_file() or dict(line.split('\t') for line in marker.read_text().splitlines()) != {
        'IS_LOCKED': '1', 'GENERATE_SYNTH_CHECKPOINT': '0'
    }:
        raise ValueError('Expected explicitly locked user-managed fixture')
    # open_example_project 将 DDR 子系统的可编辑导出件放在 .srcs；
    # .gen 仍含其他 IP，不能把原始母版的目录结构套用到示例项目。
    sources = list((root / 'project').glob('*.srcs/sources_1/ip/clock48_fixture/rtl/ip_top/clock48_fixture_ddr4.sv'))
    if len(sources) != 1:
        raise ValueError(f'Expected one active DDR wrapper, found {len(sources)}')
    source = sources[0]
    original = source.read_text()
    updated = original
    for name, old, new in [('CLKIN_PERIOD_MMCM', '10416', '20833'),
                           ('CLKFBOUT_MULT_MMCM', '10', '20')]:
        expression = rf'(parameter\s+{name}\s*=\s*){old}(\s*,)'
        updated, count = re.subn(expression, lambda m: m[1] + new + m[2], updated)
        if count != 1:
            raise ValueError(f'Expected exactly one original {name}={old}, found {count}')
    changes = [(source, original, updated)]
    iproot = source.parents[2]
    for xdc in sorted(iproot.rglob('*.xdc')):
        raw = xdc.read_text()
        # 只修改本控制器的输入时钟定义；不改 DRC、路径例外或其他时钟。
        expression = r'(create_clock\s+-period\s+)10\.416(\s+\[get_ports\s+c0_sys_clk_p\])'
        new, count = re.subn(expression, lambda m: m[1] + '20.833333' + m[2], raw)
        if count:
            changes.append((xdc, raw, new))
    if len(changes) != 2:
        raise ValueError(f'Expected wrapper plus one active input XDC, found {len(changes)}')
    # 所有原值先核对再修改；重复运行会拒绝，原件与差异永久保留。
    backup = root / 'clock-patch-originals'
    backup.mkdir(exist_ok=False)
    records = []
    diffs = []
    for index, (path, old, new) in enumerate(changes):
        relative = str(path.relative_to(root))
        saved = backup / f'{index}-{path.name}'
        saved.write_text(old)
        path.write_text(new)
        records.append(dict(path=relative, original=str(saved.relative_to(root)),
                            before_sha256=sha(old.encode()), after_sha256=sha(new.encode())))
        diffs.extend(difflib.unified_diff(old.splitlines(True), new.splitlines(True),
                                         fromfile='original/' + relative, tofile='derived/' + relative))
    (root / 'clock-patch.diff').write_text(''.join(diffs))
    report = dict(status='patched_structural_proxy_not_for_programming',
                  validation_profile='experimental_clock48', vendor_supported=False,
                  nominal_input_hz=48000000, M=20, D=1, O=5,
                  nominal_vco_hz=960000000, nominal_ui_hz=192000000,
                  approximate_ddr_mtps=1536, memory_part_verified=False, changes=records)
    (root / 'clock-patch.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('root', type=Path)
    patch(p.parse_args().root)

"""Generate M1 constants and cold scratch template from one checked layout."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def generate(check=False, template=None):
    source = ROOT / 'configs/m1/layout.json'
    cfg = json.loads(source.read_text())
    ref = json.loads((ROOT / 'assets/reference/summary.json').read_text())
    for key in ('kv_base', 'prefix_bytes', 'result_address', 'logits_address', 'prompt_address'):
        assert cfg[key] == ref[key], key
    assert cfg['object_bytes'] == 3 * cfg['prefix_bytes']
    assert cfg['logical_bytes'] == 2**31
    assert cfg['scratch_template_base'] >= cfg['cold_image_bytes']
    assert cfg['scratch_template_base'] + sum(n for _, n in cfg['scratch_restore']) <= cfg['logical_bytes']
    for start, size in cfg['scratch_restore']:
        assert start % 128 == size % 128 == 0 and size > 0
        for immutable_start, immutable_size in cfg['immutable_regions']:
            assert start + size <= immutable_start or start >= immutable_start + immutable_size
    values = {k.upper(): v for k, v in cfg.items() if isinstance(v, int)}
    values.update({f'OP_{k}': v for k, v in cfg['operations'].items()})
    values.update({f'REG_{k}': v for k, v in cfg['registers'].items()})
    values.update({f'MB_{k}': v for k, v in cfg['mailbox'].items()})
    profile_path = ROOT / 'configs/npu-vu440-core.json'
    assert digest(profile_path) == ref['profile_sha256']
    profile = json.loads(profile_path.read_text())
    values.update({f'CFG_{k}': int(v) for k, v in (profile['architecture'] | profile['microarchitecture']).items()})
    for name, p in cfg['programs'].items():
        assert digest(ROOT / f'assets/reference/{name}.bin') == p['sha256']
        values[name.upper() + '_ADDR'] = p['address']
        values[name.upper() + '_INSNS'] = p['instructions']
    values['SCRATCH_RANGES'] = len(cfg['scratch_restore'])
    values['SCRATCH_BYTES'] = sum(n for _, n in cfg['scratch_restore'])
    sv = ['// 自动生成；源 configs/m1/layout.json。字节地址，原生小端。',
          'package rkv_m1_layout_pkg;']
    header = ['/* Generated from configs/m1/layout.json. Byte addresses. */',
              '#ifndef RKV_M1_LAYOUT_H', '#define RKV_M1_LAYOUT_H', '#include <stdint.h>']
    for key, value in values.items():
        sv.append(f"    localparam logic [31:0] {key} = 32'h{value & 0xffffffff:08x};")
        header.append(f'#define RKV_{key} UINT32_C(0x{value & 0xffffffff:08x})')
    # 范围 ROM 与测试/固件共源；首范围按清理模式选择 KV，其余均从冷模板恢复。
    for field in ('base', 'bytes', 'source'):
        sv.extend([f'    function automatic logic [31:0] scratch_{field}(input logic [2:0] index);', '        case (index)'])
        offset = 0
        for i, (base, size) in enumerate(cfg['scratch_restore']):
            value = {'base': base, 'bytes': size, 'source': cfg['scratch_template_base'] + offset}[field]
            sv.append(f"            3'd{i}: scratch_{field} = 32'h{value:08x};")
            offset += size
        sv.extend([f"            default: scratch_{field} = 32'b0;", '        endcase', '    endfunction'])
    sv.append('endpackage')
    header.append('#endif')
    outputs = {ROOT / 'rtl/m1/rkv_m1_layout_pkg.sv': '\n'.join(sv) + '\n',
               ROOT / 'firmware/m1/layout.h': '\n'.join(header) + '\n'}
    for path, content in outputs.items():
        if check:
            assert path.read_text() == content, f'stale generated file: {path}'
        else:
            path.write_text(content)
    if template is not None:
        cold = ROOT / 'assets/data/dram-input.bin'
        assert digest(cold) == cfg['cold_image_sha256']
        with cold.open('rb') as src, template.open('xb') as dst:
            for base, size in cfg['scratch_restore']:
                src.seek(base)
                data = src.read(size)
                assert len(data) == size
                dst.write(data)
        template.with_suffix('.json').write_text(json.dumps(dict(
            address=cfg['scratch_template_base'], bytes=template.stat().st_size,
            sha256=digest(template), layout_sha256=digest(source),
            cold_image_sha256=digest(cold), ranges=cfg['scratch_restore']), indent=2) + '\n')
    print(json.dumps(dict(status='checked' if check else 'generated', layout_sha256=digest(source),
                         scratch_bytes=values['SCRATCH_BYTES'])))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--template', type=Path)
    args = parser.parse_args()
    generate(args.check, args.template)

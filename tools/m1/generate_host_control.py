"""Generate only the physical host address decoder; no controller behavior."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

def content():
    cfg = json.loads((ROOT / 'configs/m1/host-control.json').read_text())
    layout = json.loads((ROOT / 'configs/m1/layout.json').read_text())
    # The mailbox base remains owned by the existing core layout.
    mb = layout['mailbox_base']
    assert cfg['mailbox_words'] == 64 and cfg['mailbox_stride'] == 8
    assert cfg['mailbox_alias_base'] & 511 == 0 and mb & 255 == 0
    assert len({v['id'] for v in cfg['registers'].values()}) == len(cfg['registers'])
    lines = [
        '// 由configs/m1/host-control.json与layout.json生成；仅组合地址译码，不持有事务。',
        'module rkv_m1_host_map (',
        '    input wire [31:0] address,',
        '    output reg [4:0] register_id,',
        '    output wire mailbox_select,',
        '    output wire [15:0] mailbox_address',
        ');',
        f"    assign mailbox_select = address[31:9] == 23'h{cfg['mailbox_alias_base'] >> 9:06x} && address[2:0] == 3'd0;",
        '// 每个8-byte主机别名对应一个4-byte原邮箱字；低两位保持字对齐。',
        f"    assign mailbox_address = {{8'h{mb >> 8:02x}, address[8:3], 2'd0}};",
        '    always @* begin',
        "        register_id = 5'd0;",
        '        case (address)',
    ]
    for name, reg in cfg['registers'].items():
        assert reg['offset'] % 8 == 0 and 0 < reg['id'] < 32
        lines.append(f"            32'h{cfg['control_base'] + reg['offset']:08x}: register_id = 5'd{reg['id']}; // {name}")
    lines += ["            default: register_id = 5'd0;", '        endcase', '    end', 'endmodule', '']
    return '\n'.join(lines)

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--check', action='store_true')
    a = p.parse_args()
    target = ROOT / 'platform/m1/rkv_m1_host_map.v'
    text = content()
    if a.check:
        assert target.read_text() == text, 'host map differs; regenerate and review'
    else:
        target.write_text(text)
    print(json.dumps(dict(status='matched' if a.check else 'generated', file=str(target.relative_to(ROOT)))))

if __name__ == '__main__':
    main()

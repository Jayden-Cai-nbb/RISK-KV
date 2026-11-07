"""Derive structural-proxy pin LOCs from the user's manual, without defaults."""
import argparse
import hashlib
import json
from pathlib import Path
import re


def derive(source):
    rows = source['rows']
    pins = {row['net']: row for row in rows}
    if len(pins) != len(rows) or len({r['package_pin'] for r in rows}) != len(rows):
        raise ValueError('Duplicate net or package pin')
    lanes = []
    # x8 每组 DQ/DM/DQS 必须占同一 byte lane；DQS 为上半 byte 的 N6/N7。
    for byte in range(8):
        names = [f'DDR4_DQ{i}' for i in range(byte * 8, byte * 8 + 8)]
        names += [f'DDR4_DM{byte}', f'DDR4_DQS{byte}_T', f'DDR4_DQS{byte}_C']
        lane_ids = set()
        for net in names:
            row = pins[net]
            match = re.search(r'_T([0-3])([LU])_N(\d+)', row['pin_function'])
            if not match:
                raise ValueError(f'No byte-lane function for {net}')
            lane_ids.add((row['bank'], int(match[1])))
            bit = int(match[3])
            if '_DQS' in net:
                expected = 6 if net.endswith('_T') else 7
                if bit != expected or match[2] != 'U':
                    raise ValueError(f'Invalid DQS lane position: {net}')
            elif bit in (1, 12):
                raise ValueError(f'Invalid DQ/DM lane position: {net}')
        if len(lane_ids) != 1:
            raise ValueError(f'Byte {byte} crosses physical lanes')
        bank, lane = next(iter(lane_ids))
        lanes.append(dict(byte=byte, bank=bank, lane=lane))
    if len({(r['bank'], r['lane']) for r in lanes}) != 8:
        raise ValueError('Overlapping data byte lanes')
    mapping = {}

    def add(net, port):
        if port in mapping:
            raise ValueError(f'Duplicate port: {port}')
        mapping[port] = pins[net]['package_pin']

    for i in range(17):
        net = f'DDR4_A{i}' if i < 14 else ['DDR4_WE_N_A14', 'DDR4_CAS_N_A15', 'DDR4_RAS_N_A16'][i - 14]
        add(net, f'c0_ddr4_adr[{i}]')
    for stem in ['BA', 'BG']:
        for i in range(2):
            add(f'DDR4_{stem}{i}', f'c0_ddr4_{stem.lower()}[{i}]')
    for stem, port in [('CKE0', 'cke[0]'), ('ODT0', 'odt[0]'), ('CS0_N', 'cs_n[0]'),
                       ('CK0_T', 'ck_t[0]'), ('CK0_C', 'ck_c[0]'),
                       ('RESET_N', 'reset_n'), ('ACT_N', 'act_n')]:
        add('DDR4_' + stem, 'c0_ddr4_' + port)
    for i in range(64):
        add(f'DDR4_DQ{i}', f'c0_ddr4_dq[{i}]')
    for i in range(8):
        add(f'DDR4_DM{i}', f'c0_ddr4_dm_dbi_n[{i}]')
        for suffix in ['T', 'C']:
            add(f'DDR4_DQS{i}_{suffix}', f'c0_ddr4_dqs_{suffix.lower()}[{i}]')
    if len(mapping) != 116:
        raise ValueError(f'Unexpected memory port count: {len(mapping)}')
    # 手册表 5-1 的 pair6 和表 5-13 的 RESET_IN1；频率不是本表提供的信息。
    mapping.update(c0_sys_clk_p='Y47', c0_sys_clk_n='Y48', sys_rst_n='BC27')
    if len(set(mapping.values())) != len(mapping):
        raise ValueError('Clock/reset collide with memory pins')
    return mapping, lanes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pins', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    source = json.loads(args.pins.read_text())
    mapping, lanes = derive(source)
    args.output.mkdir(parents=True, exist_ok=False)
    lines = ['# STRUCTURAL PROXY ONLY: frequency/DIMM/physical revision unverified.',
             '# J11 table 5-12, clock pair6 table 5-1, reset table 5-13.']
    for port, pin in mapping.items():
        lines.append(f'set_property PACKAGE_PIN {pin} [get_ports {{{port}}}]')
    lines += ['set_property IOSTANDARD LVDS [get_ports {c0_sys_clk_p c0_sys_clk_n}]',
              'set_property DIFF_TERM_ADV TERM_NONE [get_ports {c0_sys_clk_p c0_sys_clk_n}]',
              'set_property IOSTANDARD LVCMOS18 [get_ports sys_rst_n]',
              '# DDR I/O standards, VREF and clock definitions remain owned by generated IP.',
              '# No configuration-voltage guesses or timing exceptions are added.']
    (args.output / 'prodigy-pins.xdc').write_text('\n'.join(lines) + '\n')
    report = dict(status='static_pin_mapping_checked_not_hardware_validated',
                  pins_sha256=hashlib.sha256(args.pins.read_bytes()).hexdigest(),
                  port_count=len(mapping), ports=mapping, byte_lanes=lanes,
                  clock_reference_hz=None, physical_speed_grade=None)
    (args.output / 'pin-plan.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(dict(status=report['status'], port_count=len(mapping), byte_lanes=lanes)))


if __name__ == '__main__':
    main()

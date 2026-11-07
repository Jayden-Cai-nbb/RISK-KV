"""Check regenerated OOC provenance and report constraints without running Vivado."""
import argparse
import json
from pathlib import Path
import re
from recorded import ROOT, save, sha, utc


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    a.output = a.output.resolve()
    result = dict(status='audited_not_resynthesized', executed_at=utc(), scopes={})
    for name in ('service', 'cpu', 'compute'):
        old = ROOT / ('platform/ooc-' + name)
        new = a.output / ('ooc-' + name)
        reports = ROOT / ('evidence/original/synthesis-' + name)
        timing = reports / ('timing.rpt' if name == 'compute' else 'timing-estimate.rpt')
        text = timing.read_text()
        util = (reports / 'utilization.rpt').read_text()
        def count(pattern):
            return int(re.search(pattern, text).group(1))
        row = re.search(r'WNS\(ns\).*\n[- \t]+\n([^\n]+)', text).group(1).split()
        resources = {}
        for label in ('CLB LUTs*', 'CLB Registers', 'Block RAM Tile', 'DSPs'):
            found = re.search(r'\|\s*' + re.escape(label) + r'\s*\|\s*([\d.]+)', util)
            resources[label] = float(found.group(1)) if found else None
        files = []
        targets = list(new.rglob('*.sv')) + list(new.rglob('*.v')) if new.exists() else list(old.glob('*.sv'))
        for f in targets:
            if name == 'service':
                original = ROOT / 'rtl' / f.name
            else:
                original = old / f.relative_to(new)
            files.append(dict(path=str(f.relative_to(ROOT)), original=str(original.relative_to(ROOT)), sha256=sha(f),
                byte_equal=f.read_bytes() == original.read_bytes(), normalized_text_equal=f.read_text() == original.read_text()))
        result['scopes'][name] = dict(files=files, resources=resources, wns_ns=float(row[0]), tns_ns=float(row[1]),
            whs_ns=float(row[4]), missing_input_delays=count(r'There are (\d+) input ports with no input delay specified'),
            missing_output_delays=count(r'There are (\d+) ports with no output delay specified'),
            pins_without_clock=count(r'There are (\d+) register/latch pins with no clock'),
            unconstrained_max_delay_pins=count(r'There are (\d+) pins that are not constrained for maximum delay'),
            historical_timing_sha256=sha(timing), historical_utilization_sha256=sha(reports/'utilization.rpt'),
            tcl_sha256=sha(old/('probe.tcl' if name == 'compute' else 'run.tcl')))
    result['limits'] = ['CPU includes service; their resource counts must not be summed.',
        'Historical Vivado 2019.1 synthesis; locally available 2015.4 is not substituted.',
        'Clocks are created after synth_design. No place/route, board I/O timing, DDR or reset/clock shell validated.',
        'Compute clk and clk_f primary clocks do not prove required board 2x phase relationship.',
        'CPU export differs only in metadata, PicoRV32 CRLF and removal of diagnostic puts in Tcl.',
        'Compute export-manifest serialization differs but parsed JSON and exported source/config/Tcl match.']
    save(a.output/'ooc-audit.json', result)


if __name__ == '__main__':
    main()

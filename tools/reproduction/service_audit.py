"""Compile and execute the independent service protocol audit; no model arithmetic."""
import argparse
import json
from pathlib import Path
import sys

from recorded import ROOT, run, save, sha


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    sys.path.insert(0, str(ROOT / 'vendor/openTPU'))
    from opentpu import rtlsim
    rtlsim.VFLAGS[rtlsim.VFLAGS.index('-j') + 1] = '2'
    names = ['rtl/rkv_npu_control.sv', 'rtl/rkv_npu_io_control.sv',
             'rtl/rkv_context_guard.sv', 'rtl/rkv_npu_context_service.sv',
             'tb/audit/tb_rkv_service_audit.sv']
    sources = [ROOT / name for name in names]
    save(out / 'inputs.json', {name: sha(ROOT / name) for name in names})
    exe = rtlsim.build('tb_rkv_service_audit', sources)
    rc = run(out / 'execution', [exe], 120, sources)
    log = (out / 'execution/stdout.log').read_text()
    cases = [line for line in log.splitlines() if line.startswith('AUDIT_CASE ')]
    observations = [line for line in log.splitlines() if line.startswith('AUDIT_OBSERVATION ')]
    passed = rc == 0 and 'PASS service audit ' in log and len(cases) == 5 and len(observations) == 5
    save(out / 'summary.json', dict(status='passed' if passed else 'failed',
         scope='Service protocol fixture; five contract cases and five boundary observations. No arithmetic/DDR proof.',
         tool_version=rtlsim.verilator_version(), executable_sha256=sha(exe), cases=cases, observations=observations))
    print(log)
    if not passed:
        raise SystemExit(1)


if __name__ == '__main__':
    main()

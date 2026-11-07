"""Serial original-asset replay, with separate outputs and preserved old unit logs."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

from recorded import ROOT, run, save, sha, snapshot_tooling, utc


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--host-opt', action='store_true', help='Explicit host C++ optimization; same RTL and timeout')
    parser.add_argument('--host-default', action='store_true', help='Record host build with upstream C++ flags and two build jobs')
    parser.add_argument('--sim-threads', type=int, choices=(1,2,4), default=1)
    parser.add_argument('--platform', type=Path, help='Reuse an already validated, unchanged platform export')
    args = parser.parse_args()
    if args.host_opt and args.host_default:
        parser.error('Select only one host mode')
    if args.sim_threads != 1 and not (args.host_opt or args.host_default):
        parser.error('Select an explicit host mode for multithreaded simulation')
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    tooling = snapshot_tooling(out)
    status = dict(status='running', started_at=utc(), stages={}, host_optimization=args.host_opt, host_default=args.host_default, sim_threads=args.sim_threads,
                  original_manifest_sha256=sha(ROOT / 'MANIFEST.json'), tooling_sha256=tooling)
    shutil.copy2(ROOT / 'MANIFEST.json', out / 'original-manifest.json')
    save(out / 'suite.json', status)
    try:
        for name, cmd in [
            ('integrity', [sys.executable, ROOT / 'tools/verify_handoff.py', '--data']),
            ('environment', ['make', 'rtl-doctor'])]:
            rc = run(out / name, cmd, 600)
            status['stages'][name] = rc
            save(out / 'suite.json', status)
            if rc:
                raise RuntimeError(name)
        vendors = {}
        for name in ('openTPU', 'picorv32'):
            path = ROOT / 'vendor' / name
            vendors[name] = {key: subprocess.check_output(['git', '-C', str(path), *cmd], text=True)
                for key, cmd in [('head', ['rev-parse', 'HEAD']), ('diff', ['diff', 'HEAD']), ('status', ['status', '--short'])]}
        save(out / 'vendors.json', vendors)
        if (ROOT / 'build/unit').exists():
            shutil.copytree(ROOT / 'build/unit', out / 'unit-before')
        rc = run(out / 'unit-command', [sys.executable, ROOT / 'tools/replay.py', 'unit'], 1800)
        shutil.copytree(ROOT / 'build/unit', out / 'unit')
        status['stages']['unit'] = rc
        save(out / 'suite.json', status)
        if rc:
            raise RuntimeError('unit')
        for case in ('cancel', 'fault', 'positive'):
            host_flags = ['--default-cxx'] if args.host_default else []
            host_flags += ['--sim-threads', str(args.sim_threads)]
            prefix = ([sys.executable, ROOT / 'tools/reproduction/npu_host.py', '--record', out / (case + '-host'), *host_flags, '--']
                      if args.host_opt or args.host_default else [sys.executable, ROOT / 'tools/run_npu_context_build.py'])
            command = [*prefix,
                '--source', ROOT / 'vendor/openTPU', '--reference', ROOT / 'assets/reference',
                '--firmware', ROOT / 'assets/firmware' / case, '--platform', args.platform.resolve() if args.platform else out / 'platform',
                '--output', out / case]
            rc = run(out / (case + '-command'), command)
            status['stages'][case] = rc
            save(out / 'suite.json', status)
            if rc:
                raise RuntimeError(case)
            if (args.host_opt or args.host_default) and case in ('cancel', 'fault'):
                old_path = ROOT / 'evidence/original' / ('model-' + case) / 'summary.json'
                old = json.loads(old_path.read_text())
                actual = json.loads((out / case / 'summary.json').read_text())
                keys = ('total_control_cycles', 'accepted', 'rejected', 'built_tokens', 'states', 'build_commits',
                        'seals', 'binds', 'immutable_equal', 'final_prefix_sha256', 'traffic_native_requested_bytes')
                comparisons = {key: dict(original=old[key], actual=actual[key], equal=old[key] == actual[key]) for key in keys}
                save(out / (case + '-host-equivalence.json'), dict(original_summary_sha256=sha(old_path),
                     actual_summary_sha256=sha(out / case / 'summary.json'), comparisons=comparisons))
                if not all(item['equal'] for item in comparisons.values()):
                    raise RuntimeError('Host optimization changed frozen semantics/cycles: ' + case)
        rc = run(out / 'integrity-after', [sys.executable, ROOT / 'tools/verify_handoff.py', '--data'], 600)
        status['stages']['integrity_after'] = rc
        if rc:
            raise RuntimeError('Frozen inputs changed')
        status['status'] = 'passed'
    except BaseException as ex:
        status.update(status='failed', error=f'{type(ex).__name__}: {ex}')
        raise
    finally:
        status['finished_at'] = utc()
        save(out / 'suite.json', status)


if __name__ == '__main__':
    main()

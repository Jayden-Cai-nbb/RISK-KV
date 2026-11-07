"""Validate completed suites and derive local metrics without altering frozen evidence."""
import argparse
import json
from pathlib import Path
import sys
import time

from recorded import ROOT, run, save, sha, snapshot_tooling, utc


def read(path):
    return json.loads(path.read_text())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--frozen', type=Path, required=True)
    parser.add_argument('--rebuilt', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    status = dict(status='waiting', started_at=utc(), stages={},
                  tooling_sha256=snapshot_tooling(out))
    save(out / 'summary.json', status)

    def stage(name, command):
        rc = run(out / name, command, 600)
        status['stages'][name] = rc
        save(out / 'summary.json', status)
        if rc:
            raise RuntimeError(name)

    try:
        for name, suite in [('frozen', args.frozen), ('rebuilt', args.rebuilt)]:
            while True:
                state = read(suite / 'suite.json')['status']
                if state not in ('waiting', 'running'):
                    if state != 'passed':
                        raise RuntimeError(f'{name} suite did not pass: {state}')
                    break
                time.sleep(30)
        status.update(status='checking', execution_started_at=utc())
        save(out / 'summary.json', status)
        for name, suite, firmware, flags in [
            ('frozen', args.frozen, ROOT / 'assets/firmware', ['--require-identical-cycles']),
            ('rebuilt', args.rebuilt, args.rebuilt / 'firmware', [])]:
            stage(name + '-comparison', [sys.executable, ROOT / 'tools/reproduction/compare_replays.py',
                  '--suite', suite, '--firmware-root', firmware, *flags])
        stage('capacity-local', [sys.executable, ROOT / 'tools/reproduction/capacity_study.py',
              '--metrics', args.frozen / 'positive-metrics.json', '--output', out / 'capacity-local-results'])
        assets = read(args.rebuilt / 'asset-comparison.json')
        assert assets['status'] == 'passed' and all(assets['metadata_checks'].values())
        assert assets['summary_semantic_equal']
        assert all(value['byte_equal'] for value in assets['files'].values())
        reports = {}
        resources = {}
        for name, suite in [('frozen', args.frozen), ('rebuilt', args.rebuilt)]:
            reports[name] = dict(suite=str(suite), suite_sha256=sha(suite / 'suite.json'),
                comparison_sha256=sha(suite / 'comparison.json'),
                cases={case: read(suite / case / 'summary.json')['status']
                       for case in ('cancel', 'fault', 'positive')})
            resources[name] = {}
            for command in sorted(suite.glob('*/command.json')):
                row = read(command)
                resources[name][command.parent.name] = {key: row.get(key) for key in (
                    'status', 'returncode', 'wall_seconds', 'sampled_resources', 'timeout_seconds')}
        status.update(status='passed_full_reproduction', suites=reports, resources=resources,
            rebuilt_assets_sha256=sha(args.rebuilt / 'asset-comparison.json'),
            scope='Frozen inputs and independent source rebuild through full numerical RTL lifecycle; no synthesized or board performance acceptance',
            vivado_rerun=False, place_and_route=False, board_execution=False)
    except BaseException as ex:
        status.update(status='failed', error=f'{type(ex).__name__}: {ex}')
        raise
    finally:
        status['finished_at'] = utc()
        save(out / 'summary.json', status)


if __name__ == '__main__':
    main()

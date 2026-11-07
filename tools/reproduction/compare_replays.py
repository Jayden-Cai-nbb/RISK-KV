"""Compare complete replays, separating frozen semantics from firmware identity and cycles."""
import argparse
import json
from pathlib import Path
import re
from recorded import ROOT, save, sha, utc
from metrics import measure


def read(path):
    return json.loads(path.read_text())


def compare(case, directory, firmware):
    original = read(ROOT / 'evidence/original' / ('model-' + case) / 'summary.json')
    actual_path = directory / 'summary.json'
    actual = read(actual_path)
    old_fw = read(ROOT / 'assets/firmware' / case / 'manifest.json')
    new_fw = read(firmware / 'manifest.json')
    keys = ['status', 'failure', 'initial_kv_all_zero', 'target_tokens', 'accepted', 'rejected',
            'built_tokens', 'decode_tasks', 'states', 'build_commits', 'seals', 'binds',
            'immutable_equal', 'final_prefix_sha256', 'traffic_native_requested_bytes']
    if case == 'positive':
        keys += ['private_at_bind_all_zero', 'final_pool_equal', 'steps']
    semantics = {key: dict(original=original[key], actual=actual[key], equal=original[key] == actual[key])
                 for key in keys}
    configuration = {key: dict(original=value, actual=new_fw['configuration'].get(key),
                      equal=value == new_fw['configuration'].get(key))
                     for key, value in old_fw['configuration'].items() if key not in ('SESSION_LO', 'SESSION_HI')}
    original_sources = {key: value == new_fw['source_sha256'].get(key)
                        for key, value in old_fw['source_sha256'].items()}
    logs = [p for p in directory.glob('*.log') if 'CTX_LAUNCH ' in p.read_text(errors='replace')]
    assert len(logs) == 1, logs
    launches, completions = [], []
    for line in logs[0].read_text().splitlines():
        if line.startswith(('CTX_LAUNCH ', 'CTX_COMPLETE ')):
            fields = dict(re.findall(r'(\w+)=(\w+)', line))
            (launches if line.startswith('CTX_LAUNCH ') else completions).append(fields)
    launch_ids = [int(x['seq'], 16) for x in launches]
    complete_ids = [int(x['seq'], 16) for x in completions]
    identity = dict(expected_session=new_fw['session'],
                    launch_sessions=sorted({int(x['session'], 16) for x in launches}),
                    launch_sequences=launch_ids, completion_sequences=complete_ids,
                    sequences_equal=launch_ids == complete_ids == list(range(1, actual['accepted'] + 1)),
                    session_equal=all(int(x['session'], 16) == new_fw['session'] for x in launches))
    cycles = dict(original=original['total_control_cycles'], actual=actual['total_control_cycles'],
                  delta=actual['total_control_cycles'] - original['total_control_cycles'])
    metrics = measure(directory)
    old_metrics = measure(ROOT / 'evidence/original' / ('model-' + case))
    task_deltas = [n['cycles'] - o['cycles'] for n, o in zip(metrics['tasks'], old_metrics['tasks'], strict=True)]
    cycles.update(task_interval_deltas=task_deltas,
                  outside_task_delta=metrics['outside_task_cycles'] - old_metrics['outside_task_cycles'])
    result = dict(directory=str(directory), summary_sha256=sha(actual_path), semantics=semantics,
                  cycles=cycles, identity=identity, firmware=dict(configuration=configuration,
                    original_source_hashes_equal=original_sources,
                    additional_source_records=sorted(set(new_fw['source_sha256'])-set(old_fw['source_sha256'])),
                    original_sha256=old_fw['firmware_sha256'], actual_sha256=new_fw['firmware_sha256'],
                    original_session=old_fw['session'], actual_session=new_fw['session'],
                    original_bytes=old_fw['firmware_bytes'], actual_bytes=new_fw['firmware_bytes']))
    result['semantics_equal'] = (all(x['equal'] for x in semantics.values()) and
        all(x['equal'] for x in configuration.values()) and all(original_sources.values()) and
        identity['session_equal'] and identity['sequences_equal'])
    return result, metrics


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite', type=Path, required=True)
    parser.add_argument('--firmware-root', type=Path, required=True)
    parser.add_argument('--require-identical-cycles', action='store_true')
    args = parser.parse_args()
    assert read(args.suite / 'suite.json')['status'] == 'passed', 'Only completed passing suites are comparable'
    results = {}
    for case in ('cancel', 'fault', 'positive'):
        results[case], metrics = compare(case, args.suite / case, args.firmware_root / case)
        save(args.suite / (case + '-metrics.json'), metrics)
    passed = all(x['semantics_equal'] for x in results.values())
    if args.require_identical_cycles:
        passed = passed and all(x['cycles']['delta'] == 0 and not any(x['cycles']['task_interval_deltas'])
                                for x in results.values())
    save(args.suite / 'comparison.json', dict(status='passed' if passed else 'mismatch', generated_at=utc(),
        require_identical_cycles=args.require_identical_cycles, cases=results,
        limits=['Identity evidence covers launch session and matched ordered completions; incorrect ACK identities are tested separately.',
                'Binary identity is reported, not required for newly randomized firmware sessions.',
                'Cycle differences alone are not a numeric mismatch or a performance claim.']))
    assert passed, 'Replay mismatch: inspect comparison.json'


if __name__ == '__main__':
    main()

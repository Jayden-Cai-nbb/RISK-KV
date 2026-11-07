"""Combine completed dirty-slot cases without hiding an interrupted experiment."""
import argparse
import json
from pathlib import Path
from recorded import save, sha, utc


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', type=Path, required=True)
    args = parser.parse_args()
    root = args.run.resolve() / 'experiments'
    sources = []
    cases = {}
    for name in ('dirty', 'dirty-full-clear'):
        summary = root / name / 'summary.json'
        command = root / (name + '-command') / 'command.json'
        data = json.loads(summary.read_text())
        execution = json.loads(command.read_text())
        sources.append(dict(summary=str(summary), sha256=sha(summary), command=str(command),
                            command_sha256=sha(command), command_status=execution['status'],
                            error=execution.get('error'), completed_cases=len(data['cases'])))
        for case in data['cases']:
            key = (case['phase'], case['name'])
            assert key not in cases
            cases[key] = dict(**case, source=str(summary))
    expected = {(phase, name) for phase in ('build', 'decode') for name in
                ('clean', 'finite_old', 'nan_old', 'nan_clear_scales', 'nan_clear_full')}
    expected.add(('build', 'cancel_physical_restart'))
    assert set(cases) == expected, (set(cases), expected)
    for (phase, name), case in cases.items():
        assert case['immutable_unchanged']
        assert case['equal_clean'] == (name != 'nan_old'), (phase, name, case)
        if phase == 'decode':
            assert case['prefix_unchanged'] and len(case['steps']) == 3
            if name == 'nan_old':
                assert all(x['finite_logits'] == 0 for x in case['steps'])
    save(root / 'dirty-combined.json', dict(status='expected_outcomes_observed', generated_at=utc(),
        sources=sources, cases=list(cases.values()), case_count=len(cases),
        scale_clear_fraction_of_full=1/33,
        limits=['First invocation timed out after ten completed cases; the missing case completed in a separate invocation.',
                'This aggregate does not change either original command status or interrupted summary.',
                'Only frozen geometry and finite/NaN fixtures; no arbitrary-pattern, RTL reuse, or data sanitization proof.']))


if __name__ == '__main__':
    main()

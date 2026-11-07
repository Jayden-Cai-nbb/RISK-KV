"""Write a live evidence checkpoint; missing or running stages never count as passes."""
import argparse
import json
from pathlib import Path
from recorded import save, utc


def optional(path):
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return dict(status='unreadable_while_updating', path=str(path))


def suite(path):
    data = optional(path / 'suite.json')
    if data is None:
        return dict(status='not_started')
    result = dict(suite=data, progress={})
    for case in ('cancel', 'fault', 'positive'):
        progress = optional(path / case / 'progress.json')
        summary = optional(path / case / 'summary.json')
        if progress or summary:
            result['progress'][case] = dict(progress=progress, summary_status=(summary or {}).get('status'))
    references = list(path.glob('reference-*/summary.json'))
    if data.get('reference_directory'):
        references.append(Path(data['reference_directory'])/'summary.json')
    for reference in references:
        data = optional(reference) or {}
        result['reference'] = dict(path=str(reference),status=data.get('status'),phase=data.get('phase'),
                                   completed_reference_runs=list(data.get('runs',{})))
    result['commands'] = {}
    for command in path.glob('*-command/command.json'):
        data = optional(command) or {}
        result['commands'][command.parent.name] = {k:data[k] for k in
            ('status','returncode','error','wall_seconds','started_at','finished_at','sampled_resources') if k in data}
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--run', type=Path, required=True)
    p.add_argument('--frozen', default='frozen-threads4')
    p.add_argument('--rebuilt', default='rebuilt-threads4')
    p.add_argument('--final-checks', default='final-checks')
    a = p.parse_args(); root = a.run.resolve()
    report = dict(observed_at=utc(), scope='Live checkpoint, not final acceptance',
        selected_toolchain='Official Verilator 5.032; isolated CPython 3.12; pinned model packages; xPack GCC 14.2.0-3',
        frozen=suite(root/a.frozen), rebuilt=suite(root/a.rebuilt),
        final_checks=optional(root/a.final_checks/'summary.json'),
        protocol_audit=optional(root/'audit/service-v4/summary.json'),
        dirty_experiments_status=(optional(root/'experiments/dirty-combined.json') or {}).get('status'),
        immutable_history=True, board_execution=False, vivado_rerun=False)
    report['full_reproduction_passed'] = (all(report[x].get('suite',{}).get('status')=='passed' for x in ('frozen','rebuilt'))
        and (report['final_checks'] or {}).get('status')=='passed_full_reproduction')
    save(root/'checkpoint.json',report)
    print(json.dumps(dict(observed_at=report['observed_at'],
        frozen=report['frozen'].get('suite',{}).get('status'),
        frozen_progress=report['frozen'].get('progress'),
        rebuilt=report['rebuilt'].get('suite',{}).get('status'),
        rebuilt_reference=report['rebuilt'].get('reference'),
        rebuilt_progress=report['rebuilt'].get('progress'),
        rebuilt_stages=report['rebuilt'].get('suite',{}).get('stages'),
        final_checks=(report['final_checks'] or {}).get('status'),
        full_reproduction_passed=report['full_reproduction_passed']),ensure_ascii=False))


if __name__ == '__main__': main()

"""Index validated evidence, explicitly distinguishing user-deferred replay acceptance."""
import argparse
import json
from pathlib import Path
import re
from recorded import ROOT, save, sha, utc


def read(path):
    return json.loads(path.read_text())


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--run', type=Path, required=True)
    p.add_argument('--rebuilt', default='rebuilt-continuation')
    p.add_argument('--final-checks', default='final-checks-continuation')
    p.add_argument('--deferred-positive', action='store_true')
    a = p.parse_args(); root = a.run.resolve(); output = root/'delivery.json'
    assert not output.exists(), 'Preserve the existing delivery index'
    final = root/a.final_checks/'summary.json'
    expected = 'passed_preparation_with_user_deferral' if a.deferred_positive else 'passed_full_reproduction'
    assert read(final)['status'] == expected
    if a.deferred_positive:
        assert read(root/'user-deferral.json')['status'] == 'authorized_deferral'
        assert read(root/a.rebuilt/'suite.json')['status'] == 'deferred_by_user'
        assert read(root/'frozen-threads4/comparison.json')['status'] == 'passed'
    protocol = root/'audit/service-v4/summary.json'
    dirty = root/'experiments/dirty-combined.json'
    ooc = root/'audit/ooc-audit.json'
    assert read(protocol)['status'] == 'passed'
    assert len(read(protocol)['cases']) == len(read(protocol)['observations']) == 5
    assert read(dirty)['status'] == 'expected_outcomes_observed' and read(dirty)['case_count'] == 11
    assert read(ooc)['status'] == 'audited_not_resynthesized'
    files = {final, protocol, dirty, ooc, root/'audit/timing-observation.json',
             root/'research/source-review.json', root/'simulator-archives/manifest.json'}
    if a.deferred_positive: files.add(root/'user-deferral.json')
    files.update((root/a.final_checks).glob('*.json'))
    for name in ('cpu','service'):
        directory=root/f'audit/{name}-evidence-20261104'
        assert read(directory/'command.json')['returncode'] == 0
        assert read(directory/'stdout.log')['status'] == 'fresh'
        files.update(directory/name for name in ('command.json','stdout.log'))
    for command in (root/a.final_checks).glob('*/command.json'):
        files.add(command)
        files.add(command.parent/'stdout.log')
    files.update((ROOT/'docs/rewrite-preparation').glob('*.md'))
    files.add(ROOT/'IMPLEMENTATION_LOG.md')
    files.update((ROOT/'tools/reproduction').glob('*.py'))
    files.update((ROOT/'tools/reproduction').glob('*.txt'))
    files.update((ROOT/'tb/audit').glob('*.sv'))
    resources = {}
    for suite in dict.fromkeys(('frozen-threads4', 'rebuilt-threads4', 'rebuilt-continuation', a.rebuilt)):
        files.add(root/suite/'suite.json')
        resources[suite] = {}
        for command in sorted((root/suite).glob('*/command.json')):
            item = read(command); files.add(command)
            measured = command.parent/'resources.txt'
            row = {k:item.get(k) for k in ('status','returncode','wall_seconds','timeout_seconds','sampled_resources')}
            if measured.exists():
                files.add(measured); text = measured.read_text()
                peak = re.search(r'Maximum resident set size \(kbytes\): (\d+)', text)
                elapsed = re.search(r'Elapsed .*?: ([^\n]+)', text)
                row.update(gnu_time_max_rss_kib=int(peak.group(1)) if peak else None,
                           gnu_time_elapsed=elapsed.group(1) if elapsed else None)
            resources[suite][command.parent.name] = row
        for name in ('comparison.json','asset-comparison.json','relocation.json'):
            if (root/suite/name).exists(): files.add(root/suite/name)
        for case in ('cancel','fault','positive'):
            for name in ('summary.json','progress.json'):
                if (root/suite/case/name).exists(): files.add(root/suite/case/name)
    for folder in ('architecture-bundle','cpu-architecture-bundle'):
        manifest = root/folder/'manifest.json'; files.add(manifest)
        for entry in read(manifest)['files']:
            path = root/folder/entry['file']; assert sha(path) == entry['sha256']
            files.add(path)
    for entry in read(root/'simulator-archives/manifest.json')['simulators'].values():
        path = ROOT/entry['archived_path']; assert sha(path) == entry['sha256']; files.add(path)
    files.update((root/a.final_checks/'capacity-local-results').glob('*.json'))
    save(output, dict(status='completed_preparation_with_deferred_positive' if a.deferred_positive else 'completed_reproduction_and_rewrite_preparation', created_at=utc(),
        run=root.name, acceptance_report=str(final.relative_to(ROOT)),
        full_reproduction_passed=not a.deferred_positive,
        deferred_items=['Source-rebuilt firmware full positive RTL acceptance'] if a.deferred_positive else [],
        source_continuation=f'rebuilt-threads4 retains the metadata-comparison failure; rebuilt-continuation retains an interrupted positive run. Final selected suite: {a.rebuilt}; earlier completed stages are explicitly reused.',
        resources=resources,
        limits=['OOC sources/reports audited; no Vivado rerun, placement/routing or board execution.',
                'Architecture candidates remain partial and unapproved; no browser visual acceptance.',
                'Native/ISA/RTL consistency does not replace independent model quality evaluation.',
                'Dirty-slot tests are finite ISA experiments; capacity results are a synthetic cost model.',
                'Research novelty, real user workloads, causal stall attribution and physical DDR performance remain unproven.',
                'GNU time and Python monotonic durations differ; both are preserved.'],
        files={str(path.relative_to(ROOT)):dict(sha256=sha(path),bytes=path.stat().st_size)
               for path in sorted(files)}))
    print(output)


if __name__ == '__main__': main()

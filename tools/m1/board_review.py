"""Collect read-only physical evidence from the final board; never approves or programs it."""
import argparse
import json
import shutil
import sys
from pathlib import Path
import host

sys.path.insert(0, str(host.ROOT / 'tools/reproduction'))
import recorded


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('build', 'vivado', 'output'):
        p.add_argument('--' + name, type=Path, required=True)
    a = p.parse_args()
    build = a.build.resolve()
    assert json.loads((build / 'summary.json').read_text())['status'] == 'routed_requires_review'
    checkpoint = build / 'work/implementation-result.dcp'
    out = a.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    script = out / 'review_board.tcl'
    shutil.copy2(host.ROOT / 'platform/m1/prodigy/review_board.tcl', script)
    summary = dict(status='running', board_acceptance_passed=False, program_allowed=False,
                   build_summary_sha256=host.sha(build / 'summary.json'),
                   checkpoint_sha256=host.sha(checkpoint))
    host.save(out / 'summary.json', summary)
    recorded.ROOT = out
    try:
        rc = recorded.run(out / 'record', [a.vivado.resolve(), '-mode', 'batch', '-source', script,
                          '-tclargs', checkpoint], 1800, [checkpoint, script, build / 'summary.json'])
        assert rc == 0, 'Physical evidence collection failed; retain first failure'
        assert 'M1_BOARD_READONLY_REVIEW_REPORTS_NOT_ACCEPTANCE' in (out / 'record/stdout.log').read_text()
        summary.update(status='collected_requires_physical_review',
                       files=[dict(path=f.name, sha256=host.sha(f)) for f in sorted(out.iterdir())
                              if f.is_file() and f.suffix in ('.tsv', '.rpt', '.tcl')])
    except BaseException as e:
        summary.update(status='failed', error=repr(e))
        raise
    finally:
        summary['finished_at'] = host.utc()
        host.save(out / 'summary.json', summary)


if __name__ == '__main__':
    main()

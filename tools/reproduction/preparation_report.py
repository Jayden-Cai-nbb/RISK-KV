"""Finish audit evidence after explicit deferral, without claiming full source replay."""
import argparse
import json
from pathlib import Path
import sys
from compare_assets import compare as compare_assets
from compare_replays import compare as compare_case
from recorded import ROOT, run, save, sha, snapshot_tooling, utc


def read(path):
    return json.loads(path.read_text())


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--run',type=Path,required=True)
    p.add_argument('--rebuilt',default='rebuilt-retry-20261104')
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();root=a.run.resolve();out=a.output.resolve();suite=root/a.rebuilt
    out.mkdir(parents=True,exist_ok=False)
    state=dict(status='checking',started_at=utc(),stages={},full_reproduction_passed=False,
               tooling_sha256=snapshot_tooling(out))
    save(out/'summary.json',state)
    def stage(name,argv):
        rc=run(out/name,argv,600);state['stages'][name]=rc;save(out/'summary.json',state)
        if rc:raise RuntimeError(name)
    try:
        assert read(root/'user-deferral.json')['status']=='authorized_deferral'
        assert read(suite/'suite.json')['status']=='deferred_by_user'
        assert read(root/'frozen-threads4/suite.json')['status']=='passed'
        frozen=read(root/'frozen-threads4/comparison.json')
        assert frozen['status']=='passed' and frozen['require_identical_cycles']
        selected=read(suite/'suite.json')
        assets=compare_assets(Path(selected['reference_directory']),Path(selected['input_image']))
        save(out/'asset-comparison.json',assets);assert assets['status']=='passed'
        failures={}
        for case in ('cancel','fault'):
            result,_=compare_case(case,suite/case,suite/'firmware'/case)
            assert result['semantics_equal'];failures[case]=result
        save(out/'rebuilt-failure-comparison.json',dict(status='passed',cases=failures))
        stage('capacity-local',[sys.executable,ROOT/'tools/reproduction/capacity_study.py',
            '--metrics',root/'frozen-threads4/positive-metrics.json','--output',out/'capacity-local-results'])
        stage('integrity-after',[sys.executable,ROOT/'tools/verify_handoff.py','--data'])
        state.update(status='passed_preparation_with_user_deferral',
            frozen_full_replay=True,rebuilt_assets_equal=True,rebuilt_cancel_fault=True,
            rebuilt_full_positive=False,source_chain_acceptance='incomplete_by_user_deferral',
            deferral_sha256=sha(root/'user-deferral.json'),
            scope='Preparation report only. No full source-rebuilt RTL acceptance, no architecture approval, no board result.')
    except BaseException as ex:
        state.update(status='failed',error=f'{type(ex).__name__}: {ex}');raise
    finally:
        state['finished_at']=utc();save(out/'summary.json',state)


if __name__=='__main__':main()

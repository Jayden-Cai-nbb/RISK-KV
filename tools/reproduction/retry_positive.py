"""Replay only the interrupted full positive case; retain completed stage evidence."""
import argparse
import json
from pathlib import Path
import sys
from compare_assets import compare as compare_assets
from compare_replays import compare as compare_case
from recorded import ROOT, run, save, sha, snapshot_tooling, utc


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--prior',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();prior=a.prior.resolve();out=a.output.resolve()
    out.mkdir(parents=True,exist_ok=False)
    previous=json.loads((prior/'suite.json').read_text())
    state=dict(status='running',started_at=utc(),stages={},tooling_sha256=snapshot_tooling(out),
        prior_suite=str(prior),prior_suite_sha256=sha(prior/'suite.json'),
        reference_directory=previous['reference_directory'],input_image=previous['input_image'],
        reused_stages={},host_default=True,sim_threads=4)
    save(out/'suite.json',state)
    def stage(name,command,timeout=25200):
        rc=run(out/(name+'-command'),command,timeout)
        state['stages'][name]=rc;save(out/'suite.json',state)
        if rc:raise RuntimeError(name)
    try:
        assert previous['status']=='interrupted_process_missing'
        assert previous['stages']['rtl-cancel']==previous['stages']['rtl-fault']==0
        stage('integrity-before',[sys.executable,ROOT/'tools/verify_handoff.py','--data'],600)
        ref=Path(state['reference_directory']);image=Path(state['input_image'])
        assets=compare_assets(ref,image);save(out/'asset-comparison.json',assets)
        assert assets['status']=='passed'
        for case in ('cancel','fault'):
            check,_=compare_case(case,prior/case,prior/'firmware'/case)
            assert check['semantics_equal']
            save(out/(case+'-reused-comparison.json'),check)
        for name in ('firmware','cancel','fault','firmware-positive-command',
                     'firmware-cancel-command','firmware-fault-command','rtl-cancel-command','rtl-fault-command'):
            (out/name).symlink_to(Path('..')/prior.name/name,target_is_directory=True)
            state['reused_stages'][name]=dict(path=str(prior/name),
                evidence_sha256=sha(prior/name/('command.json' if name.endswith('-command') else
                    'summary.json' if name in ('cancel','fault') else 'positive/manifest.json')))
        save(out/'suite.json',state)
        stage('rtl-positive',[sys.executable,ROOT/'tools/reproduction/npu_host.py',
            '--record',out/'positive-host','--default-cxx','--sim-threads','4','--',
            '--source',ROOT/'vendor/openTPU','--reference',ref,'--firmware',prior/'firmware/positive',
            '--platform',prior/'platform','--output',out/'positive','--input',image])
        stage('integrity-after',[sys.executable,ROOT/'tools/verify_handoff.py','--data'],600)
        assert sha(prior/'suite.json')==state['prior_suite_sha256']
        assert compare_assets(ref,image)['status']=='passed'
        state['status']='passed'
    except BaseException as ex:
        state.update(status='failed',error=f'{type(ex).__name__}: {ex}');raise
    finally:
        state['finished_at']=utc();save(out/'suite.json',state)


if __name__=='__main__':main()

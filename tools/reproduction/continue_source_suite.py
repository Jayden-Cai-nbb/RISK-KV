"""Continue the preserved post-reference metadata failure using its completed outputs."""
import argparse
import json
from pathlib import Path
import sys
from recorded import ROOT, run, save, sha, snapshot_tooling, utc
from compare_assets import compare
from source_suite import equal_files


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--prior',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--toolchain',type=Path,required=True)
    a=p.parse_args(); prior=a.prior.resolve(); out=a.output.resolve()
    out.mkdir(parents=True,exist_ok=False)
    state=dict(status='running',started_at=utc(),stages={},
        tooling_sha256=snapshot_tooling(out),prior_suite=str(prior),
        prior_suite_sha256=sha(prior/'suite.json'),host_default=True,sim_threads=4)
    save(out/'suite.json',state)
    def stage(name,command,timeout=25200):
        rc=run(out/(name+'-command'),command,timeout)
        state['stages'][name]=rc;save(out/'suite.json',state)
        if rc:raise RuntimeError(name)
    try:
        previous=json.loads((prior/'suite.json').read_text())
        assert previous['status']=='failed' and previous['stages']=={'input':0,'reference':0}
        for name in ('input','reference'):
            command=json.loads((prior/(name+'-command')/'command.json').read_text())
            assert command['status']=='completed' and command['returncode']==0
        refs=list(prior.glob('reference-*/summary.json'));assert len(refs)==1
        ref=refs[0].parent;image=prior/'input/reference-dram-input.bin'
        assert equal_files(image,prior/'input/dram-input.bin')
        assets=compare(ref,image);save(out/'asset-comparison.json',assets)
        assert assets['status']=='passed'
        state.update(reference_directory=str(ref),input_image=str(image),
            completed_source_stages={'suite':str(prior/'suite.json'),'stages':['input','reference']})
        state['stages']['validated-completed-assets']=0;save(out/'suite.json',state)
        for case,failure in [('positive',0),('cancel',1),('fault',2)]:
            stage('firmware-'+case,[sys.executable,ROOT/'tools/prepare_npu_context_firmware.py',
                '--reference',ref,'--toolchain',a.toolchain.resolve(),'--output',out/'firmware'/case,
                '--failure',failure],300)
        for case in ('cancel','fault','positive'):
            stage('rtl-'+case,[sys.executable,ROOT/'tools/reproduction/npu_host.py',
                '--record',out/(case+'-host'),'--default-cxx','--sim-threads','4','--',
                '--source',ROOT/'vendor/openTPU','--reference',ref,'--firmware',out/'firmware'/case,
                '--platform',out/'platform','--output',out/case,'--input',image])
        stage('integrity-after',[sys.executable,ROOT/'tools/verify_handoff.py','--data'],600)
        assert sha(prior/'suite.json')==state['prior_suite_sha256']
        assert compare(ref,image)['status']=='passed'
        state['status']='passed'
    except BaseException as ex:
        state.update(status='failed',error=f'{type(ex).__name__}: {ex}');raise
    finally:
        state['finished_at']=utc();save(out/'suite.json',state)


if __name__=='__main__': main()

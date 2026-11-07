"""Generate paired bit/ltx from the actual final routed checkpoint; never programs hardware."""
import argparse,json,shutil,sys
from pathlib import Path
import host
sys.path.insert(0,str(host.ROOT/'tools/reproduction'))
import recorded

def main():
    p=argparse.ArgumentParser(description=__doc__)
    for n in ('build','vivado','output'):p.add_argument('--'+n,type=Path,required=True)
    a=p.parse_args();build=json.loads((a.build/'summary.json').read_text());assert build['status']=='routed_requires_review'
    out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
    checkpoint=(a.build/'work/implementation-result.dcp').resolve();script=out/'write_board_bit.tcl'
    shutil.copy2(host.ROOT/'platform/m1/prodigy/write_board_bit.tcl',script)
    summary=dict(status='running',board_acceptance_passed=False,program_allowed=False,build_summary_sha256=host.sha(a.build/'summary.json'),checkpoint_sha256=host.sha(checkpoint))
    recorded.ROOT=out
    try:
        rc=recorded.run(out/'record',[a.vivado.resolve(),'-mode','batch','-source',script,'-tclargs',checkpoint],1800,[checkpoint,script,a.build/'summary.json'])
        assert rc==0,'Bitgen guard failed; preserve first failure'
        assert 'M1_EXPERIMENTAL_BOARD_BIT_GENERATED_REQUIRES_PHYSICAL_REVIEW_AND_ACCEPTANCE' in (out/'record/stdout.log').read_text()
        summary.update(status='paired_bit_generated_not_program_qualified',artifacts={n:host.sha(out/n) for n in ('rkv-m1-board.bit','rkv-m1-board.ltx')})
    except BaseException as e:summary.update(status='failed',error=repr(e));raise
    finally:summary['finished_at']=host.utc();host.save(out/'summary.json',summary)
if __name__=='__main__':main()

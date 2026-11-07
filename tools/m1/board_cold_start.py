"""Explicit full FPGA reconfiguration after service/isolation. Invalidates all image/session trust."""
import argparse,fcntl,json,shutil,sys,time,uuid
from pathlib import Path
import host
from board_qualify import verify_step
from board_suite import qualified_input
from experimental_acceptance import require_experimental_profile
from jtag_transport import digest,durable_json,durable_bytes
sys.path.insert(0,str(host.ROOT/'tools/reproduction'))
import recorded

def main():
    p=argparse.ArgumentParser(description=__doc__)
    for n in ('platform','qualification','previous-state','previous-ltx','output'):p.add_argument('--'+n,type=Path,required=True)
    p.add_argument('--previous-state-sha256',required=True)
    p.add_argument('--reason',required=True,help='Recorded reason for discarding all prior in-flight state and memory trust')
    a=p.parse_args();assert 1<=len(a.reason)<=300
    cfg=json.loads(a.platform.read_text());require_experimental_profile(cfg);qualified_input(a.qualification,cfg)
    review=json.loads(Path(cfg['physical_review']).read_text());require_experimental_profile(review);assert review['status']=='reviewed_passed'
    for name in ('bit','ltx'):assert digest(cfg[name])==cfg[name+'_sha256']==review[name+'_sha256']
    for name in ('part','experiment_id','firmware_sha256','vivado_version'):assert cfg[name]==review[name]
    for name in ('unconstrained_required_paths','unresolved_cdc','unresolved_reset','drc_errors','drc_critical_warnings'):assert review[name]==0
    for name in ('setup_slack_ns','hold_slack_ns'):assert review[name]>=0
    for name in ('clock_phase_verified','all_external_paths_reviewed','exceptions_have_evidence','source_manifest_matches','bit_ltx_paired'):assert review[name] is True
    for item in review['files']:assert digest(Path(cfg['physical_review']).parent/item['path'])==item['sha256']
    out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
    journal=Path(cfg['state_path']);receipt=Path(cfg['cold_start_receipt'])
    assert not journal.exists() and not receipt.exists(),'Fresh receipt/journal paths required; do not clear the old journal'
    state=dict(status='running',incarnation=uuid.uuid4().hex,reason=a.reason,started_ns=time.time_ns(),bit_sha256=cfg['bit_sha256'],ltx_sha256=cfg['ltx_sha256'],scope='whole FPGA reconfiguration; pending old transactions are discarded, not claimed retired; full reload required',board_acceptance_passed=False)
    with Path(cfg['owner_lock_path']).open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        assert digest(a.previous_state)==a.previous_state_sha256
        old=json.loads(a.previous_state.read_text());identity=old['identity']
        assert identity['profile']=='m1_experimental_board' and identity['target_serial']==cfg['target_serial']
        assert digest(a.previous_ltx)==identity['ltx_sha256']
        assert old['status'] in ('NEW','READY','PENDING','QUARANTINED','RECOVERING')
        durable_bytes(out/'previous-state.json',a.previous_state.read_bytes())
        old.update(status='QUARANTINED',image=dict(status='INVALIDATED_BEFORE_WHOLE_CHAIN_RESET'),superseded_by=str(journal),cold_reset_reason=a.reason)
        durable_json(a.previous_state,old);durable_json(out/'summary.json',state)
        try:
            for name in ('board_qualify.tcl','vio_access.tcl'):shutil.copy2(host.ROOT/'platform/m1/prodigy'/name,out/name)
            c=dict(name='cold-recovery-window',base=0xfc0,blocks=128,seconds=0,seed=0x65a51c3d)
            durable_json(out/'configuration.json',c);recorded.ROOT=out
            cmd=[cfg['vivado'],'-mode','batch','-source',out/'board_qualify.tcl','-tclargs',cfg['bit'],cfg['ltx'],a.previous_ltx.resolve(),'0x44445251',c['base'],c['blocks'],0,c['seed'],1,'explicit_full_chain_reset']
            assert recorded.run(out/'record',cmd,900,[a.platform,cfg['bit'],cfg['ltx'],out/'board_qualify.tcl',out/'vio_access.tcl'])==0
            result=verify_step(out,c);assert (out/'service-handover.tsv').is_file()
            identity={k:cfg[k] for k in ('profile','target_serial','bit_sha256','ltx_sha256','memory_bytes')}
            journal.parent.mkdir(parents=True,exist_ok=True);receipt.parent.mkdir(parents=True,exist_ok=True)
            durable_json(journal,dict(schema=1,identity=identity,status='NEW',sequence=0,pending=None,first_failure=None,last_completion=None,incarnation=state['incarnation'],image=dict(status='UNKNOWN')))
            durable_json(receipt,dict(status='programmed_qualified_and_released',bit_sha256=cfg['bit_sha256'],ltx_sha256=cfg['ltx_sha256'],incarnation=state['incarnation'],qualification_summary=str(a.qualification.resolve()),qualification_sha256=digest(a.qualification),cold_start_summary=str(out/'summary.json')))
            state.update(status='cold_reconfigured_contents_invalid',result=result,next_action='full image/template write and readback before releasing CPU')
        except BaseException as e:state.update(status='failed_quarantined',error=repr(e));raise
        finally:
            state['finished_ns']=time.time_ns();state['files']=[dict(path=str(f.relative_to(out)),bytes=f.stat().st_size,sha256=digest(f)) for f in sorted(out.rglob('*')) if f.is_file() and f.name!='summary.json'];durable_json(out/'summary.json',state)
if __name__=='__main__':main()

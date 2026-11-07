"""Final-bit DDR qualification only: fixed 10 cold starts/full range/stress, stop first failure."""
import argparse,csv,fcntl,json,shutil,struct,sys,time,uuid
from pathlib import Path
import host
from jtag_transport import durable_json,durable_bytes,digest
from experimental_acceptance import require_experimental_profile
sys.path.insert(0,str(host.ROOT/'tools/reproduction'))
import recorded

def verify_step(step,cfg):
    result={k:int(v) for k,v in (x.split('\t') for x in (step/'batch-result.tsv').read_text().splitlines())}
    for k in ('base','blocks','seed'):assert result[k]==cfg[k],k
    assert result['rounds']>=1 and result['per_channel_count']==result['rounds']*3*cfg['blocks']
    assert 'Overall Status:  CAL PASS' in (step/'mig-final.txt').read_text()
    rows=list(csv.DictReader((step/'host-peeks.tsv').open(),delimiter='\t'));assert len(rows)>=3
    for row in rows:
        a,s,r=(int(row[k]) for k in ('address','seed','round'))
        assert cfg['base']<=a<cfg['base']+64*cfg['blocks'] and s==cfg['seed'] and r==result['rounds']-1
        ref=[]
        for i in range(16):
            x=a^s^r^((0x9e3779b9*i)&0xffffffff);x=(x^(x<<13))&0xffffffff;x^=x>>17;x=(x^(x<<5))&0xffffffff;ref.append(x)
        assert (step/f"peek-{int(row['index']):03}.bin").read_bytes()==struct.pack('<16I',*ref)
    final={int(k):int(v) for k,v in (line.split('\t') for line in (step/'final.tsv').read_text().splitlines()[2:])}
    count=result['per_channel_count'];assert final[2]&0x1f==9
    assert final[6]==count+len(rows)
    for shift in (0,48,96,144):assert (final[5]>>shift)&((1<<48)-1)==count+(len(rows) if shift==0 else 0)
    if cfg['seconds']:assert result['host_run_ms']>=1800000 and result['seconds']>=1800
    return dict(name=cfg['name'],status='passed',result=result,independent_host_peeks=len(rows))

def main():
    p=argparse.ArgumentParser(description=__doc__)
    for n in ('platform','previous-state','previous-ltx','output'):p.add_argument('--'+n,type=Path,required=True)
    p.add_argument('--previous-state-sha256',required=True);a=p.parse_args()
    cfg=json.loads(a.platform.read_text());require_experimental_profile(cfg)
    review=json.loads(Path(cfg['physical_review']).read_text());require_experimental_profile(review)
    assert review['status']=='reviewed_passed'
    for n in ('bit','ltx'):assert digest(cfg[n])==cfg[n+'_sha256']==review[n+'_sha256']
    assert review['part']==cfg['part'] and review['experiment_id']==cfg['experiment_id']
    for n in ('unconstrained_required_paths','unresolved_cdc','unresolved_reset','drc_errors','drc_critical_warnings'):assert review[n]==0,n
    for n in ('setup_slack_ns','hold_slack_ns'):assert review[n]>=0
    for f in review['files']:assert digest(Path(cfg['physical_review']).parent/f['path'])==f['sha256']
    out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
    windows=[(0xfc0,128),(0x7ffff000,64),(0,1024),(0x100000,1024),(0x1000000,1024),(0x10000000,1024),(0x20000000,1024),(0x40000000,1024),(0x60000000,1024),(0x7fff0000,1024)]
    plan=[dict(name=f'cold-{i+1:02}',base=a,blocks=n,seconds=0,seed=0x12345678^(i*0x1020304)) for i,(a,n) in enumerate(windows)]
    plan += [dict(name='full-2gib',base=0,blocks=33554432,seconds=0,seed=0x13579bdf),dict(name='stress-30min',base=0,blocks=33554432,seconds=1830,seed=0x2468ace0)]
    durable_json(out/'plan.json',plan)
    journal=Path(cfg['state_path']);receipt=Path(cfg['cold_start_receipt'])
    assert not journal.exists() and not receipt.exists(),'New run paths required; no implicit recovery/retry'
    state=dict(status='running',bit_sha256=cfg['bit_sha256'],ltx_sha256=cfg['ltx_sha256'],steps=[],incarnation=uuid.uuid4().hex,started_ns=time.time_ns(),board_acceptance_passed=False)
    with Path(cfg['owner_lock_path']).open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        assert digest(a.previous_state)==a.previous_state_sha256,'Old hardware journal changed'
        old=json.loads(a.previous_state.read_text())
        assert old['status']=='DDR_DATA_TEST_SUITE_PASSED_WITH_OPEN_PLATFORM_QUALIFICATION','Only known drained diagnostic chain may enter this workflow'
        durable_bytes(out/'previous-state.json',a.previous_state.read_bytes())
        old.update(status='SUPERSEDED_BY_FINAL_BOARD_QUALIFICATION',superseded_by=str(out));durable_json(a.previous_state,old)
        oldltx=a.previous_ltx.resolve()
        try:
            for i,c in enumerate(plan):
                step=out/c['name'];step.mkdir()
                for name in ('board_qualify.tcl','vio_access.tcl'):shutil.copy2(host.ROOT/'platform/m1/prodigy'/name,step/name)
                durable_json(step/'configuration.json',c);state['current_step']=c['name'];durable_json(out/'summary.json',state)
                recorded.ROOT=step
                cmd=[cfg['vivado'],'-mode','batch','-source',step/'board_qualify.tcl','-tclargs',cfg['bit'],cfg['ltx'],oldltx,'0x44445251',c['base'],c['blocks'],c['seconds'],c['seed'],int(i==len(plan)-1)]
                rc=recorded.run(step/'record',cmd,c['seconds']+900,[cfg['bit'],cfg['ltx'],a.platform,step/'board_qualify.tcl',step/'vio_access.tcl',step/'configuration.json'])
                assert rc==0 and 'M1_FINAL_BIT_DDR_BATCH_PASSED_NOT_MODEL_ACCEPTANCE' in (step/'record/stdout.log').read_text(),'First failure retained; stop'
                entry=verify_step(step,c);durable_json(step/'verification.json',entry);state['steps'].append(entry);oldltx=Path(cfg['ltx'])
                print(json.dumps(entry),flush=True)
            assert (out/'stress-30min/service-handover.tsv').is_file()
            identity={k:cfg[k] for k in ('profile','target_serial','bit_sha256','ltx_sha256','memory_bytes')}
            journal.parent.mkdir(parents=True,exist_ok=True);receipt.parent.mkdir(parents=True,exist_ok=True)
            durable_json(journal,dict(schema=1,identity=identity,status='NEW',sequence=0,pending=None,first_failure=None,last_completion=None,incarnation=state['incarnation'],image=dict(status='UNKNOWN')))
            state.update(status='passed_final_board_ddr_qualification',configuration_cold_starts_passed=10,physical_power_cycles_tested=0,full_2gib_data_passed=True,stress_30min_passed=True)
            durable_json(receipt,dict(status='programmed_qualified_and_released',bit_sha256=cfg['bit_sha256'],ltx_sha256=cfg['ltx_sha256'],incarnation=state['incarnation'],qualification_summary=str(out/'summary.json')))
        except BaseException as e:state.update(status='failed_stopped',error=repr(e));raise
        finally:
            state['finished_ns']=time.time_ns()
            state['files']=[dict(path=str(f.relative_to(out)),bytes=f.stat().st_size,sha256=digest(f)) for f in sorted(out.rglob('*')) if f.is_file() and f.name!='summary.json']
            durable_json(out/'summary.json',state)
if __name__=='__main__':main()

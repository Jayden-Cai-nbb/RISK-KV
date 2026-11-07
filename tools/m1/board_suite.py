"""One exclusive live session: final-bit DDR host checks, full load and ordered M1 subsets."""
import argparse,hashlib,importlib.util,json,os,shutil,sys,time,uuid
from pathlib import Path
import host
from experimental_acceptance import require_experimental_profile
from jtag_transport import digest

STAGES=('ddr','load','smoke','continuous','faults','benchmark','isolation')

def qualified_input(path,cfg):
    q=json.loads(path.read_text())
    assert q['status']=='passed_final_board_ddr_qualification'
    assert q['bit_sha256']==cfg['bit_sha256'] and q['ltx_sha256']==cfg['ltx_sha256']
    assert q['configuration_cold_starts_passed']>=10 and q['full_2gib_data_passed'] and q['stress_30min_passed']
    assert len(q['steps'])>=12 and all(x['status']=='passed' for x in q['steps'])
    for item in q['files']:
        f=path.parent/item['path'];assert f.stat().st_size==item['bytes'] and digest(f)==item['sha256']
    return q

def ddr_host_checks(driver,layout,out):
    """Supplement same-bit full BIST with the actual host path, masks and boundary ordering."""
    driver.hold_cold_boot();assert driver.observe()['host_write_grant']
    size=layout['logical_bytes'];addresses={0,size-128,layout['kv_base'],layout['kv_base']+layout['prefix_bytes'],layout['scratch_template_base']}
    addresses.update(p['address'] for p in layout['programs'].values());addresses.update(a for a,_ in layout['scratch_restore'])
    rows=[]
    for base in sorted(addresses):
        base &= ~127
        for index,mask in enumerate((bytes([0,1])*64,bytes([1,0])*64,bytes([1])*128,bytes(128))):
            driver.memory_write(base,bytes([0xa5])*128)
            driver.memory_write_masked(base,bytes(range(128)),mask)
            expected=bytes(i if mask[i] else 0xa5 for i in range(128))
            host.checked_read(driver,base,expected,out/f'mask-{base:08x}-{index}.bin')
            rows.append(dict(address=base,mask=mask.hex()))
        if base+4096+129<=size:
            for boundary in (32,64,128,4096):
                address=base+boundary-3;expected=bytes(range(131))
                driver.memory_write(address,expected)
                host.checked_read(driver,address,expected,out/f'boundary-{base:08x}-{boundary}.bin')
    # Small actual throughput measurement before the 1.61GB load; preserves the full load requirement.
    payload=bytes((i*73+19)&255 for i in range(1<<20));begin=time.monotonic()
    driver.memory_write(0x100000,payload);written=time.monotonic()
    host.checked_read(driver,0x100000,payload,out/'throughput-1mib.bin');end=time.monotonic()
    obs=driver.observe();assert obs['host_idle'] and obs['transport_idle'] and not obs['isolated']
    result=dict(status='passed_host_masks_boundaries_and_bulk',masks=rows,observation=obs,
        bulk_bytes=len(payload),write_seconds=written-begin,read_seconds=end-written,
        projected_full_cold_write_read_seconds=(end-begin)*layout['cold_image_bytes']/len(payload),projection_includes_templates=False)
    host.save(out/'ddr-host.json',result);return result

def main():
    p=argparse.ArgumentParser(description=__doc__)
    for n in ('platform','qualification','reference','output'):p.add_argument('--'+n,type=Path,required=True)
    p.add_argument('--stop-after',choices=STAGES,default='isolation',help='Explicit staged stop is never full acceptance')
    a=p.parse_args();cfg=json.loads(a.platform.read_text());require_experimental_profile(cfg);assert cfg['state']=='bound'
    q=qualified_input(a.qualification,cfg);ref=host.checked_reference(a.reference)
    layout=json.loads((host.ROOT/'configs/m1/layout.json').read_text())
    out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
    cfg=dict(cfg);cfg['session_output']=str(out/'vivado-session')
    summary=dict(status='running',run_id=out.name+'-'+uuid.uuid4().hex[:12],started_at=host.utc(),stages=[],board_acceptance_passed=False)
    host.save(out/'summary.json',summary);driver=None;client=None
    try:
        spec=importlib.util.spec_from_file_location('rkv_board_driver',Path(cfg['driver']).resolve());module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        driver=module.open(cfg);info=driver.describe();host.validate_platform(cfg,info,layout)
        def progress():host.save(out/'live-status.json',dict(run_id=summary['run_id'],stage=summary.get('current_stage'),observed_ns=time.time_ns(),observation=driver.observe()))
        for stage in STAGES:
            dest=out/stage;dest.mkdir();summary['current_stage']=stage;host.save(out/'summary.json',summary)
            host.save(dest/'reference-input.json',ref)
            if stage=='continuous':
                import numpy as np
                for gi,g in enumerate(ref['pairs']):
                    for si,step in enumerate(g['steps']):shutil.copy2(a.reference/step['logits_file'],dest/f'reference-logits-{gi}-{si}.npy')
                host.save(dest/'raw-reference-sha256.json',[[hashlib.sha256(np.load(a.reference/step['logits_file'],allow_pickle=False).tobytes()).hexdigest() for step in g['steps']] for g in ref['pairs']])
            report=dict(status='running',command=stage,started_at=host.utc(),platform=cfg,hardware=info,platform_sha256=digest(a.platform),layout_sha256=digest(host.ROOT/'configs/m1/layout.json'),driver_sha256=digest(cfg['driver']),reference_sha256=digest(a.reference/'summary.json'),run_id=summary['run_id'],board_acceptance_passed=False)
            try:
                if stage=='ddr':
                    result=ddr_host_checks(driver,layout,dest)
                    host.save(dest/'ddr.json',dict(status='passed_final_bit_bist_and_host',qualification=q,qualification_sha256=digest(a.qualification),host=result))
                    report['status']='passed_ddr_subset'
                    print(json.dumps(dict(stage=stage,projection=result)),flush=True)
                elif stage=='load':
                    def load_progress(name,done,total):
                        progress();host.save(out/'load-progress.json',dict(name=name,verified_bytes=done,total_bytes=total,time_ns=time.time_ns()))
                    host.load_and_verify(driver,layout,dest,progress=load_progress);report['status']='image_loaded_and_verified'
                    client=host.Mailbox(driver,layout,progress=progress);client.operation('BOOT')
                elif stage=='smoke':
                    host.build_prefix(client,a.reference,dest,1);report.update(status='passed_four_token_full_kv',valid_kv_bytes=236544)
                    client.operation('RETIRE')
                elif stage=='continuous':
                    host.build_prefix(client,a.reference,dest)
                    for i in range(100):host.query_pair(client,a.reference,ref['pairs'][i%2],dest/f'batch-{i:03d}')
                    for i in range(10):
                        client.operation('RETIRE');d=dest/f'rebuild-{i:02d}';d.mkdir();host.build_prefix(client,a.reference,d)
                        host.query_pair(client,a.reference,ref['pairs'][i%2],d/'query',check_immutable=(i==9))
                    client.operation('RETIRE');report.update(status='passed_continuous_subset',batches=100,rebuilds=10)
                elif stage=='faults':
                    client=host.fault_matrix(client,a.reference,ref,dest);report['status']='passed_retiring_faults_subset'
                elif stage=='benchmark':
                    host.benchmark(client,a.reference,ref,dest,30);report.update(status='measured_not_functional_acceptance',samples=60)
                elif stage=='isolation':
                    host.isolation_test(client,dest);report['status']='passed_isolation_subset'
            except BaseException as e:
                report.update(status='failed',error=repr(e));raise
            finally:
                report['finished_at']=host.utc()
                report['files']=[dict(path=str(f.relative_to(dest)),bytes=f.stat().st_size,sha256=digest(f)) for f in sorted(dest.rglob('*')) if f.is_file() and f.name!='report.json']
                if stage=='ddr':
                    for item in q['files']:
                        f=(a.qualification.parent/item['path']).resolve();report['files'].append(dict(path=os.path.relpath(f,dest),bytes=f.stat().st_size,sha256=digest(f)))
                host.save(dest/'report.json',report)
            summary['stages'].append(dict(name=stage,status=report['status'],report_sha256=digest(dest/'report.json')));host.save(out/'summary.json',summary)
            print(json.dumps(dict(stage=stage,status=report['status'])),flush=True)
            if stage==a.stop_after:break
        summary['status']='all_subsets_completed_requires_acceptance' if a.stop_after=='isolation' else 'staged_stop_not_acceptance'
    except BaseException as e:
        summary.update(status='failed_stopped',error=repr(e));raise
    finally:
        if driver:driver.close()
        summary['finished_at']=host.utc();host.save(out/'summary.json',summary)
if __name__=='__main__':main()

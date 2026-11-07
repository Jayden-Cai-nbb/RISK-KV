"""Real CPU/NPU full-page build, seal, bind, continuation and safe retirement.

The full positive run is intentionally long. progress.json and simulation.log
are updated while it runs; no KV/reference answer is injected into the input.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time

ROOT=Path(__file__).resolve().parents[1]
def sha(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def write_json(p,value):
    temporary=p.with_suffix(p.suffix+'.tmp');temporary.write_text(json.dumps(value,indent=2)+'\n');temporary.replace(p)

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',type=Path,required=True);p.add_argument('--reference',type=Path,required=True)
    p.add_argument('--firmware',type=Path,required=True);p.add_argument('--platform',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--input',type=Path,default=ROOT/'assets/data/dram-input.bin');p.add_argument('--timeout-seconds',type=int,default=21600);a=p.parse_args()
    src=a.source.resolve();ref=a.reference.resolve();fw=a.firmware.resolve();platform=a.platform.resolve();out=a.output.resolve()
    assert subprocess.check_output(['git','-C',str(src),'rev-parse','HEAD'],text=True).strip()=='91df41092f612361c5bc22f83b31d23382ffabb0'
    # Release archives omit the machine-specific index; restore it without changing source files.
    if not (src/'.git/index').exists():subprocess.run(['git','-C',str(src),'read-tree','HEAD'],check=True)
    changed=subprocess.check_output(['git','-C',str(src),'diff','HEAD','--name-only'],text=True).splitlines()
    if changed:
        name='rtl/mxu/otpu_mxu.sv';before=subprocess.check_output(['git','-C',str(src),'show','HEAD:'+name]).replace(b'\r\n',b'\n');after=(src/name).read_bytes().replace(b'\r\n',b'\n')
        assert changed==[name] and after.count(b'rkv_max_sort_key')==4 and after.replace(b'rkv_max_sort_key',b'mk')==before
    r=read(ref/'summary.json');f=read(fw/'manifest.json');assert r['status']=='passed_cold_context_isa' and f['status']=='context_firmware_prepared'
    assert f['reference_sha256']==sha(ref/'summary.json') and sha(fw/'firmware.hex')==f['firmware_hex_sha256']
    for rel,h in f['source_sha256'].items():assert sha(ROOT/rel)==h,rel
    for name,h in f['overlay'].items():assert sha(fw/'control'/name)==h['exported_sha256']
    input_path=a.input.resolve();assert sha(input_path)==r['input_sha256']
    out.mkdir(parents=True,exist_ok=False);sys.path.insert(0,str(src))
    import numpy as np
    from opentpu import rtlsim
    from opentpu.isasim import Config
    from npu_core_profile import load,simulation_parameters
    from npu_sim_memory import install
    from npu_context_harness import export
    profile,ph=load(ROOT/'configs/npu-vu440-core.json');cfg=Config(**profile['architecture']);assert ph==r['profile_sha256']
    image=np.memmap(input_path,mode='r',dtype=np.uint8)
    assert not np.any(image[r['pool_base']:r['pool_base']+r['pool_bytes']]),'Candidate input must contain zero KV'
    del image
    failure=f['configuration']['EXPECT_FAILURE'];report=dict(status='running',phase='build',failure=failure,profile_sha256=ph,
        reference_path=ref.relative_to(ROOT).as_posix(),reference_sha256=sha(ref/'summary.json'),input_sha256=r['input_sha256'],
        initial_kv_all_zero=True,target_tokens=256,firmware_directory=fw.relative_to(ROOT).as_posix(),firmware_manifest_sha256=sha(fw/'manifest.json'),
        platform=platform.relative_to(ROOT).as_posix(),board_execution=False)
    paths=('tools/run_npu_context_build.py','tools/npu_context_harness.py','tools/npu_context_integration.py',
           'rtl/rkv_context_guard.sv','rtl/rkv_npu_context_service.sv','tb/npu_dpi/observe_context.cpp','tb/npu_dpi/observe_logits.cpp')
    hashes={rel:sha(ROOT/rel) for rel in paths}
    for rel in paths:
        target=out/'sources'/rel;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes((ROOT/rel).read_bytes())
    def save():write_json(out/'summary.json',report)
    proc=None
    try:
        if not platform.exists():
            platform.mkdir(parents=True);overlay=export(src,platform/'integration',r)
            manifest=dict(reference_sha256=sha(ref/'summary.json'),source_sha256=hashes,overlay=overlay)
            write_json(platform/'manifest.json',manifest)
        else:
            manifest=read(platform/'manifest.json');assert manifest['reference_sha256']==sha(ref/'summary.json') and manifest['source_sha256']==hashes
            overlay=manifest['overlay']
        for name,h in overlay['control'].items():assert sha(platform/'integration'/name)==h['exported_sha256']
        assert sha(platform/'integration/tb_top.sv')==overlay['tb_sha256']
        report['overlay']=overlay;report['memory_adapter']=install(rtlsim)
        rtlsim.RTL_SOURCES=[str(platform/'integration/otpu_top.sv') if x=='top/otpu_top.sv' else x for x in rtlsim.RTL_SOURCES]
        rtlsim.RTL_SOURCES += [str(ROOT/'vendor/picorv32/picorv32.v')]
        rtlsim.RTL_SOURCES += [str(platform/'integration'/name) for name in ('rkv_npu_control.sv','rkv_npu_io_control.sv','rkv_npu_context_cpu.sv')]
        rtlsim.RTL_SOURCES += [str(ROOT/rel) for rel in ('rtl/rkv_context_guard.sv','rtl/rkv_npu_context_service.sv','tb/npu_dpi/observe_logits.cpp','tb/npu_dpi/observe_context.cpp')]
        rtlsim.TB=platform/'integration';rtlsim.VFLAGS[rtlsim.VFLAGS.index('-j')+1]='2';save();t=time.perf_counter()
        exe=rtlsim.build_top(cfg,8,simulation_parameters(profile),axi=False)
        report.update(phase='simulate',build_seconds=time.perf_counter()-t,simulator_sha256=sha(exe));save()
        print(json.dumps(dict(phase='simulate',failure=failure,build_seconds=report['build_seconds'])),flush=True)
        scratch=ROOT/'build/npu-dpi-runtime';scratch.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='context_npu_',dir=scratch) as td:
            td=Path(td);rtlsim._write_hex(td/'prog_0.hex',np.zeros(cfg.IMEM_WORDS,np.uint32))
            for kind in ('build','decode'):rtlsim._write_hex(td/f'expected_{kind}.hex',np.fromfile(ref/f'{kind}.bin',dtype='<u4'))
            data=np.memmap(input_path,mode='r',dtype='<u4')
            with (td/'dram_0.bin').open('wb') as dst:
                for start in range(0,len(data),16<<20):dst.write(data[start:start+(16<<20)].astype('>u4').tobytes())
            del data
            command=[str(exe),f'+dir={td}',f'+firmware={fw/"firmware.hex"}',f'+failure={failure}','+max_cycles=500000000']
            report['simulation_command']=command;save();start=time.monotonic();logfile=out/'simulation.log'
            progress=dict(status='running',failure=failure,target_tokens=256,built_tokens=0,elapsed_seconds=0,last_event='started')
            with logfile.open('w') as stream:
                proc=subprocess.Popen(command,stdout=stream,stderr=subprocess.STDOUT,text=True)
                report['simulation_pid']=proc.pid;save()
                position=0
                while proc.poll() is None:
                    if time.monotonic()-start>a.timeout_seconds:
                        proc.terminate()
                        try:proc.wait(timeout=20)
                        except subprocess.TimeoutExpired:proc.kill();proc.wait()
                        raise TimeoutError('Full-size run exceeded timeout; no reduced-size fallback')
                    time.sleep(5)
                    with logfile.open() as current:
                        current.seek(position);lines=current.read();position=current.tell()
                    for line in lines.splitlines():
                        if line.startswith('CTX_'):progress['last_event']=line
                        match=re.search(r'CTX_BUILD_COMMIT tokens=(\d+)',line)
                        if match:progress['built_tokens']=int(match[1])
                    progress['elapsed_seconds']=round(time.monotonic()-start,1)
                    write_json(out/'progress.json',progress)
                if proc.returncode:raise RuntimeError(f'Simulator exit {proc.returncode}; inspect simulation.log')
            log=logfile.read_text();report['simulation_wall_seconds']=time.monotonic()-start
            match=re.search(r'CTX_RESULT failure=(\d+) code=(\w+) cycles=(\d+) accepted=(\d+) rejected=(\d+) built=(\d+) decode=(\d+) seals=(\d+) binds=(\d+) safe=1',log)
            if not match:raise AssertionError('No safe lifecycle result')
            assert int(match[1])==failure
            code=int(match[2],16);cycles,accepted,rejected,built,decoded,seals,binds=map(int,match.groups()[2:])
            states=[int(x) for x in re.findall(r'CTX_STATE state=(\d+)',log)]
            commits=[int(x) for x in re.findall(r'CTX_BUILD_COMMIT tokens=(\d+)',log)]
            final_prefix=np.fromfile(td/'prefix-final.bin',dtype=np.uint8);gold=np.fromfile(ref/'reference-prefix.bin',dtype=np.uint8)
            assert len(final_prefix)==len(gold)==r['prefix_bytes']
            final_prefix.tofile(out/'prefix-final.bin')
            memory=np.memmap(td/'dram_out_0.bin',mode='r',dtype=np.uint8);assert len(memory)==cfg.DRAM_BYTES
            h=hashlib.sha256()
            for addr,n in r['immutable_regions']:h.update(memory[addr:addr+n])
            assert h.hexdigest()==r['immutable_sha256']
            steps=[]
            if failure==0:
                assert code==0x600d4000|decoded and (accepted,rejected,built,seals,binds)==(64+decoded,5,256,1,1)
                assert commits==list(range(4,257,4)) and states==[1,2,3,0]
                sealed=np.fromfile(td/'prefix-sealed.bin',dtype=np.uint8);assert sealed.tobytes()==gold.tobytes()==final_prefix.tobytes()
                sealed.tofile(out/'prefix-sealed.bin')
                private=np.fromfile(td/'private-at-bind.bin',dtype=np.uint8);assert len(private)==2*r['prefix_bytes'] and not np.any(private)
                report['private_at_bind_sha256']=hashlib.sha256(private).hexdigest();report['private_at_bind_all_zero']=True
                tokens={}
                for line in log.splitlines():
                    if line.startswith('CTX_TOKEN '):
                        fields=dict(x.split('=') for x in line.split()[1:]);key=(int(fields['seq'],16),int(fields['row']));assert key not in tokens;tokens[key]=int(fields['value'])
                expected=r['runs']['candidate']['steps'];assert decoded==len(expected)==3 and len(tokens)==6
                for i,row in enumerate(expected):
                    outputs=[tokens[65+i,k] for k in (0,1)];assert outputs==row['output_tokens']
                    actual=np.fromfile(td/f'observed-logits-{i+1}.bin',dtype='<f4').reshape(2,151936)
                    reference=np.load(ref/row['logits_file'],allow_pickle=False);assert actual.tobytes()==reference.tobytes() and np.isfinite(actual).all()
                    fn=f'rtl-logits-{i}.npy';np.save(out/fn,actual)
                    steps.append(dict(step=i,input_tokens=row['input_tokens'],output_tokens=outputs,logits_file=fn,logits_sha256=sha(out/fn)))
                assert hashlib.sha256(memory[r['pool_base']:r['pool_base']+r['pool_bytes']]).hexdigest()==r['runs']['candidate']['final_pool_sha256']
                report['final_pool_equal']=True
            else:
                assert code==0x600d3000|failure and (accepted,rejected,built,decoded,seals,binds)==(1,3,0,0,0,0)
                assert commits==[] and states==[1,4,3,0]
                partial=np.zeros_like(gold);offset=0
                for _ in range(28*8):
                    for field,n in [('k',32768),('ks',1024),('vt',32768),('vs',1024)]:
                        if field=='vt':partial[offset:offset+n].reshape(128,256)[:,:4]=gold[offset:offset+n].reshape(128,256)[:,:4]
                        else:
                            valid=4*(128 if field=='k' else 4);partial[offset:offset+valid]=gold[offset:offset+valid]
                        offset+=n
                assert np.any(final_prefix) and final_prefix.tobytes()==partial.tobytes()
                assert not np.any(memory[r['kv_base']+r['prefix_bytes']:r['context_end']])
                report['partial_writes_verified_but_not_sealed']=True
            del memory
            byte_line=next(line for line in log.splitlines() if line.startswith('CTX_BYTES '))
            traffic={k:int(v) for k,v in (x.split('=') for x in byte_line.split()[1:])}
            report.update(status='passed_full_page_lifecycle' if failure==0 else 'passed_failed_build_lifecycle',phase='complete',
                total_control_cycles=cycles,accepted=accepted,rejected=rejected,built_tokens=built,decode_tasks=decoded,
                states=states,build_commits=commits,seals=seals,binds=binds,steps=steps,immutable_equal=True,
                final_prefix_sha256=sha(out/'prefix-final.bin'),traffic_native_requested_bytes=traffic,
                scope='Complete 256-token page, zero initial KV, real CPU/NPU lifecycle; failure cases execute one build batch then refuse seal/bind. No board or service-speed claim.')
            save();progress.update(status=report['status'],built_tokens=built,elapsed_seconds=round(report['simulation_wall_seconds'],1));write_json(out/'progress.json',progress)
            print(json.dumps({k:v for k,v in report.items() if k not in ('overlay','simulation_command','memory_adapter','build_commits')}),flush=True)
    except Exception as ex:
        if proc is not None and proc.poll() is None:proc.terminate();proc.wait(timeout=20)
        report.update(status='failed',error=f'{type(ex).__name__}: {ex}');save();write_json(out/'progress.json',dict(status='failed',error=report['error']))
        raise

if __name__=='__main__':main()

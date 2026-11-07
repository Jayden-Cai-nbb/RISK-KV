"""Prepare complete-page cold KV build and independent native-model references.

Candidate input contains zero KV. Expected built KV/logits are separate evidence
files and are never inserted into the input image.
"""
import argparse
from dataclasses import asdict
import gc
import hashlib
import json
import os
from pathlib import Path
import sys
import time

ROOT=Path(__file__).resolve().parents[1]
def sha(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();src=a.source.resolve();out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
    os.environ.update(HF_HUB_OFFLINE='1',OTPU_FORMATS='',OTPU_IMAGE_CACHE='0',OTPU_IMG_CACHE='0',OTPU_PROG_CACHE='0',OPENBLAS_NUM_THREADS='2',OMP_NUM_THREADS='2')
    sys.path.insert(0,str(src))
    import numpy as np
    import torch
    from transformers import AutoTokenizer
    from opentpu import isa as I
    from opentpu.compiler import Affine,arg_words,k_scale_bytes
    from opentpu.llm.qwen3 import Spec,Engine,load_weights,IsaBackend
    from opentpu.isasim import Config
    from npu_core_profile import load
    from npu_kv_pool import PoolSpec
    from npu_context_programs import ColdContextImage
    from npu_model_contract import WEIGHT_SHA256
    torch.set_num_threads(2);model=ROOT/'models/Qwen3-0.6B-hf';assert sha(model/'model.safetensors')==WEIGHT_SHA256
    profile,ph=load(ROOT/'configs/npu-vu440-core.json');cfg=Config(**profile['architecture']);spec=Spec.from_hf(model)
    tok=AutoTokenizer.from_pretrained(str(model),local_files_only=True)
    document=ROOT/'assets/reference/source-document.md';text=document.read_text(encoding='utf-8')
    ids=tok.encode(text,add_special_tokens=False);assert len(ids)>256
    prefix=ids[:256];seeds=[]
    for word in (' What',' Why'):
        one=tok.encode(word,add_special_tokens=False);assert len(one)==1;seeds.append(one[0])
    workload=dict(source='assets/reference/source-document.md',source_sha256=sha(document),input_ids=prefix,seed_tokens=seeds,
        target_tokens=256,rows_per_build=4,build_tasks=64,decode_steps=3,seed_text=[' What',' Why'],
        quality_scored=False,scope='Exact first complete token page of real project documentation; not a complete QA prompt')
    (out/'workload.json').write_text(json.dumps(workload,ensure_ascii=True,indent=2)+'\n');(out/'source-document.md').write_bytes(document.read_bytes())
    record=dict(status='running',phase='native_reference',profile_sha256=ph,workload_sha256=sha(out/'workload.json'),
        model_manifest_sha256=sha(model/'risc-kv-model-manifest.json'),runs={},initial_kv_zero=True,board_execution=False)
    for name in ('npu_context_programs.py','prepare_npu_context_build.py'):(out/name).write_bytes((ROOT/'tools'/name).read_bytes())
    def save():(out/'summary.json').write_text(json.dumps(record,indent=2)+'\n')
    def event(**kw):print(json.dumps(kw),flush=True)
    def native_prefix(engine,slot=0):
        result=[]
        for li in range(28):
            kv=engine.image.descriptors(0).layer(li).kvs[slot]
            for h in range(8):
                for field,n in [('k',256*128),('ks',256*4),('vt',256*128),('vs',256*4)]:
                    result.append(engine.backend.read(0,Affine.of(kv.heads[h][field]).static(),n))
        return np.concatenate(result)
    try:
        save();W=load_weights(model);e=Engine(spec,W,cap=1024,cfg=cfg,batch=2,rows=4,backend='isa',resident=True,
            embed_host=False,wformat='int8',head_format='int8',pipeline=False,prog_cache=False,prompt_runs=False,tile_runs=False)
        assert e.device_inputs and not e.server and not e.row_server
        t=time.perf_counter()
        for i,_ in enumerate(e.prefill_chunks(prefix,seq=0,chunk=4,logits=False)):
            if i%8==0:event(phase='native_reference',built=(i+1)*4)
        raw=native_prefix(e);raw.tofile(out/'reference-prefix.bin')
        # Independent contiguous-slot reference duplicates the prefix for row 1.
        cursor=0
        for li in range(28):
            kv=e.image.descriptors(0).layer(li).kvs[1]
            for h in range(8):
                for field,n in [('k',32768),('ks',1024),('vt',32768),('vs',1024)]:
                    e.backend.write(0,Affine.of(kv.heads[h][field]).static(),raw[cursor:cursor+n]);cursor+=n
        rows=[];tokens=seeds.copy()
        for step in range(3):
            logits=e.run_rows([(0,256+step),(1,256+step)],tokens,[0,1]);nxt=np.argmax(logits,axis=1).tolist()
            fn=f'native-logits-{step}.npy';np.save(out/fn,logits)
            assert native_prefix(e).tobytes()==raw.tobytes() and native_prefix(e,1).tobytes()==raw.tobytes()
            rows.append(dict(step=step,input_tokens=tokens.copy(),output_tokens=nxt,logits_file=fn,logits_sha256=sha(out/fn)));tokens=nxt
        record['runs']['native']=dict(prefix_sha256=sha(out/'reference-prefix.bin'),steps=rows,wall_seconds=time.perf_counter()-t)
        del e,W;gc.collect();save()
        image=ColdContextImage(PoolSpec(**asdict(spec),pool_bytes=256<<20),cfg,1024,lookup=True)
        context=image.create_cold('context',256);programs={};recipes={}
        for kind,address in [('build',0x60000000),('decode',0x60010000)]:
            program,_=image.compile_operation(kind);programs[kind]=program;words=np.asarray(I.assemble(program),dtype='<u4');words.tofile(out/f'{kind}.bin')
            recipes[kind]=dict(address=address,instructions=len(words)//8,bytes=words.nbytes,sha256=sha(out/f'{kind}.bin'),
                args=[dict(name=v.name,coefficient=c,register=15-i) for i,(v,c) in enumerate(program.run_args)])
        size=recipes['decode']['address']+((recipes['decode']['bytes']+127)//128)*128
        initial=np.zeros(size,np.uint8)
        W=load_weights(model);packed=image.build(W)[0];initial[:len(packed)]=packed
        del W,packed;gc.collect()
        initial[image.pool_base:image.pool_base+image.pool_bytes]=0
        assert not np.any(initial[image.pool_base:image.pool_base+image.pool_bytes])
        result_address=image.lookup['gen']['state'];prompt_address=image.lookup['gen']['out']
        initial[prompt_address:prompt_address+1024]=np.asarray(prefix,dtype='<f4').view(np.uint8)
        initial.view('<u4')[result_address//4:result_address//4+2]=0x7fc0c0de
        initial.view('<u4')[image.io['logits']//4:image.io['logits']//4+2*151936]=0x7fc0c0de
        for kind in programs:
            code=np.fromfile(out/f'{kind}.bin',dtype=np.uint8);addr=recipes[kind]['address'];initial[addr:addr+len(code)]=code
        builddir=ROOT/'build/npu-context-inputs'/out.name;builddir.mkdir(parents=True,exist_ok=False);initial.tofile(builddir/'dram-input.bin')
        record.update(phase='candidate_isa',programs=recipes,input_path=(builddir/'dram-input.bin').relative_to(ROOT).as_posix(),
            input_sha256=sha(builddir/'dram-input.bin'),input_bytes=len(initial),kv_base=context['start'],
            prefix_bytes=context['prefix']['stride']*28,pool_base=image.pool_base,pool_bytes=image.pool_bytes,
            context_end=context['end'],result_address=result_address,prompt_address=prompt_address,logits_address=image.io['logits'],
            immutable_regions=image.immutable_regions());save()
        backend=IsaBackend(cfg,[initial],adopt=True);mem=backend.machine.slices[0].dram
        h=hashlib.sha256()
        for addr,n in image.immutable_regions():h.update(mem[addr:addr+n])
        record['immutable_sha256']=h.hexdigest();t=time.perf_counter()
        for start in range(0,256,4):
            vals=image.argument_values(start);args=arg_words(programs['build'].run_args,vals)
            backend.run([programs['build']],args=args)
            assert backend.read(0,result_address,8).view('<f4').tolist()==[1.,4.]
            if start%32==0:event(phase='candidate_isa',built=start+4)
        built=backend.read(0,context['start'],record['prefix_bytes']);built.tofile(out/'candidate-prefix.bin')
        assert built.tobytes()==raw.tobytes()
        assert np.frombuffer(backend.read(0,prompt_address,1024),dtype='<f4').astype(np.uint32).tolist()==prefix
        tokens=seeds.copy();steps=[]
        for step in range(3):
            backend.run([programs['decode']],args=arg_words(programs['decode'].run_args,image.argument_values(step,tokens)))
            logits=backend.read(0,image.io['logits'],2*151936*4).view('<f4').reshape(2,151936)
            nxt=backend.read(0,result_address,8).view('<f4').astype(np.uint32).tolist();assert nxt==np.argmax(logits,axis=1).tolist()
            fn=f'candidate-logits-{step}.npy';np.save(out/fn,logits);reference=rows[step]
            assert tokens==reference['input_tokens'] and nxt==reference['output_tokens'] and sha(out/fn)==reference['logits_sha256']
            assert backend.read(0,context['start'],record['prefix_bytes']).tobytes()==raw.tobytes()
            steps.append(dict(step=step,input_tokens=tokens,output_tokens=nxt,logits_file=fn,logits_sha256=sha(out/fn)));tokens=nxt
        h=hashlib.sha256()
        for addr,n in image.immutable_regions():h.update(mem[addr:addr+n])
        assert h.hexdigest()==record['immutable_sha256']
        record['runs']['candidate']=dict(prefix_sha256=sha(out/'candidate-prefix.bin'),steps=steps,wall_seconds=time.perf_counter()-t,
            final_pool_sha256=hashlib.sha256(mem[image.pool_base:image.pool_base+image.pool_bytes]).hexdigest())
        record.update(status='passed_cold_context_isa',phase='complete');save();event(status=record['status'])
    except Exception as ex:
        record.update(status='failed',error=f'{type(ex).__name__}: {ex}');save();raise

if __name__=='__main__':main()

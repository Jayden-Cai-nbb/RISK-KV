"""Rebuild the frozen cold image directly from the checkpoint, without old warm images."""
import argparse
from dataclasses import asdict
import hashlib
import json
import os
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[1]

def sha(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    out=a.output.resolve();out.parent.mkdir(parents=True,exist_ok=True)
    if out.exists():raise FileExistsError(out)
    os.environ.update(HF_HUB_OFFLINE='1',OTPU_FORMATS='',OTPU_IMAGE_CACHE='0',OTPU_IMG_CACHE='0',OTPU_PROG_CACHE='0',OMP_NUM_THREADS='2',OPENBLAS_NUM_THREADS='2')
    sys.path.insert(0,str(ROOT/'vendor/openTPU'))
    import numpy as np
    import torch
    from opentpu.llm.qwen3 import Spec,load_weights
    from opentpu.isasim import Config
    from opentpu import isa as I
    from npu_context_programs import ColdContextImage
    from npu_kv_pool import PoolSpec
    from npu_core_profile import load
    from npu_model_contract import WEIGHT_SHA256
    torch.set_num_threads(2)
    ref=ROOT/'assets/reference';r=json.loads((ref/'summary.json').read_text());w=json.loads((ref/'workload.json').read_text())
    model=ROOT/'models/Qwen3-0.6B-hf';assert sha(model/'model.safetensors')==WEIGHT_SHA256
    profile,ph=load(ROOT/'configs/npu-vu440-core.json');assert ph==r['profile_sha256']
    image=ColdContextImage(PoolSpec(**asdict(Spec.from_hf(model)),pool_bytes=256<<20),Config(**profile['architecture']),1024,lookup=True)
    image.create_cold('context',256)
    weights=load_weights(model);raw=image.build(weights)[0];del weights
    initial=np.zeros(r['input_bytes'],np.uint8);initial[:len(raw)]=raw;del raw
    initial[image.pool_base:image.pool_base+image.pool_bytes]=0
    initial[r['prompt_address']:r['prompt_address']+1024]=np.asarray(w['input_ids'],dtype='<f4').view(np.uint8)
    initial.view('<u4')[r['result_address']//4:r['result_address']//4+2]=0x7fc0c0de
    initial.view('<u4')[r['logits_address']//4:r['logits_address']//4+2*151936]=0x7fc0c0de
    for kind in ('build','decode'):
        program,_=image.compile_operation(kind);code=np.asarray(I.assemble(program),dtype='<u4').view(np.uint8)
        assert code.tobytes()==(ref/f'{kind}.bin').read_bytes(),kind+' program mismatch'
        addr=r['programs'][kind]['address'];initial[addr:addr+len(code)]=code
    actual=hashlib.sha256(initial).hexdigest()
    report=dict(status='passed' if actual==r['input_sha256'] else 'mismatch',sha256=actual,expected_sha256=r['input_sha256'],bytes=len(initial),source='checkpoint; no historical image dependency')
    if actual!=r['input_sha256']:
        old=np.memmap(ROOT/'assets/data/dram-input.bin',mode='r',dtype=np.uint8)
        report['mismatch_bytes']=int(np.count_nonzero(initial!=old))
        report['first_offsets']=np.flatnonzero(initial!=old)[:32].tolist()
    out.with_suffix('.json').write_text(json.dumps(report,indent=2)+'\n')
    if report['status']!='passed':raise AssertionError(report)
    initial.tofile(out);print(json.dumps(report))

if __name__=='__main__':main()

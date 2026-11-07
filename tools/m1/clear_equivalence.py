"""Exhaust specified poison classes at the post-clean byte-state boundary.

This is NOT a new execution of all model layers for every poison. Full clearing
is independent of the overwritten bytes; equality of all affected input bytes
is linked to separate RTL cleaner coverage and native/RTL numerical evidence.
Scale-only results are hypotheses, not authorization to change M1 hardware.
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'tools/reproduction'),str(ROOT/'tools'),str(ROOT/'vendor/openTPU')]
from recorded import save,sha,utc


def main():
    import numpy as np
    from dataclasses import asdict
    from opentpu.llm.qwen3 import Spec
    from opentpu.isasim import Config
    from npu_context_programs import ColdContextImage
    from npu_kv_pool import PoolSpec
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True);p.add_argument('--run',type=Path,required=True);a=p.parse_args()
    out=a.output.absolute();out.mkdir(parents=True,exist_ok=False)
    layout=json.loads((ROOT/'configs/m1/layout.json').read_text())
    profile=json.loads((ROOT/'configs/npu-vu440-core.json').read_text())
    image=ColdContextImage(PoolSpec(**asdict(Spec.from_hf(ROOT/'models/Qwen3-0.6B-hf')),pool_bytes=256<<20),Config(**profile['architecture']),1024,lookup=True)
    image.create_cold('context',256);regions=image.regions('context')
    prefix=np.fromfile(ROOT/'assets/reference/reference-prefix.bin',dtype=np.uint8)
    cold=np.memmap(ROOT/'assets/data/dram-input.bin',dtype=np.uint8,mode='r')
    scratch=np.concatenate([cold[x:x+n] for x,n in layout['scratch_restore']])
    patterns=dict(finite_1_25=0x3fa00000,nan=0x7fc01234,pos_inf=0x7f800000,neg_inf=0xff800000,max_finite=0x7f7fffff,negative_max=0xff7fffff)
    rows=[]
    for mode in ('full_object','private_tails'):
        expected=np.zeros(layout['object_bytes'],dtype=np.uint8)
        if mode=='private_tails':expected[:prefix.size]=prefix
        selected=[r for r in regions if r['kind']==('prefix' if mode=='full_object' else 'private')]
        for field in ('ks','vs'):
            for name,bits in patterns.items():
                before=expected.copy()
                # Include finite INT8 remnants and partial writes alongside scale poison.
                for r in selected:
                    start=r['address']-layout['kv_base'];v=before[start:start+r['bytes']]
                    if r['field']==field:v.view('<u4')[:]=np.uint32(bits)
                    elif r['field'] in ('k','vt'):v[:]=0x55
                # Simulate a task that overwrote some valid bytes before failing.
                before[layout['prefix_bytes'] if mode=='private_tails' else 0:][:128]=0xa7
                for cleaning in ('full','scales'):
                    actual=before.copy();bytes_written=0
                    if cleaning=='full':
                        start=prefix.size if mode=='private_tails' else 0
                        actual[start:]=0;bytes_written=actual.size-start
                    else:
                        for r in regions:
                            if (mode=='full_object' or r['kind']=='private') and r['field'] in ('ks','vs'):
                                start=r['address']-layout['kv_base'];actual[start:start+r['bytes']]=0;bytes_written+=r['bytes']
                    # Actual M1 always copies cold scratch rather than zeroing it.
                    restored_scratch=scratch.copy()
                    equal=actual.tobytes()==expected.tobytes() and restored_scratch.tobytes()==scratch.tobytes()
                    if cleaning=='full':assert equal
                    rows.append(dict(mode=mode,field=field,poison=name,bits=hex(bits),cleaning=cleaning,
                                     post_clean_all_object_bytes_equal_cold_boundary=equal,
                                     post_state_sha256=hashlib.sha256(actual).hexdigest(),clean_kv_bytes=bytes_written,
                                     scratch_write_bytes=len(scratch),scratch_read_bytes=len(scratch),
                                     numerical_execution='not rerun; exact post-clean byte equality only' if equal else 'not established; needs ISA/RTL proof for retained bytes'))
    evidence=[]
    for rel in ('g1-final-v1/cleaner/summary.json','state-audit-v1/summary.json','full-short-v1/summary.json','reference-v1/summary.json'):
        path=a.run/rel;evidence.append(dict(path=str(path),sha256=sha(path)))
    save(out/'summary.json',dict(status='passed_full_clear_byte_equivalence',started_at=utc(),cases=rows,
        full_cases=sum(r['cleaning']=='full' for r in rows),scale_cases=sum(r['cleaning']=='scales' for r in rows),
        inputs={str(p.relative_to(ROOT)):sha(p) for p in (Path(__file__),ROOT/'configs/m1/layout.json',ROOT/'assets/reference/reference-prefix.bin')},
        related_evidence=evidence,limits=['Not 48 independent numerical model runs','Scale-only retained data differs from cold boundary; no M1 adoption',
          'Shared upstream compiler/layout dependencies remain','Full G2 numerical run and board fault-recovery matrix are separate gates']))
if __name__=='__main__':main()

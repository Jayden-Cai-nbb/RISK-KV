"""Export the canonical current controller; no historical patch chain."""
import hashlib
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
NAMES=('rkv_npu_control.sv','rkv_npu_io_control.sv','rkv_npu_context_cpu.sv')

def export_control(dest,*,kv_base=1233223680,result_address=1229289088,build_insns=1026,decode_insns=1004):
    if (kv_base,result_address,build_insns,decode_insns)!=(1233223680,1229289088,1026,1004):
        raise ValueError('New geometry requires coordinated firmware, guard and harness validation; no implicit port')
    dest.mkdir(parents=True,exist_ok=True)
    result={}
    for name in NAMES:
        raw=(ROOT/'rtl'/name).read_bytes();(dest/name).write_bytes(raw)
        h=hashlib.sha256(raw).hexdigest()
        result[name]=dict(original_sha256=h,exported_sha256=h)
    return result

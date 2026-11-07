"""Copy the tested full-model simulation wrapper, independent of old generators.

The wrappers include simulation-only DPI storage and observers, not a board top.
"""
import hashlib
from pathlib import Path
from npu_context_integration import export_control

ROOT=Path(__file__).resolve().parents[1]

def export(source,dest,reference):
    expected=dict(kv_base=1233223680,result_address=1229289088,logits_address=13312,
                  prefix_bytes=15138816)
    for key,value in expected.items():
        if reference[key]!=value:raise ValueError('Update and validate the harness for changed '+key)
    control=export_control(dest,kv_base=reference['kv_base'],result_address=reference['result_address'],
        build_insns=reference['programs']['build']['instructions'],decode_insns=reference['programs']['decode']['instructions'])
    hashes={}
    for name in ('otpu_top.sv','tb_top.sv'):
        raw=(ROOT/'tb/full_model'/name).read_bytes();(dest/name).write_bytes(raw)
        hashes[name]=hashlib.sha256(raw).hexdigest()
    return dict(control=control,tb_sha256=hashes['tb_top.sv'],top_sha256=hashes['otpu_top.sv'],
        scope='Canonical validated RTL; simulation-only memory and observers; no historical generator dependency')

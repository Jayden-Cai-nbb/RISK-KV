"""Fixed startup recorder verification. No DDR device or hardware access."""
import argparse,json,shutil,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/reproduction'))
import recorded
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--output',required=True,type=Path)
p.add_argument('--verilator-prefix',required=True,type=Path)
a=p.parse_args();out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
inputs=[ROOT/x for x in ['platform/m1/prodigy/rkv_boot_trace.v','platform/m1/prodigy/rkv_ddr_init_trace.v','tb/m1/tb_rkv_boot_trace.sv','tb/m1/tb_rkv_ddr_init_trace.sv','tools/m1/ddr_init_trace_test.py','tools/reproduction/with_verilator.py']]
for src in inputs:
 dst=out/'sources'/src.relative_to(ROOT);dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
recorded.save(out/'inputs.json',{str(f.relative_to(ROOT)):recorded.sha(f) for f in inputs})
result={'status':'running','scope':'recorder unit tests only; no physical DDR'}
try:
 for top,files,marker in [('tb_rkv_boot_trace',inputs[:1]+inputs[2:3],'BOOT_TRACE_PASS'),('tb_rkv_ddr_init_trace',inputs[:2]+inputs[3:4],'DDR_INIT_TRACE_PASS')]:
  cmd=[sys.executable,ROOT/'tools/reproduction/with_verilator.py','--prefix',a.verilator_prefix.resolve(),'--','verilator','--binary','--timing','--assert','-j','2','-Wno-fatal','--Mdir',out/top/'obj','--top-module',top,*files]
  assert recorded.run(out/top/'compile',cmd,300,inputs)==0
  assert recorded.run(out/top/'run',[out/top/'obj'/('V'+top)],60,inputs)==0
  assert marker in (out/top/'run/stdout.log').read_text()
 result['status']='passed'
finally:
 recorded.save(out/'summary.json',result)
 print(json.dumps(result))

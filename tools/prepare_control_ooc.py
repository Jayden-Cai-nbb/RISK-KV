"""Export current CPU/control for Vivado OOC synthesis, never a board bitstream."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

ROOT=Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--firmware',type=Path,default=ROOT/'assets/firmware/positive/firmware.hex');a=p.parse_args()
    out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
    files=['rkv_npu_control.sv','rkv_npu_io_control.sv','rkv_context_guard.sv','rkv_npu_context_service.sv','rkv_npu_context_cpu.sv']
    records={}
    for name in files:
        before=(ROOT/'rtl'/name).read_bytes();after=before.decode().replace('\r\n','\n')
        if name=='rkv_npu_context_cpu.sv':
            after=after.replace('parameter string FIRMWARE=""','parameter FIRMWARE="firmware.hex"')
            first=after.index('    string image;');last=after.index('    always_ff',first)
            after=after[:first]+'    initial begin\n        for(int i=0;i<16384;i++)ram[i]=0;\n        $readmemh(FIRMWARE,ram);\n    end\n'+after[last:]
        raw=after.encode();(out/name).write_bytes(raw)
        records[name]=dict(source_sha256=hashlib.sha256(before).hexdigest(),exported_sha256=hashlib.sha256(raw).hexdigest())
    shutil.copy2(ROOT/'vendor/picorv32/picorv32.v',out/'picorv32.v');shutil.copy2(a.firmware,out/'firmware.hex')
    tcl='''cd [file dirname [file normalize [info script]]]
set_param general.maxThreads 2
read_verilog -sv {picorv32.v rkv_npu_control.sv rkv_npu_io_control.sv rkv_context_guard.sv rkv_npu_context_service.sv rkv_npu_context_cpu.sv}
synth_design -top rkv_npu_context_cpu -part xcvu440-flga2892-2-e -mode out_of_context
create_clock -name clk -period 20.000 [get_ports clk]
report_utilization -file utilization.rpt
report_utilization -hierarchical -file hierarchy.rpt
report_timing_summary -file timing-estimate.rpt
write_checkpoint context-cpu-synth.dcp
exit
'''
    (out/'run.tcl').write_text(tcl,newline='\n')
    (out/'export.json').write_text(json.dumps(dict(scope='CPU/control OOC; no NPU/DDR/board timing claim',sources=records,
        firmware_sha256=hashlib.sha256(a.firmware.read_bytes()).hexdigest()),indent=2)+'\n')

if __name__=='__main__':main()

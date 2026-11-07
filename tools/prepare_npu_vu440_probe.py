"""Export a bounded MXU synthesis probe, not a board bitstream or full NPU.

Vivado 2019.1 compatibility is confined to generated copies: a local variable
rename, untyped RAM-style string parameters, and a closed-form constant helper.
The original pinned dependency and existing board projects are never edited.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

COMMIT='91df41092f612361c5bc22f83b31d23382ffabb0'
FILES=['rtl/vpu/otpu_fp.sv','rtl/top/otpu_pkg.sv','rtl/vpu/otpu_fpipe.sv',
       'rtl/tech/xilinxus/otpu_tech_dsp.sv','rtl/tech/generic/otpu_tech_ram.sv','rtl/mxu/otpu_mxu.sv']
SLICE_FILES=['rtl/mem/otpu_tmem.sv','rtl/mem/otpu_actram.sv','rtl/seq/otpu_seq.sv',
             'rtl/vpu/otpu_vtree.sv','rtl/dma/otpu_dma.sv','rtl/vpu/otpu_quant.sv',
             'rtl/vpu/otpu_se_comp.sv','rtl/vpu/otpu_se_tail.sv','rtl/vpu/otpu_vpu.sv',
             'rtl/exp/tmem_nocopy/otpu_tmem_model.sv','rtl/top/otpu_slice.sv']

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--top',choices=['mxu','slice'],default='mxu')
    p.add_argument('--core-profile',type=Path)
    p.add_argument('--tmem-impl',choices=[0,3],type=int,default=3,
                   help='Slice only: 3 is the upstream board sub-banked RAM organization')
    a=p.parse_args();src=a.source.resolve();out=a.output.resolve()
    if subprocess.check_output(['git','-C',str(src),'rev-parse','HEAD'],text=True).strip()!=COMMIT:
        raise ValueError('Unexpected source revision')
    # Export explicitly from the pinned Git tree, independent of simulation compatibility edits.
    out.mkdir(parents=True,exist_ok=False)
    records=[]
    files=FILES+(SLICE_FILES if a.top=='slice' else [])
    for name in files:
        before=subprocess.check_output(['git','-C',str(src),'show',COMMIT+':'+name]).decode('utf-8');after=before
        if name.endswith('otpu_tech_ram.sv'):
            after,n=re.subn(r'parameter string STYLE', 'parameter        STYLE', after)
            if n!=5:raise ValueError('RAM parameter changes differ from audit')
        if name=='rtl/mem/otpu_tmem.sv':
            after,n=re.subn(r'parameter string STYLE', 'parameter        STYLE', after)
            if n!=1:raise ValueError('Pumped RAM parameter differs from audit')
        if name.endswith('otpu_mxu.sv'):
            # Only code references: comments deliberately stay byte-identical.
            after,n=re.subn(r'\bmk(?=\s*\[)', 'rkv_max_sort_key',after)
            if n!=4:raise ValueError('MXU rename differs from audit')
            old='for (int i = 0; i < g; i++) c = c + FC / FG + ((i < FC % FG) ? 1 : 0);'
            new='c = g * (FC / FG) + ((g < FC % FG) ? g : FC % FG);'
            if after.count(old)!=1:raise ValueError('Constant-helper source changed')
            after=after.replace(old,new)
        target=out/'src'/name;target.parent.mkdir(parents=True,exist_ok=True)
        target.write_text(after,encoding='utf-8',newline='\n')
        records.append(dict(path=name,original_sha256=hashlib.sha256(before.encode()).hexdigest(),
                            exported_sha256=hashlib.sha256(after.encode()).hexdigest()))
    cases=0
    for width in (64,128,256,512,1024,2048):
        fc=(width+35)//36;fg=min(fc,4)
        for g in range(fg+1):
            old=sum(fc//fg+(i<fc%fg) for i in range(g))
            new=g*(fc//fg)+min(g,fc%fg)
            assert old==new
            cases+=1
    tcl=['cd [file dirname [file normalize [info script]]]','create_project -in_memory -part xcvu440-flga2892-2-e',
         'set_property verilog_define {SYNTHESIS} [get_filesets sources_1]']
    tcl += ['read_verilog -sv {'+('src/'+f)+'}' for f in files]
    generics=('D=128 MCOLS=4 ROWS=16 DEPTH=128 LANES=8 TLANES=8 E=4' if a.top=='mxu' else
              'S=1 D=128 MCOLS=4 ACT_BLOCKS=128 ACT_ROWS=16 TMEM_WORDS=65536 IMEM_WORDS=32768 FIFO_DEPTH=128 LANES=8 WIN=16 MXU_E=4 HAS_DSTEP=1 TMEM_IMPL='+str(a.tmem_impl))
    if a.top=='slice' and a.tmem_impl==3:
        generics+=' TMEM_NSB=2 TMEM_RPL=1 TMEM_TDP=1 TMEM_GST=1 TMEM_PMP=1 RPB=64 WPB=1 VPU_CL=2 ULANES=8'
    profile_record=None
    if a.core_profile:
        if a.top!='slice':raise ValueError('A full core profile requires --top slice')
        from npu_core_profile import load,synthesis_parameters
        profile,profile_sha=load(a.core_profile)
        if a.tmem_impl!=profile['microarchitecture']['TMEM_IMPL']:raise ValueError('Conflicting TMEM options')
        generics=' '.join(f'{k}={v}' for k,v in synthesis_parameters(profile).items())
        profile_record=dict(sha256=profile_sha,profile=profile)
        (out/'core-profile.json').write_bytes(a.core_profile.read_bytes())
    period=profile['core_period_ns'] if profile_record else 20.0
    fast=profile['fast_period_ns'] if profile_record else 10.0
    tcl += ['synth_design -mode out_of_context -top otpu_'+a.top+' -part xcvu440-flga2892-2-e -generic {'+generics+'}',
            f'create_clock -period {period} [get_ports clk]']
    if a.top=='slice' and a.tmem_impl==3:
        # No MMCM exists in this OOC top. Do not invent a generated-clock path.
        tcl+=[f'create_clock -name clk_f -period {fast} [get_ports clk_f]']
    tcl += [
            'report_utilization -file utilization.rpt','report_timing_summary -file timing.rpt',
            'write_checkpoint '+a.top+'-synth.dcp','exit']
    (out/'probe.tcl').write_text('\n'.join(tcl)+'\n',encoding='utf-8')
    report=dict(status='prepared_not_synthesized',top='otpu_'+a.top,parameters=generics,core_profile=profile_record,commit=COMMIT,source_files=records,
                constant_helper_cases=cases,technology='upstream xilinxus DSP48E2 implementation',
                scope='Compute block OOC only; no DDR controller, RISC-V, board pins or routed timing claim',
                changes=['Four-site local array rename','RAM STYLE parameters untyped (five tech RAM, plus one TMEM pump for slice)',
                         'Constant fg_lo loop expressed in closed form'],
                numeric_or_timing_changes_intended=False)
    (out/'export-manifest.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report))

if __name__=='__main__':main()

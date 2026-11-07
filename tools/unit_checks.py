"""Guard assertions and real RV32I control with a declared synthetic NPU fixture."""
import json
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]

def main():
    sys.path.insert(0,str(ROOT/'vendor/openTPU'))
    from opentpu import rtlsim
    rtlsim.VFLAGS[rtlsim.VFLAGS.index('-j')+1]='2'
    out=ROOT/'build/unit';out.mkdir(parents=True,exist_ok=True)
    runs=[]
    for top,names in [('tb_rkv_context_guard',['rkv_context_guard.sv']),
                      ('tb_rkv_context_cpu',['rkv_npu_control.sv','rkv_npu_io_control.sv','rkv_context_guard.sv','rkv_npu_context_service.sv','rkv_npu_context_cpu.sv'])]:
        sources=[ROOT/'rtl'/n for n in names]+[ROOT/'tb'/f'{top}.sv']
        if top.endswith('_cpu'):sources.insert(0,ROOT/'vendor/picorv32/picorv32.v')
        exe=rtlsim.build(top,sources)
        cases=('positive','cancel','fault') if top.endswith('_cpu') else ('unit',)
        for i,case in enumerate(cases):
            cmd=[str(exe)]
            if case!='unit':cmd += [f'+firmware={ROOT/"assets/firmware"/case/"firmware.hex"}',f'+failure={i}']
            result=subprocess.run(cmd,capture_output=True,text=True,timeout=120)
            (out/f'{top}-{case}.log').write_text(result.stdout+result.stderr)
            if result.returncode or 'PASS ' not in result.stdout:raise RuntimeError(result.stdout+result.stderr)
            print(result.stdout.strip(),flush=True);runs.append(dict(top=top,case=case,returncode=result.returncode))
    (out/'summary.json').write_text(json.dumps(dict(status='passed',runs=runs,scope='Unit/control fixture; not full NPU arithmetic'),indent=2)+'\n')

if __name__=='__main__':main()

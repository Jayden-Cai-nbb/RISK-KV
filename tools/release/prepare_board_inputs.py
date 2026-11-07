"""Plan or generate board IP inputs from published recipes, without synthesis or hardware access."""
import argparse,json,os,shutil,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/reproduction'))
import recorded

def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--output',type=Path,required=True)
 p.add_argument('--vivado',type=Path,required=True)
 p.add_argument('--execute',action='store_true',help='Run IP generation; default only records the plan')
 a=p.parse_args();out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
 source=ROOT/'platform/m1';frozen=source/'prodigy/frozen'
 ddr=out/'ddr';ddr.mkdir()
 for name in ('create.tcl','custom.csv'):shutil.copy2(frozen/name,ddr/name)
 inp=out/'ddr-input';inp.mkdir()
 for name in ('patch_trace.py','patch_clock48_fixture.py'):shutil.copy2(frozen/name,inp/name)
 for name in ('j11-pins.json','rkv_boot_trace.v','rkv_ddr_init_trace.v'):shutil.copy2(source/'prodigy'/name,inp/name)
 shutil.copy2(ROOT/'tools/m1/prodigy_pin_plan.py',inp/'prodigy_pin_plan.py')
 stages=[(ddr,'create.tcl',[])]
 hc=json.loads((ROOT/'configs/m1/host-control.json').read_text());layout=json.loads((ROOT/'configs/m1/layout.json').read_text())
 for label,script in [('fabric','create_axi_fabric.tcl'),('router','create_host_router.tcl'),('cdc','create_axi_cdc.tcl')]:
  folder=out/'clocked-work'/(label+'-copy');folder.mkdir(parents=True)
  shutil.copy2(source/script,folder/script);args=[]
  if label=='router':
   spec=folder/'address-spec.tcl';spec.write_text(f"set rkv_logical_bytes {layout['logical_bytes']}\nset rkv_control_base {hc['control_base']}\nset rkv_mailbox_base {hc['mailbox_alias_base']}\nset rkv_mailbox_bytes {hc['mailbox_words']*hc['mailbox_stride']}\n")
   args=['-tclargs',str(spec)]
  stages.append((folder,script,args))
 plan=dict(status='prepared_not_executed',vivado=str(a.vivado.resolve()),required_version='2022.2',hardware_actions=[],stages=[dict(cwd=str(d),script=s,args=args) for d,s,args in stages],board_build_inputs=dict(ddr_example=str(ddr/'example/rkv_ddr_candidate_ex'),ddr_input=str(inp),clocked_work=str(out/'clocked-work')))
 recorded.save(out/'plan.json',plan)
 if not a.execute:print(json.dumps(plan,indent=2));return
 try:
  recorded.ROOT=out
  assert recorded.run(out/'version',[a.vivado.resolve(),'-version'],60)==0
  assert 'v2022.2' in (out/'version/stdout.log').read_text(),'Use the validated Vivado version'
  for index,(folder,script,args) in enumerate(stages):
   recorded.ROOT=folder
   inputs=[f for f in folder.iterdir() if f.is_file()]
   assert recorded.run(out/f'generate-{index}',[a.vivado.resolve(),'-mode','batch','-source',folder/script,*args],1800,inputs)==0,'IP generation failed; preserve this run'
  assert (ddr/'example/rkv_ddr_candidate_ex/rkv_ddr_candidate_ex.xpr').exists()
  plan['status']='generated_inputs_not_implemented'
 except BaseException as e:plan.update(status='failed',error=repr(e));raise
 finally:recorded.save(out/'plan.json',plan)
if __name__=='__main__':main()

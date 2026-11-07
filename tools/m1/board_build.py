"""Build the full experimental board shell from fixed MIG/platform inputs; no programming."""
import argparse,json,shutil,sys,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/reproduction'))
import recorded

def main():
    p=argparse.ArgumentParser(description=__doc__)
    for n in ('ddr-example','ddr-input','clocked-work','firmware','vivado','output'):p.add_argument('--'+n,type=Path,required=True)
    a=p.parse_args();out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
    work=out/'work';work.mkdir();frozen=out/'frozen';frozen.mkdir()
    def tree(source,label,target):
        shutil.copytree(source.resolve(),frozen/label)
        shutil.copytree(frozen/label,work/target)
    tree(a.ddr_example,'ddr-example','project/example')
    for n in ('fabric','router','cdc'):tree(a.clocked_work/(n+'-copy/project'),n,n+'-copy/project')
    for p in a.ddr_input.resolve().iterdir():
        if p.is_file():shutil.copy2(p,work/p.name)
    names=[x for x in (ROOT/'platform/m1/platform.f').read_text().splitlines() if x and not x.startswith('#')]
    for n in names+['platform/m1/platform.f']:
        dst=work/'sources'/n;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/n,dst)
    for n in ('rkv_m1_board_top.v','rkv_m1_board_memory.sv','rkv_m1_boot_mux.v','rkv_m1_jtag_mask.v','rkv_ddr_qualifier.v','rkv_ddr_first_guard.v','prepare_board.tcl','implement_board.tcl','board_constraints.tcl'):
        shutil.copy2(ROOT/'platform/m1/prodigy'/n,work/n)
    shutil.copy2(ROOT/'tools/m1/patch_board_clock_export.py',work/'patch_board_clock_export.py')
    shutil.copy2(a.firmware/'firmware.hex',work/'firmware.hex')
    shutil.copy2(a.firmware/'manifest.json',work/'firmware-manifest.json')
    # 在任何导出件patch前冻结顶层/脚本/常量；工具只允许改变work副本。
    for src in work.iterdir():
        if src.is_file():shutil.copy2(src,frozen/src.name)
    shutil.copytree(work/'sources',frozen/'sources')
    shutil.copy2(Path(__file__),frozen/'board_build.py');shutil.copy2(Path(recorded.__file__),frozen/'recorded.py')
    inputs=[p for p in frozen.rglob('*') if p.is_file()]
    recorded.save(out/'inputs.json',{str(p.relative_to(out)):recorded.sha(p) for p in inputs})
    identity=hashlib.sha256(''.join(str(p.relative_to(frozen))+recorded.sha(p) for p in sorted(inputs)).encode()).hexdigest()[:16]
    (work/'experiment-id.txt').write_text(identity+'\n')
    recorded.save(out/'experiment-identity.json',dict(experiment_id=int(identity,16),hex=identity,source='SHA256 of frozen build inputs; first 64 bits'))
    summary=dict(status='running',validation_profile='experimental_m1',vendor_supported=False,
                 unsupported_reasons=['MIG_PFD_48MHZ','MODULE_TIMINGS_UNCONFIRMED','PHYSICAL_SPEED_GRADE_UNCONFIRMED'],
                 part='xcvu440-flga2892-1-c',actual_speed_grade='unconfirmed',hardware_actions=[],board_acceptance_passed=False,stages=[])
    recorded.ROOT=work
    def run(name,cmd,limit):
        summary['current_stage']=name;recorded.save(out/'summary.json',summary)
        rc=recorded.run(out/name,cmd,limit,inputs)
        summary['stages'].append(dict(stage=name,returncode=rc));recorded.save(out/'summary.json',summary)
        if rc:raise RuntimeError(f'{name} failed with {rc}; preserve first failure')
    try:
        run('version',[a.vivado.resolve(),'-version'],60)
        assert 'v2022.2' in (out/'version/stdout.log').read_text()
        run('pins',[sys.executable,'prodigy_pin_plan.py','--pins','j11-pins.json','--output','pins'],30)
        shutil.copy2(work/'pins/prodigy-pins.xdc',work/'prodigy-pins.xdc')
        run('prepare',[a.vivado.resolve(),'-mode','batch','-source','prepare_board.tcl'],1200)
        run('patch-clock',[sys.executable,'patch_clock48_fixture.py',work],30)
        run('patch-trace',[sys.executable,'patch_trace.py',work],30)
        run('patch-export',[sys.executable,'patch_board_clock_export.py',work],30)
        run('implement',[a.vivado.resolve(),'-mode','batch','-source','implement_board.tcl'],14400)
        assert 'M1_BOARD_ROUTED_REQUIRES_REVIEW_NOT_NUMERICALLY_VALIDATED' in (out/'implement/stdout.log').read_text()
        summary['status']='routed_requires_review'
    except BaseException as e:
        summary.update(status='failed',error=repr(e));raise
    finally:
        summary['finished_at']=recorded.utc();recorded.save(out/'summary.json',summary);print(json.dumps(summary),flush=True)
if __name__=='__main__':main()

"""Combine real-board reports; a subset or unbound report can never pass M1-board."""
import argparse
import json
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/reproduction'))
from recorded import save,sha,utc


def require_formal_profile(data):
    # 旧报告缺少支持范围声明也不能自动升级成正式 M1-board。
    assert data.get('validation_profile') == 'formal_m1', 'formal acceptance rejects missing/experimental profile'
    assert data.get('vendor_supported') is True, 'formal acceptance requires verified vendor support'
    assert data.get('unsupported_reasons') == [], 'formal acceptance rejects unsupported conditions'


def evaluate(paths,physical_path, *, validation_profile="formal_m1"):
    if validation_profile == "formal_m1":
        require_profile = require_formal_profile
    elif validation_profile == "experimental_m1":
        from experimental_acceptance import require_experimental_profile
        require_profile = require_experimental_profile
    else:
        raise ValueError("Unknown acceptance profile")
    expected={'ddr':'passed_ddr_subset','load':'image_loaded_and_verified','smoke':'passed_four_token_full_kv',
              'continuous':'passed_continuous_subset','faults':'passed_retiring_faults_subset',
              'isolation':'passed_isolation_subset','benchmark':'measured_not_functional_acceptance'}
    reports={};identity=None;records=[]
    for name,status in expected.items():
        p=paths[name];data=json.loads(p.read_text())
        assert data['command']==name and data['status']==status, f'{name}: not passed'
        hw=data['hardware'];assert hw['backend_kind']=='hardware'
        require_profile(hw)
        require_profile(data['platform'])
        key=(hw['device_id'],hw['part'],hw['bit_sha256'],hw['ltx_sha256'],data['layout_sha256'],data['driver_sha256'])
        if identity is None:identity=key
        assert key==identity,'reports are from different hardware/design/driver/layout'
        assert hw['core_hz']==50000000 and hw['fast_hz']==100000000 and hw['clock_phase_verified']
        assert hw['ddr_capacity_bytes']>=2147483648 and hw['ddr_calibrated']
        assert data['files'],f'{name}: raw evidence manifest is missing'
        for item in data['files']:
            evidence=p.parent/item['path']
            assert evidence.is_file() and evidence.stat().st_size==item['bytes'] and sha(evidence)==item['sha256'],f'raw evidence changed: {evidence}'
        reports[name]=data;records.append(dict(kind=name,path=str(p),sha256=sha(p)))
    assert reports['continuous']['batches']>=100 and reports['continuous']['rebuilds']>=10
    assert reports['benchmark']['samples']>=60
    assert len({reports[n]['reference_sha256'] for n in ('smoke','continuous','faults','isolation','benchmark')})==1, 'numerical reference mismatch across runs'
    faults=json.loads((paths['faults'].parent/'faults.json').read_text())
    assert faults['status']=='passed_retiring_faults'
    for mode in ('cancel','error','reset'):
        selected=[x for x in faults['results'] if x['mode']==mode]
        assert len(selected)>=10
        assert {'build_early','build_middle','build_last','decode'}<={x['stage'] for x in selected}
    from board_evidence import verify_numeric
    numerical=verify_numeric(paths)
    physical=json.loads(physical_path.read_text())
    require_profile(physical)
    assert physical['status']=='reviewed_passed' and physical['part']==identity[1]
    assert physical['bit_sha256']==identity[2] and physical['ltx_sha256']==identity[3]
    assert physical['vivado_version']==reports['load']['hardware']['vivado_version']
    for key in ('setup_slack_ns','hold_slack_ns'):assert physical[key]>=0
    for key in ('unconstrained_required_paths','unresolved_cdc','unresolved_reset','drc_errors','drc_critical_warnings'):
        assert physical[key]==0,key
    for key in ('clock_phase_verified','all_external_paths_reviewed','exceptions_have_evidence','source_manifest_matches','bit_ltx_paired'):
        assert physical[key] is True,key
    required={'timing_summary','check_timing','cdc','drc','clocks','clock_interaction','exceptions','utilization','route_status','reset_review','source_manifest','bit','ltx'}
    assert required<={f['kind'] for f in physical['files']}
    for item in physical['files']:
        file=physical_path.parent/item['path'];assert sha(file)==item['sha256'],f'physical evidence changed: {file}'
    records.append(dict(kind='physical',path=str(physical_path),sha256=sha(physical_path)))
    return dict(status='passed_M1_board' if validation_profile=='formal_m1' else 'passed_M1_experimental_demo',
                board_acceptance_passed=validation_profile=='formal_m1',
                experimental_demo_passed=validation_profile=='experimental_m1',
                validation_profile=validation_profile,identity=identity,evidence=records,numerical=numerical,
                scope='full fixed Qwen3 native format, continuous shared-prefix service and bounded recovery; no QA-quality, multi-object, power or novelty claim')


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('ddr','load','smoke','continuous','faults','isolation','benchmark','physical'):p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    report=dict(status='failed',board_acceptance_passed=False,started_at=utc())
    try:report.update(evaluate({n:getattr(a,n) for n in ('ddr','load','smoke','continuous','faults','isolation','benchmark')},a.physical))
    except Exception as exc:
        report['error']=f'{type(exc).__name__}: {exc}';raise
    finally:
        report['finished_at']=utc();save(a.output/'report.json',report);print(json.dumps(report,ensure_ascii=False))
if __name__=='__main__':main()

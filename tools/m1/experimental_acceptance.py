"""Apply identical numerical/physical gates while explicitly rejecting formal-board status."""
import argparse,json
from pathlib import Path
from board_acceptance import evaluate,save,utc

ALLOWED_UNSUPPORTED={
    'MIG_PFD_48MHZ': 'MIG input PFD 48 MHz is below its supported minimum',
    'MODULE_TIMINGS_UNCONFIRMED': 'Kingston -SP secondary timing coverage is incomplete',
    'PHYSICAL_SPEED_GRADE_UNCONFIRMED': 'Implementation uses -1-c; physical grade is unconfirmed',
}

def require_experimental_profile(data):
    assert data.get('validation_profile')=='experimental_m1', 'explicit experimental profile required'
    assert data.get('vendor_supported') is False, 'experimental profile must disclose unsupported operation'
    reasons=data.get('unsupported_reasons')
    assert isinstance(reasons,list) and reasons and all(isinstance(x,str) for x in reasons)
    assert len(set(reasons))==len(reasons) and set(reasons)<=set(ALLOWED_UNSUPPORTED), 'unreviewed support exception'
    assert 'MIG_PFD_48MHZ' in reasons, '48 MHz deviation must remain visible'


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('ddr','load','smoke','continuous','faults','isolation','benchmark','physical'):p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    report=dict(status='failed',board_acceptance_passed=False,experimental_demo_passed=False,started_at=utc())
    try:
        report.update(evaluate({n:getattr(a,n) for n in ('ddr','load','smoke','continuous','faults','isolation','benchmark')},a.physical,validation_profile='experimental_m1'))
        report['limitations']=ALLOWED_UNSUPPORTED
    except BaseException as exc:
        report['error']=f'{type(exc).__name__}: {exc}';raise
    finally:
        report['finished_at']=utc();save(a.output/'report.json',report);print(json.dumps(report,ensure_ascii=False))
if __name__=='__main__':main()

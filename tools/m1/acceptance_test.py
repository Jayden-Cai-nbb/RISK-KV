"""Acceptance profile regression; synthetic dictionaries only, no board evidence."""
import argparse,json,unittest
from pathlib import Path
from board_acceptance import require_formal_profile,evaluate
from experimental_acceptance import require_experimental_profile
class Tests(unittest.TestCase):
    def test_formal_profile(self):require_formal_profile(dict(validation_profile='formal_m1',vendor_supported=True,unsupported_reasons=[]))
    def test_experimental_disclosure(self):require_experimental_profile(dict(validation_profile='experimental_m1',vendor_supported=False,unsupported_reasons=['MIG_PFD_48MHZ']))
    def test_formal_rejects_experimental(self):
        with self.assertRaises(AssertionError):require_formal_profile(dict(validation_profile='experimental_m1',vendor_supported=False,unsupported_reasons=['MIG_PFD_48MHZ']))
    def test_no_blanket_exception(self):
        with self.assertRaises(AssertionError):require_experimental_profile(dict(validation_profile='experimental_m1',vendor_supported=False,unsupported_reasons=['MIG_PFD_48MHZ','NEGATIVE_HOLD_SLACK']))
    def test_cannot_hide_clock_deviation(self):
        with self.assertRaises(AssertionError):require_experimental_profile(dict(validation_profile='experimental_m1',vendor_supported=False,unsupported_reasons=['MODULE_TIMINGS_UNCONFIRMED']))
    def test_missing_numerical_evidence_never_passes(self):
        with self.assertRaises(KeyError):evaluate({},Path('nonexistent'),validation_profile='experimental_m1')
    def test_unknown_profile(self):
        with self.assertRaises(ValueError):evaluate({},Path('nonexistent'),validation_profile='anything')
def main():
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    r=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Tests))
    (a.output/'summary.json').write_text(json.dumps(dict(status='passed' if r.wasSuccessful() else 'failed',tests=r.testsRun,scope=__doc__),indent=2)+'\n')
    raise SystemExit(0 if r.wasSuccessful() else 1)
if __name__=='__main__':main()

"""Console action ownership/idempotency checks with no hardware backend."""
import argparse,json,threading,time,unittest,uuid
from pathlib import Path
from demo import Console
class Tests(unittest.TestCase):
    def setUp(self):
        self.out=OUTPUT/self._testMethodName;self.cfg=Path('configs/m1/platform-unbound.json')
        self.c=Console(self.cfg,Path('assets/reference'),self.out,'demo')
    def tearDown(self):self.c.stop.set()
    def test_unknown_phase_no_query(self):
        with self.assertRaises(RuntimeError):self.c.submit('query-a',str(uuid.uuid4()))
        self.assertFalse(self.c.busy)
    def test_duplicate_job_never_executes_twice(self):
        entered=threading.Event();release=threading.Event();calls=[]
        def runner(job):calls.append(job['id']);entered.set();release.wait(2)
        self.c.run=runner;rid=str(uuid.uuid4());self.c.submit('inspect',rid);self.assertTrue(entered.wait(1))
        self.c.submit('inspect',rid);self.assertEqual(calls,[rid]);release.set()
    def test_same_id_cannot_change_action(self):
        rid=str(uuid.uuid4());self.c.jobs[rid]=dict(id=rid,action='inspect')
        with self.assertRaises(ValueError):self.c.submit('load',rid)
    def test_busy_does_not_queue_hardware_action(self):
        self.c.busy=True
        with self.assertRaises(RuntimeError):self.c.submit('inspect',str(uuid.uuid4()))
        self.assertEqual(self.c.jobs,{})
    def test_unbound_refused_without_hardware(self):
        rid=str(uuid.uuid4());self.c.submit('inspect',rid)
        for _ in range(100):
            if not self.c.busy:break
            time.sleep(.01)
        self.assertEqual(self.c.jobs[rid]['status'],'failed');self.assertIsNone(self.c.driver)
        self.assertFalse(self.c.snapshot()['connected']);self.assertTrue(self.c.snapshot()['stale'])
    def test_stale_data_never_shown_live(self):
        self.c.state.update(connected=True,last_observation_ns=time.time_ns()-6_000_000_000)
        self.assertTrue(self.c.snapshot()['stale'])
    def test_export_only_completed_jobs(self):
        import hashlib
        done=str(uuid.uuid4());running=str(uuid.uuid4())
        for jid,status in ((done,'completed'),(running,'running')):
            (self.out/jid).mkdir();(self.out/jid/'raw.bin').write_bytes(b'actual-artifact-bytes')
            self.c.jobs[jid]=dict(id=jid,status=status,action='inspect')
        report=self.c.export_report();self.assertFalse(report['board_acceptance_passed'])
        self.assertEqual(len(report['files']),1)
        self.assertEqual(report['files'][0]['path'],done+'/raw.bin')
        self.assertEqual(report['files'][0]['sha256'],hashlib.sha256(b'actual-artifact-bytes').hexdigest())
    def test_refresh_does_not_create_jobs(self):
        for _ in range(10):self.c.snapshot()
        self.assertEqual(self.c.jobs,{})
def main():
    global OUTPUT
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args();OUTPUT=a.output;OUTPUT.mkdir(parents=True,exist_ok=False)
    r=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Tests))
    (OUTPUT/'summary.json').write_text(json.dumps(dict(status='passed' if r.wasSuccessful() else 'failed',tests=r.testsRun,scope=__doc__),indent=2)+'\n');raise SystemExit(0 if r.wasSuccessful() else 1)
if __name__=='__main__':main()

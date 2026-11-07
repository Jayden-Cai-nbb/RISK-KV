"""Host trust crash/restart and byte-order checks; fake RPC, no hardware evidence."""
import argparse
import json
import os
from pathlib import Path
import queue
import subprocess
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from jtag_transport import GuardedJtag, Quarantined, TransportError, VivadoSession, RemoteCommandError


def config(path):
    return dict(profile='jtg1_diagnostic', memory_bytes=65536, target_serial='test-only',
                bit_sha256='0'*64, ltx_sha256='1'*64, state_path=str(path))


class FakeSession:
    def __init__(self, cfg, output):
        self.path=Path(cfg['state_path']); self.calls=[]; self.memory=bytearray(65536)
        self.mode=None

    def call(self, op, *fields):
        self.calls.append((op,*fields))
        if op == 'VIO':
            if self.mode=='vio_error': raise RemoteCommandError('VIO identity changed')
            status=0x24c7|0x100 if self.mode=='busy' else 0x4c7
            return ' '.join(f'{x:016x}' for x in (0x4a544731,1,status,0,0,0,0,0))
        if op == 'VCTL': return ''
        state=json.loads(self.path.read_text())
        assert state['status']=='PENDING' and state['pending']['operation']==op
        address=int(fields[0],16); words=int(fields[1])
        assert address//4096==(address+words*8-1)//4096
        if self.mode=='lost': raise TransportError('lost response')
        if self.mode=='short': return '0'*15
        if self.mode=='crash': os._exit(71)
        if self.mode=='interrupt': raise KeyboardInterrupt('test interrupt')
        if op=='WRITE':
            raw=fields[2]
            data=b''.join(int(raw[i:i+16],16).to_bytes(8,'little') for i in reversed(range(0,len(raw),16)))
            self.memory[address:address+len(data)]=data
            return raw
        if address>=0x80000000:
            value={0x80000000:0x0000000152564b50,0x80000048:0x4a54473100000001}[address]
            if self.mode=='stale_identity': value=0x0000000152564b50
            return f'{value:016x}'
        data=self.memory[address:address+8*words]
        if self.mode=='corrupt' and data:data[0]^=1
        return ''.join(f'{int.from_bytes(data[i:i+8],"little"):016x}' for i in reversed(range(0,len(data),8)))

    def close(self): pass


class TrustTests(unittest.TestCase):
    def setUp(self):
        self.case=OUTPUT/self._testMethodName; self.case.mkdir()
        self.cfg=config(self.case/'state.json')
        self.driver=GuardedJtag(self.cfg,self.case/'unused',FakeSession)

    def tearDown(self): self.driver.close()

    def test_first_connection_and_reconnect_need_live_checks(self):
        with self.assertRaises(Quarantined): self.driver.read64(0)
        self.driver.activate(); self.driver.close()
        self.driver=GuardedJtag(self.cfg,self.case/'unused2',FakeSession)
        before=len(self.driver.session.calls)
        with self.assertRaises(Quarantined): self.driver.write64(0,1)
        self.assertEqual(len(self.driver.session.calls),before)
        self.driver.activate(); self.driver.write64(0,0x0123456789abcdef)
        self.assertEqual(self.driver.memory_read(0,8),bytes.fromhex('efcdab8967452301'))

    def test_boundary_and_word_order(self):
        self.driver.activate()
        data=bytes((i*37+19)%256 for i in range(6168))
        self.driver.memory_write(4088,data)
        self.assertEqual(self.driver.memory_read(4088,len(data)),data)
        self.assertEqual(self.driver.memory_read(4093,4099),data[5:4104])
        writes=[row for row in self.driver.session.calls if row[0]=='WRITE']
        self.assertEqual([int(row[2]) for row in writes],[1,256,256,256,2])

    def test_uncertain_write_never_retried_or_cleared_by_cold(self):
        self.driver.activate(); self.driver.session.mode='lost'
        with self.assertRaises(TransportError): self.driver.write64(0,123)
        before=len(self.driver.session.calls)
        for action in (lambda:self.driver.read64(0),lambda:self.driver.write64(0,456),self.driver.activate):
            with self.assertRaises(Quarantined): action()
        self.assertEqual(len(self.driver.session.calls),before)
        self.driver.diagnostic_control(1); self.driver.diagnostic_control(0)
        self.assertEqual(self.driver.observe()['host_trust'],'QUARANTINED')
        self.driver.close(); self.driver=GuardedJtag(self.cfg,self.case/'unused2',FakeSession)
        with self.assertRaises(Quarantined): self.driver.activate()
        self.assertFalse(any(row[0] in ('READ','WRITE') for row in self.driver.session.calls))
        saved=json.loads(Path(self.cfg['state_path']).read_text())
        self.assertEqual(saved['first_failure']['pending']['operation'],'WRITE')

    def test_short_response_is_quarantined(self):
        self.driver.activate(); self.driver.session.mode='short'
        with self.assertRaises(TransportError): self.driver.read64(0)
        self.assertEqual(self.driver.state['status'],'QUARANTINED')

    def test_interrupt_is_quarantined(self):
        self.driver.activate(); self.driver.session.mode='interrupt'
        with self.assertRaises(KeyboardInterrupt): self.driver.read64(0)
        self.assertEqual(json.loads(Path(self.cfg['state_path']).read_text())['status'],'QUARANTINED')

    def test_distinct_identity_reads_detect_stale_return(self):
        self.driver.session.mode='stale_identity'
        with self.assertRaises(Quarantined): self.driver.activate()
        self.assertEqual(self.driver.state['status'],'QUARANTINED')

    def test_reject_unbound_mask_and_range_without_dispatch(self):
        self.driver.activate(); before=len(self.driver.session.calls)
        for action in (lambda:self.driver.memory_write(1,b'12345678'),
                       lambda:self.driver.memory_write_masked(0,b'12345678',bytes(8))):
            with self.assertRaises(NotImplementedError): action()
        for action in (lambda:self.driver.memory_read(65530,8),lambda:self.driver.memory_write(-8,b'12345678')):
            with self.assertRaises(ValueError): action()
        self.assertEqual(len(self.driver.session.calls),before)
        self.assertEqual(self.driver.state['status'],'READY')

    def test_second_owner_refused(self):
        with self.assertRaises(TransportError): GuardedJtag(self.cfg,self.case/'second',FakeSession)

    def test_foreign_journal_is_not_rewritten(self):
        self.driver.close(); old=Path(self.cfg['state_path']).read_bytes()
        other=dict(self.cfg,bit_sha256='f'*64)
        with self.assertRaises(Quarantined): GuardedJtag(other,self.case/'unused2',FakeSession)
        self.assertEqual(Path(self.cfg['state_path']).read_bytes(),old)
        self.driver=GuardedJtag(self.cfg,self.case/'unused3',FakeSession)

    def test_vio_error_prevents_later_axi(self):
        self.driver.activate(); self.driver.session.mode='vio_error'
        with self.assertRaises(RemoteCommandError): self.driver.observe()
        before=len(self.driver.session.calls)
        with self.assertRaises(Quarantined): self.driver.read64(0)
        self.assertEqual(len(self.driver.session.calls),before)

    def test_cold_refused_while_real_responsibility_pending(self):
        self.driver.activate(); self.driver.session.mode='busy'
        with self.assertRaises(Quarantined): self.driver.diagnostic_control(1)
        self.assertFalse(any(row[0]=='VCTL' for row in self.driver.session.calls))

    def test_clean_cold_requires_connection_recheck(self):
        self.driver.activate(); self.driver.diagnostic_control(1); self.driver.diagnostic_control(0)
        with self.assertRaises(Quarantined): self.driver.read64(0)
        self.driver.activate(); self.assertEqual(self.driver.read64(0),0)

    def test_actual_process_crash_retains_pending(self):
        self.driver.close()
        process=subprocess.run([sys.executable,str(Path(__file__).resolve()),'--crash-state',self.cfg['state_path']])
        self.assertEqual(process.returncode,71)
        self.assertEqual(json.loads(Path(self.cfg['state_path']).read_text())['status'],'PENDING')
        self.driver=GuardedJtag(self.cfg,self.case/'unused2',FakeSession)
        self.assertEqual(self.driver.state['status'],'QUARANTINED')
        with self.assertRaises(Quarantined): self.driver.activate()
        self.assertFalse(any(row[0] in ('READ','WRITE') for row in self.driver.session.calls))


class FramingTests(unittest.TestCase):
    def session(self,item):
        obj=VivadoSession.__new__(VivadoSession)
        obj.nonce='a'*32; obj.broken=False; obj.events=queue.Queue(); obj.events.put(item)
        return obj

    def test_stale_rpc_sequence_breaks_stream(self):
        obj=self.session(['RKVJTAG','a'*32,'6','OK','30'])
        with self.assertRaises(TransportError): obj._response(7,.1)
        self.assertTrue(obj.broken)

    def test_matched_tcl_error_preserves_vio_rpc(self):
        obj=self.session(['RKVJTAG','a'*32,'7','ERROR','6c6f7374'])
        with self.assertRaises(RemoteCommandError): obj._response(7,.1)
        self.assertFalse(obj.broken)

    def test_eof_breaks_stream(self):
        obj=self.session(None)
        with self.assertRaises(TransportError): obj._response(7,.1)
        self.assertTrue(obj.broken)


def fake_programmer(cfg, output):
    saved=json.loads(Path(cfg['state_path']).read_text())
    assert saved['status']=='RECOVERING' and saved['image']['status']=='INVALID_AFTER_CONFIGURATION_REQUEST'
    return dict(status='programmed_reviewed_jtg1',bit_sha256=cfg['bit_sha256'],ltx_sha256=cfg['ltx_sha256'],unit_test_only=True)


class RecoveryTests(unittest.TestCase):
    setUp=TrustTests.setUp
    tearDown=TrustTests.tearDown

    def recover(self):
        return self.driver.reconfigure_diagnostic(self.case/'recover',fake_programmer)

    def test_configuration_does_not_qualify_contents(self):
        incarnation=self.recover()
        self.assertEqual(self.driver.state['status'],'READY')
        with self.assertRaises(Quarantined):self.driver.require_verified_image(incarnation)
        data=bytes(range(256))*256
        self.driver.validate_diagnostic_image(data,self.case/'image',write=True)
        self.assertEqual(self.driver.require_verified_image(incarnation)['bytes'],65536)
        self.driver.write64(0,0)
        with self.assertRaises(Quarantined):self.driver.require_verified_image(incarnation)

    def test_new_connection_requires_full_content_recheck(self):
        incarnation=self.recover();data=bytes(range(256))*256
        self.driver.validate_diagnostic_image(data,self.case/'image',write=True)
        self.driver.close();self.driver=GuardedJtag(self.cfg,self.case/'unused3',FakeSession)
        self.driver.session.memory[:]=data
        self.driver.activate()
        with self.assertRaises(Quarantined):self.driver.require_verified_image(incarnation)
        before=len(self.driver.session.calls)
        self.driver.validate_diagnostic_image(data,self.case/'recheck')
        self.assertEqual(self.driver.require_verified_image(incarnation)['status'],'VERIFIED')
        self.assertFalse(any(row[0]=='WRITE' for row in self.driver.session.calls[before:]))

    def test_pending_hardware_prevents_programmer(self):
        self.driver.session.mode='busy';called=[]
        def programmer(*args):called.append(1);raise AssertionError('must not execute')
        with self.assertRaises(Quarantined):self.driver.reconfigure_diagnostic(self.case/'recover',programmer)
        self.assertEqual(called,[])

    def test_program_failure_keeps_old_identity_and_archive(self):
        before=Path(self.cfg['state_path']).read_bytes()
        def programmer(*args):raise TransportError('programming interrupted')
        with self.assertRaises(TransportError):self.driver.reconfigure_diagnostic(self.case/'recover',programmer)
        self.assertEqual(self.driver.state['status'],'QUARANTINED')
        self.assertIsNone(self.driver.state['incarnation'])
        self.assertEqual((self.case/'recover/previous-state.json').read_bytes(),before)

    def test_invalid_program_receipt_refused(self):
        with self.assertRaises(TransportError):self.driver.reconfigure_diagnostic(self.case/'recover',lambda *_:{})
        self.assertEqual(self.driver.state['status'],'QUARANTINED')

    def test_post_program_busy_is_not_a_new_incarnation(self):
        def factory(cfg,out):
            value=FakeSession(cfg,out);value.mode='busy';return value
        self.driver.session_factory=factory
        with self.assertRaises(TransportError):self.recover()
        self.assertIsNone(self.driver.state['incarnation'])
        self.assertEqual(self.driver.state['status'],'QUARANTINED')

    def test_bad_image_never_becomes_usable(self):
        incarnation=self.recover();self.driver.session.mode='corrupt'
        with self.assertRaises(TransportError):self.driver.validate_diagnostic_image(bytes(range(256))*256,self.case/'image',write=True)
        self.assertEqual(self.driver.state['status'],'QUARANTINED')
        self.assertEqual(json.loads((self.case/'image/first-difference.json').read_text())['address'],0)
        with self.assertRaises(Quarantined):self.driver.require_verified_image(incarnation)

    def test_new_generation_rejects_old_content_qualification(self):
        old=self.recover();data=bytes(range(256))*256
        self.driver.validate_diagnostic_image(data,self.case/'image',write=True)
        new=self.driver.reconfigure_diagnostic(self.case/'recover2',fake_programmer)
        self.assertNotEqual(old,new)
        with self.assertRaises(Quarantined):self.driver.require_verified_image(old)
        with self.assertRaises(Quarantined):self.driver.require_verified_image(new)

    def test_process_crashes_during_recovery_and_between_image_bursts(self):
        self.driver.close()
        for mode,expected in (('before_program',72),('after_program',73),('image_gap',74)):
            with self.subTest(mode=mode):
                state=self.case/(mode+'.json')
                process=subprocess.run([sys.executable,str(Path(__file__).resolve()),'--recovery-crash',mode,'--crash-state',str(state)])
                self.assertEqual(process.returncode,expected)
                saved=json.loads(state.read_text())
                self.assertEqual(saved['status'],'READY' if mode=='image_gap' else 'RECOVERING')
                self.driver=GuardedJtag(config(state),self.case/('reopen-'+mode),FakeSession)
                self.assertEqual(self.driver.state['status'],'QUARANTINED')
                self.assertFalse(any(row[0] in ('READ','WRITE') for row in self.driver.session.calls))
                self.driver.close()


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path)
    parser.add_argument('--crash-state',type=Path)
    parser.add_argument('--recovery-crash',choices=('before_program','after_program','image_gap'))
    args=parser.parse_args()
    if args.crash_state:
        if args.recovery_crash:
            cfg=config(args.crash_state);calls=[]
            def factory(config,out):
                calls.append(1)
                if len(calls)==2 and args.recovery_crash=='after_program':os._exit(73)
                return FakeSession(config,out)
            d=GuardedJtag(cfg,'unused',factory)
            def programmer(config,out):
                if args.recovery_crash=='before_program':os._exit(72)
                return fake_programmer(config,out)
            d.reconfigure_diagnostic(args.crash_state.with_suffix('.recovery'),programmer)
            original=d._burst
            def burst(*a,**k):
                result=original(*a,**k)
                if a[0]=='WRITE':os._exit(74)
                return result
            d._burst=burst
            d.validate_diagnostic_image(bytes(range(256))*256,args.crash_state.with_suffix('.image'),write=True)
            raise AssertionError('unreachable recovery crash')
        d=GuardedJtag(config(args.crash_state),'unused',FakeSession); d.activate()
        d.session.mode='crash'; d.write64(0,99); raise AssertionError('unreachable')
    if args.output is None: parser.error('--output required')
    OUTPUT=args.output.resolve(); OUTPUT.mkdir(parents=True,exist_ok=False)
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__]))
    (OUTPUT/'summary.json').write_text(json.dumps(dict(status='passed' if result.wasSuccessful() else 'failed',
        tests=result.testsRun, failures=len(result.failures),errors=len(result.errors),
        scope='Python persistent trust, process crash, framing and byte conversion with fake RPC; no hardware'),indent=2)+'\n')
    raise SystemExit(not result.wasSuccessful())

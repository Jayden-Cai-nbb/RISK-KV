"""Host/acceptance negative checks; this simulator is never board evidence."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/m1'))
import host
import board_acceptance
LAYOUT=json.loads((ROOT/'configs/m1/layout.json').read_text())

class MailboxFixture:
    # Separate tiny firmware boundary model: CQ visibility never commits;
    # only exact staged receipt consumption commits a build. No NPU numerics.
    def __init__(self):
        self.r=[0]*64;self.r[18]=1;self.sequence=1;self.generation=0;self.commits=0;self.cq=None
    def mailbox_read(self,w,n):return self.r[w:w+n]
    def mailbox_write(self,w,values):
        self.r[w:w+len(values)]=values
        if w!=0:return
        action,op=self.r[1:3];identity=self.r[3:10]
        if action==1:
            assert self.cq is None
            if identity[3]!=self.sequence:self.r[17]=0x80020001
            else:
                self.cq=[op,0,*identity,374,28];self.r[20:31]=self.cq
                self.sequence+=1;self.r[17]=0
        elif action==2:
            if self.cq is None or identity!=self.cq[2:9]:self.r[17]=8
            else:
                if self.cq[0]==2:self.generation+=1
                if self.cq[0]==3:self.commits+=1
                self.cq=None;self.r[17]=0
        self.r[33]=self.generation;self.r[34]=self.sequence;self.r[35]=0;self.r[16]=self.r[0]
    def observe(self):return dict(backend_kind='software_fixture',committed_tasks=self.commits,task_active=False)

class HostTests(unittest.TestCase):
    def test_visibility_identity_consumption(self):
        driver=MailboxFixture();client=host.Mailbox(driver,LAYOUT,timeout=.02)
        client.operation('BOOT');client.operation('REGISTER')
        result=client.command('BUILD');self.assertEqual(driver.commits,0)
        bad=dict(result['cq']);bad['session']^=1
        with self.assertRaises(RuntimeError):client.exchange(2,receipt=bad)
        self.assertEqual(driver.commits,0)
        client.consume(result);self.assertEqual(driver.commits,1)
        self.assertEqual(client.sequence,4);self.assertEqual(client.generation,1)
    def test_software_backend_cannot_be_hardware(self):
        with self.assertRaises(RuntimeError):host.validate_platform(dict(state='bound'),dict(backend_kind='software_fixture'),LAYOUT)
    def test_serial_exhaustion(self):
        d=MailboxFixture();d.r[0]=0xffffffff;c=host.Mailbox(d,LAYOUT)
        with self.assertRaises(RuntimeError):c.operation('BOOT')
        self.assertEqual(d.sequence,1)
    def test_partial_report_cannot_pass_board(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'report.json';p.write_text(json.dumps(dict(command='ddr',status='pending_platform_binding')))
            with self.assertRaises(AssertionError):board_acceptance.evaluate({'ddr':p},p)
    def test_formal_profile_fails_closed(self):
        formal=dict(validation_profile='formal_m1',vendor_supported=True,unsupported_reasons=[])
        board_acceptance.require_formal_profile(formal)
        for bad in ({},dict(formal,validation_profile='experimental_clock48'),
                    dict(formal,vendor_supported=False),dict(formal,vendor_supported='true'),
                    dict(formal,unsupported_reasons=['MIG PFD below supported range'])):
            with self.subTest(profile=bad):
                with self.assertRaises(AssertionError):board_acceptance.require_formal_profile(bad)
    def test_experimental_hardware_report_cannot_pass_formal(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'report.json'
            p.write_text(json.dumps(dict(command='ddr',status='passed_ddr_subset',hardware=dict(
                backend_kind='hardware',validation_profile='experimental_clock48',
                vendor_supported=False,unsupported_reasons=['48 MHz MIG reference']))))
            with self.assertRaisesRegex(AssertionError,'experimental profile'):
                board_acceptance.evaluate({'ddr':p},p)
    def test_four_token_extraction(self):
        import hashlib
        raw=host.four_token_prefix(ROOT/'assets/reference')
        self.assertEqual(len(raw),15138816)
        # Observed complete four-token RTL snapshot, not a hash computed by this test.
        self.assertEqual(hashlib.sha256(raw).hexdigest(),'23cf98b2bff28698e10235408f3dbb743680779a0d50eef1aff6998615cd7bd4')
    def test_non_argmax_difference_is_not_ignored(self):
        with tempfile.TemporaryDirectory() as tmp:
            class Memory:
                def observe(self):return {'host_read_grant':True}
                def memory_read(self,a,n):return b'\x02\x00\x80\x3f'
            path=Path(tmp)/'bad.bin'
            with self.assertRaises(AssertionError):host.checked_read(Memory(),13312,b'\x01\x00\x80\x3f',path)
            self.assertEqual(json.loads(path.with_suffix('.difference.json').read_text())['address'],13312)
    def test_cold_ready_must_be_fresh(self):
        class BootDriver:
            def __init__(self):self.ready=7;self.hold=True;self.events=[]
            def observe(self):return {'boot_waiting':self.hold}
            def mailbox_write(self,w,values):
                assert self.hold and w==18
                self.events.append('clear');self.ready=values[0]
            def mailbox_read(self,w,n):return [self.ready]
            def release_cpu(self):
                assert self.ready==0
                self.events.append('release');self.hold=False;self.ready=1
        d=BootDriver();host.release_loaded_cpu(d,LAYOUT)
        self.assertEqual(d.events,['clear','release']);self.assertEqual(d.ready,1)
    def test_wrong_live_abi_rejected(self):
        cfg=dict(state='bound',part='xcvu440-flga2892-2-e',logical_bytes=2147483648,core_hz=50000000,fast_hz=100000000,
                 clock_phase_verified=True,vivado_version='fixture',bit_sha256='a',ltx_sha256='b',firmware_sha256='c')
        info=dict(cfg,backend_kind='hardware',device_id='TEST_FIXTURE_NOT_A_BOARD',ddr_capacity_bytes=2147483648,ddr_calibrated=True,
                  abi_magic=0x524e5033,layout_version=1,firmware_mode='mailbox')
        with self.assertRaisesRegex(AssertionError,'live ABI'):host.validate_platform(cfg,info,LAYOUT)
    def test_load_refuses_running_cpu_before_write(self):
        class UnsafeDriver:
            def hold_cold_boot(self):pass
            def observe(self):return dict(boot_waiting=False,host_write_grant=False,host_idle=True)
            def memory_write(self,*args):raise RuntimeError('must never reach memory mutation')
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(AssertionError,'phase not granted'):
                host.load_and_verify(UnsafeDriver(),LAYOUT,Path(tmp))

if __name__=='__main__':unittest.main()

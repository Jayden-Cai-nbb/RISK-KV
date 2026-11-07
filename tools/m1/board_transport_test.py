"""M1 host framing/mask/crash checks with fake RPC; not hardware evidence."""
import argparse,json,sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from board_transport import BoardTransport
from jtag_transport import TransportError,Quarantined

class Fake:
    def __init__(self,cfg,out):
        self.cfg=cfg;self.calls=[];self.memory=bytearray(32768);self.mask=255;self.fail=False;self.sequence=0;self.flags=(1<<4)|(1<<5)|(1<<6)|(1<<7)|(1<<10)|(1<<15)|(1<<16);self.misc=12
    def call(self,op,*args):
        self.calls.append((op,*args))
        if op=='QSTATUS':return '00000009'
        if op=='VIO':
            self.sequence+=1;w=[0]*48;w[0]=self.flags;w[1]=1;w[38]=3;w[42]=self.sequence
            bits=sum(x<<(32*i) for i,x in enumerate(w))
            return ' '.join([f'{x:016x}' for x in (0x4d314231,99,self.sequence,self.misc)]+[f'{(bits>>(i*256))&((1<<256)-1):064x}' for i in range(6)])
        state=json.loads(Path(self.cfg['state_path']).read_text());assert state['status']=='PENDING'
        if self.fail:raise TransportError('injected lost response')
        if op=='VCTL':
            value=int(args[0],16);self.mask=(value>>8)&255 if value&4 else 255;return 'ok'
        a=int(args[0],16);n=int(args[1])*(8 if op in ('READ','WRITE') else 1)
        if a==0x80000000:data=(0x152564b50).to_bytes(8,'little')
        elif a==0x80000048:data=self.cfg['experiment_id'].to_bytes(8,'little')
        elif op in ('WRITE','BWRITE'):
            raw=args[2];data=b''.join(int(raw[i:i+16],16).to_bytes(8,'little') for i in reversed(range(0,len(raw),16)))
            for i,x in enumerate(data):
                if self.mask>>(i%8)&1:self.memory[a+i]=x
        else:data=bytes(self.memory[a:a+n])
        return ''.join(f'{int.from_bytes(data[i:i+8],"little"):016x}' for i in reversed(range(0,len(data),8)))
    def close(self):pass

class Tests(unittest.TestCase):
    def setUp(self):
        self.out=OUTPUT/self._testMethodName;self.out.mkdir()
        self.cfg=dict(profile='m1_experimental_board',memory_bytes=2**31,target_serial='synthetic-test-only',bit_sha256='0'*64,ltx_sha256='1'*64,experiment_id=0xabcdef0123456789,state_path=str(self.out/'state.json'),owner_lock_path=str(self.out/'owner.lock'))
        self.t=BoardTransport(self.cfg,self.out/'session',Fake);self.t.activate()
    def tearDown(self):self.t.close()
    def test_bulk_order_and_unaligned_read(self):
        data=bytes((i*71+39)&255 for i in range(16384));self.t.memory_write(4088,data)
        self.assertEqual(self.t.memory_read(4088,len(data)),data)
        self.assertEqual(self.t.memory_read(4093,8197),data[5:8202])
    def test_real_masks_without_read_modify_write(self):
        self.t.memory_write(0,bytes([0xa5])*128);before=len(self.t.session.calls)
        data=bytes(range(83));mask=bytes(i%2 for i in range(83))
        self.t.memory_write_masked(3,data,mask)
        self.assertFalse(any(x[0] in ('READ','BREAD') for x in self.t.session.calls[before:]))
        expected=bytearray([0xa5]*128)
        for i,x in enumerate(data):
            if mask[i]:expected[i+3]=x
        self.assertEqual(self.t.memory_read(0,128),bytes(expected))
        self.assertEqual(self.t.session.mask,255)
    def test_unaligned_write_preserves_neighbors(self):
        self.t.memory_write(0,bytes([0x91])*128);self.t.memory_write(5,b'abcde123456789')
        self.assertEqual(self.t.memory_read(0,24),bytes([0x91])*5+b'abcde123456789'+bytes([0x91])*5)
    def test_empty_masked_write_no_transaction(self):
        before=len(self.t.session.calls);self.t.memory_write_masked(3,b'',b'')
        self.assertEqual(len(self.t.session.calls),before)
    def test_mask_input_prevalidated(self):
        before=len(self.t.session.calls)
        with self.assertRaises(ValueError):self.t.memory_write_masked(0,b'ab',bytes([0,2]))
        self.assertEqual(len(self.t.session.calls),before)
    def test_bulk_loss_stays_quarantined_after_restart(self):
        self.t.session.fail=True
        with self.assertRaises(TransportError):self.t.memory_write(0,bytes(4096))
        self.assertEqual(self.t.state['first_failure']['pending']['operation'],'BWRITE')
        self.t.close();self.t=BoardTransport(self.cfg,self.out/'session2',Fake)
        with self.assertRaises(Quarantined):self.t.activate()
        self.assertFalse(any(x[0] in ('READ','BREAD','WRITE','BWRITE') for x in self.t.session.calls))
    def test_control_loss_quarantines(self):
        self.t.session.fail=True
        with self.assertRaises(TransportError):self.t.set_control(4)
        self.assertEqual(self.t.state['first_failure']['pending']['operation'],'VCTL')
    def test_native_isolation_retains_csr_diagnostics(self):
        self.t.session.flags|=(1<<2)|(1<<11)
        self.assertTrue(self.t.observe()['isolated'])
        self.assertEqual(self.t.read64(0x80000000),0x152564b50)
    def test_mig_fault_quarantines(self):
        self.t.session.misc|=16;self.t.observe()
        with self.assertRaises(Quarantined):self.t.read64(0x80000000)
    def test_no_legacy_reset(self):
        with self.assertRaises(TransportError):self.t.diagnostic_control(1)

def main():
    global OUTPUT
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    OUTPUT=a.output;OUTPUT.mkdir(parents=True,exist_ok=False)
    r=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Tests))
    (OUTPUT/'summary.json').write_text(json.dumps(dict(status='passed' if r.wasSuccessful() else 'failed',tests=r.testsRun,scope=__doc__),indent=2)+'\n')
    raise SystemExit(0 if r.wasSuccessful() else 1)
if __name__=='__main__':main()

"""Host-side protocol checks: no hardware claim and no simulated NPU answers."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('host_control', ROOT/'tools/m1/host_control.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class HostControlTest(unittest.TestCase):
    def setUp(self):
        self.memory = {0x80000000:0x0000000152564b50, 0x80000040:1, 0x80000048:0, 0x80000010:0}
        self.writes = []
        def write(address, value):
            self.writes.append((address,value))
            if address != 0x80000010:
                self.memory[address] = value
        self.port = module.HostControl(lambda address:self.memory[address], write)

    def test_alias_and_doorbell_order(self):
        self.port.mailbox_write(1,range(11))
        self.port.mailbox_write(0,[17])
        self.assertEqual(self.writes,[(0x80010000+(i+1)*8,i) for i in range(11)]+[(0x80010000,17)])
        self.assertEqual(self.port.mailbox_read(0,12),[17]+list(range(11)))
        self.port.mailbox_write(63,[0xffffffff])
        self.assertEqual(self.writes[-1],(0x800101f8,0xffffffff))

    def test_prevalidate_before_side_effect(self):
        for first,values in [(63,[0,1]),(-1,[1]),(1,[1,1<<32]),(1,[True])]:
            with self.assertRaises(ValueError):self.port.mailbox_write(first,values)
        self.assertEqual(self.writes,[])
        self.memory[0x80010000]=1<<32
        with self.assertRaises(RuntimeError):self.port.mailbox_read(0,1)

    def test_identity_and_request_semantics(self):
        self.assertEqual(self.port.verify_identity(),dict(experiment_id=0,support=1))
        self.port.release_boot();self.port.controlled_reset()
        self.assertEqual(self.writes,[(0x80000010,0x52554e31),(0x80000018,0x52535431)])
        self.memory[0x80000000]=0
        with self.assertRaises(RuntimeError):self.port.verify_identity()

if __name__=='__main__':unittest.main()

"""M1 control/mailbox address translation over a supplied 64-bit AXI transport.

This is not a hardware backend. read64/write64 must finish the actual AXI
response, raise on errors and never retry writes after uncertain completion.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

class HostControl:
    def __init__(self, read64, write64, config=None):
        self.read64 = read64
        self.write64 = write64
        self.config = config or json.loads((ROOT/'configs/m1/host-control.json').read_text())
        if self.config['schema_version'] != 1:
            raise ValueError('unsupported host control map')

    def address(self, name):
        return self.config['control_base'] + self.config['registers'][name]['offset']

    def read_register(self, name):
        value = self.read64(self.address(name))
        if type(value) is not int or not 0 <= value < 1 << 64:
            raise ValueError('transport returned an invalid 64-bit value')
        return value

    def verify_identity(self):
        expected = self.config['abi_version'] << 32 | self.config['abi_magic']
        if self.read_register('identity') != expected:
            raise RuntimeError('host control ABI identity mismatch')
        return dict(experiment_id=self.read_register('experiment_id'),
                    support=self.read_register('support'))

    def _range(self, first, count):
        if type(first) is not int or type(count) is not int or min(first, count) < 0 or first + count > self.config['mailbox_words']:
            raise ValueError('mailbox range outside the 64-word aperture')
        return [self.config['mailbox_alias_base'] + i*self.config['mailbox_stride'] for i in range(first, first+count)]

    def mailbox_read(self, first, count):
        values = []
        for address in self._range(first, count):
            value = self.read64(address)
            if type(value) is not int or not 0 <= value < 1 << 32:
                raise RuntimeError('mailbox response has nonzero reserved bits or an invalid value')
            values.append(value)
        return values

    def mailbox_write(self, first, values):
        values = list(values)
        addresses = self._range(first, len(values))
        # Validate the whole descriptor before the first potentially visible write.
        if any(type(v) is not int or not 0 <= v < 1 << 32 for v in values):
            raise ValueError('mailbox values must be unsigned 32-bit words')
        for address, value in zip(addresses, values):
            self.write64(address, value)

    def release_boot(self):
        self.write64(self.address('boot'), self.config['boot_release_key'])
        if self.read_register('boot') != 0:
            raise RuntimeError('boot hold was not released; inspect platform health and outstanding DDR')

    def controlled_reset(self):
        # Request only; the caller must wait for retirement/cleanup and a new epoch.
        self.write64(self.address('reset'), self.config['controlled_reset_key'])

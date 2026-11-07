"""Persistent Vivado AXI transport with durable, fail-closed host trust state.

The current hardware attachment is restricted to the reviewed JTG1 diagnostic.
It is a transport component, not the complete M1 board driver. No automatic
reset, reconfiguration, retry, masked-write emulation or quarantine clearance.
"""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import queue
import re
import secrets
import signal
import subprocess
import threading
import time


class TransportError(RuntimeError):
    pass


class Quarantined(TransportError):
    pass


class RemoteCommandError(TransportError):
    """Matched Tcl error: this RPC ended, but an AXI request may remain in flight."""
    pass


def digest(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def durable_bytes(path, data):
    """Publish state only after both file content and directory entry are durable."""
    temporary = path.with_name(path.name + '.' + secrets.token_hex(8) + '.tmp')
    with temporary.open('xb') as stream:
        stream.write(data); stream.flush(); os.fsync(stream.fileno())
    os.replace(temporary, path)
    fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def durable_json(path, value):
    durable_bytes(path, (json.dumps(value,sort_keys=True,indent=2)+'\n').encode('utf-8'))


class VivadoSession:
    OPERATIONS = ('READ', 'WRITE', 'VIO', 'VCTL', 'CLOSE')
    SCOPE = 'JTG1; no DDR/NPU'
    """One serial RPC stream; stdout framing is independent of Vivado messages."""
    def __init__(self, config, output):
        self.output = Path(output).resolve()
        self.output.mkdir(parents=True, exist_ok=False)
        self.nonce = secrets.token_hex(16)
        self.serial = 0
        self.broken = False
        self.events = queue.Queue()
        self.lock = threading.Lock()
        self.log = (self.output/'vivado-output.log').open('wb')
        self.requests = (self.output/'requests.jsonl').open('x')
        for key in ('bit', 'ltx'):
            if digest(config[key]) != config[key+'_sha256']:
                self.log.close(); self.requests.close()
                raise ValueError(f'{key} artifact does not match the reviewed profile')
        script = Path(config['session_script']).resolve()
        command = [str(Path(config['vivado']).resolve()), '-mode', 'batch', '-source', str(script),
                   '-tclargs', str(Path(config['ltx']).resolve()), str(config['jtag_hz']),
                   config['target_serial'], self.nonce]
        self.timeout = float(config.get('rpc_timeout_seconds', 25))
        if not 15 <= self.timeout <= 120:
            self.log.close(); self.requests.close(); raise ValueError('RPC timeout must preserve the observed Vivado timeout')
        durable_json(self.output/'session.json', dict(command=command, config=config,
                     script_sha256=digest(script), helper_sha256=digest(script.with_name('vio_access.tcl')),
                     python_source_sha256=digest(Path(__file__)), scope=self.SCOPE))
        try:
            self.process = subprocess.Popen(command, cwd=self.output, stdin=subprocess.PIPE,
                                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                            start_new_session=True)
        except BaseException:
            self.log.close(); self.requests.close(); raise
        self.reader = threading.Thread(target=self._read_output, daemon=True)
        self.reader.start()
        try:
            self.initial = self._response(0, max(60, self.timeout), 'READY')
        except BaseException:
            self.close(); raise

    def _read_output(self):
        try:
            for line in self.process.stdout:
                self.log.write(line); self.log.flush()
                prefix = ('RKVJTAG ' + self.nonce + ' ').encode()
                if line.startswith(prefix):
                    self.events.put(line.decode('ascii').strip().split(' ', 4))
        except BaseException as exc:
            self.events.put(exc)
        finally:
            self.events.put(None)

    def _response(self, serial, timeout, expected='OK'):
        try:
            item = self.events.get(timeout=timeout)
            if item is None: raise TransportError('Vivado exited before response')
            if isinstance(item, BaseException): raise TransportError(str(item))
            if len(item) != 5 or item[:3] != ['RKVJTAG', self.nonce, str(serial)]:
                raise TransportError('RPC response identity mismatch')
            payload = bytes.fromhex(item[4]).decode('utf-8')
            if item[3] == 'ERROR': raise RemoteCommandError('Vivado: ' + payload)
            if item[3] != expected: raise TransportError('Unexpected RPC status')
            return payload
        except queue.Empty as exc:
            self.broken = True
            raise TransportError('RPC timeout; hardware retirement remains unknown') from exc
        except (UnicodeError, ValueError) as exc:
            self.broken = True
            raise TransportError('Malformed RPC response') from exc
        except RemoteCommandError:
            raise
        except BaseException:
            self.broken = True
            raise

    def call(self, operation, *fields):
        with self.lock:
            if self.broken or self.process.poll() is not None:
                raise TransportError('RPC session unavailable; no implicit reconnect')
            if operation not in self.OPERATIONS:
                raise ValueError('Unsupported operation')
            parts = [str(x) for x in fields]
            if any(not re.fullmatch('[0-9a-f-]+', x) for x in parts):
                raise ValueError('Invalid wire field')
            self.serial += 1
            line = ' '.join([str(self.serial), operation, *parts]) + '\n'
            self.requests.write(json.dumps(dict(sequence=self.serial, request=line.strip(), start_ns=time.time_ns()))+'\n')
            self.requests.flush()
            try:
                self.process.stdin.write(line.encode('ascii')); self.process.stdin.flush()
                result = self._response(self.serial, self.timeout)
                self.requests.write(json.dumps(dict(sequence=self.serial, response=result, end_ns=time.time_ns()))+'\n')
                self.requests.flush()
                return result
            except BaseException as exc:
                # An explicit Tcl ERROR consumes this serial. A timeout or broken
                # framing cannot be followed by VIO on the same RPC stream.
                if not isinstance(exc, RemoteCommandError): self.broken = True
                self.requests.write(json.dumps(dict(sequence=self.serial, error=str(exc), end_ns=time.time_ns()))+'\n')
                self.requests.flush()
                raise

    def close(self):
        if not hasattr(self, 'process'): return
        if self.process.poll() is None and not self.broken:
            try: self.call('CLOSE')
            except BaseException: self.broken = True
        if self.process.poll() is None:
            try: self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(self.process.pid, signal.SIGTERM)
                try: self.process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(self.process.pid, signal.SIGKILL); self.process.wait()
        # Terminating our tool process does not retire/reset any FPGA request.
        self.reader.join(timeout=5)
        self.process.stdin.close(); self.process.stdout.close(); self.log.close(); self.requests.close()


class GuardedJtag:
    """Single-owner transport trust survives process restarts through state_path.

    This is an engineering interlock, not an authorization boundary against
    another user deleting state or operating hardware with independent tools.
    """
    PROFILE = "jtg1_diagnostic"
    MEMORY_BYTES = 65536

    def __init__(self, config, output, session_factory=VivadoSession):
        self.config = dict(config)
        if config['profile'] != self.PROFILE or config['memory_bytes'] != self.MEMORY_BYTES:
            raise ValueError('Transport profile or memory geometry differs from its reviewed attachment')
        self.path = Path(config['state_path']).resolve()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.owner = Path(config.get('owner_lock_path', self.path.with_suffix(self.path.suffix+'.lock'))).open('a')
        try:
            fcntl.flock(self.owner, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BaseException:
            self.owner.close(); raise TransportError('Another owner holds this transport state')
        self.mutex = threading.RLock()
        self.session = None
        self.session_factory = session_factory
        self.activated = False
        self.image_verified_in_session = False
        validated_state = False
        identity = {k:config[k] for k in ('profile','target_serial','bit_sha256','ltx_sha256','memory_bytes')}
        try:
            if self.path.exists():
                self.state = json.loads(self.path.read_text())
                if self.state['schema'] != 1 or self.state['identity'] != identity:
                    raise Quarantined('Stored hardware identity differs; explicit platform recovery required')
                if self.state['status'] not in ('NEW','READY','PENDING','QUARANTINED','RECOVERING'):
                    raise Quarantined('Invalid saved trust state')
                if (type(self.state['sequence']) is not int or self.state['sequence'] < 0
                        or 'first_failure' not in self.state or 'pending' not in self.state):
                    raise Quarantined('Malformed saved trust state')
                validated_state = True
                if self.state['status'] in ('PENDING','RECOVERING'):
                    self._quarantine('Previous owner ended with an unresolved transaction')
                elif self.state.get('image',{}).get('status') == 'LOADING':
                    self._quarantine('Previous owner interrupted full image verification')
            else:
                self.state = dict(schema=1, identity=identity, status='NEW', sequence=0,
                                  pending=None, first_failure=None, last_completion=None)
                self._save()
                validated_state = True
            self.state.setdefault('incarnation',None)
            self.state.setdefault('image',dict(status='UNKNOWN'))
            self.session = session_factory(config, output)
            # Read-only VIO is available even while host AXI trust is quarantined.
            self.observe()
        except BaseException:
            try:
                # Do not rewrite a foreign/corrupt journal to make it match us.
                if validated_state: self._quarantine('Connection/identity inspection failed')
            finally:
                try:
                    if self.session is not None: self.session.close()
                finally: self.owner.close()
            raise

    def _save(self):
        self.state['updated_ns'] = time.time_ns()
        durable_json(self.path, self.state)

    def _quarantine(self, reason):
        self.activated = False
        self.image_verified_in_session = False
        self.state['status'] = 'QUARANTINED'
        if not self.state['first_failure']:
            self.state['first_failure'] = dict(reason=reason, time_ns=time.time_ns(), pending=self.state['pending'])
        self._save()

    def _allowed(self, initializing=False):
        allowed = ('NEW','READY') if initializing else ('READY',)
        if self.state['status'] not in allowed:
            raise Quarantined('Host transport is untrusted; AXI access refused before dispatch')
        if not initializing and not self.activated:
            raise Quarantined('This connection has not passed live cross-address identity checks')

    def observe(self):
        with self.mutex:
            try:
                raw = self.session.call('VIO').split()
                if len(raw) != 8 or any(not re.fullmatch('[0-9a-f]{16}', x) for x in raw):
                    raise TransportError('Malformed VIO snapshot')
                values = [int(x,16) for x in raw]
                if values[0] != 0x4a544731: raise TransportError('VIO identity mismatch')
            except BaseException as exc:
                self._quarantine(f'VIO observation failed: {exc}'); raise
            if values[2]&0x38 and self.state['status']!='QUARANTINED':
                self._quarantine('Device latched clock/ingress/gate fault')
            result = dict(zip(('magic','heartbeat','status','ingress_error','gate_error',
                               'target_accepts','target_returns','ordinary_resets'), values))
            result['host_trust'] = self.state['status']
            result['host_incarnation'] = self.state.get('incarnation')
            result['image_record'] = self.state.get('image',dict(status='UNKNOWN'))
            result['image_usable_in_this_connection'] = bool(self.image_verified_in_session and self.activated and self.state['status']=='READY')
            # Separate scans are diagnostic observations, not an atomic counter snapshot.
            result['atomic_snapshot'] = False
            return result

    def activate(self):
        with self.mutex:
            self._allowed(initializing=True)
            if self.observe()['status'] != 0x4c7:
                self._quarantine('Not healthy idle at activation'); raise Quarantined('Device is not healthy idle')
            # Two unequal live constants detect the observed fixed one-response shift.
            for address, expected in ((0x80000000,0x0000000152564b50), (0x80000048,0x4a54473100000001)):
                data = self._burst('READ', address, 1, initializing=True)
                if int.from_bytes(data, 'little') != expected:
                    self._quarantine('Live cross-address identity mismatch')
                    raise Quarantined('Live cross-address identity mismatch')
            self.state['status'] = 'READY'; self._save(); self.activated = True

    def _burst(self, operation, address, words, data=None, initializing=False):
        self._allowed(initializing)
        if type(address) is not int or address < 0 or address+words*8 > 1<<32 or address%8:
            raise ValueError('Invalid aligned byte address')
        if type(words) is not int or not 1 <= words <= 256 or address%4096+words*8>4096:
            raise ValueError('Invalid burst length/boundary')
        if operation == 'WRITE':
            if not isinstance(data, bytes) or len(data) != words*8: raise ValueError('Invalid payload')
            payload = ''.join(f'{int.from_bytes(data[i:i+8], "little"):016x}' for i in reversed(range(0,len(data),8)))
            if address<self.config['memory_bytes'] and self.state['image']['status']=='VERIFIED':
                self.state['image']=dict(status='INVALIDATED_BY_WRITE')
                self.image_verified_in_session=False
        else: payload = '-'
        previous = self.state['status']
        self.state['sequence'] += 1
        self.state['pending'] = dict(sequence=self.state['sequence'], operation=operation,
                                     address=address, words=words,
                                     payload_sha256=hashlib.sha256(data).hexdigest() if data is not None else None)
        self.state['status'] = 'PENDING'
        self._save()  # Must complete before any tool dispatch.
        try:
            raw = self.session.call(operation, f'{address:08x}', str(words), payload)
            if not re.fullmatch('[0-9a-f]{'+str(16*words)+'}', raw):
                raise TransportError('Wrong response data length/encoding')
            result = b''.join(int(raw[i:i+16],16).to_bytes(8,'little') for i in reversed(range(0,len(raw),16)))
            if operation == 'WRITE' and result != data:
                raise TransportError('Tool write payload identity mismatch')
            self.state['last_completion'] = self.state['pending']
            self.state['pending'] = None
            self.state['status'] = previous
            self._save()
            return result
        except BaseException as exc:
            self._quarantine(f'{type(exc).__name__}: {exc}')
            raise

    def read64(self, address):
        with self.mutex:
            return int.from_bytes(self._burst('READ', address, 1), 'little')

    def write64(self, address, value):
        if type(value) is not int or not 0 <= value < 1<<64: raise ValueError('Invalid uint64')
        with self.mutex:
            self._burst('WRITE', address, 1, value.to_bytes(8,'little'))

    def _range(self, address, size):
        if type(address) is not int or type(size) is not int or min(address,size)<0 or address+size>self.config['memory_bytes']:
            raise ValueError('Memory range exceeds the actual target')

    def memory_read(self, address, size):
        self._range(address,size)
        with self.mutex:
            self._allowed()
            data=bytearray(); base=address & ~7; limit=(address+size+7)&~7
            if size == 0: return b''
            cursor=base
            while cursor<limit:
                count=min(2048, 4096-cursor%4096, limit-cursor)
                data.extend(self._burst('READ',cursor,count//8)); cursor+=count
            return bytes(data[address-base:address-base+size])

    def memory_write(self, address, data):
        if not isinstance(data, bytes): raise ValueError('Expected immutable byte payload')
        self._range(address,len(data))
        if address%8 or len(data)%8:
            raise NotImplementedError('JTAG byte-enable binding missing; unaligned write refused without read-modify-write')
        with self.mutex:
            self._allowed()
            cursor=0
            while cursor<len(data):
                count=min(2048,4096-(address+cursor)%4096,len(data)-cursor)
                self._burst('WRITE',address+cursor,count//8,data[cursor:cursor+count]); cursor+=count

    def memory_write_masked(self, address, data, mask):
        raise NotImplementedError('Actual JTAG WSTRB interface is not bound; no emulated masks')

    def diagnostic_control(self, value):
        """Explicit JTG1-only hold/cold stimulus; never clears host quarantine."""
        if type(value) is not int or value not in (0,1,2,4): raise ValueError('Invalid JTG1 control')
        with self.mutex:
            if value == 1:
                status = self.observe()['status']
                if ((status>>13)&3) or status&0x100:
                    raise Quarantined('Actual responsibility still pending; cold diagnostic reset refused')
            self.session.call('VCTL', str(value))
            if value == 1:
                self.activated = False
                self.image_verified_in_session = False
                self.state['image']=dict(status='INVALIDATED_BY_DEVICE_COLD')
                self.state['last_diagnostic_cold_ns'] = time.time_ns()
                self._save()

    def reconfigure_diagnostic(self, output, programmer=None):
        """Explicit reviewed JTG1 reconfiguration, never an implicit retry.

        Returns transport readiness with INVALID contents. The host incarnation
        is bound to this programming event; it is not a hardware session epoch.
        """
        if programmer is None:
            from jtag_recovery import program_reviewed_diagnostic
            programmer=program_reviewed_diagnostic
        with self.mutex:
            if self.state['status'] not in ('NEW','READY','QUARANTINED'):
                raise Quarantined('Cannot begin recovery from an unresolved local operation')
            before=self.observe()
            if ((before['status']>>13)&3) or before['status']&0x100:
                raise Quarantined('Actual memory responsibility pending; reconfiguration refused')
            out=Path(output).resolve();out.mkdir(parents=True,exist_ok=False)
            previous=self.path.read_bytes()
            durable_bytes(out/'previous-state.json',previous)
            candidate=secrets.token_hex(16)
            if candidate==self.state['incarnation']: raise RuntimeError('Incarnation collision')
            recovery=dict(candidate=candidate,previous_incarnation=self.state['incarnation'],
                          previous_state_sha256=hashlib.sha256(previous).hexdigest(),
                          previous_state_file=str(out/'previous-state.json'),before=before,
                          phase='PROGRAMMING',started_ns=time.time_ns())
            self.state.update(status='RECOVERING',recovery=recovery,image=dict(status='INVALID_AFTER_CONFIGURATION_REQUEST'))
            self.activated=False;self.image_verified_in_session=False
            self._save()  # A crash at any later step must not restore old READY.
            try:
                self.session.close();self.session=None
                receipt=programmer(self.config,out/'program')
                if (receipt.get('status')!='programmed_reviewed_jtg1'
                        or receipt.get('bit_sha256')!=self.config['bit_sha256']
                        or receipt.get('ltx_sha256')!=self.config['ltx_sha256']):
                    raise TransportError('Invalid programming completion receipt')
                self.session=self.session_factory(self.config,out/'new-session')
                after=self.observe()
                if after['status']!=0x4c7 or after['target_accepts']!=0 or after['target_returns']!=0:
                    raise TransportError('Post-program health or zero-traffic check failed')
                recovery.update(phase='IDENTITY_CHECK',program_receipt=receipt,after=after)
                self.state.update(status='NEW',incarnation=candidate,first_failure=None,pending=None,
                                  last_completion=None,image=dict(status='INVALID_AFTER_CONFIGURATION'))
                self._save()
                self.activate()
                recovery.update(phase='TRANSPORT_READY_CONTENTS_INVALID',finished_ns=time.time_ns())
                self._save()
                durable_json(out/'recovery.json',dict(status='transport_ready_contents_invalid',recovery=recovery))
                return candidate
            except BaseException as exc:
                recovery.update(phase='FAILED',error=f'{type(exc).__name__}: {exc}',finished_ns=time.time_ns())
                self._quarantine(f'Reconfiguration failed: {exc}')
                durable_json(out/'recovery.json',dict(status='failed_quarantined',recovery=recovery))
                raise

    def require_verified_image(self, incarnation):
        with self.mutex:
            self._allowed()
            image=self.state['image']
            if (not self.image_verified_in_session or not incarnation
                    or incarnation!=self.state['incarnation'] or image.get('incarnation')!=incarnation
                    or image.get('status')!='VERIFIED'):
                raise Quarantined('Image is not verified for this incarnation and connection')
            return dict(image)

    def validate_diagnostic_image(self, expected, output, *, write=False):
        """Whole target compare; write=True restores, False rechecks after attach."""
        if not isinstance(expected,bytes) or len(expected)!=self.config['memory_bytes']:
            raise ValueError('A complete diagnostic image is required')
        with self.mutex:
            self._allowed()
            if not self.state['incarnation']:
                raise Quarantined('No controlled configuration identity; explicit recovery required')
            out=Path(output).resolve();out.mkdir(parents=True,exist_ok=False)
            durable_bytes(out/'expected.bin',expected)
            incarnation=self.state['incarnation'];start=time.monotonic()
            self.image_verified_in_session=False
            self.state['image']=dict(status='LOADING',incarnation=incarnation,write=write,
                                      expected_sha256=hashlib.sha256(expected).hexdigest())
            self._save()
            try:
                if write:self.memory_write(0,expected)
                actual=self.memory_read(0,len(expected))
                durable_bytes(out/'actual.bin',actual)
                if actual!=expected:
                    first=next((i for i,(a,b) in enumerate(zip(actual,expected)) if a!=b),min(len(actual),len(expected)))
                    durable_json(out/'first-difference.json',dict(address=first,expected_bytes=len(expected),actual_bytes=len(actual)))
                    raise TransportError('Complete image comparison failed')
                image=dict(status='VERIFIED',incarnation=incarnation,bytes=len(expected),
                           sha256=hashlib.sha256(actual).hexdigest(),write=write,
                           seconds=time.monotonic()-start,source=str(out/'expected.bin'),
                           actual=str(out/'actual.bin'),validated_ns=time.time_ns())
                self.state['image']=image
                self._save();self.image_verified_in_session=True
                durable_json(out/'image.json',image)
                return dict(image)
            except BaseException as exc:
                self.state['image']['status']='INVALID_FAILED_VALIDATION'
                self._quarantine(f'Image load/validation failed: {exc}')
                durable_json(out/'image.json',dict(status='failed_quarantined',error=str(exc)))
                raise

    def close(self):
        with self.mutex:
            if self.owner.closed: return
            try:
                if self.session is not None: self.session.close()
            finally:
                self.owner.close()

    def __enter__(self): return self
    def __exit__(self, *_): self.close()

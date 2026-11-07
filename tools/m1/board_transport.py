"""Persistent transport for the real M1 board. No implicit reset or write retry."""
import json,re,time
from pathlib import Path
from jtag_transport import GuardedJtag,VivadoSession,TransportError,Quarantined

class BoardSession(VivadoSession):
    OPERATIONS = VivadoSession.OPERATIONS + ('BREAD','BWRITE','LOSS','QSTATUS')
    SCOPE = 'experimental full M1 board; a transport session is not numerical acceptance'

class BoardTransport(GuardedJtag):
    PROFILE='m1_experimental_board'
    MEMORY_BYTES=1<<31

    def __init__(self,config,output,session_factory=BoardSession):
        self.control=0
        if not config.get('owner_lock_path'):raise ValueError('shared physical-device lock required')
        super().__init__(config,output,session_factory)

    def observe(self):
        with self.mutex:
            try:
                raw=self.session.call('VIO').split()
                if len(raw)!=10 or any(not re.fullmatch('[0-9a-f]+',x) for x in raw):raise TransportError('bad board snapshot')
                if any(len(x)!=16 for x in raw[:4]) or any(len(x)!=64 for x in raw[4:]):raise TransportError('bad snapshot widths')
                magic,heartbeat,sequence,misc=map(lambda x:int(x,16),raw[:4])
                if magic!=0x4d314231:raise TransportError('wrong board identity')
                bits=sum(int(x,16)<<(i*256) for i,x in enumerate(raw[4:]))
                words=[(bits>>(i*32))&0xffffffff for i in range(48)]
                def u64(i):return words[i]|words[i+1]<<32
                qraw=self.session.call('QSTATUS')
                if not re.fullmatch('[0-9a-f]{8}',qraw):raise TransportError('bad independent DDR status')
                qstatus=int(qraw,16)
                flags=words[0]
                names=('task_active','cq_valid','isolated','reset_pending','boot_waiting','host_read_grant','host_write_grant','host_idle','bound_pair','session_valid','admission_enable','platform_error','trap','flush_req','memory_accept_now','boot_hold','cmd_ready')
                result={n:bool(flags>>i&1) for i,n in enumerate(names)}
                result.update(magic=magic,heartbeat=heartbeat,snapshot_sequence=sequence,atomic_snapshot=True,
                    ddr_calibrated=bool(qstatus&1),ddr_ui_reset=bool(qstatus&2),ddr_bist_pass=bool(qstatus&8) and not bool(qstatus&16),snapshot_scope='core fields atomic; DDR status sampled separately',service_mode=bool(misc&8),clock_locked=bool(misc&4),switch_fault=bool(misc&16),mask_active=bool(misc&32),
                    epoch=words[1],generation=words[2],built_tokens=words[3],committed_tasks=u64(4),task_cycles=u64(6),
                    clear_cleaned_bytes=u64(8),last_error=words[10],object_state=words[11],decode_steps=words[12],
                    next_sequence=u64(13),session=u64(15),accepted_count=u64(17),rejected_count=u64(19),
                    host_verified_beats=u64(21),native_verified_writes=u64(23),tokens=words[25:27],clear_fault_code=words[27],
                    loader_cycles=u64(28),memory_outstanding=words[30],object_id=words[31],injected_errors=words[32],
                    transport_error=words[33],clear_writes_accepted=u64(34),clear_writes_retired=u64(36),
                    transport_idle=bool(words[38]&1) and bool(flags&128) and not bool(misc&32),
                    reset_count=u64(40),device_cycles=u64(42),observed_ns=time.time_ns())
                if result['switch_fault'] and self.state['status']!='QUARANTINED':
                    self._quarantine('Hardware platform isolation/fault')
                result.update(host_trust=self.state['status'],image_usable_in_this_connection=self.image_verified_in_session,
                              host_incarnation=self.state.get('incarnation'))
                return result
            except BaseException as e:
                self._quarantine(f'Board observation failed: {e}');raise

    def activate(self):
        with self.mutex:
            self._allowed(initializing=True)
            obs=self.observe()
            if not obs['service_mode'] or not obs['clock_locked'] or obs['platform_error'] or obs['switch_fault']:
                raise Quarantined('Final board has not entered healthy service mode')
            for address,expected in ((0x80000000,0x0000000152564b50),(0x80000048,self.config['experiment_id'])):
                if int.from_bytes(self._burst('READ',address,1,initializing=True),'little')!=expected:
                    self._quarantine('Board live build identity mismatch');raise Quarantined('Wrong live build')
            self.state['status']='READY';self._save();self.activated=True

    def set_control(self,value):
        if type(value)is not int or value<0 or value & ~0xff06:raise ValueError('invalid board control')
        with self.mutex:
            self._allowed()
            # Snapshot请求位由Tcl独占，掩码/注入与快照握手不互相覆盖。
            self.state['pending']=dict(operation='VCTL',value=value)
            self.state['status']='PENDING';self._save()
            try:
                self.session.call('VCTL',f'{value:x}');self.control=value
                self.state['pending']=None;self.state['status']='READY';self._save()
            except BaseException as e:
                self._quarantine(f'Control transaction incomplete: {e}');raise

    def memory_write_masked(self,address,data,mask):
        if not isinstance(data,bytes) or not isinstance(mask,bytes) or len(data)!=len(mask) or any(x not in (0,1) for x in mask):
            raise ValueError('byte mask must match immutable data and contain only 0/1')
        self._range(address,len(data))
        if not data:return
        with self.mutex:
            self._allowed()
            for base in range(address&~7,(address+len(data)+7)&~7,8):
                value=bytearray(8);enable=0
                for lane in range(8):
                    index=base+lane-address
                    if 0<=index<len(data):value[lane]=data[index];enable|=mask[index]<<lane
                self.set_control(enable<<8|4)
                self._burst('WRITE',base,1,bytes(value))
            # 未知状态时异常直接上抛，不修改正在退休事务的资格或自动重试。
            self.set_control(0)

    def _bulk(self,operation,address,size,data=None):
        import hashlib
        self._allowed();self._range(address,size)
        if address%8 or size%8 or not 8<=size<=1<<20:raise ValueError('bad bulk alignment/size')
        if operation=='BWRITE':
            if not isinstance(data,bytes) or len(data)!=size:raise ValueError('bad bulk payload')
            payload=''.join(f'{int.from_bytes(data[i:i+8],"little"):016x}' for i in reversed(range(0,size,8)))
            if self.state['image']['status']=='VERIFIED':
                self.state['image']=dict(status='INVALIDATED_BY_WRITE');self.image_verified_in_session=False
        else:payload='-'
        self.state['sequence']+=1
        self.state['pending']=dict(operation=operation,address=address,bytes=size,sequence=self.state['sequence'],
            payload_sha256=hashlib.sha256(data).hexdigest() if data is not None else None)
        self.state['status']='PENDING';self._save()
        try:
            raw=self.session.call(operation,f'{address:08x}',str(size),payload)
            if len(raw)!=size*2 or not re.fullmatch('[0-9a-f]+',raw):raise TransportError('bad bulk response')
            result=b''.join(int(raw[i:i+16],16).to_bytes(8,'little') for i in reversed(range(0,len(raw),16)))
            if operation=='BWRITE' and result!=data:raise TransportError('bulk write identity mismatch')
            self.state['last_completion']=self.state['pending'];self.state['pending']=None
            self.state['status']='READY';self._save();return result
        except BaseException as e:
            self._quarantine(f'Uncertain bulk operation: {e}');raise

    def memory_read(self,address,size):
        self._range(address,size)
        if not size:return b''
        with self.mutex:
            base=address&~7;end=(address+size+7)&~7;chunks=[]
            for at in range(base,end,1<<20):chunks.append(self._bulk('BREAD',at,min(1<<20,end-at)))
            return b''.join(chunks)[address-base:address-base+size]

    def memory_write(self,address,data):
        if not isinstance(data,bytes):raise ValueError('immutable bytes required')
        self._range(address,len(data))
        if not data:return
        if address%8 or len(data)%8:return self.memory_write_masked(address,data,bytes([1])*len(data))
        with self.mutex:
            for at in range(0,len(data),1<<20):
                chunk=data[at:at+(1<<20)];self._bulk('BWRITE',address+at,len(chunk),chunk)

    def diagnostic_control(self,*args):raise TransportError('JTG1 diagnostic reset is not valid on the full board')
    def reconfigure_diagnostic(self,*args,**kwargs):raise TransportError('Use reviewed whole-board cold recovery')
    def validate_diagnostic_image(self,*args,**kwargs):raise TransportError('Full image proof required')

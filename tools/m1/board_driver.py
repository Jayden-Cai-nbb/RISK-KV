"""Full board driver; requires a reviewed bitstream and an explicit cold-start receipt."""
import json,time,hashlib
from pathlib import Path
from board_transport import BoardTransport
from host_control import HostControl
from experimental_acceptance import require_experimental_profile
from jtag_transport import digest,TransportError

class BoardDriver:
    def __init__(self,cfg):
        require_experimental_profile(cfg)
        self.cfg=cfg
        self.layout=json.loads((Path(__file__).resolve().parents[2]/'configs/m1/layout.json').read_text())
        physical=Path(cfg['physical_review']).resolve()
        review=json.loads(physical.read_text())
        require_experimental_profile(review)
        if review['status']!='reviewed_passed':raise ValueError('Physical review is not passed')
        for name in ('bit_sha256','ltx_sha256','part','vivado_version','firmware_sha256','experiment_id'):
            if review[name]!=cfg[name]:raise ValueError('physical identity mismatch: '+name)
        for name in ('setup_slack_ns','hold_slack_ns'):
            if review[name]<0:raise ValueError('physical timing failed')
        for name in ('unconstrained_required_paths','unresolved_cdc','unresolved_reset','drc_errors','drc_critical_warnings'):
            if review[name]!=0:raise ValueError('unclosed physical condition: '+name)
        for name in ('clock_phase_verified','all_external_paths_reviewed','exceptions_have_evidence','source_manifest_matches','bit_ltx_paired'):
            if review.get(name) is not True:raise ValueError('unclosed physical review: '+name)
        for item in review['files']:
            if digest(physical.parent/item['path'])!=item['sha256']:raise ValueError('physical evidence changed')
        receipt=json.loads(Path(cfg['cold_start_receipt']).read_text())
        if receipt['status']!='programmed_qualified_and_released' or receipt['bit_sha256']!=cfg['bit_sha256'] or receipt['ltx_sha256']!=cfg['ltx_sha256']:
            raise ValueError('No completed cold-start qualification for this bit')
        self.transport=BoardTransport(cfg,cfg['session_output'])
        self.control=HostControl(self.transport.read64,self.transport.write64)
        try:
            self.transport.activate()
            live=self.control.verify_identity()
            if live['experiment_id']!=cfg['experiment_id'] or live['support']!=1:raise TransportError('live experimental identity mismatch')
        except BaseException:
            self.transport.close();raise
        self.receipt=receipt

    def describe(self):
        obs=self.observe()
        return {k:self.cfg[k] for k in ('part','logical_bytes','core_hz','fast_hz','vivado_version','bit_sha256','ltx_sha256','validation_profile','vendor_supported','unsupported_reasons','firmware_sha256')}|dict(
            backend_kind='hardware',device_id=self.cfg['target_serial'],ddr_capacity_bytes=self.cfg['ddr_capacity_bytes'],
            ddr_calibrated=obs['ddr_calibrated'],clock_phase_verified=True,abi_magic=self.layout['abi_magic'],
            layout_version=self.layout['layout_version'],firmware_mode='mailbox',
            firmware_identity_source='paired bit/source manifest; not a direct runtime BRAM digest')

    def observe(self):return self.transport.observe()
    def mailbox_read(self,first,count):return self.control.mailbox_read(first,count)
    def mailbox_write(self,first,values):
        self.transport.require_verified_image(self.receipt['incarnation'])
        return self.control.mailbox_write(first,values)
    def memory_read(self,address,size):return self.transport.memory_read(address,size)
    def memory_write(self,address,data):return self.transport.memory_write(address,data)
    def memory_write_masked(self,address,data,mask):return self.transport.memory_write_masked(address,data,mask)

    def hold_cold_boot(self):
        obs=self.observe()
        if not obs['boot_waiting'] or not obs['boot_hold'] or not obs['host_idle'] or not obs['host_write_grant']:
            raise TransportError('Explicit whole-chain cold-start required before loading; no ordinary reset shortcut')
        state=self.transport.state
        if state.get('incarnation') not in (None,self.receipt['incarnation']):raise TransportError('cold incarnation mismatch')
        state['incarnation']=self.receipt['incarnation'];state['image']=dict(status='LOADING',started_ns=time.time_ns())
        self.transport.image_verified_in_session=False;self.transport._save()

    def finish_image_load(self,records):
        if self.transport.state['image']['status']!='LOADING':raise TransportError('No active full image load')
        cold=records[0]
        if cold['bytes']!=self.layout['cold_image_bytes'] or cold['sha256']!=self.layout['cold_image_sha256']:
            raise TransportError('cold image proof differs')
        if len(records)!=1+len(self.layout['scratch_restore']):raise TransportError('scratch proof incomplete')
        for rec,(_,size) in zip(records[1:],self.layout['scratch_restore']):
            if rec['bytes']!=size:raise TransportError('scratch proof size differs')
        self.transport.state['image']=dict(status='VERIFIED',records=records,incarnation=self.receipt['incarnation'])
        self.transport.image_verified_in_session=True;self.transport._save()

    def release_cpu(self):
        self.transport.require_verified_image(self.receipt['incarnation'])
        self.control.release_boot()

    def controlled_reset(self):self.control.controlled_reset()
    def inject_task_error(self):
        if not self.observe()['task_active']:raise TransportError('no active compute task')
        self.transport.set_control(2);self.transport.set_control(0)
    def suppress_retirement(self):
        if not self.observe()['task_active']:raise TransportError('no active compute task')
        t=self.transport
        with t.mutex:
            t._allowed();t.state['pending']=dict(operation='LOSS',value=3);t.state['status']='PENDING';t._save()
            try:
                t.session.call('LOSS','3');t.state['pending']=None;t.state['status']='READY';t._save()
            except BaseException as e:t._quarantine(f'Loss injection incomplete: {e}');raise
    def close(self):self.transport.close()

def open(config):return BoardDriver(config)

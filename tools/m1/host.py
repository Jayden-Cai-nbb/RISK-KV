"""M1 hardware host workflow. Requires an explicitly bound transport driver."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import secrets
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/reproduction'))
from recorded import save, sha, utc


class Mailbox:
    def __init__(self, driver, layout, timeout=120, progress=None):
        self.progress = progress; self.progress_at = 0.0
        self.driver = driver; self.layout = layout; self.words = layout['mailbox']; self.timeout = timeout
        self.serial = self.read('DOORBELL')
        self.cancel_serial = self.read('CANCEL_SERIAL')
        self.session = secrets.randbits(64) or 1
        self.sequence = 1; self.generation = 0; self.context = 7
        self.epoch = self.wait(lambda: self.read('READY_EPOCH'), 'firmware startup')

    def read(self, name):
        return self.driver.mailbox_read(self.words[name], 1)[0]

    def wait(self, condition, description):
        start = time.monotonic()
        while True:
            if self.progress is not None and time.monotonic() >= self.progress_at:
                self.progress(); self.progress_at = time.monotonic()+1.0
            value = condition()
            if value: return value
            if time.monotonic()-start > self.timeout: raise TimeoutError(description)
            time.sleep(0.001)

    def exchange(self, action, op=0, tokens=(0,0), receipt=None, intervention=None):
        if self.serial == 0xffffffff: raise RuntimeError('host mailbox serial exhausted; establish a new cold boot')
        identity = receipt or dict(session=self.session, epoch=self.epoch, sequence=self.sequence,
                                   context=self.context, generation=self.generation)
        s, q = identity['session'], identity['sequence']
        words = [action, op, s & 0xffffffff, s >> 32, identity['epoch'], q & 0xffffffff, q >> 32,
                 identity['context'], identity['generation'], *tokens]
        self.driver.mailbox_write(self.words['ACTION'], words)
        self.serial += 1
        start = time.monotonic()
        self.driver.mailbox_write(self.words['DOORBELL'], [self.serial])
        event = None
        if intervention:
            def active_snapshot():
                snapshot=self.driver.observe()
                return snapshot if snapshot['task_active'] else None
            event = self.wait(active_snapshot, 'injection target never became active')
        if intervention == 'cancel':
            self.cancel_serial += 1
            if self.cancel_serial > 0xffffffff: raise RuntimeError('cancel serial exhausted')
            self.driver.mailbox_write(self.words['CANCEL_SERIAL'], [self.cancel_serial])
        elif intervention == 'error':
            self.driver.inject_task_error()
        elif intervention == 'reset':
            self.driver.controlled_reset()
            self.wait(lambda: self.read('READY_EPOCH') != self.epoch, 'controlled reset did not retire/clean')
            return dict(intervention=intervention, before=event, after=self.driver.observe(), host_seconds=time.monotonic()-start)
        elif intervention == 'loss':
            self.driver.suppress_retirement()
            self.wait(lambda: self.driver.observe()['isolated'], 'lost retirement did not enter isolation')
            return dict(intervention=intervention,before=event,after=self.driver.observe(),host_seconds=time.monotonic()-start)
        elif intervention is not None:
            raise ValueError(intervention)
        self.wait(lambda: self.read('RESPONSE') == self.serial, 'mailbox command timeout; inspect device isolation before recovery')
        raw = self.driver.mailbox_read(self.words['CQ0'], 11)
        cq = dict(op=raw[0], status=raw[1], session=raw[2] | raw[3]<<32, epoch=raw[4],
                  sequence=raw[5] | raw[6]<<32, context=raw[7], generation=raw[8], tokens=raw[9:11])
        result = self.read('RESULT')
        self.generation = self.read('CURRENT_GENERATION')
        self.sequence = self.read('CURRENT_SEQUENCE0') | self.read('CURRENT_SEQUENCE1')<<32
        if result & 0x80000000: raise RuntimeError(f'device refused/isolated: 0x{result:08x}')
        if action == 1:
            assert all(cq[key] == identity[key] for key in ('session','epoch','sequence','context','generation')), 'CQ identity mismatch'
            assert cq['op'] == op
        elif result:
            raise RuntimeError(f'control receipt failed: {result}')
        return dict(cq=cq, result=result, host_seconds=time.monotonic()-start, observation=self.driver.observe(), intervention=intervention, injected_at=event)

    def command(self, name, tokens=(0,0), intervention=None):
        return self.exchange(1, self.layout['operations'][name], tokens, intervention=intervention)

    def consume(self, result):
        return self.exchange(2, receipt=result['cq'])

    def operation(self, name):
        result = self.command(name)
        if result['cq']['status'] != 0: raise RuntimeError(f'{name} failed: {result}')
        self.consume(result)
        return result


def validate_platform(config, info, layout):
    if config['state'] != 'bound': raise RuntimeError('platform is unbound; collect actual DDR/transport/Vivado project first')
    if info.get('backend_kind') != 'hardware': raise RuntimeError('board acceptance requires a hardware transport, not a simulator')
    for key in ('part','logical_bytes','core_hz','fast_hz'):
        assert info[key] == config[key], f'platform identity mismatch: {key}'
    assert info['logical_bytes'] == layout['logical_bytes']
    assert info['ddr_capacity_bytes'] >= layout['logical_bytes']
    assert info['core_hz'] == layout['core_hz'] and info['fast_hz'] == layout['fast_hz']
    assert info['clock_phase_verified'] and config['clock_phase_verified']
    assert info['part'] in ('xcvu440-flga2892-1-c', 'xcvu440-flga2892-2-e'), 'unreviewed device configuration'
    profile = config.get('validation_profile')
    if profile == 'experimental_m1':
        from experimental_acceptance import require_experimental_profile
        require_experimental_profile(config); require_experimental_profile(info)
    elif profile == 'formal_m1':
        from board_acceptance import require_formal_profile
        require_formal_profile(config); require_formal_profile(info)
    else:
        raise RuntimeError('explicit validation profile is required')
    assert info['ddr_calibrated'], 'DDR is not calibrated'
    for key in ('vivado_version','bit_sha256','ltx_sha256'):
        assert config.get(key) and config[key] == info[key], f'missing/unmatched implementation identity: {key}'
    assert info.get('device_id'), 'physical device identity is required'
    assert info['abi_magic']==layout['abi_magic'] and info['layout_version']==layout['layout_version'], 'live ABI/layout mismatch'
    assert info['firmware_mode']=='mailbox' and config.get('firmware_sha256')==info['firmware_sha256'], 'live firmware identity mismatch'
    assert config['firmware_sha256'], 'verified firmware identity is required'


def load_and_verify(driver, layout, output, progress=None):
    cold = ROOT / 'assets/data/dram-input.bin'
    assert sha(cold) == layout['cold_image_sha256']
    driver.hold_cold_boot()
    phase=driver.observe()
    assert phase['boot_waiting'] and phase['host_write_grant'] and phase['host_idle'], 'cold loading phase not granted'
    records = []
    def transfer(stream, address, size, description):
        start = time.monotonic(); h = hashlib.sha256()
        for offset in range(0, size, 1<<20):
            data = stream.read(min(1<<20, size-offset)); assert len(data) == min(1<<20,size-offset)
            driver.memory_write(address+offset, data)
            got = driver.memory_read(address+offset, len(data))
            if got != data:
                first = next(i for i,(x,y) in enumerate(zip(data,got)) if x != y) if len(got)==len(data) else 0
                save(output/'first-ddr-difference.json', dict(address=address+offset+first, expected_bytes=len(data), received_bytes=len(got)))
                raise AssertionError('DDR load/readback mismatch')
            h.update(got)
            if progress is not None: progress(description, offset+len(data), size)
        records.append(dict(name=description, address=address, bytes=size, sha256=h.hexdigest(), host_seconds=time.monotonic()-start))
    with cold.open('rb') as stream:
        transfer(stream, 0, layout['cold_image_bytes'], 'full_cold_image')
        cursor = layout['scratch_template_base']
        for index,(address,size) in enumerate(layout['scratch_restore']):
            stream.seek(address); transfer(stream, cursor, size, f'cold_scratch_{index}'); cursor += size
    save(output/'load.json', dict(status='passed_readback', regions=records, observation=driver.observe()))
    if hasattr(driver, 'finish_image_load'): driver.finish_image_load(records)
    release_loaded_cpu(driver,layout)


def release_loaded_cpu(driver,layout):
    # CPU RAM survives cold-reset pulses: discard the old startup flag while
    # boot_hold is still asserted, then require a fresh firmware publication.
    assert driver.observe()['boot_waiting'], 'CPU already running during cold load'
    driver.mailbox_write(layout['mailbox']['READY_EPOCH'],[0])
    assert driver.mailbox_read(layout['mailbox']['READY_EPOCH'],1)==[0]
    driver.release_cpu()


def four_token_prefix(reference):
    import numpy as np
    gold = np.fromfile(reference/'reference-prefix.bin', dtype=np.uint8)
    expected = np.zeros_like(gold); cursor = 0
    for _ in range(28*8):
        for field, length in [('k',32768), ('ks',1024), ('vt',32768), ('vs',1024)]:
            if field == 'vt':
                expected[cursor:cursor+length].reshape(128,256)[:,:4] = gold[cursor:cursor+length].reshape(128,256)[:,:4]
            else:
                valid = 4*(128 if field == 'k' else 4)
                expected[cursor:cursor+valid] = gold[cursor:cursor+valid]
            cursor += length
    return expected.tobytes()


def checked_read(driver, address, expected, path):
    assert driver.observe()['host_read_grant']
    got = driver.memory_read(address, len(expected)); path.write_bytes(got)
    if got != expected:
        first = next((i for i,(x,y) in enumerate(zip(got,expected)) if x!=y), min(len(got),len(expected)))
        save(path.with_suffix('.difference.json'), dict(address=address+first, expected_bytes=len(expected), received_bytes=len(got)))
        raise AssertionError(f'readback mismatch: {path}')
    return got


def checked_reference(directory):
    ref=json.loads((directory/'summary.json').read_text())
    assert ref['status']=='passed_independent_native_reference' and len(ref['pairs'])==2
    assert sha(directory/'reference-prefix.bin')==ref['prefix_sha256']
    assert (directory/'reference-prefix.bin').read_bytes()==(ROOT/'assets/reference/reference-prefix.bin').read_bytes()
    assert ref['seed_pairs']==[[3555,8429],[2585,3197]], 'M1 frozen input pairs changed'
    for group in ref['pairs']:
        assert len(group['steps'])==3
        assert sha(directory/group['context_file'])==group['context_sha256']
        for step in group['steps']:assert sha(directory/step['logits_file'])==step['logits_sha256']
    return ref


def verify_immutable(driver, layout, output, *, four_token=False):
    """Read every immutable byte while a completion remains unconsumed."""
    assert driver.observe()['host_read_grant'], 'immutable check requires a read phase'
    regions=[(a,n,a,'immutable') for a,n in layout['immutable_regions']]
    regions += [(p['address'],p['bytes'],p['address'],'program-'+name) for name,p in layout['programs'].items()]
    cursor=layout['scratch_template_base']
    for index,(a,n) in enumerate(layout['scratch_restore']):
        regions.append((cursor,n,a,'scratch-template-'+str(index)));cursor+=n
    unused_start=layout['kv_base']+(layout['prefix_bytes'] if four_token else layout['object_bytes'])
    regions.append((unused_start,layout['kv_base']+layout['pool_bytes']-unused_start,unused_start,'unused-kv-pool'))
    records=[]
    with (ROOT/'assets/data/dram-input.bin').open('rb') as cold:
        for address,size,source,name in regions:
            h=hashlib.sha256();cold.seek(source)
            for offset in range(0,size,1<<20):
                expected=cold.read(min(1<<20,size-offset));assert len(expected)==min(1<<20,size-offset), 'immutable source truncated'
                got=driver.memory_read(address+offset,len(expected))
                if got!=expected:
                    first=next((i for i,(x,y) in enumerate(zip(got,expected)) if x!=y),min(len(got),len(expected)))
                    save(output/'immutable-first-difference.json',dict(address=address+offset+first,region=name))
                    raise AssertionError('immutable data changed')
                h.update(got)
            records.append(dict(name=name,address=address,bytes=size,sha256=h.hexdigest()))
    save(output/'immutable.json',dict(status='passed_all_declared_immutable_regions',regions=records))


def build_prefix(client, reference, output, tasks=64, validate=True):
    client.operation('REGISTER')
    rows = []
    for index in range(tasks):
        result = client.command('BUILD')
        assert result['cq']['status'] == 0
        if validate and (index == 63 or (tasks == 1 and index == 0)):
            expected = (reference/'reference-prefix.bin').read_bytes() if index == 63 else four_token_prefix(reference)
            checked_read(client.driver, client.layout['kv_base'], expected, output/'built-prefix.bin')
            if tasks == 1: verify_immutable(client.driver,client.layout,output,four_token=True)
        client.consume(result); rows.append(result)
    if tasks == 64: client.operation('SEAL')
    save(output/'build.json', dict(status='passed' if validate else 'measurement_only', tasks=tasks, results=rows))


def query_pair(client, reference, group, output, validate=True, cleanup_name='RELEASE', check_immutable=False):
    import numpy as np
    output.mkdir(parents=True, exist_ok=False)
    start = time.monotonic(); before = client.driver.observe()
    client.operation('BIND'); tokens = group['seeds']; steps = []; read_seconds = 0.0; first_seconds = None
    for step, expected in enumerate(group['steps']):
        result = client.command('DECODE', tokens)
        assert result['cq']['status'] == 0
        assert result['cq']['tokens'] == expected['output_tokens']
        if step == 0: first_seconds = time.monotonic()-start
        if validate:
            assert client.driver.observe()['host_read_grant']
            begin = time.monotonic()
            gold = np.load(reference/expected['logits_file'], allow_pickle=False)
            checked_read(client.driver, client.layout['logits_address'], gold.tobytes(), output/f'logits-{step}.bin')
            if step == 2:
                context = client.driver.memory_read(client.layout['kv_base'], client.layout['object_bytes'])
                (output/'context.bin').write_bytes(context)
                assert hashlib.sha256(context).hexdigest() == group['context_sha256']
            read_seconds += time.monotonic()-begin
        client.consume(result); tokens = result['cq']['tokens']; steps.append(result)
    # 清理费用包含在同一批次内，不能挪到下一批或忽略。
    cleanup = client.command(cleanup_name); assert cleanup['cq']['status'] == 0
    if validate and cleanup_name == 'RELEASE':
        begin = time.monotonic()
        expected = (reference/'reference-prefix.bin').read_bytes()+bytes(client.layout['object_bytes']-client.layout['prefix_bytes'])
        checked_read(client.driver,client.layout['kv_base'],expected,output/'cleared-object.bin')
        read_seconds += time.monotonic()-begin
    if check_immutable:
        assert validate, 'immutable proof belongs to numerical validation'
        verify_immutable(client.driver,client.layout,output)
    client.consume(cleanup)
    after=client.driver.observe()
    assert after['epoch']==before['epoch'] and after['reset_count']==before['reset_count'], 'unexpected reset during service'
    assert after['transport_idle'] and not after['isolated']
    result = dict(status='passed' if validate else 'completed_measurement_with_token_check_only',
                  host_seconds=time.monotonic()-start, readback_seconds=read_seconds,
                  first_result_seconds=first_seconds,
                  steps=steps, cleanup=cleanup, before=before, after=after)
    save(output/'result.json', result)
    return result


def ddr_test(driver, layout, output):
    """Destructive cold-boot-only test; all writes precede the read sweep."""
    import numpy as np
    driver.hold_cold_boot()
    assert driver.observe()['host_write_grant']
    size = layout['logical_bytes']; chunk = 1<<20; rounds = []
    for salt in (0x1248abcef137bd69, 0xedb754310ec84296):
        begin = time.monotonic(); h = hashlib.sha256()
        for address in range(0,size,chunk):
            pattern = (np.arange(address//8,(address+chunk)//8,dtype='<u8') ^ np.uint64(salt)).tobytes()
            driver.memory_write(address,pattern)
        # 完整写扫后再读，能够检测不同块映射到同一物理地址的别名。
        for address in range(0,size,chunk):
            expected = (np.arange(address//8,(address+chunk)//8,dtype='<u8') ^ np.uint64(salt)).tobytes()
            got = driver.memory_read(address,chunk)
            if got != expected:
                first = next((i for i,(a,b) in enumerate(zip(got,expected)) if a!=b),min(len(got),chunk))
                save(output/'first-ddr-difference.json',dict(address=address+first,pass_salt=hex(salt)))
                raise AssertionError('full-range DDR mismatch')
            h.update(got)
        rounds.append(dict(bytes=size,salt=hex(salt),sha256=h.hexdigest(),host_seconds=time.monotonic()-begin))
    addresses = {0,size-128,layout['kv_base'],layout['kv_base']+layout['prefix_bytes'],layout['scratch_template_base']}
    addresses.update(p['address'] for p in layout['programs'].values())
    addresses.update(a for a,_ in layout['scratch_restore'])
    masks = []
    for base in sorted(addresses):
        base &= ~127
        for mask in (bytes([0,1])*64,bytes([1,0])*64,bytes([1])*128,bytes(128)):
            driver.memory_write(base,bytes([0xa5])*128)
            driver.memory_write_masked(base,bytes(range(128)),mask)
            expected = bytes(i if mask[i] else 0xa5 for i in range(128))
            assert driver.memory_read(base,128) == expected, f'byte mask mismatch at {base:x}'
            masks.append(dict(address=base,mask=mask.hex()))
        # 无对齐主机传输跨 32/64/128/4096 边界；实际写掩码须由 transport 实现。
        if base+4096+129 <= size:
            for boundary in (32,64,128,4096):
                address=base+boundary-3; data=bytes(range(131))
                driver.memory_write(address,data)
                assert driver.memory_read(address,len(data)) == data
    observed = driver.observe()
    assert observed['host_idle'] and observed['transport_idle'] and not observed['isolated']
    save(output/'ddr.json',dict(status='passed_full_range_and_masks',rounds=rounds,masks=masks,observation=observed,
                              next_action='load full cold image and scratch template; CPU remains held'))


def fault_matrix(client, reference, ref, output):
    rows=[]
    # 取消覆盖前缀构建的首/中/末任务以及续算；错误和复位也各执行十次。
    for mode in ('cancel','error','reset'):
        for index in range(10):
            stage=('build_early','build_middle','build_last','decode')[index%4]
            tasks={'build_early':0,'build_middle':32,'build_last':63,'decode':64}[stage]
            dest=output/f'{mode}-{index:02d}'; dest.mkdir()
            build_prefix(client,reference,dest,tasks)
            if tasks==64: client.operation('BIND')
            before=client.driver.observe()
            result=client.command('DECODE' if tasks==64 else 'BUILD',ref['pairs'][index%2]['seeds'],intervention=mode)
            after=client.driver.observe()
            assert after['committed_tasks']==before['committed_tasks'], 'failed/reset task committed'
            if mode!='reset':
                assert result['cq']['status']==(1 if mode=='cancel' else 2)
                assert after['built_tokens']==tasks*4 and after['decode_steps']==0
                if mode=='error': assert after['injected_errors']==before['injected_errors']+1
                client.consume(result); client.operation('RECOVER')
            else:
                assert after['epoch']==before['epoch']+1 and not after['session_valid']
                assert after['clear_cleaned_bytes']-before['clear_cleaned_bytes']==client.layout['object_bytes']+sum(n for _,n in client.layout['scratch_restore'])
                client=Mailbox(client.driver,client.layout,progress=client.progress); client.operation('BOOT')
            recovered=dest/'recovered'; recovered.mkdir()
            build_prefix(client,reference,recovered)
            query_pair(client,reference,ref['pairs'][index%2],recovered/'query',cleanup_name='RETIRE',check_immutable=(mode=='reset' and index==9))
            rows.append(dict(mode=mode,stage=stage,before=before,event=result,after=after,recovered_generation=client.generation))
            save(output/'faults.json',dict(status='running',results=rows))
    save(output/'faults.json',dict(status='passed_retiring_faults',results=rows,
                                 excluded='permanent transport loss requires separate isolation test and cold restart'))
    return client


def isolation_test(client, output):
    client.operation('REGISTER')
    before=client.driver.observe()
    result=client.command('BUILD',intervention='loss')
    after=result['after']
    assert after['isolated'] and not after['transport_idle']
    assert after['committed_tasks']==before['committed_tasks'] and after['built_tokens']==0
    assert not after['host_write_grant'] and not after['cmd_ready']
    # 普通受控复位不能消除未退休队列；观察窗口内必须保持隔离及原 epoch。
    client.driver.controlled_reset()
    time.sleep(0.1)
    final=client.driver.observe()
    assert final['isolated'] and final['epoch']==before['epoch'] and not final['cmd_ready']
    assert final['committed_tasks']==before['committed_tasks']
    save(output/'isolation.json',dict(status='passed_no_reuse_after_loss',before=before,result=result,final=final,
                                    next_action='cold platform reset, disable injection, reload and verify all model/template bytes'))


def benchmark(client, reference, ref, output, batches):
    import numpy as np
    assert batches>=30
    rows=[]; summaries={}
    for mode in ('prefix_reuse','rebuild_each_batch'):
        for index in range(batches):
            dest=output/f'{mode}-{index:03d}'; dest.mkdir()
            start=time.monotonic(); before=client.driver.observe(); build_seconds=0.
            if mode=='rebuild_each_batch' or index==0:
                build_prefix(client,reference,dest,validate=False)
                build_seconds=time.monotonic()-start
            # baseline 只做一次整对象退休；不能额外加清尾来人为放大收益。
            query=query_pair(client,reference,ref['pairs'][index%2],dest/'query',validate=False,
                             cleanup_name='RETIRE' if mode=='rebuild_each_batch' or index==batches-1 else 'RELEASE')
            after=client.driver.observe()
            rows.append(dict(mode=mode,batch=index,host_seconds=time.monotonic()-start,
                             first_result_seconds=build_seconds+query['first_result_seconds'],
                             device_cycles=after['device_cycles']-before['device_cycles'],
                             clear_bytes=after['clear_cleaned_bytes']-before['clear_cleaned_bytes'],
                             build_tasks=64 if mode=='rebuild_each_batch' or index==0 else 0,
                             before=before,after=after))
        selected=[r for r in rows if r['mode']==mode]
        summaries[mode]={key:dict(median=float(np.median([r[key] for r in selected])),
                                  p95=float(np.percentile([r[key] for r in selected],95)),
                                  total=sum(r[key] for r in selected))
                         for key in ('host_seconds','first_result_seconds','device_cycles','clear_bytes','build_tasks')}
    save(output/'measurements.json',dict(status='measured_not_functional_acceptance',rows=rows,summary=summaries,
         cost_scope='same initial empty state, first prefix build and final retirement included; command and cleanup costs included; logits readback excluded and reported separately by continuous validation',
         limitation='host wall/device cycle comparison only; no energy or physical DDR bandwidth claim'))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('command', choices=['inspect','ddr','load','smoke','continuous','faults','isolation','benchmark'])
    p.add_argument('--platform', type=Path, default=ROOT/'configs/m1/platform-unbound.json')
    p.add_argument('--reference', type=Path)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--batches', type=int, default=100)
    a = p.parse_args(); out = a.output.absolute(); out.mkdir(parents=True, exist_ok=False)
    cfg = json.loads(a.platform.read_text()); layout = json.loads((ROOT/'configs/m1/layout.json').read_text())
    report = dict(status='running', command=a.command, started_at=utc(), platform=cfg,
                  platform_sha256=sha(a.platform), layout_sha256=sha(ROOT/'configs/m1/layout.json'),
                  board_acceptance_passed=False)
    save(out/'report.json', report)
    try:
        if cfg['state'] != 'bound':
            report.update(status='pending_platform_binding', requirements=['actual DDR and host project','Vivado/IP/XDC and clock phase','transport driver and real retirement semantics','paired bit/ltx and physical implementation reports'])
            return 0 if a.command=='inspect' else 2
        driver_path = Path(cfg['driver']).expanduser().absolute()
        spec = importlib.util.spec_from_file_location('rkv_board_driver', driver_path)
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        driver = module.open(cfg); info = driver.describe()
        validate_platform(cfg, info, layout); report.update(hardware=info, driver_sha256=sha(driver_path))
        if a.command == 'inspect': report['status'] = 'platform_identity_checked'; return
        if a.command == 'ddr': ddr_test(driver,layout,out); report['status']='passed_ddr_subset'; return
        if a.command == 'load': load_and_verify(driver, layout, out); report['status'] = 'image_loaded_and_verified'; return
        if not a.reference: p.error('run commands require --reference')
        ref = checked_reference(a.reference)
        report['reference_sha256']=sha(a.reference/'summary.json')
        save(out/'reference-input.json',ref)
        client = Mailbox(driver, layout); client.operation('BOOT')
        if a.command=='isolation':
            isolation_test(client,out); report['status']='passed_isolation_subset'; return
        if a.command in ('smoke','continuous'): build_prefix(client, a.reference, out, 1 if a.command == 'smoke' else 64)
        if a.command == 'smoke':
            report['status'] = 'passed_four_token_full_kv'; report['valid_kv_bytes']=236544
            return
        if a.command=='faults':
            fault_matrix(client,a.reference,ref,out); report['status']='passed_retiring_faults_subset'; return
        if a.command == 'continuous':
            assert a.batches >= 100, 'M1 requires at least 100 batches'
            rows = [query_pair(client, a.reference, ref['pairs'][i % 2], out/f'batch-{i:03d}') for i in range(a.batches)]
            for i in range(10):
                client.operation('RETIRE')
                dest = out/f'rebuild-{i:02d}'; dest.mkdir()
                build_prefix(client, a.reference, dest)
                query_pair(client, a.reference, ref['pairs'][i % 2], dest/'query',check_immutable=(i==9))
            report.update(status='passed_continuous_subset', batches=len(rows), rebuilds=10,
                          remaining=['DDR full-range test','cancel/error/reset matrix','physical timing/CDC/DRC evidence'])
        else:
            benchmark(client,a.reference,ref,out,a.batches)
            report.update(status='measured_not_functional_acceptance',samples=2*a.batches)
    except BaseException as exc:
        report.update(status='failed', error=f'{type(exc).__name__}: {exc}')
        if 'driver' in locals():
            try: report['failure_observation']=driver.observe()
            except Exception as observe_error: report['observation_error']=str(observe_error)
        raise
    finally:
        if 'driver' in locals(): driver.close()
        report['files']=[dict(path=f.relative_to(out).as_posix(),bytes=f.stat().st_size,sha256=sha(f))
                         for f in sorted(out.rglob('*')) if f.is_file() and f!=out/'report.json']
        report['finished_at'] = utc(); save(out/'report.json', report)
        print(json.dumps({k:v for k,v in report.items() if k != 'platform'}, ensure_ascii=False))


if __name__ == '__main__':
    raise SystemExit(main())

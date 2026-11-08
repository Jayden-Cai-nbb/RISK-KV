"""Check remote raw-file digests against locally recomputed independent references."""
from pathlib import Path
import hashlib,json,statistics
import numpy as np
p=Path(__file__).resolve().parent;s=p/'snapshots/board-suite-v3'
c=json.loads((p/'check.json').read_text());layout=json.loads(Path('configs/m1/layout.json').read_text())
ref=Path('build/reproduction/m1-20261104T073837Z/reference-kv-v1')
gold=json.loads((ref/'summary.json').read_text())
def sha(data):return hashlib.sha256(data).hexdigest()
for name,record in c['snapshots'].items():
    data=(p/'snapshots'/name).read_bytes()
    assert len(data)==record['bytes'] and sha(data)==record['sha256'],name
assert c['frozen_inputs_checked']==118 and not c['frozen_inputs_mismatched']
prefix=Path('assets/reference/reference-prefix.bin').read_bytes()
assert sha(prefix)==gold['prefix_sha256']
cleared=sha(prefix+bytes(layout['object_bytes']-len(prefix)))
expected=[]
for group in gold['pairs']:
    context=(ref/group['context_file']).read_bytes();assert sha(context)==group['context_sha256']
    items={'context.bin':(len(context),sha(context)), 'cleared-object.bin':(layout['object_bytes'],cleared)}
    for i,step in enumerate(group['steps']):
        path=ref/step['logits_file'];assert sha(path.read_bytes())==step['logits_sha256']
        raw=np.load(path,allow_pickle=False).tobytes();items[f'logits-{i}.bin']=(len(raw),sha(raw))
    expected.append(items)
faults=json.loads((s/'faults/faults.json').read_text())['results']
assert len(faults)==len(c['fault_rows'])
for event,row in zip(faults,c['fault_rows']):
    mode,index=row['mode'],row['index'];before,after=event['before'],event['after']
    assert mode==event['mode'] and after['committed_tasks']==before['committed_tasks']
    if mode!='reset':
        assert event['event']['cq']['status']==(1 if mode=='cancel' else 2)
        assert after['built_tokens']==before['built_tokens'] and after['decode_steps']==0
        if mode=='error':assert after['injected_errors']==before['injected_errors']+1
    else:
        assert after['epoch']==before['epoch']+1 and not after['session_valid']
        assert after['clear_cleaned_bytes']-before['clear_cleaned_bytes']==layout['object_bytes']+sum(n for _,n in layout['scratch_restore'])
    d=s/'faults'/f'{mode}-{index:02d}'
    query=json.loads((d/'recovered/query/result.json').read_text())
    assert query['status']=='passed'
    assert query['after']['committed_tasks']-query['before']['committed_tasks']==3
    assert query['after']['epoch']==query['before']['epoch']
    assert query['after']['transport_idle'] and not query['after']['isolated']
    for name,(size,h) in expected[index%2].items():
        if name=='cleared-object.bin':continue
        assert row['files']['recovered/query/'+name]==dict(bytes=size,sha256=h)
    assert row['files']['recovered/built-prefix.bin']==dict(bytes=len(prefix),sha256=sha(prefix))
    for i,step in enumerate(query['steps']):assert step['cq']['tokens']==gold['pairs'][index%2]['steps'][i]['output_tokens']

    expected_names={'recovered/built-prefix.bin','recovered/query/context.bin',*(f'recovered/query/logits-{i}.bin' for i in range(3))}
    if event['stage']=='decode':
        expected_names.add('built-prefix.bin')
        assert row['files']['built-prefix.bin']==dict(bytes=len(prefix),sha256=sha(prefix))
    assert set(row['files'])==expected_names
    assert event['event']['before' if mode=='reset' else 'injected_at']['task_active']
    assert after['memory_outstanding']==0 and after['transport_idle']
    assert query['after']['reset_count']==query['before']['reset_count']
    assert query['after']['clear_cleaned_bytes']-query['before']['clear_cleaned_bytes']==layout['object_bytes']+sum(n for _,n in layout['scratch_restore'])
    assert query['before']['generation']==event['recovered_generation']
    assert query['cleanup']['cq']['status']==0
    if mode!='reset':
        cq=event['event']['cq']
        for field in ('session','epoch','generation'):assert cq[field]==before[field]
        assert cq['context']==before['object_id']
        assert after['native_verified_writes']>before['native_verified_writes']

from collections import Counter
counts=dict(Counter(e['mode'] for e in faults))
result=dict(status='passed_local_completed_fault_audit',completed=counts,
    raw_files_checked=sum(len(r['files']) for r in c['fault_rows']),
    raw_bytes_checked=sum(f['bytes'] for r in c['fault_rows'] for f in r['files'].values()),
    snapshots_checked=len(c['snapshots']), frozen_inputs_checked=c['frozen_inputs_checked'],
    board_acceptance_passed=False,
    scope='Completed fault recoveries only; full fault matrix, benchmark, isolation and acceptance remain pending.')
(p/'local-verification.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))

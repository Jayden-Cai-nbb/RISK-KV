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
assert c['prefix_sha256']==sha(prefix)==gold['prefix_sha256']
cleared=sha(prefix+bytes(layout['object_bytes']-len(prefix)))
expected=[]
for group in gold['pairs']:
    context=(ref/group['context_file']).read_bytes();assert sha(context)==group['context_sha256']
    items={'context.bin':(len(context),sha(context)), 'cleared-object.bin':(layout['object_bytes'],cleared)}
    for i,step in enumerate(group['steps']):
        path=ref/step['logits_file'];assert sha(path.read_bytes())==step['logits_sha256']
        raw=np.load(path,allow_pickle=False).tobytes();items[f'logits-{i}.bin']=(len(raw),sha(raw))
    expected.append(items)
batch=[];rebuild=[];seconds=[];read_seconds=[]
for row in c['rows']:
    d=s/row['path'];result=json.loads((d/'result.json').read_text())
    index=int((d.parent.name if d.name=='query' else d.name).split('-')[1])
    assert result['status']=='passed' and len(result['steps'])==3
    assert set(row['files'])==set(expected[index%2])
    for name,(size,h) in expected[index%2].items():assert row['files'][name]==dict(bytes=size,sha256=h),(row['path'],name)
    before,after=result['before'],result['after']
    assert before['built_tokens']==after['built_tokens']==256
    assert before['generation']==after['generation']
    assert before['epoch']==after['epoch']==1 and before['reset_count']==after['reset_count']==0
    assert after['committed_tasks']-before['committed_tasks']==3
    assert after['transport_idle'] and not after['isolated']
    assert after['clear_cleaned_bytes']-before['clear_cleaned_bytes']==layout['object_bytes']-layout['prefix_bytes']+sum(n for _,n in layout['scratch_restore'])
    for i,step in enumerate(result['steps']):assert step['cq']['tokens']==gold['pairs'][index%2]['steps'][i]['output_tokens']
    if d.name=='query':
        assert row['prefix_sha256']==sha(prefix)
        assert json.loads((d.parent/'build.json').read_text())['tasks']==64
        rebuild.append(dict(index=index,generation=before['generation']))
    else:
        assert before['generation']==2
        batch.append(index);seconds.append(result['host_seconds']);read_seconds.append(result['readback_seconds'])
assert batch==list(range(100))
assert [x['generation'] for x in rebuild]==list(range(3,3+len(rebuild)))
assert len(rebuild)==10
continuous=json.loads((s/'continuous/report.json').read_text())
assert continuous['status']=='passed_continuous_subset' and continuous['batches']==100 and continuous['rebuilds']==10
actual={}
for name,record in c['snapshots'].items():
    lead='board-suite-v3/continuous/'
    if name.startswith(lead):actual[name[len(lead):]]={k:record[k] for k in ('bytes','sha256')}
actual['built-prefix.bin']=dict(bytes=len(prefix),sha256=sha(prefix))
for row in c['rows']:
    lead=row['path'].removeprefix('continuous/')
    for name,record in row['files'].items():actual[lead+'/'+name]=record
    if lead.endswith('/query'):actual[lead.removesuffix('/query')+'/built-prefix.bin']=dict(bytes=len(prefix),sha256=sha(prefix))
for gi,group in enumerate(gold['pairs']):
    for si,step in enumerate(group['steps']):
        raw=(ref/step['logits_file']).read_bytes()
        actual[f'reference-logits-{gi}-{si}.npy']=dict(bytes=len(raw),sha256=sha(raw))
for f in continuous['files']:assert actual[f['path']]==dict(bytes=f['bytes'],sha256=f['sha256']),f['path']
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
smoke=json.loads((s/'smoke/report.json').read_text());assert smoke['status']=='passed_four_token_full_kv'
for f in smoke['files']:
    path=s/'smoke'/f['path']
    if f['path']=='built-prefix.bin':path=p.parent/'status-check-20261108-v2/built-prefix.bin'
    assert path.stat().st_size==f['bytes'] and sha(path.read_bytes())==f['sha256']
immutable=json.loads((s/'smoke/immutable.json').read_text())
with Path('assets/data/dram-input.bin').open('rb') as cold:
    final_immutable=json.loads((s/'continuous/rebuild-09/query/immutable.json').read_text())
    assert final_immutable['status']=='passed_all_declared_immutable_regions'
    for row in immutable['regions']+final_immutable['regions']:
        address=row['address']
        if row['name'].startswith('scratch-template-'):address=layout['scratch_restore'][int(row['name'].rsplit('-',1)[1])][0]
        cold.seek(address);h=hashlib.sha256();left=row['bytes']
        while left:
            data=cold.read(min(left,1<<20));assert data;h.update(data);left-=len(data)
        assert h.hexdigest()==row['sha256'],row['name']
result=dict(status='passed_local_completed_milestone_audit',completed_batches=len(batch),completed_rebuilds=len(rebuild),
    raw_files_checked=sum(len(x['files']) for x in c['rows']),raw_bytes_checked=sum(f['bytes'] for x in c['rows'] for f in x['files'].values()),
    immutable_regions_checked=len(immutable['regions'])+len(final_immutable['regions']),immutable_bytes_checked=sum(x['bytes'] for x in immutable['regions']+final_immutable['regions']),
    batch_median_host_seconds=statistics.median(seconds),batch_median_readback_seconds=statistics.median(read_seconds),
    frozen_inputs_checked=c['frozen_inputs_checked'],board_acceptance_passed=False,
    completed_fault_recoveries=len(faults),
    fault_raw_files_checked=sum(len(r['files']) for r in c['fault_rows']),
    fault_raw_bytes_checked=sum(f['bytes'] for r in c['fault_rows'] for f in r['files'].values()),
    scope='All 100 batches and 10 rebuilds plus captured completed fault recoveries rehashed remotely and matched to independent local references. Full fault matrix, benchmark, isolation and acceptance remain pending.')
(p/'local-verification.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))

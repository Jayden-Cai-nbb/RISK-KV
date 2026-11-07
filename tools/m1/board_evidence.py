"""Check declared M1 numerical artifacts against fixed reference bytes, not only status strings."""
import hashlib,json
from pathlib import Path
import numpy as np
import host

def immutable_proof(path,layout,*,short=False):
    data=json.loads(path.read_text());assert data['status']=='passed_all_declared_immutable_regions'
    expected=[(a,n,a) for a,n in layout['immutable_regions']]
    expected += [(p['address'],p['bytes'],p['address']) for p in layout['programs'].values()]
    at=layout['scratch_template_base']
    for a,n in layout['scratch_restore']:expected.append((at,n,a));at+=n
    start=layout['kv_base']+(layout['prefix_bytes'] if short else layout['object_bytes'])
    expected.append((start,layout['kv_base']+layout['pool_bytes']-start,start))
    assert len(data['regions'])==len(expected)
    with (host.ROOT/'assets/data/dram-input.bin').open('rb') as cold:
        for row,(address,size,source) in zip(data['regions'],expected):
            assert (row['address'],row['bytes'])==(address,size)
            cold.seek(source);h=hashlib.sha256();remaining=size
            while remaining:
                b=cold.read(min(1<<20,remaining));assert b;h.update(b);remaining-=len(b)
            assert h.hexdigest()==row['sha256'],'immutable digest differs from frozen input'

def verify_numeric(paths):
    layout=json.loads((host.ROOT/'configs/m1/layout.json').read_text())
    # Every suite preserves the exact reference summary; payload manifests are independently checked by the caller.
    summary=json.loads((paths['continuous'].parent/'reference-input.json').read_text())
    assert summary['status']=='passed_independent_native_reference' and len(summary['pairs'])==2
    prefix=(host.ROOT/'assets/reference/reference-prefix.bin').read_bytes()
    assert hashlib.sha256(prefix).hexdigest()==summary['prefix_sha256']
    smoke=paths['smoke'].parent
    expected=host.four_token_prefix(host.ROOT/'assets/reference')
    assert (smoke/'built-prefix.bin').read_bytes()==expected
    immutable_proof(smoke/'immutable.json',layout,short=True)
    cleared=hashlib.sha256(prefix+bytes(layout['object_bytes']-len(prefix))).hexdigest()
    # Raw logits are little-endian float32; the independent summary binds .npy file hashes,
    # therefore carry verified raw hashes explicitly instead of confusing header-inclusive hashes.
    raw_refs=json.loads((paths['continuous'].parent/'raw-reference-sha256.json').read_text())
    assert len(raw_refs)==2 and all(len(x)==3 for x in raw_refs)
    for gi,g in enumerate(summary['pairs']):
        for si,step in enumerate(g['steps']):
            file=paths['continuous'].parent/f'reference-logits-{gi}-{si}.npy'
            assert host.sha(file)==step['logits_sha256']
            assert hashlib.sha256(np.load(file,allow_pickle=False).tobytes()).hexdigest()==raw_refs[gi][si]
    def pair(folder,index,cleanup=True):
        result=json.loads((folder/'result.json').read_text());assert result['status']=='passed' and len(result['steps'])==3
        group=summary['pairs'][index]
        assert host.sha(folder/'context.bin')==group['context_sha256']
        for j,step in enumerate(result['steps']):
            assert step['cq']['status']==0 and step['cq']['tokens']==group['steps'][j]['output_tokens']
            assert (folder/f'logits-{j}.bin').stat().st_size==layout['logits_bytes']
            assert host.sha(folder/f'logits-{j}.bin')==raw_refs[index][j]
        if cleanup:assert host.sha(folder/'cleared-object.bin')==cleared
    continuous=paths['continuous'].parent
    assert (continuous/'built-prefix.bin').read_bytes()==prefix
    for i in range(100):pair(continuous/f'batch-{i:03d}',i%2)
    for i in range(10):
        d=continuous/f'rebuild-{i:02d}';assert (d/'built-prefix.bin').read_bytes()==prefix;pair(d/'query',i%2)
    immutable_proof(continuous/'rebuild-09/query/immutable.json',layout)
    for mode in ('cancel','error','reset'):
        for i in range(10):
            d=paths['faults'].parent/f'{mode}-{i:02d}/recovered'
            assert (d/'built-prefix.bin').read_bytes()==prefix;pair(d/'query',i%2,False)
    immutable_proof(paths['faults'].parent/'reset-09/recovered/query/immutable.json',layout)
    load=json.loads((paths['load'].parent/'load.json').read_text());assert load['status']=='passed_readback'
    first=load['regions'][0];assert first['bytes']==layout['cold_image_bytes'] and first['sha256']==layout['cold_image_sha256']
    assert len(load['regions'])==1+len(layout['scratch_restore'])
    with (host.ROOT/'assets/data/dram-input.bin').open('rb') as cold:
        target=layout['scratch_template_base']
        for row,(address,size) in zip(load['regions'][1:],layout['scratch_restore']):
            cold.seek(address);assert (row['address'],row['bytes'])==(target,size)
            assert row['sha256']==hashlib.sha256(cold.read(size)).hexdigest();target+=size
    isolation=json.loads((paths['isolation'].parent/'isolation.json').read_text());assert isolation['status']=='passed_no_reuse_after_loss'
    assert isolation['final']['isolated'] and not isolation['final']['cmd_ready']
    measurements=json.loads((paths['benchmark'].parent/'measurements.json').read_text())
    for mode in ('prefix_reuse','rebuild_each_batch'):assert len([r for r in measurements['rows'] if r['mode']==mode])>=30
    ddr=json.loads((paths['ddr'].parent/'ddr.json').read_text())
    if ddr['status']=='passed_final_bit_bist_and_host':
        q=ddr['qualification'];hw=json.loads(paths['ddr'].read_text())['hardware']
        assert q['status']=='passed_final_board_ddr_qualification' and q['bit_sha256']==hw['bit_sha256'] and q['ltx_sha256']==hw['ltx_sha256']
        assert q['configuration_cold_starts_passed']>=10 and q['full_2gib_data_passed'] and q['stress_30min_passed']
        steps={x['name']:x for x in q['steps']}
        assert all(x['status']=='passed' for x in q['steps'])
        for name in ('full-2gib','stress-30min'):
            r=steps[name]['result'];assert r['base']==0 and r['blocks']*64==layout['logical_bytes']
        assert steps['stress-30min']['result']['host_run_ms']>=1800000
        assert len(ddr['host']['masks'])>=20
    else:
        assert ddr['status']=='passed_full_range_and_masks' and len(ddr['rounds'])>=2
        assert all(x['bytes']==layout['logical_bytes'] for x in ddr['rounds'])
    return dict(all_declared_numeric_files_checked=True,continuous_pairs=110,recovered_pairs=30)

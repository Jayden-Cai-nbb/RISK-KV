"""One profile drives the common compute-slice RTL and simulator parameters."""
import hashlib
import json

def load(path):
    raw=path.read_bytes();p=json.loads(raw)
    if p['schema']!='risc-kv-npu-core-profile-1' or p['part']!='xcvu440-flga2892-2-e':raise ValueError('Unsupported core profile')
    if p['commit']!='91df41092f612361c5bc22f83b31d23382ffabb0':raise ValueError('Unexpected source version')
    if p['microarchitecture']['TMEM_PMP']!=1 or p['core_period_ns']!=2*p['fast_period_ns']:
        raise ValueError('This profile requires the validated 2x clock relationship')
    u=p['microarchitecture'];a=p['architecture']
    if u['TMEM_IMPL']==3 and u['TMEM_RPL'] and (u['RPB']<8*a['LANES'] or u['WPB']!=1):
        raise ValueError('Leaf slice requires RPB >= 8*LANES and WPB=1; target sentinel RPB=0 must be expanded')
    return p,hashlib.sha256(raw).hexdigest()

def simulation_parameters(p):
    return {**p['microarchitecture'],'SEQ_WC':int(p['architecture']['SEQ_WC']),
            'COLL_GATHER':p['simulation_collective_gather']}

def synthesis_parameters(p):
    a=p['architecture']
    result={k:a[k] for k in ('S','D','MCOLS','ACT_BLOCKS','ACT_ROWS','TMEM_WORDS','IMEM_WORDS','LANES')}
    result.update(p['microarchitecture']);result['SEQ_WC']=int(a['SEQ_WC'])
    result['HAS_DSTEP']=1  # otpu_top instantiates this upstream default as well
    return result

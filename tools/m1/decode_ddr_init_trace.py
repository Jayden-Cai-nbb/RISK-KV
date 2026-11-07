"""Decode passive pre-PHY eight-slot frames; never infer analog pin behavior."""
import argparse,csv,hashlib,json
from pathlib import Path
EXPECTED_MR={0:0x314,1:0x301,2:0x10,3:0,4:0,5:0x400,6:0x41b}

def decode(rows):
    frames=[];mrs=[];prev_tick=-1
    for idx,r in enumerate(rows):
        assert int(r['index'])==idx
        meta,tick,payload=(int(r[k]) for k in ('metadata','timestamp','payload'))
        assert (meta&1023)==idx and meta&(1<<21)
        assert 0<=payload<1<<256 and 0<=tick<1<<48 and tick>prev_tick
        assert (meta>>10)&2047<=1024
        prev_tick=tick
        def field(offset,width):return (payload>>offset)&((1<<width)-1)
        adr,ba,bg=(field(o,w) for o,w in ((0,136),(136,16),(152,16)))
        act,cs,cke,reset,odt,status=(field(o,8) for o in (168,176,184,192,200,208))
        assert field(216,40)==0
        def slot(v,width,s):return sum(((v>>(b*8+s))&1)<<b for b in range(width))
        commands=[]
        for s in range(8):
            if (cs>>s)&1 or not ((cke>>s)&1) or reset!=255 or status&2:continue
            a=slot(adr,17,s);b=slot(ba,2,s);g=slot(bg,2,s)
            kind='ACT' if not ((act>>s)&1) else {0:'MRS',1:'REF',2:'PRE',3:'RESERVED',4:'WRITE',5:'READ',6:'ZQ',7:'NOP'}[(a>>14)&7]
            entry=dict(slot=s,kind=kind,address=a,bank=b,group=g)
            if kind=='MRS':entry.update(mr=(g<<2)|b,value=a&8191)
            commands.append(entry)
        # 同一 fabric 帧可能含重复串行槽：记录签名，不把去重数量当物理命令数。
        signatures=[]
        for c in commands:
            sig={k:v for k,v in c.items() if k!='slot'}
            if sig not in signatures:signatures.append(sig)
        for c in signatures:
            if c['kind']=='MRS':mrs.append(dict(frame=idx,tick=tick,**c))
        frames.append(dict(index=idx,tick=tick,reset_n=reset,cke=cke,cs_n=cs,status=status,
                           odt=odt,overflow_at_readout=bool(meta&(1<<22)),commands=commands))
    initial=[(x['mr'],x['value']) for x in mrs[:7]]
    expected=[(n,EXPECTED_MR[n]) for n in [3,6,5,4,2,1,0]]
    return dict(scope='digital pre-PHY observation only; no physical acceptance or DDR data proof',
                frames=frames,mrs=mrs,initial_mrs_match=(initial==expected),
                expected_initial_mrs=expected,read_frames=sum(any(c['kind']=='READ' for c in f['commands']) for f in frames),
                mr4_read_preamble_training_seen=any(x['mr']==4 and x['value']&(1<<10) for x in mrs),
                overflow=any(f['overflow_at_readout'] for f in frames))

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('trace',type=Path);p.add_argument('--output',required=True,type=Path)
    a=p.parse_args()
    result=decode(list(csv.DictReader(a.trace.open(),delimiter='\t')))
    result['input_sha256']=hashlib.sha256(a.trace.read_bytes()).hexdigest()
    with a.output.open('x') as f:json.dump(result,f,indent=2);f.write('\n')
    print(json.dumps({k:v for k,v in result.items() if k not in ['frames','mrs']}))

"""Experimental software KV descriptors: immutable whole-block prefix + private tail.

No arithmetic replacement. Existing _Head visits the original token blocks in
the original order and keeps one (m,l,acc) state. Prototype supports static block
addresses and <=1024 positions; dynamic loop-index routing is rejected.
Writes use logical-position-biased tail addresses and REQUIRE the trusted caller
to validate_append before compiling/submitting. This is not hardware isolation.
"""
import ast
from dataclasses import dataclass
import hashlib
import inspect
import textwrap
from types import SimpleNamespace

from opentpu.compiler import Affine,KVDesc,vt_tile,k_scale_bytes
from opentpu.llm import qwen3 as q3

BLOCK=256

def _integer(x):
    if type(x) is int:return x
    if isinstance(x,Affine) and not x.terms:return int(x.const)
    raise ValueError('Split KV prototype requires static token block boundaries')

class _View:
    def __init__(self,prefix,tail,biased,split,axis,cap):
        self.prefix,self.tail,self.biased=prefix,tail,biased
        self.split,self.axis,self.cap=split,axis,cap
        self.shape=biased.shape
        if axis==1:self.tiles=(BLOCK,self.shape[0]*BLOCK)
    def __getattr__(self,name):return getattr(self.biased,name)
    def locate(self,start,count):
        start,count=_integer(start),_integer(count)
        if start<0 or count<=0 or start+count>self.cap:raise ValueError('KV read outside logical capacity')
        if start<self.split:
            if start+count>self.split:raise ValueError('KV read/padding crosses split boundary')
            return self.prefix,start
        return self.tail,start-self.split
    def __getitem__(self,key):
        ks=key if isinstance(key,tuple) else (key,)
        s=ks[self.axis]
        if not isinstance(s,slice) or s.step not in (None,1):raise ValueError('Only contiguous token slices supported')
        start=0 if s.start is None else _integer(s.start)
        end=self.cap if s.stop is None else _integer(s.stop)
        selected,local=self.locate(start,end-start)
        adjusted=list(ks);adjusted[self.axis]=slice(local,local+end-start)
        return selected[tuple(adjusted)] if isinstance(key,tuple) else selected[adjusted[0]]
    def padded_cols(self,r0,r1,start,padded,valid):
        if self.axis!=1:raise ValueError('padded_cols is a V-transpose operation')
        selected,local=self.locate(start,padded)
        if not 0<valid<=padded:raise ValueError('Invalid padded read')
        return selected.padded_cols(r0,r1,local,padded,valid)

class SplitKV:
    def __init__(self,prefix,private):
        p,t=prefix.cap,private.cap
        if p<=0 or t<=0 or p%BLOCK or t%BLOCK or p+t>1024:raise ValueError('Unsupported split/capacity')
        if any(getattr(prefix,n)!=getattr(private,n) for n in ('d','D','S','sid','dv')):
            raise ValueError('KV geometry differs')
        if set(prefix.heads)!=set(private.heads):raise ValueError('KV head ownership differs')
        if vt_tile(p)!=BLOCK or vt_tile(t)!=BLOCK:raise ValueError('Native V tile differs')
        self.prefix,self.private,self.split=prefix,private,p
        self.cap=p+t
        for n in ('d','D','S','sid','dv'):setattr(self,n,getattr(prefix,n))
        biased={h:{'k':Affine.of(r['k'])-p*self.d,'ks':Affine.of(r['ks'])-p*k_scale_bytes(self.d,self.D),
                   'vt':Affine.of(r['vt'])-p*self.d,'vs':Affine.of(r['vs'])-p*4}
                for h,r in private.heads.items()}
        self._write=KVDesc(biased,self.cap,self.d,self.D,self.S,self.sid,dv=self.dv)
    def owned_heads(self,n):return self.prefix.owned_heads(n)
    def validate_append(self,position,rows=1):
        if type(position)is not int or type(rows)is not int or rows<1 or position<self.split or position+rows>self.cap:
            raise ValueError('Append would touch sealed prefix or exceed private capacity')
    def k(self,h):return _View(self.prefix.k(h),self.private.k(h),self._write.k(h),self.split,0,self.cap)
    def vt(self,h):return _View(self.prefix.vt(h),self.private.vt(h),self._write.vt(h),self.split,1,self.cap)
    def vscale(self,h):return _View(self.prefix.vscale(h),self.private.vscale(h),self._write.vscale(h),self.split,0,self.cap)
    def vt_column(self,h,t):return self._write.vt_column(h,t)

def _allocate(lb,L,cap,d,D,batch,nheads,prefix):
    if cap%256 or prefix%256 or not 0<prefix<cap<=1024 or batch!=2:
        raise ValueError('Experimental image requires two slots and complete 256-token segments')
    def head(n):return {'k':lb.alloc(n*d),'ks':lb.alloc(n*k_scale_bytes(d,D)),
                       'vt':lb.alloc(d*n),'vs':lb.alloc(4*n)}
    L['shared_prefix']=[head(prefix) for _ in range(nheads)]
    return [[head(cap-prefix) for _ in range(nheads)] for _ in range(batch)]

def _initializer():
    """Change ONE allocation expression, preserving the native weight/lookup layout code."""
    original=textwrap.dedent(inspect.getsource(q3.Image.__init__))
    tree=ast.parse(original);original_dump=ast.dump(tree,include_attributes=False)
    targets=[]
    for node in ast.walk(tree):
        if isinstance(node,ast.Assign) and len(node.targets)==1:
            t=node.targets[0]
            if isinstance(t,ast.Subscript) and isinstance(t.value,ast.Name) and t.value.id=='L' and isinstance(t.slice,ast.Constant) and t.slice.value=='kvs':
                targets.append(node)
    if len(targets)!=1:raise ValueError('Pinned allocation site changed')
    node=targets[0];old=node.value
    node.value=ast.parse('_rkv_allocate(lb,L,cap,d,D,batch,self.nkv_loc,self.shared_prefix_tokens)',mode='eval').body
    ast.fix_missing_locations(tree);changed=ast.unparse(tree)
    namespace=dict(q3.__dict__);namespace['_rkv_allocate']=_allocate
    exec(compile(tree,'<rkv_split_image_allocator>','exec'),namespace)
    node.value=old
    if ast.dump(tree,include_attributes=False)!=original_dump:raise AssertionError('Non-allocation AST changed')
    return namespace['__init__'],dict(original_sha256=hashlib.sha256(original.encode()).hexdigest(),
                 derived_ast_sha256=hashlib.sha256(changed.encode()).hexdigest(),changed_expressions=1,
                 reverse_ast_equal=True)

_INIT,ALLOCATOR_PROOF=_initializer()

class SplitImage(q3.Image):
    def __init__(self,spec,cfg,cap,batch=2,rows=2,wformat='int8',head_format=None,lookup=False,embed_host=None,formats=None):
        self.shared_prefix_tokens=spec.shared_prefix_tokens
        _INIT(self,spec,cfg,cap,batch,rows,wformat,head_format,lookup,embed_host,formats)
        unit=spec.layers*self.nkv_loc*(2*spec.head_dim+k_scale_bytes(spec.head_dim,cfg.D)+4)
        self.shared_prefix_bytes=unit*self.shared_prefix_tokens
        self.private_bytes_per_slot=unit*(cap-self.shared_prefix_tokens)
        self.physical_kv_bytes=self.shared_prefix_bytes+batch*self.private_bytes_per_slot
    def descriptors(self,sid):
        base=super().descriptors(sid);native_layer=base.layer
        def layer(li,it=None):
            ns=native_layer(li,it);off=self._off(li,it);lofs=self.bofs[self.lf[li]]
            def make(heads,cap):
                return KVDesc({sid+j*self.cfg.S:{k:off+v for k,v in r.items()} for j,r in enumerate(heads)},
                              cap,self.spec.head_dim,self.cfg.D,self.cfg.S,sid)
            prefix=make(lofs['shared_prefix'],self.shared_prefix_tokens)
            ns.kvs=[SplitKV(prefix,make(heads,self.cap-self.shared_prefix_tokens)) for heads in lofs['kvs']]
            ns.kv=ns.kvs[0];return ns
        base.layer=layer;return base

@dataclass(frozen=True)
class SharedSpec(q3.Spec):
    shared_prefix_tokens:int=256
    def image(self,cfg,cap,batch=1,rows=1,wformat='int8',head_format=None,lookup=False,embed_host=None,formats=None):
        return SplitImage(self,cfg,cap,batch,rows,wformat,head_format,lookup,embed_host,formats)

def physical_regions(image,sid=0):
    regions=[]
    for li in range(image.spec.layers):
        ns=image.descriptors(sid).layer(li)
        groups=[('prefix',-1,ns.kvs[0].prefix)]+[('private',i,x.private) for i,x in enumerate(ns.kvs)]
        for kind,slot,kv in groups:
            for head,r in kv.heads.items():
                for name,n in (('k',kv.cap*kv.d),('ks',kv.cap*k_scale_bytes(kv.d,kv.D)),('vt',kv.cap*kv.d),('vs',kv.cap*4)):
                    addr=Affine.of(r[name]).static()
                    if not 0<=addr<addr+n<=image.nbytes:raise ValueError('Physical KV allocation out of image')
                    regions.append(dict(layer=li,head=head,kind=kind,slot=slot,field=name,address=addr,bytes=n))
    cursor=0
    for r in sorted(regions,key=lambda r:r['address']):
        if r['address']<cursor:raise ValueError('Physical KV allocations overlap')
        cursor=r['address']+r['bytes']
    return regions

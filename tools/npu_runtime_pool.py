"""Cold-compiled two-row decode template: runtime KV base, tokens and local step.

Reuses the native NPU ISA and math. A narrowly scoped compiler adapter factors
base + c*step into one host-provided argument; no global patch survives tracing.
Trusted serial prototype, not a hardware permission boundary.
"""
from contextlib import contextmanager
from dataclasses import dataclass
import threading

from opentpu import language as ol
from opentpu import isa as I
from opentpu.compiler import Affine, Builder, RunVar, KVDesc, arg_words
from opentpu.llm import qwen3 as q3
from opentpu.llm.batch import step_rows
from npu_kv_pool import PoolImage
from npu_split_kv import SplitKV

_TRACE_LOCK=threading.Lock()


class AddressFactors:
    def __init__(self,base):
        self.base=base
        self.combined={}
        self.examples=[]

    def fold(self,address):
        a=Affine.of(address)
        runtime=[(v,c) for v,c in a.terms.items() if isinstance(v,RunVar)]
        if self.base not in a.terms or len(runtime)<2:return a
        if len(runtime)!=2 or a.terms[self.base]!=1:
            raise ValueError('Unsupported composite address')
        other,coef=next((v,c) for v,c in runtime if v is not self.base)
        if other.name!='tpos' or coef not in (1,4,128):
            raise ValueError('Unreviewed KV write stride')
        if coef not in self.combined:self.combined[coef]=RunVar(f'kv_plus_step_{coef}')
        terms={v:c for v,c in a.terms.items() if v not in (self.base,other)}
        terms[self.combined[coef]]=1
        if len(self.examples)<8:self.examples.append(dict(const=a.const,coefficient=coef))
        return Affine(a.const,terms)

    @contextmanager
    def installed(self):
        # Native compilation is serialized; do not use with unrelated compile workers.
        with _TRACE_LOCK:
            original=Builder.addr
            def addr(builder,address):return original(builder,self.fold(address))
            Builder.addr=addr
            try:yield
            finally:Builder.addr=original


@ol.jit
def runtime_rows(m,prefix,span,tokens):
    rows=step_rows([(0,prefix),(1,prefix)],span,256,m.zmask,1024)
    x=ol.empty([2,m.xr.shape[1]],dense=True)
    c=ol.empty([2,m.cosr.shape[1]],dense=True)
    s=ol.empty([2,m.sinr.shape[1]],dense=True)
    for r,(_,pos) in enumerate(rows):
        x[r:r+1,:].set(q3._embed(m,tokens[r]))
        ol.release(tokens[r])
        ol.load(m.cos_t[pos.pos:pos.pos+1,:],out=c[r:r+1,:])
        ol.load(m.sin_t[pos.pos:pos.pos+1,:],out=s[r:r+1,:])
    for lw in q3._layers(m):
        x.set(q3._attention_rows(x,lw,c,s,rows,m.spec,256))
        x.set(q3._mlp(x,lw,m.spec))
    q3._lm_head_rows(x,m,m.spec,[0,1])


@dataclass(frozen=True)
class Template:
    prefix:int
    span:int
    context_bytes:int
    programs:list
    factors:AddressFactors
    owner:object

    def values(self,base,step,tokens,*,vocab,dram_bytes):
        if type(base)is not int or base<0 or base%128 or base+self.context_bytes>dram_bytes:
            raise ValueError('KV base/range outside device memory')
        if type(step)is not int or not 0<=step<self.span:
            raise ValueError('Step outside compiled attention bucket')
        if len(tokens)!=2 or any(type(t)is not int or not 0<=t<vocab for t in tokens):
            raise ValueError('Invalid token ids')
        values=dict(kv_base=base,tpos=step,tok0=tokens[0],tok1=tokens[1])
        for c in self.factors.combined:
            value=base+c*step
            if not 0<=value<1<<32:raise ValueError('Composite address overflow')
            values[f'kv_plus_step_{c}']=value
        return values

    def arguments(self,base,step,tokens,*,vocab,dram_bytes):
        values=self.values(base,step,tokens,vocab=vocab,dram_bytes=dram_bytes)
        return [arg_words(p.run_args,values) for p in self.programs]


@dataclass(frozen=True)
class RuntimeSubmission:
    context:str
    epoch:int
    positions:tuple
    tokens:tuple
    template:Template
    args:list


class RuntimePoolImage(PoolImage):
    def kv(self,name,slot,li,it=None):
        runtime=getattr(self,'_runtime_base',None)
        if runtime is None:return super().kv(name,slot,li,it)
        ctx=self.contexts[name]
        index=Affine.of(li) if it is None else Affine.of(li)+Affine.of(it)
        def desc(segment):
            base=runtime+(segment['base']-ctx['start'])+index*segment['stride']
            return KVDesc({h:{k:base+v for k,v in rr.items()} for h,rr in enumerate(segment['heads'])},
                          segment['tokens'],self.spec.head_dim,self.cfg.D,1,0)
        return SplitKV(desc(ctx['prefix']),desc(ctx['private'][slot]))

    def compile_template(self,span=256,fold_addresses=True):
        if self.bound is None or self.busy or self.faulted:raise ValueError('Unbound or unavailable image')
        c=self.contexts[self.bound];prefix=c['prefix']['tokens']
        if self.spec.head_dim!=128 or self.cfg.D!=128 or self.spec.embed!='f32':
            raise ValueError('Pilot contract requires D=128 and FP32 resident embedding table')
        if type(span)is not int or not 1<=span<=min(256,c['private'][0]['tokens']):raise ValueError('Invalid span')
        if any(s['tokens']!=256 for s in c['private']):raise ValueError('Only one private native block per row')
        base=RunVar('kv_base');factors=AddressFactors(base)
        self._runtime_base=base
        try:
            def compile_one():
                return runtime_rows.trace(self.cfg,0,dict(m=self.descriptors(0),prefix=prefix,span=span,
                    tokens=[RunVar('tok0'),RunVar('tok1')])).finish()
            if fold_addresses:
                with factors.installed():program=compile_one()
            else:program=compile_one()
        finally:self._runtime_base=None
        if len(program.run_args)>8:raise AssertionError('More than eight native arguments')
        if len(I.assemble(program))>self.cfg.IMEM_WORDS:raise ValueError('Template exceeds IMEM')
        return Template(prefix,span,c['end']-c['start'],[program],factors,self)

    def prepare_runtime(self,template,tokens):
        if template.owner is not self or self.bound is None or self.busy or self.faulted:
            raise ValueError('Foreign template or unavailable image')
        c=self.contexts[self.bound]
        if not c['sealed'] or c['prefix']['tokens']!=template.prefix or c['end']-c['start']!=template.context_bytes:
            raise ValueError('Binding geometry differs from compiled template')
        if len(set(c['positions']))!=1:
            raise ValueError('Pilot advances two queries in lockstep')
        args=template.arguments(c['start'],c['positions'][0]-template.prefix,list(tokens),
                                vocab=self.spec.vocab,dram_bytes=self.cfg.DRAM_BYTES)
        return RuntimeSubmission(self.bound,self.epoch,tuple(c['positions']),tuple(tokens),template,args)

    def execute_runtime(self,engine,submission):
        if engine.image is not self or self.busy or self.faulted or submission.context!=self.bound or submission.epoch!=self.epoch:
            raise ValueError('Stale binding or unavailable execution')
        checked=self.prepare_runtime(submission.template,submission.tokens)
        if checked.positions!=submission.positions or checked.args!=submission.args:
            raise ValueError('Stale positions or changed arguments')
        if not getattr(engine.backend,'args',False):raise ValueError('Backend lacks runtime arguments')
        self.busy=True
        try:
            import numpy as np
            stats=engine.backend.run(submission.template.programs,args=submission.args[0])
            engine.stats.append(stats)
            v=engine.backend.read(0,self.io['logits'],2*self.spec.vocab*4).view(np.float32).reshape(2,self.spec.vocab)
            self.contexts[self.bound]['positions']=[p+1 for p in submission.positions]
            return v
        except Exception:
            self.faulted=True
            raise
        finally:self.busy=False

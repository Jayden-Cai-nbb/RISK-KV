"""Native full-model build/bind/decode programs for a single cold context.

The accepted experiment builds exactly one native 256-token page and reads it
in place after sealing. No short-prefix copy fallback is used.
"""
from opentpu import language as ol
from opentpu import isa as I
from opentpu.compiler import Affine,KVDesc,RunVar,Tensor,k_scale_bytes
from opentpu.llm import qwen3 as q3
from npu_kv_pool import PoolImage
from npu_split_kv import SplitKV
from npu_runtime_pool import AddressFactors
from npu_generating_pool import generating_rows


def completion_words(address,kind,count):
    value=ol.empty([2]);value[0:1].set(ol.full([1],float(kind)));value[1:2].set(ol.full([1],float(count)))
    ol.store(Tensor(address,(2,),(1,)),value)


@ol.jit
def build_rows(m,rows,result_address):
    q3.qwen3_rows.fn(m,rows,[],256)
    completion_words(result_address,1,rows.R)


class ColdContextImage(PoolImage):
    def create_cold(self,name,valid_tokens):
        if type(valid_tokens)is not int or valid_tokens!=256:
            raise ValueError('User-selected experiment requires a complete 256-token page')
        ctx=self.create_context(name,256,256)
        ctx['valid_tokens']=valid_tokens
        self.bound=name  # compiler selection only, never a claim that the object is sealed
        self.view='build';self.runtime_base=None
        return ctx

    def segments(self,name,slot,li,it=None):
        c=self.contexts[name]
        index=Affine.of(li) if it is None else Affine.of(li)+Affine.of(it)
        def make(segment):
            base=Affine.of(segment['base']) if self.runtime_base is None else self.runtime_base+(segment['base']-c['start'])
            base=base+index*segment['stride']
            return KVDesc({h:{k:base+v for k,v in r.items()} for h,r in enumerate(segment['heads'])},256,128,128,1,0)
        return make(c['prefix']),make(c['private'][slot])

    def descriptors(self,sid):
        if self.bound is None:raise ValueError('No compile context')
        m=q3.Image.descriptors(self,sid);native=m.layer;name=self.bound;view=self.view
        def layer(li,it=None):
            ns=native(li,it);pairs=[self.segments(name,s,li,it) for s in (0,1)]
            ns.prefix=pairs[0][0];ns.private=[p[1] for p in pairs]
            if view=='build':ns.kvs=[ns.prefix,ns.prefix]
            elif view=='decode':ns.kvs=[SplitKV(p,t) for p,t in pairs]
            else:raise ValueError('Unknown compile view')
            ns.kv=ns.kvs[0];return ns
        m.layer=layer;return m

    def compile_operation(self,kind):
        if self.spec.head_dim!=128 or self.cfg.D!=128 or self.cfg.S!=1 or self.spec.embed!='f32':raise ValueError('Unsupported frozen geometry')
        c=self.contexts[self.bound];n=c['valid_tokens'];base=RunVar('kv_base');factors=AddressFactors(base)
        self.runtime_base=base;self.view=kind
        result=self.lookup['gen']['state']  # keep prompt token buffer gen.out untouched
        try:
            with factors.installed():
                m=self.descriptors(0)
                if kind=='build':
                    rows=q3.RunRows(1,256,0,self.lookup['zmask'],1024,4,toks_at=0)
                    program=build_rows.trace(self.cfg,0,dict(m=m,rows=rows,result_address=result)).finish()
                elif kind=='decode':
                    span=256
                    program=generating_rows.trace(self.cfg,0,dict(m=m,prefix=n,span=span,
                        tokens=[RunVar('tok0'),RunVar('tok1')],result_address=result)).finish()
                else:raise ValueError('Unknown operation')
        finally:self.runtime_base=None
        if len(program.run_args)>8 or len(I.assemble(program))>self.cfg.IMEM_WORDS:raise ValueError('Instruction/argument limit')
        return program,factors

    def argument_values(self,step,tokens=(0,0)):
        base=self.contexts[self.bound]['start']
        return dict(kv_base=base,tpos=step,tok0=tokens[0],tok1=tokens[1],
                    kv_plus_step_1=base+step,kv_plus_step_4=base+4*step,kv_plus_step_128=base+128*step)

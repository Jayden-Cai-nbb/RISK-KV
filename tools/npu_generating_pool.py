"""Native device-side greedy sinks, retaining full logits for verification."""
from opentpu import language as ol
from opentpu import isa as I
from opentpu.compiler import RunVar,Tensor,current
from opentpu.llm import qwen3 as q3
from opentpu.llm import generate as G
from npu_runtime_pool import RuntimePoolImage,AddressFactors,Template,runtime_rows


class MirrorGreedy:
    raw=True
    def __init__(self,m,row,chunk):
        self.m,self.row=m,row
        self.greedy=G.Greedy(current(),m.v_loc,chunk)
    def __call__(self,value,column):
        ol.store(self.m.logitsr[self.row:self.row+1,column:column+value.cols],value)
        self.greedy(value,column)


@ol.jit
def generating_rows(m,prefix,span,tokens,result_address):
    sinks=[MirrorGreedy(m,row,q3.head_rows_chunk(2)) for row in range(2)]
    m.lm_sinks=sinks
    runtime_rows.fn(m,prefix,span,tokens)
    for row in range(2):
        token=sinks[row].greedy.token()
        ol.store(Tensor(result_address+4*row,(1,),(1,)),token)


class GeneratingPoolImage(RuntimePoolImage):
    def compile_generation(self,span=256):
        if self.bound is None or self.busy or self.faulted:raise ValueError('Unavailable binding')
        c=self.contexts[self.bound]
        if self.cfg.S!=1 or self.cfg.D!=128 or self.spec.head_dim!=128 or self.spec.embed!='f32':
            raise ValueError('Frozen single-slice geometry required')
        if c['prefix']['tokens']!=512 or any(s['tokens']!=256 for s in c['private']):raise ValueError('Pilot geometry differs')
        if type(span)is not int or not 1<=span<=256:raise ValueError('Invalid span')
        base=RunVar('kv_base');factors=AddressFactors(base);self._runtime_base=base
        try:
            with factors.installed():
                program=generating_rows.trace(self.cfg,0,dict(m=self.descriptors(0),prefix=512,span=span,
                    tokens=[RunVar('tok0'),RunVar('tok1')],result_address=self.lookup['gen']['out'])).finish()
        finally:self._runtime_base=None
        if len(program.run_args)>8 or len(I.assemble(program))>self.cfg.IMEM_WORDS:raise ValueError('Program/argument capacity exceeded')
        return Template(512,span,c['end']-c['start'],[program],factors,self)

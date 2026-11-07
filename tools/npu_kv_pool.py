"""Experimental fixed-weight image with an independently allocated, serial KV pool.

Trusted Python control only. No MMU, hardware permissions, asynchronous retirement,
or production ABI. The original NPU arithmetic and weight builder are unchanged.
"""
import ast
from dataclasses import dataclass
import hashlib
import inspect
import textwrap

from opentpu.compiler import Affine, KVDesc, k_scale_bytes
from opentpu.llm import qwen3 as q3
from npu_split_kv import SplitKV


def _initializer():
    original = textwrap.dedent(inspect.getsource(q3.Image.__init__))
    tree = ast.parse(original)
    original_dump = ast.dump(tree, include_attributes=False)
    matches = [n for n in ast.walk(tree) if isinstance(n, ast.Assign) and len(n.targets) == 1
               and isinstance(n.targets[0], ast.Subscript)
               and isinstance(n.targets[0].value, ast.Name) and n.targets[0].value.id == 'L'
               and isinstance(n.targets[0].slice, ast.Constant) and n.targets[0].slice.value == 'kvs']
    if len(matches) != 1:
        raise ValueError('Pinned allocation expression changed')
    n = matches[0]
    old = n.value
    # Descriptor placeholders allocate NO bytes and never reach model execution:
    # descriptors() replaces them with pool addresses, or fails while unbound.
    n.value = ast.parse("[[dict(k=0,ks=0,vt=0,vs=0) for _ in range(self.nkv_loc)] for _ in range(batch)]", mode='eval').body
    ast.fix_missing_locations(tree)
    changed = ast.unparse(tree)
    ns = dict(q3.__dict__)
    exec(compile(tree, '<rkv_external_kv_allocator>', 'exec'), ns)
    n.value = old
    if ast.dump(tree, include_attributes=False) != original_dump:
        raise AssertionError('Non-allocation constructor change')
    return ns['__init__'], dict(changed_expressions=1, reverse_ast_equal=True,
        original_sha256=hashlib.sha256(original.encode()).hexdigest(),
        derived_ast_sha256=hashlib.sha256(changed.encode()).hexdigest())


_INIT, ALLOCATOR_PROOF = _initializer()


@dataclass(frozen=True)
class Prepared:
    context: str
    epoch: int
    rows: tuple
    tokens: tuple
    programs: list


class PoolImage(q3.Image):
    def __init__(self, spec, cfg, cap, batch=2, rows=2, wformat='int8', head_format=None,
                 lookup=False, embed_host=None, formats=None):
        if cfg.S != 1 or batch != 2 or cap != 1024 or not lookup:
            raise ValueError('Pilot requires S=1, two slots, fixed 1024-token lookup capacity')
        _INIT(self, spec, cfg, cap, batch, rows, wformat, head_format, lookup, embed_host, formats)
        if len(set(self.lf)) != 1:
            raise ValueError('Pilot supports one uniform layer layout')
        self.fixed_image_bytes = self.nbytes
        self.pool_base = (self.nbytes + 4095) // 4096 * 4096
        self.pool_bytes = spec.pool_bytes
        self.nbytes = self.pool_base + self.pool_bytes
        if self.nbytes > cfg.DRAM_BYTES:
            raise MemoryError('Pool exceeds device address capacity')
        self.next_pool = self.pool_base
        self.contexts = {}
        self.bound = None
        self.epoch = 0
        self.busy = False
        self.faulted = False

    def create_context(self, name, prefix_tokens, private_tokens=256):
        if self.busy or self.faulted or name in self.contexts:
            raise ValueError('Busy or duplicate context')
        if not isinstance(name, str) or not name:
            raise ValueError('Context name required')
        if type(prefix_tokens) is not int or type(private_tokens) is not int or \
                prefix_tokens <= 0 or private_tokens <= 0 or prefix_tokens % 256 or \
                private_tokens % 256 or prefix_tokens + private_tokens > self.cap:
            raise ValueError('Invalid native KV geometry')
        cursor = self.next_pool
        def segment(tokens):
            nonlocal cursor
            base = cursor
            heads = []
            for _ in range(self.nkv_loc):
                h = {}
                for field, size in self.field_sizes(tokens):
                    h[field] = cursor - base
                    cursor += size
                heads.append(h)
            stride = cursor - base
            cursor = base + stride * self.spec.layers
            return dict(base=base, stride=stride, heads=heads, tokens=tokens)
        prefix = segment(prefix_tokens)
        private = [segment(private_tokens) for _ in range(self.batch)]
        if cursor > self.pool_base + self.pool_bytes:
            raise MemoryError('KV pool full')
        context = dict(prefix=prefix, private=private, start=self.next_pool, end=cursor,
                       sealed=False, positions=[prefix_tokens] * self.batch)
        self.contexts[name] = context
        self.next_pool = cursor
        return context

    def field_sizes(self, tokens):
        d = self.spec.head_dim
        return [('k', tokens*d), ('ks', tokens*k_scale_bytes(d, self.cfg.D)),
                ('vt', tokens*d), ('vs', tokens*4)]

    def seal(self, name):
        if self.busy or self.faulted or self.contexts[name]['sealed']:
            raise ValueError('Busy or already sealed')
        # Caller must finish publishing before seal; this is a trusted serial API.
        self.contexts[name]['sealed'] = True

    def bind(self, name):
        if self.busy or self.faulted or not self.contexts[name]['sealed']:
            raise ValueError('Busy or unsealed context')
        self.bound = name
        self.epoch += 1

    def kv(self, name, slot, li, it=None):
        c = self.contexts[name]
        index = Affine.of(li) if it is None else Affine.of(li) + Affine.of(it)
        def desc(segment):
            base = Affine.of(segment['base']) + index * segment['stride']
            return KVDesc({h: {k: base+v for k,v in r.items()}
                           for h,r in enumerate(segment['heads'])}, segment['tokens'],
                          self.spec.head_dim, self.cfg.D, 1, 0)
        return SplitKV(desc(c['prefix']), desc(c['private'][slot]))

    def descriptors(self, sid):
        if self.bound is None:
            raise ValueError('No sealed context bound')
        base = super().descriptors(sid)
        native_layer = base.layer
        name = self.bound
        def layer(li, it=None):
            ns = native_layer(li, it)
            ns.kvs = [self.kv(name, slot, li, it) for slot in range(self.batch)]
            ns.kv = ns.kvs[0]
            return ns
        base.layer = layer
        return base

    def prepare(self, tokens, block=256):
        if self.busy or self.faulted or self.bound is None or len(tokens) != self.batch:
            raise ValueError('Pilot requires an idle bound context and two rows')
        c = self.contexts[self.bound]
        rows = tuple(enumerate(c['positions']))
        for slot, position in rows:
            self.kv(self.bound, slot, 0).validate_append(position)
        programs = self.compile_rows(rows, list(range(self.batch)), block, tokens=tokens)
        return Prepared(self.bound, self.epoch, rows, tuple(tokens), programs)

    def execute(self, engine, prepared):
        if engine.image is not self or self.busy or self.faulted or prepared.context != self.bound or prepared.epoch != self.epoch:
            raise ValueError('Stale binding or busy execution')
        c = self.contexts[self.bound]
        if prepared.rows != tuple(enumerate(c['positions'])):
            raise ValueError('Stale positions / already executed submission')
        self.busy = True
        try:
            output = engine._run_rows(prepared.rows, prepared.tokens, list(range(self.batch)), prepared.programs)
            c['positions'] = [p+1 for p in c['positions']]
            return output
        except Exception:
            self.faulted = True  # no reuse after an uncertain partial execution
            raise
        finally:
            self.busy = False

    def regions(self, name):
        c = self.contexts[name]
        result = []
        for kind, slot, s in [('prefix', -1, c['prefix'])] + [('private', i, s) for i,s in enumerate(c['private'])]:
            for li in range(self.spec.layers):
                for h, offsets in enumerate(s['heads']):
                    for field, n in self.field_sizes(s['tokens']):
                        result.append(dict(kind=kind, slot=slot, layer=li, head=h, field=field,
                                           address=s['base']+li*s['stride']+offsets[field], bytes=n))
        return result

    def immutable_regions(self):
        # Norms, all projection/head weights, embedding and RoPE/mask tables.
        # Generation scratch follows gen.state and is deliberately excluded.
        return [(self.io['gf'], 4*self.spec.hidden),
                (self.layer0, self.lookup['gen']['state']-self.layer0)]


@dataclass(frozen=True)
class PoolSpec(q3.Spec):
    pool_bytes: int = 128 << 20

    def image(self, cfg, cap, batch=2, rows=2, wformat='int8', head_format=None,
              lookup=False, embed_host=None, formats=None):
        return PoolImage(self, cfg, cap, batch, rows, wformat, head_format, lookup, embed_host, formats)

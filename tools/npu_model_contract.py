"""Pinned identity for the uncropped M0 checkpoint (not a configurable model family)."""
MODEL_ID='Qwen/Qwen3-0.6B'
REVISION='c1899de289a04d12100db370d81485cdf75e47ca'
WEIGHT_BYTES=1503300328
WEIGHT_SHA256='f47f71177f32bcd101b7573ec9171e6a57f4f4d31148d38e382306f42996874b'
GEOMETRY=dict(model_type='qwen3',num_hidden_layers=28,hidden_size=1024,
              intermediate_size=3072,num_attention_heads=16,num_key_value_heads=8,
              head_dim=128,vocab_size=151936)

def tensor_shapes():
    shapes={'model.embed_tokens.weight':[151936,1024], 'lm_head.weight':[151936,1024],
            'model.norm.weight':[1024]}
    suffixes={'input_layernorm.weight':[1024],'post_attention_layernorm.weight':[1024],
              'self_attn.q_proj.weight':[2048,1024],'self_attn.k_proj.weight':[1024,1024],
              'self_attn.v_proj.weight':[1024,1024],'self_attn.o_proj.weight':[1024,2048],
              'self_attn.q_norm.weight':[128],'self_attn.k_norm.weight':[128],
              'mlp.gate_proj.weight':[3072,1024],'mlp.up_proj.weight':[3072,1024],
              'mlp.down_proj.weight':[1024,3072]}
    for i in range(28):shapes.update({f'model.layers.{i}.{k}':v for k,v in suffixes.items()})
    return shapes

"""Install simulation-only DRAM storage; arithmetic and source checkout unchanged."""
import hashlib
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

def install(rt):
    adjacent=Path(__file__).resolve().parent/'npu_dpi'
    assets=adjacent if adjacent.is_dir() else ROOT/'tb/npu_dpi'
    sv=assets/'otpu_dram_dpi.sv';cpp=assets/'dram_store.cpp'
    key='mem/otpu_dram.sv'
    if rt.RTL_SOURCES.count(key)!=1:raise ValueError('Unexpected upstream DRAM source list')
    rt.RTL_SOURCES=[str(sv) if f==key else f for f in rt.RTL_SOURCES]+[str(cpp)]
    return dict(kind='DPI byte storage with SV latency/write-order wrapper',
                source_sha256={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (sv,cpp)},
                adapter_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                arithmetic_offloaded_to_cpp=False,capacity_reduced=False,
                limits='Simulation only; not physical DDR bandwidth or a synthesizable controller')

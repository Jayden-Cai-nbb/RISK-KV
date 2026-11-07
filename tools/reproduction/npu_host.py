"""Explicit host C++ compilation experiment; frozen RTL and timeouts are unchanged."""
import argparse
import json
from pathlib import Path
import runpy
import subprocess
import sys
from recorded import ROOT, save, sha, utc


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--record',type=Path,required=True)
    p.add_argument('--compile-only',action='store_true')
    p.add_argument('--platform',type=Path)
    p.add_argument('--default-cxx',action='store_true',help='Keep upstream host compiler flags for a version-matched baseline')
    p.add_argument('--sim-threads',type=int,choices=(1,2,4),default=1)
    p.add_argument('arguments',nargs=argparse.REMAINDER)
    a=p.parse_args();out=a.record.resolve();out.mkdir(parents=True,exist_ok=False)
    sys.path[:0]=[str(ROOT/'tools'),str(ROOT/'vendor/openTPU')]
    from opentpu import rtlsim
    if not a.default_cxx:
        rtlsim.VFLAGS.extend(['-CFLAGS','-O3 -march=native -fno-fast-math'])
    if a.sim_threads != 1:
        # DPI byte storage has shared state; keep every imported DPI call serialized.
        rtlsim.VFLAGS.extend(['--threads',str(a.sim_threads),'--threads-dpi','none'])
    rtlsim.VFLAGS[rtlsim.VFLAGS.index('-j')+1]='2'
    record=dict(status='running',started_at=utc(),verilator=rtlsim.verilator_version(),vflags=rtlsim.VFLAGS,
        wrapper_sha256=sha(Path(__file__)),default_cxx=a.default_cxx,sim_threads=a.sim_threads,
        cxx=subprocess.check_output(['g++','--version'],text=True),scope='Host simulator code optimization only; no RTL, model, workload, hardware parameters, arithmetic replacement or timeout changes')
    save(out/'host.json',record)
    try:
        if a.compile_only:
            if not a.platform:p.error('--platform is required for compile-only')
            platform=a.platform.resolve()
            manifest=json.loads((platform/'manifest.json').read_text())
            for rel,digest in manifest['source_sha256'].items():assert sha(ROOT/rel)==digest
            for name,h in manifest['overlay']['control'].items():assert sha(platform/'integration'/name)==h['exported_sha256']
            assert sha(platform/'integration/tb_top.sv')==manifest['overlay']['tb_sha256']
            from opentpu.isasim import Config
            from npu_core_profile import load,simulation_parameters
            from npu_sim_memory import install
            profile,ph=load(ROOT/'configs/npu-vu440-core.json');record['profile_sha256']=ph
            record['memory_adapter']=install(rtlsim)
            rtlsim.RTL_SOURCES=[str(platform/'integration/otpu_top.sv') if x=='top/otpu_top.sv' else x for x in rtlsim.RTL_SOURCES]
            rtlsim.RTL_SOURCES += [str(ROOT/'vendor/picorv32/picorv32.v')]
            rtlsim.RTL_SOURCES += [str(platform/'integration'/name) for name in ('rkv_npu_control.sv','rkv_npu_io_control.sv','rkv_npu_context_cpu.sv')]
            rtlsim.RTL_SOURCES += [str(ROOT/rel) for rel in ('rtl/rkv_context_guard.sv','rtl/rkv_npu_context_service.sv','tb/npu_dpi/observe_logits.cpp','tb/npu_dpi/observe_context.cpp')]
            rtlsim.TB=platform/'integration'
            exe=rtlsim.build_top(Config(**profile['architecture']),8,simulation_parameters(profile),axi=False)
            record.update(status='compiled_not_simulated',executable=str(exe),executable_sha256=sha(exe))
        else:
            args=a.arguments[1:] if a.arguments[:1]==['--'] else a.arguments
            sys.argv=[str(ROOT/'tools/run_npu_context_build.py'),*args]
            runpy.run_path(sys.argv[0],run_name='__main__')
            record['status']='completed'
    except BaseException as ex:
        record.update(status='failed',error=f'{type(ex).__name__}: {ex}');raise
    finally:
        record['finished_at']=utc();save(out/'host.json',record)


if __name__=='__main__':main()

"""Compile whole-page lifecycle firmware and freeze its generated controller ports."""
import argparse
import hashlib
import json
from pathlib import Path
import secrets
import subprocess
from npu_context_integration import export_control

ROOT=Path(__file__).resolve().parents[1]
def sha(p):
    with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--reference',type=Path,required=True);p.add_argument('--toolchain',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True);p.add_argument('--failure',type=int,choices=(0,1,2),default=0);a=p.parse_args()
    ref=a.reference.resolve();r=json.loads((ref/'summary.json').read_text());assert r['status']=='passed_cold_context_isa'
    workload=json.loads((ref/'workload.json').read_text());assert workload['target_tokens']==256 and workload['build_tasks']==64
    for kind in ('build','decode'):assert sha(ref/f'{kind}.bin')==r['programs'][kind]['sha256']
    out=a.output.resolve();out.mkdir(parents=True,exist_ok=False);tc=a.toolchain.resolve()
    # Caller supplies its installed toolchain; compiler --version is recorded below.
    session=secrets.randbits(64) or 1
    config=dict(SESSION_LO=session&0xffffffff,SESSION_HI=session>>32,KV_BASE=r['kv_base'],BUILD_ADDR=r['programs']['build']['address'],
        BUILD_INSNS=r['programs']['build']['instructions'],DECODE_ADDR=r['programs']['decode']['address'],DECODE_INSNS=r['programs']['decode']['instructions'],
        VOCAB=151936,SEED0=workload['seed_tokens'][0],SEED1=workload['seed_tokens'][1],MAX_DECODE=3,EOS0=151645,EOS1=151643,EXPECT_FAILURE=a.failure)
    (out/'npu_context_config.h').write_text('\n'.join(f'#define {k} {v}u' for k,v in config.items())+'\n')
    overlay=export_control(out/'control',kv_base=r['kv_base'],result_address=r['result_address'],build_insns=config['BUILD_INSNS'],decode_insns=config['DECODE_INSNS'])
    def exe(n):return tc/'bin'/('riscv-none-elf-'+n+('.exe' if __import__('os').name=='nt' else ''))
    def run(command,log):
        x=subprocess.run([str(y) for y in command],cwd=out,capture_output=True,text=True,timeout=120);(out/log).write_text(x.stdout+'\n'+x.stderr)
        if x.returncode:raise RuntimeError(log)
    run([exe('gcc'),'--version'],'compiler-version.log')
    run([exe('gcc'),'-march=rv32i','-mabi=ilp32','-Os','-ffreestanding','-fno-builtin','-nostdlib','-msmall-data-limit=0','-mno-relax',
        '-Wall','-Wextra','-Werror','-Wl,--no-relax','-Wl,-Map=firmware.map','-I',out,'-T',ROOT/'firmware/link.ld',
        ROOT/'firmware/start.S',ROOT/'firmware/npu_context_build.c','-o','firmware.elf'],'compile.log')
    run([exe('objcopy'),'-O','binary','firmware.elf','firmware.bin'],'objcopy.log');run([exe('objdump'),'-d','firmware.elf'],'disassembly.txt')
    code=(out/'firmware.bin').read_bytes();assert len(code)<61440;rom=code.ljust(65536,b'\0')
    (out/'firmware.hex').write_text(''.join(f'{int.from_bytes(rom[i:i+4],"little"):08x}\n' for i in range(0,65536,4)))
    source={}
    paths=('firmware/npu_context_build.c','firmware/start.S','firmware/link.ld','rtl/rkv_context_guard.sv','rtl/rkv_npu_context_service.sv',
           'rtl/rkv_npu_control.sv','rtl/rkv_npu_io_control.sv','rtl/rkv_npu_context_cpu.sv','tools/npu_context_integration.py','tools/prepare_npu_context_firmware.py',
           'vendor/picorv32/picorv32.v','vendor/picorv32/COPYING')
    for rel in paths:
        f=ROOT/rel;dest=out/'sources'/rel;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(f.read_bytes());source[rel]=sha(f)
    m=dict(status='context_firmware_prepared',configuration=config,session=session,firmware_bytes=len(code),firmware_sha256=sha(out/'firmware.bin'),
        firmware_hex_sha256=sha(out/'firmware.hex'),reference_sha256=sha(ref/'summary.json'),overlay=overlay,source_sha256=source,
        scope='Full 256-token page, actual build acknowledgements, hardware seal/bind gate, no KV payload or future token table in firmware')
    (out/'manifest.json').write_text(json.dumps(m,indent=2)+'\n');print(json.dumps({k:v for k,v in m.items() if k not in ('source_sha256','overlay')}))

if __name__=='__main__':main()

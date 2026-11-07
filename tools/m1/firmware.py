"""Compile isolated-test or host-mailbox RV32I firmware for the M1 ABI."""
import argparse
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/reproduction'))
from recorded import run, save, sha


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--toolchain', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--mode', choices=['mailbox', 'autorun'], default='mailbox')
    p.add_argument('--build-tasks', type=int, choices=[1, 64], default=64)
    p.add_argument('--second-seeds', type=int, nargs=2, default=[3555, 8429])
    a = p.parse_args()
    if a.mode == 'mailbox' and a.build_tasks != 64:
        p.error('build-tasks is an isolated-test setting only')
    assert all(0 <= token < 151936 for token in a.second_seeds)
    out = a.output.absolute(); out.mkdir(parents=True, exist_ok=False)
    tc = a.toolchain.absolute() / 'bin/riscv-none-elf-'
    exe = lambda name: str(tc) + name
    sources = [ROOT / f for f in ['firmware/start.S', 'firmware/m1/link.ld', 'firmware/m1/layout.h',
                                 'firmware/m1/service.c', 'configs/m1/layout.json', 'tools/m1/firmware.py']]
    for src in sources:
        dst = out / 'sources' / src.relative_to(ROOT)
        dst.parent.mkdir(parents=True, exist_ok=True); shutil.copy2(src, dst)
    manifest = dict(status='running', mode=a.mode, build_tasks=a.build_tasks, second_seeds=a.second_seeds,
                    inputs={str(f.relative_to(ROOT)): sha(f) for f in sources})
    save(out / 'manifest.json', manifest)
    try:
        assert run(out / 'compiler', [exe('gcc'), '--version']) == 0
        command = [exe('gcc'), '-march=rv32i', '-mabi=ilp32', '-Os', '-ffreestanding', '-fno-builtin',
                   '-nostdlib', '-msmall-data-limit=0', '-mno-relax', '-Wall', '-Wextra',
                   '-DM1_AUTORUN=' + str(int(a.mode == 'autorun')), '-DM1_BUILD_TASKS=' + str(a.build_tasks),
                   '-DM1_SEED20=' + str(a.second_seeds[0]), '-DM1_SEED21=' + str(a.second_seeds[1]),
                   '-T', ROOT / 'firmware/m1/link.ld', '-o', out / 'firmware.elf',
                   ROOT / 'firmware/start.S', ROOT / 'firmware/m1/service.c']
        assert run(out / 'compile', command, inputs=sources) == 0
        assert run(out / 'binary', [exe('objcopy'), '-O', 'binary', out / 'firmware.elf', out / 'firmware.bin']) == 0
        assert run(out / 'disassembly', [exe('objdump'), '-d', out / 'firmware.elf']) == 0
        raw = (out / 'firmware.bin').read_bytes(); assert len(raw) < 0xd000
        rom = raw + bytes(65536-len(raw))
        (out / 'firmware.hex').write_text(''.join(f'{int.from_bytes(rom[i:i+4], "little"):08x}\n' for i in range(0,65536,4)))
        manifest.update(status='compiled_not_executed', bytes=len(raw), hex_sha256=sha(out / 'firmware.hex'),
                        deployment='isolated simulation only' if a.mode == 'autorun' else 'platform binding required; fresh host session at BOOT')
    except BaseException as exc:
        manifest.update(status='failed', error=f'{type(exc).__name__}: {exc}')
        raise
    finally:
        save(out / 'manifest.json', manifest)
        print(json.dumps(manifest))


if __name__ == '__main__':
    main()

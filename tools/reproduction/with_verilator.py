"""Run one command with an isolated, explicitly version-checked Verilator installation."""
import argparse
import os
from pathlib import Path
import subprocess


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--prefix', type=Path, required=True)
    p.add_argument('command', nargs=argparse.REMAINDER)
    a = p.parse_args()
    command = a.command[1:] if a.command[:1] == ['--'] else a.command
    if not command: p.error('Command required after --')
    prefix = a.prefix.resolve()
    env = os.environ.copy()
    env['PATH'] = str(prefix / 'bin') + os.pathsep + env['PATH']
    env['VERILATOR_ROOT'] = str(prefix / 'share/verilator')
    # Official image's make defaults to ccache, which is optional and absent here.
    env['OBJCACHE'] = ''
    version = subprocess.check_output([str(prefix / 'bin/verilator'), '--version'], env=env, text=True).strip()
    if version != 'Verilator 5.032 2025-01-01 rev v5.032':
        raise RuntimeError('Unexpected Verilator identity: ' + version)
    print('Isolated tool: ' + version + '; OBJCACHE disabled (direct host compiler)', flush=True)
    os.execvpe(command[0], command, env)


if __name__ == '__main__': main()

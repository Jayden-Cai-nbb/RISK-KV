"""Portable entry point for WSL/Linux; no inference libraries needed for RTL replay."""
import argparse
from pathlib import Path
import subprocess
import sys
import shutil

ROOT=Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('case',choices=['unit','cancel','fault','positive'])
    p.add_argument('--output',type=Path);a=p.parse_args()
    if sys.platform=='win32':raise SystemExit('Run this entry point inside WSL/Linux. See docs/02-reproduce.md.')
    if any(c.isspace() for c in str(ROOT)):raise SystemExit('Use an ASCII path without spaces for the upstream Verilator/Make build.')
    for tool in ('verilator','make','g++','git'):
        if not shutil.which(tool):raise SystemExit('Missing tool: '+tool)
    if a.case=='unit':
        subprocess.run([sys.executable,str(ROOT/'tools/unit_checks.py')],check=True,cwd=ROOT);return
    out=(a.output or ROOT/'build'/('replay-'+a.case)).resolve()
    subprocess.run([sys.executable,str(ROOT/'tools/run_npu_context_build.py'),
        '--source',str(ROOT/'vendor/openTPU'),'--reference',str(ROOT/'assets/reference'),
        '--firmware',str(ROOT/'assets/firmware'/a.case),'--platform',str(ROOT/'build/platform'),
        '--output',str(out)],check=True,cwd=ROOT)

if __name__=='__main__':main()

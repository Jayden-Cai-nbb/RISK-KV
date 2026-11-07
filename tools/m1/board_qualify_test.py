"""Actual Tcl qualification/recovery entry tested against a fake tool, including destructive-action guards."""
import argparse,json,subprocess,struct,hashlib,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--tclsh',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
 script=ROOT/'platform/m1/prodigy/board_qualify.tcl';mock=ROOT/'tb/m1/board_qualify_mock.tcl'
 addrs=[0,64,4032,4096,4160,65536,1048576,1073741824,2147483584];refs={}
 for addr in addrs:
  words=[]
  for i in range(16):
   x=addr^0x13579bdf^54^((0x9e3779b9*i)&0xffffffff);x=(x^(x<<13))&0xffffffff;x^=x>>17;x=(x^(x<<5))&0xffffffff;words.append(x)
  refs[addr]=int.from_bytes(struct.pack('<16I',*words),'little')
 rows=[]
 for name,board,service,status,policy,error in (
  ('qualification',0,0,233,'qualification',None),
  ('full-cold-after-loss',1,1,16,'explicit_full_chain_reset',None),
  ('reject-implicit-service-restart',1,1,233,'qualification','Previous board already in service/fault'),
  ('reject-unidentified-recovery',0,0,233,'explicit_full_chain_reset','Cold recovery requires identified full board')):
  out=a.output/name;out.mkdir();shutil.copy2(script,out/'board_qualify.tcl')
  expected='set expected {'+' '.join(f'{addr} {v}' for addr,v in refs.items())+'}\n';(out/'vio_access.tcl').write_text(expected+mock.read_text())
  (out/'run.tcl').write_text(f'set PREVIOUS_BOARD {board}\nset PREVIOUS_SERVICE {service}\nset PREVIOUS_STATUS {status}\nset argc 10\nset argv {{mock.bit mock.ltx old.ltx 0x44445251 0 33554432 0 324508639 1 {policy}}}\nsource board_qualify.tcl\n')
  r=subprocess.run([str(a.tclsh),'run.tcl'],cwd=out,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=30);(out/'stdout.log').write_text(r.stdout)
  if error:
   assert r.returncode!=0 and error in r.stdout and not (out/'programmed-marker.txt').exists(),r.stdout
  else:
   assert r.returncode==0 and 'MOCK_PASS_NO_HARDWARE' in r.stdout,r.stdout
   assert (out/'service-handover.tsv').is_file()
   for row in (out/'host-peeks.tsv').read_text().splitlines()[1:]:
    idx,addr,rd,seed=map(int,row.split('\t'));assert (out/f'peek-{idx:03}.bin').read_bytes()==refs[addr].to_bytes(64,'little')
  rows.append(dict(name=name,status='passed',programmed_mock=not bool(error)))
 result=dict(status='passed',scope=__doc__,cases=rows,script_sha256=hashlib.sha256(script.read_bytes()).hexdigest(),mock_sha256=hashlib.sha256(mock.read_bytes()).hexdigest());(a.output/'summary.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
if __name__=='__main__':main()

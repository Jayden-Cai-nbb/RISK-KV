"""Verify the curated source release and its linked evidence. No hardware access."""
import argparse,ast,hashlib,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for chunk in iter(lambda:f.read(1<<20),b''):h.update(chunk)
 return h.hexdigest()
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--source-check',action='store_true',help='Check development source structure without enforcing the original snapshot hashes');a=p.parse_args()
 manifest=json.loads((ROOT/'publication/manifest.json').read_text());errors=[]
 for name,entry in manifest['files'].items():
  f=ROOT/name
  if not f.is_file():errors.append('missing '+name)
  elif not a.source_check and sha(f)!=entry['sha256']:errors.append('changed '+name)
 for f in (ROOT/'tools').rglob('*.py'):
  try:ast.parse(f.read_text(),filename=str(f))
  except (ValueError,SyntaxError) as e:errors.append(str(e))
 for f in [*ROOT.glob('rtl/**/*.f'),*ROOT.glob('platform/**/*.f')]:
  for line in f.read_text().splitlines():
   line=line.strip()
   if line and not line.startswith(('#','+','-')) and not (ROOT/line).is_file():errors.append('filelist '+str(f.relative_to(ROOT))+': '+line)
 docs=[*ROOT.glob('*.md'),*ROOT.glob('docs/**/*.md'),ROOT/'evidence/README.md']
 for f in docs:
  for target in re.findall(r'\]\(([^)]+)\)',f.read_text()):
   if target.startswith(('https:','http:','#','mailto:')):continue
   target=target.split('#')[0]
   if target and not (f.parent/target).exists():errors.append('link '+str(f.relative_to(ROOT))+': '+target)
 ev=json.loads((ROOT/'evidence/manifest.json').read_text())
 for row in ev['records']:
  f=ROOT/row['path']
  if not f.exists() or sha(f)!=row['published_sha256']:errors.append('evidence '+row['path'])
 figures=json.loads((ROOT/'docs/figures/sources.json').read_text())
 for name,digest in figures['sources'].items():
  if not (ROOT/name).exists() or sha(ROOT/name)!=digest:errors.append('figure source '+name)
 report=dict(status='passed' if not errors else 'failed',files=len(manifest['files']),evidence_files=len(ev['records']),errors=errors,scope='publication integrity, Python syntax, RTL file lists, documentation links, evidence and figure source identity')
 print(json.dumps(report,ensure_ascii=False,indent=2));raise SystemExit(bool(errors))
if __name__=='__main__':main()

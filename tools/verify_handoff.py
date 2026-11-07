"""Check the release file hashes without importing inference or HDL tools."""
import argparse
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--data',action='store_true');a=p.parse_args()
    manifest=json.loads((ROOT/'MANIFEST.json').read_text(encoding='utf-8'))
    checked=0;errors=[];skipped=0
    for rel,record in manifest['files'].items():
        if record['package']=='data' and not a.data:skipped+=1;continue
        path=ROOT/rel
        if not path.is_file():errors.append(dict(path=rel,error='missing'));continue
        if path.stat().st_size!=record['bytes']:errors.append(dict(path=rel,error='size'));continue
        with path.open('rb') as f:actual=hashlib.file_digest(f,'sha256').hexdigest()
        if actual!=record['sha256']:errors.append(dict(path=rel,error='sha256'));continue
        checked+=1
    report=dict(status='passed' if not errors else 'failed',checked=checked,skipped_data_files=skipped,errors=errors)
    print(json.dumps(report,indent=2))
    if errors:raise SystemExit(1)

if __name__=='__main__':main()

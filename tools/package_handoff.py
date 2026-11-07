"""Create split, verified ZIP64 archives; never delete the source project."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

ROOT=Path(__file__).resolve().parents[1]

def sha(path):
    with path.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()

def files():
    for p in sorted(ROOT.rglob('*')):
        if not p.is_file():continue
        rel=p.relative_to(ROOT)
        if rel.parts[0]=='build' or any(x in ('__pycache__','.venv-replay','.venv-reference') for x in rel.parts):continue
        if rel.parts[:3] in (('vendor','openTPU','build'),('vendor','picorv32','build')):continue
        if p.name=='MANIFEST.json' and len(rel.parts)==1:continue
        if '.git' in rel.parts and (p.name in ('index','COMMIT_EDITMSG','FETCH_HEAD','ORIG_HEAD') or 'logs' in rel.parts or p.suffix=='.lock'):continue
        if '.Xil' in rel.parts or p.suffix in ('.pyc','.jou'):continue
        yield p,rel.as_posix()

def verify_archive(path,entries):
    with zipfile.ZipFile(path) as z:
        assert len(z.namelist())==len(set(z.namelist()))==len(entries)
        for name,record in entries.items():
            with z.open(name) as f:actual=hashlib.file_digest(f,'sha256').hexdigest()
            assert actual==record['sha256'],name

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--tool-file',type=Path,action='append',default=[])
    a=parser.parse_args();out=a.output.resolve()
    if out==ROOT or ROOT in out.parents:raise ValueError('Archive destination must be outside the project')
    out.mkdir(parents=True,exist_ok=False)
    records={}
    for p,rel in files():
        records[rel]=dict(bytes=p.stat().st_size,sha256=sha(p),package='data' if rel.startswith(('assets/data/','models/')) else 'code')
    manifest=dict(schema='risc-kv-handoff-1',baseline_date='2026-11-03',files=records,
        excludes='Build caches, environments, mutable Git index/reflogs; source history remains in vendor/.git')
    (ROOT/'MANIFEST.json').write_text(json.dumps(manifest,ensure_ascii=True,indent=2)+'\n',encoding='utf-8',newline='\n')
    archives=[]
    for group in ('code','data'):
        selected={rel:r for rel,r in records.items() if r['package']==group}
        if group=='code':selected['MANIFEST.json']=dict(bytes=(ROOT/'MANIFEST.json').stat().st_size,sha256=sha(ROOT/'MANIFEST.json'))
        dest=out/f'RISC-KV-{group}-20261103.zip';entries={}
        with zipfile.ZipFile(dest,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=3,allowZip64=True) as z:
            for rel,record in selected.items():
                name='RISC-KV-current/'+rel;z.write(ROOT/rel,name);entries[name]=record
        verify_archive(dest,entries)
        result=dict(file=dest.name,bytes=dest.stat().st_size,sha256=sha(dest),files=len(entries),uncompressed_bytes=sum(x['bytes'] for x in entries.values()),verified=True)
        archives.append(result);print(json.dumps(result),flush=True)
    if a.tool_file:
        dest=out/'RISC-KV-tools-optional-20261103.zip';entries={}
        with zipfile.ZipFile(dest,'x',compression=zipfile.ZIP_STORED,allowZip64=True) as z:
            for p in a.tool_file:
                name='tool-installers/'+p.name
                if name in entries:raise ValueError('Duplicate installer name')
                z.write(p,name);entries[name]=dict(bytes=p.stat().st_size,sha256=sha(p))
        verify_archive(dest,entries)
        archives.append(dict(file=dest.name,bytes=dest.stat().st_size,sha256=sha(dest),files=len(entries),verified=True))
    report=dict(status='passed_archive_hash_verification',archives=archives,
        project_bytes=sum(r['bytes'] for r in records.values()),project_files=len(records),source_project_deleted=False)
    (out/'TRANSFER.json').write_text(json.dumps(report,indent=2)+'\n')
    (out/'SHA256SUMS.txt').write_text(''.join(r['sha256']+'  '+r['file']+'\n' for r in archives))
    print(json.dumps(report),flush=True)

if __name__=='__main__':main()

"""Fetch public official Verilator image metadata and optionally its installation layer.

No daemon, container execution, system installation, or registry login is used.
"""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import tarfile
import urllib.request


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--extract', action='store_true')
    a = p.parse_args()
    out = a.output.resolve(); out.mkdir(parents=True, exist_ok=True)
    token = json.load(urllib.request.urlopen(
        'https://auth.docker.io/token?service=registry.docker.io&scope=repository:verilator/verilator:pull', timeout=30))['token']
    headers = {'Authorization': 'Bearer ' + token,
        'Accept': 'application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json'}
    def request(part, extra=None):
        return urllib.request.urlopen(urllib.request.Request(
            'https://registry-1.docker.io/v2/verilator/verilator/' + part, headers={**headers, **(extra or {})}), timeout=60)
    def get(part, name):
        with request(part) as response:
            raw = response.read()
        (out / name).write_bytes(raw)
        return json.loads(raw)
    index = get('manifests/v5.032', 'index.json')
    ref = next(x['digest'] for x in index['manifests'] if x['platform']['architecture'] == 'amd64' and x['platform']['os'] == 'linux')
    manifest = get('manifests/' + ref, 'manifest.json')
    assert 'sha256:' + hashlib.sha256((out / 'manifest.json').read_bytes()).hexdigest() == ref
    config = get('blobs/' + manifest['config']['digest'], 'config.json')
    history = [x for x in config['history'] if not x.get('empty_layer')]
    assert len(history) == len(manifest['layers'])
    metadata = dict(image='verilator/verilator:v5.032', digest=ref,
                    layers=[dict(**layer, history=h) for layer,h in zip(manifest['layers'],history)])
    (out / 'provenance.json').write_text(json.dumps(metadata, indent=2)+'\n')
    print(json.dumps(metadata, indent=2), flush=True)
    if not a.extract:
        return
    selected = [x for x in metadata['layers'] if 'git clone' in x['history'].get('created_by','')]
    assert len(selected) == 1
    layer = selected[0]; blob = out / 'installation-layer.tar.gz'
    for attempt in range(3):
        offset = blob.stat().st_size if blob.exists() else 0
        if offset == layer['size']:
            break
        assert offset < layer['size']
        extra = {'Range': f'bytes={offset}-'} if offset else {}
        with request('blobs/' + layer['digest'], extra) as source:
            if offset and source.status == 206:
                assert source.headers['Content-Range'].startswith(f'bytes {offset}-')
                mode = 'ab'
            else:
                assert source.status == 200
                mode = 'wb'
            print(json.dumps(dict(attempt=attempt, offset=offset, http_status=source.status,
                                  content_length=source.headers.get('Content-Length'), mode=mode)), flush=True)
            with blob.open(mode) as dest:
                shutil.copyfileobj(source, dest, 4 << 20)
    assert blob.stat().st_size == layer['size'], 'Incomplete download; no files extracted'
    h = hashlib.sha256()
    with blob.open('rb') as stream:
        while data := stream.read(4 << 20): h.update(data)
    assert 'sha256:' + h.hexdigest() == layer['digest']
    files = []
    with tarfile.open(blob) as tar:
        for entry in tar:
            path = PurePosixPath(entry.name)
            if path.is_absolute() or '..' in path.parts:
                raise ValueError('Unsafe archive path')
            if not entry.isfile() or not (entry.name.startswith('usr/local/share/verilator/') or
                                           entry.name.startswith('usr/local/bin/verilator')):
                continue
            target = out / 'root' / entry.name
            target.parent.mkdir(parents=True, exist_ok=True)
            with tar.extractfile(entry) as src, target.open('wb') as dest: shutil.copyfileobj(src, dest)
            target.chmod(entry.mode & 0o777)
            files.append(dict(path=entry.name, bytes=entry.size))
    (out / 'extracted.json').write_text(json.dumps(dict(layer_sha256=h.hexdigest(), files=files),indent=2)+'\n')


if __name__ == '__main__': main()

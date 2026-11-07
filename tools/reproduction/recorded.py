"""Record an explicit command without changing the frozen handoff tools."""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import signal
import shutil
import subprocess
import threading
import time

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def utc():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def save(path, value):
    path = Path(path)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    temporary.replace(path)


def snapshot_tooling(output):
    """Keep the exact new orchestration files present when a suite starts."""
    output = Path(output) / 'orchestration-sources'
    output.mkdir(exist_ok=False)
    hashes = {}
    for source in sorted(Path(__file__).parent.iterdir()):
        if source.is_file() and source.suffix in ('.py', '.txt'):
            shutil.copy2(source, output / source.name)
            hashes[source.name] = sha(source)
    save(output / 'manifest.json', hashes)
    return hashes


def run(output, command, timeout=25200, inputs=()):
    output = Path(output).resolve()
    output.mkdir(parents=True, exist_ok=False)
    command = [str(v) for v in command]
    record = dict(status='running', command=command, cwd=str(ROOT),
                  started_at=utc(), timeout_seconds=timeout,
                  inputs={str(p): sha(p) for p in inputs},
                  environment={k: os.environ[k] for k in
                      ('PYTHONPATH', 'OMP_NUM_THREADS', 'OPENBLAS_NUM_THREADS',
                       'HF_HUB_OFFLINE', 'OTPU_IMAGE_CACHE', 'OTPU_PROG_CACHE')
                      if k in os.environ},
                  resource_scope='GNU time maximum RSS of a process; not summed concurrent tree RSS')
    save(output / 'command.json', record)
    started = time.monotonic()
    proc = None
    sampler_stop = threading.Event()
    sampler = None
    sampled = dict(interval_seconds=2, samples=0, peak_summed_rss_kib=0,
                   peak_individual_hwm_kib=0,
                   limits='Sampled descendant RSS sum can double-count shared pages; not exact physical memory. HWM is per-process. Samples survive a command timeout.')

    def sample_resources():
        try:
            with (output / 'resource-samples.jsonl').open('w') as stream:
                while True:
                    processes = {}
                    for entry in Path('/proc').iterdir():
                        if not entry.name.isdigit():
                            continue
                        try:
                            fields = {line.split(':', 1)[0]: line.split(':', 1)[1].strip()
                                      for line in (entry / 'status').read_text().splitlines() if ':' in line}
                            processes[int(entry.name)] = (int(fields['PPid']),
                                int(fields.get('VmRSS', '0 kB').split()[0]), int(fields.get('VmHWM', '0 kB').split()[0]))
                        except (OSError, ValueError, KeyError):
                            continue
                    descendants = {proc.pid}
                    while True:
                        added = {pid for pid, values in processes.items() if values[0] in descendants}
                        if added <= descendants:
                            break
                        descendants |= added
                    values = [v for pid,v in processes.items() if pid in descendants]
                    rss = sum(v[1] for v in values)
                    hwm = max((v[2] for v in values), default=0)
                    sampled['samples'] += 1
                    sampled['peak_summed_rss_kib'] = max(sampled['peak_summed_rss_kib'], rss)
                    sampled['peak_individual_hwm_kib'] = max(sampled['peak_individual_hwm_kib'], hwm)
                    stream.write(json.dumps(dict(elapsed_seconds=time.monotonic()-started, processes=len(values),
                                                 summed_rss_kib=rss, max_individual_hwm_kib=hwm))+'\n')
                    stream.flush()
                    if sampler_stop.wait(2):
                        break
        except Exception as ex:
            sampled['error'] = f'{type(ex).__name__}: {ex}'

    try:
        with (output / 'stdout.log').open('w') as stream:
            proc = subprocess.Popen(
                ['/usr/bin/time', '-v', '-o', str(output / 'resources.txt'), *command],
                cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
            record['pid'] = proc.pid
            save(output / 'command.json', record)
            sampler = threading.Thread(target=sample_resources, daemon=True)
            sampler.start()
            try:
                rc = proc.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGTERM)
                try:
                    proc.wait(timeout=25)
                except subprocess.TimeoutExpired:
                    os.killpg(proc.pid, signal.SIGKILL)
                    proc.wait()
                raise TimeoutError('Recorded command timed out; inspect preserved output')
        record.update(status='completed' if rc == 0 else 'failed', returncode=rc)
        if any(sha(p) != digest for p, digest in record['inputs'].items()):
            record.update(status='invalidated', error='Declared input changed while command ran')
            rc = 1
    except BaseException as ex:
        if proc is not None and proc.poll() is None:
            os.killpg(proc.pid, signal.SIGTERM)
            proc.wait(timeout=25)
        record.update(status='failed', error=f'{type(ex).__name__}: {ex}')
        raise
    finally:
        sampler_stop.set()
        if sampler is not None:
            sampler.join(timeout=5)
        record['sampled_resources'] = sampled
        record.update(finished_at=utc(), wall_seconds=time.monotonic() - started)
        for name in ('stdout.log', 'resources.txt'):
            p = output / name
            if p.exists():
                record[name + '_sha256'] = sha(p)
        save(output / 'command.json', record)
    print(json.dumps(dict(output=str(output), status=record['status'], returncode=rc)), flush=True)
    return rc


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--timeout', type=int, default=25200)
    parser.add_argument('--input', type=Path, action='append', default=[])
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    argv = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not argv:
        parser.error('A command after -- is required')
    raise SystemExit(run(args.output, argv, args.timeout, args.input))

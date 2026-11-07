"""Extract task intervals and native requested bytes; never infer DDR utilization."""
import argparse
import json
from pathlib import Path
import re
from recorded import save, sha


def measure(directory):
    directory = Path(directory)
    summary = json.loads((directory / 'summary.json').read_text())
    logs = [p for p in directory.glob('*.log') if 'CTX_LAUNCH' in p.read_text(errors='replace')]
    assert len(logs) == 1, logs
    pending, tasks = {}, []
    for line in logs[0].read_text().splitlines():
        if line.startswith('CTX_LAUNCH '):
            fields = dict(re.findall(r'(\w+)=(\w+)', line))
            seq = int(fields['seq'], 16)
            assert seq not in pending
            pending[seq] = dict(sequence=seq, program=fields['program'], start=int(fields['cycle']))
        elif line.startswith('CTX_COMPLETE '):
            fields = dict(re.findall(r'(\w+)=(\w+)', line))
            item = pending.pop(int(fields['seq'], 16))
            item.update(end=int(fields['cycle']), status=int(fields['status']))
            item['cycles'] = item['end'] - item['start']
            tasks.append(item)
    assert not pending, pending
    assert len(tasks) == summary['accepted']
    total = summary['total_control_cycles']
    inside = sum(x['cycles'] for x in tasks)
    phases = {}
    for name, program in [('build', '60000000'), ('decode', '60010000')]:
        values = [x['cycles'] for x in tasks if x['program'] == program]
        phases[name] = dict(tasks=len(values), sum_cycles=sum(values), min_cycles=min(values, default=None), max_cycles=max(values, default=None))
    traffic = summary['traffic_native_requested_bytes']
    return dict(source=str(directory), summary_sha256=sha(directory / 'summary.json'), log_sha256=sha(logs[0]),
        status=summary['status'], total_cycles=total, task_interval_cycles=inside, outside_task_cycles=total-inside,
        outside_task_percent=100*(total-inside)/total, phases=phases, tasks=tasks, traffic_native_requested_bytes=traffic,
        prefix_read_fraction_of_weight_plus_prefix={p: traffic[p+'_prefix_reads'] / (traffic[p+'_prefix_reads']+traffic[p+'_weight_reads'])
            if traffic[p+'_prefix_reads']+traffic[p+'_weight_reads'] else None for p in ('build', 'decode')},
        limits=['Intervals include compute, NPU control and memory stalls; not isolated arithmetic time.',
                'Outside includes boot, MMIO, program loading and completion handling; not solely RISC-V compute.',
                'Requested bytes are SV observer counts; not AXI beats, physical DDR traffic or utilization.',
                'No causal compute-vs-weight-vs-KV stall partition is present in the frozen instrumentation.'])


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--directory', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    a.output.parent.mkdir(parents=True, exist_ok=True)
    save(a.output, measure(a.directory))

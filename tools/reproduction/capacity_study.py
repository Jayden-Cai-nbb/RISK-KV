"""Synthetic pair-job replay with fixed measured NPU costs and explicit cleanup costs.

Every job is the existing two-query, three-step workload. Larger arithmetic batches,
variable context lengths and real arrival distributions are not modeled.
"""
import argparse
from collections import Counter, OrderedDict
import json
import math
from pathlib import Path
import random
from recorded import save, sha


def percentile(values, q):
    return sorted(values)[max(0, math.ceil(len(values)*q)-1)]


def simulate(jobs, policy, capacity, build, decode, prefix, tails, bandwidth, management, window=0):
    clock=0; cache=OrderedDict(); hits=0; cleaning=0; waits=[];latencies=[];events=[]
    pending=list(jobs);order=[]
    if policy=='static_batch':
        # Tune the waiting window separately. Same-document jobs within a window
        # run consecutively; width remains exactly two queries, not an invented
        # wider datapath. The group retains only its current prefix.
        while pending:
            edge=pending[0]['arrival']+window; group=[]
            while pending and pending[0]['arrival']<=edge:group.append(pending.pop(0))
            group.sort(key=lambda x:(x['document'],x['arrival']))
            order.extend((job,edge) for job in group)
    else:order=[(j,j['arrival']) for j in jobs]
    pinned=set(k for k,_ in Counter(j['document'] for j in jobs).most_common(max(0,capacity-1)))
    # Static oracle reserves one scratch slot for misses; counts that capacity.
    for job,ready in order:
        doc=job['document'];clock=max(clock,ready);start=clock
        hit=doc in cache and policy!='rebuild'
        if hit:hits+=1
        clear=tails
        if not hit:
            clear+=prefix
            if policy in ('rebuild','static_batch'):cache.clear()
            elif policy=='static_pinned':
                # Keep the most recent non-pinned prefix in the reserved scratch
                # slot. Discarding it immediately would weaken this comparator.
                if doc not in pinned:
                    for previous in list(cache):
                        if previous not in pinned:
                            del cache[previous]
                assert len(cache)<capacity
            elif len(cache)>=capacity:cache.popitem(last=False)
            cache[doc]=True
        elif doc in cache:cache.move_to_end(doc)
        clear_cycles=math.ceil(clear/bandwidth)
        duration=(0 if hit else build)+decode+management+clear_cycles
        clock+=duration;cleaning+=clear;waits.append(start-job['arrival']);latencies.append(clock-job['arrival'])
        events.append(dict(id=job['id'],document=doc,hit=hit,start=start,finish=clock,cleanup_bytes=clear,cleanup_cycles=clear_cycles))
    return dict(policy=policy,capacity=capacity,window_cycles=window,hits=hits,jobs=len(jobs),makespan_cycles=clock-jobs[0]['arrival'],
        cleanup_bytes=cleaning,mean_latency_cycles=sum(latencies)/len(latencies),p95_latency_cycles=percentile(latencies,.95),
        mean_wait_cycles=sum(waits)/len(waits),events=events)


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--metrics',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    m=json.loads(a.metrics.read_text());build=m['phases']['build']['sum_cycles'];decode=m['phases']['decode']['sum_cycles']
    assert m['phases']['build']['tasks']==64 and m['phases']['decode']['tasks']==3
    # Use the entire measured outside interval as per-job management charge,
    # including on hits. This is conservative but not a measured warm service.
    management=m['outside_task_cycles'];prefix=15138816;tails=2*prefix
    service=build+decode+management;rng=random.Random(20261103)
    traces={
        'same_document':[0]*32,
        'no_reuse':list(range(32)),
        'capacity_thrash':[i%8 for i in range(64)],
        'mixed_hot':[0 if rng.random()<.75 else rng.randrange(1,8) for _ in range(64)]}
    records=[]
    for name,documents in traces.items():
        for gap in (0,service//2,service*2):
            jobs=[dict(id=i,document=d,arrival=i*gap) for i,d in enumerate(documents)]
            save(a.output/f'trace-{name}-{gap}.json',dict(source='synthetic deterministic pair-job arrivals, no user data',jobs=jobs))
            for capacity in (1,2,5):
                for bandwidth in (1,8,32):
                    runs=[simulate(jobs,policy,capacity,build,decode,prefix,tails,bandwidth,management)
                        for policy in ('rebuild','lru','static_pinned')]
                    candidates=[simulate(jobs,'static_batch',1,build,decode,prefix,tails,bandwidth,management,w)
                        for w in (0,service//4,service,4*service)]
                    # Report the best p95 with the full sweep saved; no favorable
                    # result hidden by selecting only throughput.
                    best=min(candidates,key=lambda x:x['p95_latency_cycles'])
                    row=dict(trace=name,arrival_gap_cycles=gap,capacity_prefixes=capacity,assumed_cleanup_bytes_per_cycle=bandwidth,
                        runs=runs,static_batch_sweep=candidates,best_static_batch_p95_window=best['window_cycles'])
                    records.append(row)
    save(a.output/'summary.json',dict(status='completed_analytical_replay',source_metrics=str(a.metrics),metrics_sha256=sha(a.metrics),
        baseline_status=m['status'],build_cycles=build,decode_cycles=decode,management_charge_cycles=management,
        pool_bytes=256<<20,prefix_bytes=prefix,private_pair_bytes=tails,
        fixed_complete_objects=(256<<20)//(prefix+tails),prefixes_with_one_private_pair=((256<<20)-tails)//prefix,
        results=records,limits=['Not RTL or board measurements; current hardware cannot rebind or allocate several objects.',
            'Assumed cleanup bandwidth 1/8/32 bytes per control cycle; not measured DDR bandwidth.',
            'Full cleanup charged each job; no unproven scale-only cleanup benefit included.',
            'Static batching tunes a waiting/grouping window at fixed pair width; larger tuned compute batches remain unmeasured.',
            'Oracle static pinning knows the document frequencies of the entire trace; a strong comparison, not an implementable prediction.',
            'All costs apply only to frozen 256-token prefix plus three decode steps; no QA quality or long-context performance claim.']))


if __name__=='__main__':main()

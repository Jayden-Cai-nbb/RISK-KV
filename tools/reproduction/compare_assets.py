"""Compare rebuilt bytes and separately validate the known provenance relocation."""
import argparse
import json
from pathlib import Path
from recorded import ROOT, save, sha
from source_suite import equal_files


def compare(reference, image):
    old = ROOT / 'assets/reference'
    names = ['build.bin', 'decode.bin', 'source-document.md', 'reference-prefix.bin',
             'candidate-prefix.bin', *[f'{kind}-logits-{i}.npy'
             for kind in ('native', 'candidate') for i in range(3)]]
    files = {}
    for name in names:
        files[name] = dict(new_sha256=sha(reference/name), original_sha256=sha(old/name),
                           byte_equal=equal_files(reference/name, old/name))
    files['dram-input.bin'] = dict(new_sha256=sha(image),
        original_sha256=sha(ROOT/'assets/data/dram-input.bin'),
        byte_equal=equal_files(image, ROOT/'assets/data/dram-input.bin'))
    workloads = [json.loads((p/'workload.json').read_text()) for p in (old, reference)]
    summaries = [json.loads((p/'summary.json').read_text()) for p in (old, reference)]
    paths = [w['source'] for w in workloads]
    checks = dict(
        known_source_paths=paths == ['docs/35-npu-core-candidate.md', 'assets/reference/source-document.md'],
        source_content_hashes_valid=all(w['source_sha256'] == sha(p/'source-document.md')
            for w,p in zip(workloads,(old,reference))),
        workload_hashes_valid=all(s['workload_sha256'] == sha(p/'workload.json')
            for s,p in zip(summaries,(old,reference))),
        input_relocation_valid=(ROOT/summaries[1]['input_path']).resolve() == image.resolve(),
        input_matches_summary=summaries[0]['input_sha256'] == summaries[1]['input_sha256'] == sha(image)
            if 'input_sha256' in summaries[0] else True,
        reference_complete=all(s['status'] == 'passed_cold_context_isa' for s in summaries),
        workload_semantic_equal=({k:v for k,v in workloads[0].items() if k != 'source'} ==
                                 {k:v for k,v in workloads[1].items() if k != 'source'}))
    # Normalize only named top-level provenance fields and the two measured runtimes.
    normalized = []
    for summary in summaries:
        item = json.loads(json.dumps(summary))
        del item['input_path']
        del item['workload_sha256']
        for kind in ('native', 'candidate'):
            duration = item['runs'][kind].pop('wall_seconds')
            assert isinstance(duration, (int,float)) and duration >= 0
        normalized.append(item)
    summary_equal = normalized[0] == normalized[1]
    result = dict(files=files, metadata_checks=checks, summary_semantic_equal=summary_equal,
        workload=dict(original_sha256=sha(old/'workload.json'), new_sha256=sha(reference/'workload.json'),
            byte_equal=equal_files(old/'workload.json',reference/'workload.json'),
            original_source=paths[0], new_source=paths[1]),
        normalized_fields=['workload.source (validated exact historical/current paths and document hashes)',
            'summary.workload_sha256 (validated against each unmodified workload)',
            'summary.input_path (new relocation target validated)',
            'summary.runs.native.wall_seconds', 'summary.runs.candidate.wall_seconds'],
        reference_directory=str(reference.resolve()), image=str(image.resolve()))
    result['status'] = 'passed' if (all(v['byte_equal'] for v in files.values()) and
                                    all(checks.values()) and summary_equal) else 'mismatch'
    return result


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--reference',type=Path,required=True)
    p.add_argument('--image',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args(); result=compare(a.reference,a.image)
    save(a.output,result)
    assert result['status']=='passed', 'Inspect asset comparison; no mismatch is suppressed'


if __name__=='__main__': main()

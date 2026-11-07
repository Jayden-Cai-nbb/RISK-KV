"""Rebuild frozen assets and replay new firmware, preserving every original input."""
import argparse
import json
from pathlib import Path
import shutil
import sys
import time

from recorded import ROOT, run, save, sha, snapshot_tooling, utc


def equal_files(left, right):
    if left.stat().st_size != right.stat().st_size:
        return False
    with left.open('rb') as a, right.open('rb') as b:
        while True:
            x, y = a.read(4 << 20), b.read(4 << 20)
            if x != y:
                return False
            if not x:
                return True


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--model-python', type=Path, required=True)
    p.add_argument('--toolchain', type=Path, required=True)
    p.add_argument('--after-suite', type=Path)
    p.add_argument('--host-opt', action='store_true')
    p.add_argument('--host-default', action='store_true')
    p.add_argument('--sim-threads', type=int, choices=(1,2,4), default=1)
    a = p.parse_args()
    if a.host_opt and a.host_default:
        p.error('Select only one host mode')
    if a.sim_threads != 1 and not (a.host_opt or a.host_default):
        p.error('Select an explicit host mode for multithreaded simulation')
    out = a.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    status = dict(status='waiting' if a.after_suite else 'running', started_at=utc(), stages={},
                  host_default=a.host_default, host_optimization=a.host_opt, sim_threads=a.sim_threads,
                  tooling_sha256=snapshot_tooling(out))
    save(out / 'suite.json', status)
    # Preserve the venv interpreter symlink: resolving it bypasses pyvenv.cfg.
    model = ['env', '-u', 'PYTHONHOME', '-u', 'PYTHONEXECUTABLE', '-u', 'PYTHONPATH', str(a.model_python.absolute())]

    def stage(name, command, timeout=25200):
        rc = run(out / (name + '-command'), command, timeout)
        status['stages'][name] = rc
        save(out / 'suite.json', status)
        if rc:
            raise RuntimeError(name)

    try:
        if a.after_suite:
            while True:
                prior = json.loads(a.after_suite.read_text())
                if prior['status'] not in ('running', 'waiting'):
                    status['preceding_suite_status'] = prior['status']
                    if prior['status'] != 'passed':
                        raise RuntimeError('Preceding frozen suite did not pass; source stages were not started')
                    break
                time.sleep(30)
        status.update(status='running', execution_started_at=utc())
        save(out / 'suite.json', status)
        stage('input', model + [ROOT / 'tools/rebuild_input.py', '--output', out / 'input/dram-input.bin'], 1800)
        ref = out / ('reference-' + out.parent.name)
        stage('reference', model + [ROOT / 'tools/prepare_npu_context_build.py', '--source', ROOT / 'vendor/openTPU', '--output', ref], 21600)
        # The frozen generator writes one scratch image outside --output. Relocate
        # that newly generated file; retain the generator's original summary.
        summary_path = ref / 'summary.json'
        generated = json.loads(summary_path.read_text())
        shutil.copy2(summary_path, ref / 'summary-before-relocation.json')
        scratch = ROOT / generated['input_path']
        image = out / 'input/reference-dram-input.bin'
        assert sha(scratch) == sha(out / 'input/dram-input.bin')
        assert equal_files(scratch, out / 'input/dram-input.bin')
        shutil.move(scratch, image)
        scratch.parent.rmdir()
        generated['input_path'] = image.relative_to(ROOT).as_posix()
        save(summary_path, generated)
        save(out / 'relocation.json', dict(from_path=str(scratch), to_path=str(image), sha256=sha(image),
            reason='Constrain new artifacts to the run directory; only new summary.input_path changed'))
        from compare_assets import compare
        comparison = compare(ref, image)
        save(out / 'asset-comparison.json', comparison)
        assert comparison['status'] == 'passed', 'Reference bytes or metadata mismatch'
        for case, failure in [('positive', 0), ('cancel', 1), ('fault', 2)]:
            stage('firmware-' + case, [sys.executable, ROOT / 'tools/prepare_npu_context_firmware.py', '--reference', ref,
                '--toolchain', a.toolchain.resolve(), '--output', out / 'firmware' / case, '--failure', failure], 300)
        for case in ('cancel', 'fault', 'positive'):
            host_flags = ['--default-cxx'] if a.host_default else []
            host_flags += ['--sim-threads', str(a.sim_threads)]
            prefix = ([sys.executable, ROOT / 'tools/reproduction/npu_host.py', '--record', out / (case + '-host'), *host_flags, '--']
                      if a.host_opt or a.host_default else [sys.executable, ROOT / 'tools/run_npu_context_build.py'])
            stage('rtl-' + case, [*prefix, '--source', ROOT / 'vendor/openTPU',
                '--reference', ref, '--firmware', out / 'firmware' / case, '--platform', out / 'platform',
                '--output', out / case, '--input', image])
        stage('integrity-after', [sys.executable, ROOT / 'tools/verify_handoff.py', '--data'], 600)
        status['status'] = 'passed'
    except BaseException as ex:
        status.update(status='failed', error=f'{type(ex).__name__}: {ex}')
        raise
    finally:
        status['finished_at'] = utc()
        save(out / 'suite.json', status)


if __name__ == '__main__':
    main()

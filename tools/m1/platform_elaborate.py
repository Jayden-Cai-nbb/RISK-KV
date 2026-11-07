"""Elaborate actual CPU/NPU/native memory plus both generated SmartConnects and CDC."""
import argparse
import json
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/reproduction'))
import recorded


def main(synthesize=False, clocked=False):
    assert not clocked or synthesize
    description = 'Synthesize actual complete digital platform; no physical DDR or board signoff.' if synthesize else __doc__
    ap = argparse.ArgumentParser(description=description)
    for name in ('fixture', 'router-fixture', 'cdc-fixture', 'firmware', 'vivado', 'output'):
        ap.add_argument('--' + name, type=Path, required=True)
    args = ap.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    work = out / 'work'
    work.mkdir()
    originals = []
    snapshots = []

    def copy(source, target):
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        originals.append(source)
        snapshots.append(target)

    # BD/XCI的生成目录与源目录相对位置也是输入；完整冻结，另复制可变构建树。
    # Vivado可以重生成work副本，但不得改动被recorded校验的frozen树。
    for label, fixture in (('fabric', args.fixture), ('router', args.router_fixture), ('cdc', args.cdc_fixture)):
        parent = fixture.resolve() / 'project'
        assert parent.is_dir(), parent
        frozen = out / 'frozen' / label / 'project'
        for source in sorted(parent.rglob('*')):
            if source.is_file():
                copy(source, frozen / source.relative_to(parent))
        shutil.copytree(frozen, work / f'{label}-copy/project')
    filelist = 'platform/m1/platform_clocked.f' if clocked else 'platform/m1/platform.f'
    names = [line for line in (ROOT / filelist).read_text().splitlines() if line and not line.startswith('#')]
    for name in names + [filelist]:
        copy(ROOT / name, work / 'sources' / name)
    entry = 'platform_synthesize.tcl' if synthesize else 'platform_elaborate.tcl'
    if clocked:
        entry = 'platform_clocked_synthesize.tcl'
        copy(ROOT / 'platform/m1/platform_clocked_reset_cdc.tcl', work / 'platform_clocked_reset_cdc.tcl')
    for source, name in ((ROOT / 'platform/m1' / entry, entry),
                         (args.firmware.resolve() / 'firmware.hex', 'firmware.hex'),
                         (args.firmware.resolve() / 'manifest.json', 'firmware-manifest.json'),
                         (Path(__file__).resolve(), 'runner.py'),
                         (ROOT / 'tools/reproduction/recorded.py', 'recorded.py')):
        copy(source, work / name)
    if synthesize:
        copy(ROOT / 'tools/m1/platform_synthesize.py', work / 'platform_synthesize.py')
    if clocked:
        copy(ROOT / 'tools/m1/platform_clocked_synthesize.py', work / 'platform_clocked_synthesize.py')
    recorded.save(out / 'inputs.json', {str(p): recorded.sha(p) for p in originals})
    summary = dict(status='running', hardware_actions=[], part='xcvu440-flga2892-1-c',
                   actual_speed_grade='unconfirmed', numeric_validation=False, board_validation=False,
                   requested_stage='synthesis' if synthesize else 'elaboration')
    if clocked:
        summary['requested_stage'] = 'clocked_synthesis'
        summary['clock_scope'] = 'Actual 48 MHz input Wizard for core50/fast100; UI is external nominal clock. No MIG/board/PnR.'
    recorded.save(out / 'summary.json', summary)
    recorded.ROOT = work
    try:
        assert recorded.run(out / 'version', [args.vivado.resolve(), '-version'], 60, snapshots) == 0
        version = (out / 'version/stdout.log').read_text()
        assert 'v2022.2' in version and '3671981' in version
        rc = recorded.run(out / 'record', [args.vivado.resolve(), '-mode', 'batch', '-source', entry], 7200 if synthesize else 1800, snapshots)
        log = (out / 'record/stdout.log').read_text()
        summary['returncode'] = rc
        summary['critical'] = [line for line in log.splitlines() if line.startswith(('ERROR:', 'CRITICAL WARNING:'))]
        marker = 'M1_FULL_PLATFORM_SYNTHESIZED_NOT_BOARD_VALIDATED' if synthesize else 'M1_FULL_PLATFORM_ELABORATED_NOT_NUMERIC_OR_BOARD_VALIDATED'
        if clocked:
            marker = 'M1_CLOCKED_PLATFORM_SYNTHESIZED_NOT_BOARD_VALIDATED'
        assert rc == 0 and marker in log
        assert not summary['critical'], summary['critical']
        summary['status'] = 'synthesized_not_board_validated' if synthesize else 'elaborated_not_synthesized'
    except Exception as exc:
        summary.update(status='failed', error=repr(exc))
        raise
    finally:
        recorded.save(out / 'summary.json', summary)
        print(json.dumps(summary), flush=True)


if __name__ == '__main__':
    main()

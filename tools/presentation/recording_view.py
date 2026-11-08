#!/usr/bin/env python3
"""Recording aid: read existing evidence only; never open a hardware connection."""
import argparse
import collections
import hashlib
import json
import struct
import sys
import time
from datetime import datetime, timezone, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_RUN = ROOT / 'build/reproduction/g3-board-final-20261107/board-suite-v3'
DEFAULT_REF = ROOT / 'assets/m1/reference'
CST = timezone(timedelta(hours=8))


def read(path):
    for attempt in range(5):
        try:
            return json.loads(path.read_text())
        except json.JSONDecodeError:
            if attempt == 4:
                raise
            time.sleep(.05)


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for data in iter(lambda: f.read(1 << 20), b''):
            h.update(data)
    return h.hexdigest()


def title(name, run):
    print('\nRISK-KV | ' + name)
    print('运行编号：' + read(run / 'summary.json')['run_id'])
    print('实验配置：M1-experimental-demo；整套验收状态见阶段报告')
    print('来源：' + str(run))
    print('-' * 72)


def live(run, seconds):
    deadline = time.monotonic() + seconds
    platform = read(run / 'continuous/report.json')['platform']
    journal_path = Path(platform['state_path'])
    while True:
        summary = read(run / 'summary.json')
        state = read(run / 'live-status.json')
        obs = state['observation']
        age = max(0, (time.time_ns() - state['observed_ns']) / 1e9)
        if sys.stdout.isatty():
            print('\033[2J\033[H', end='')
        title('实时状态观察（读取现有会话快照）', run)
        print('当前北京时间：', datetime.now(CST).strftime('%Y-%m-%d %H:%M:%S'))
        print('最近硬件采样：', datetime.fromtimestamp(state['observed_ns']/1e9, CST).strftime('%H:%M:%S'),
              '| 距今 %.1f 秒' % age)
        print('验收进程：', summary['status'], '| 阶段：', summary.get('current_stage'))
        print('快照序号：', obs['snapshot_sequence'], '| 硬件心跳：', obs['heartbeat'])
        print('DDR 校准：', obs['ddr_calibrated'], '| 时钟锁定：', obs['clock_locked'])
        print('对象代际：', obs['generation'], '| 前缀进度：', obs['built_tokens'], '/ 256 token')
        print('累计提交：', obs['committed_tasks'], '| 任务活动：', obs['task_active'])
        print('访存在途：', obs['memory_outstanding'], '| 清理字节：', obs['clear_cleaned_bytes'])
        print('隔离：', obs['isolated'], '| 平台错误：', obs['platform_error'], '| CPU trap：', obs['trap'])
        print('注入错误数：', obs['injected_errors'], '| 受控复位数：', obs['reset_count'])
        journal = read(journal_path)
        completed = journal.get('last_completion') or {}
        print('主机事务日志：序号', journal['sequence'], '| 状态', journal['status'])
        print('最近已完成事务：', completed.get('operation'), '| 字节数', completed.get('bytes'),
              '| 地址', hex(completed['address']) if isinstance(completed.get('address'), int) else completed.get('address'))
        print('事务记录距今 %.1f 秒（主机记录，与硬件快照分开采样）' %
              max(0, (time.time_ns()-journal['updated_ns'])/1e9))
        fault_path = run / 'faults/faults.json'
        if fault_path.exists():
            counts = collections.Counter(x['mode'] for x in read(fault_path)['results'])
            print('已完成故障恢复：取消 %d/10，错误 %d/10，复位 %d/10' %
                  (counts['cancel'], counts['error'], counts['reset']))
        if age > 10:
            print('采样暂未更新：以上为最后一次快照，不能据此判断此刻硬件状态。')
            print('完整读回期间可能不采样；仍显示真实时间戳，不补造进度。')
        print('本窗口只读文件；Ctrl+C 仅退出本观察窗口。', flush=True)
        if time.monotonic() >= deadline:
            break
        time.sleep(min(1, max(0, deadline-time.monotonic())))


def token_data(run):
    tokenizer = ROOT/'models/Qwen3-0.6B-hf/tokenizer.json'
    tokenizer_hash = digest(tokenizer)
    if tokenizer_hash != 'aeb13307a71acd8fe81861d94ad54ab689df773318809eed3cbe794b4492dae4':
        raise ValueError('presentation tokenizer differs from verified Qwen3 tokenizer')
    model = read(tokenizer)
    if model['decoder']['type'] != 'ByteLevel':
        raise ValueError('unsupported tokenizer decoder')
    vocab = {value: key for key, value in model['model']['vocab'].items()}
    byte_values = list(range(33, 127)) + list(range(161, 173)) + list(range(174, 256))
    codepoints = byte_values[:]
    extra = 0
    for b in range(256):
        if b not in byte_values:
            byte_values.append(b)
            codepoints.append(256 + extra)
            extra += 1
    reverse = {chr(c): b for b, c in zip(byte_values, codepoints)}
    def decode(ids):
        return bytes(reverse[c] for i in ids for c in vocab[i]).decode('utf-8')
    ref = read(run/'continuous/reference-input.json')
    rows = []
    sources = []
    for group in range(2):
        path = run/('continuous/batch-%03d/result.json' % group)
        result = read(path)
        sources.append(dict(path=str(path), sha256=digest(path)))
        if result['status'] != 'passed' or len(result['steps']) != 3:
            raise ValueError('query result not complete')
        for lane in range(2):
            ids = [ref['pairs'][group]['seeds'][lane]] + [s['cq']['tokens'][lane] for s in result['steps']]
            rows.append(dict(group='AB'[group], lane=lane+1, token_ids=ids,
                             pieces=[decode([i]) for i in ids], text=decode(ids)))
    return dict(run_id=read(run/'summary.json')['run_id'], tokenizer_sha256=tokenizer_hash,
                rows=rows, source_results=sources,
                scope='Text decoding of recorded board outputs; shared 256-token prefix omitted; no new NPU execution or QA quality evaluation')


def show_tokens(data):
    for row in data['rows']:
        print('%s/路%d：%s' % (row['group'], row['lane'], ' → '.join(
            '%d %s' % (i, json.dumps(t, ensure_ascii=False)) for i, t in zip(row['token_ids'], row['pieces']))))
    print('每行：起始输入 → 第一步 → 第二步 → 第三步；引号内保留真实空格。')
    print('两路共享256-token前缀、各有私有尾部；此处为三步续算验证。')


def evidence(run):
    title('已完成的实物验收记录', run)
    for row in read(run / 'summary.json')['stages']:
        print('%-12s %s' % (row['name'], row['status']))
    report = read(run / 'continuous/report.json')
    print('\nJTAG 器件身份：', report['hardware']['device_id'])
    print('实现目标：', report['hardware']['part'], '| core/fast：50/100 MHz')
    print('配对报告 bit SHA256：', report['hardware']['bit_sha256'])
    batches = sorted((run / 'continuous').glob('batch-*/result.json'))
    results = [read(p) for p in batches]
    print('\n已完成查询批次：', len(results), '| 对象重建：', report['rebuilds'])
    print('查询批次代际：', sorted({r['before']['generation'] for r in results}))
    print('每批成功提交增量：', sorted({r['after']['committed_tasks']-r['before']['committed_tasks'] for r in results}))
    print('同代际 256-token 封存前缀被连续复用；每批完成三步双查询及清尾。')
    ref = read(run / 'continuous/reference-input.json')
    for i in range(2):
        r = read(run / ('continuous/batch-%03d/result.json' % i))
        print('查询组 %s：输入 token %s -> 三步输出 %s' %
              ('AB'[i], ref['pairs'][i]['seeds'], [x['cq']['tokens'] for x in r['steps']]))
    show_tokens(token_data(run))
    print('数值范围：全部 logits、对象 KV、清尾后对象；应保持区见报告。')
    print('原始报告：', run / 'continuous/report.json')
    print('本页读取既有报告；verify 命令另行重新比较选定原始结果。')


def cancel(run):
    title('已完成取消事件回顾（不是本窗口新发取消）', run)
    events = read(run / 'faults/faults.json')['results']
    event = next(e for e in events if e['mode'] == 'cancel')
    before, after = event['before'], event['after']
    query = read(run / 'faults/cancel-00/recovered/query/result.json')
    print('事件：cancel-00 | 注入位置：', event['stage'])
    print('注入时任务活动：', event['event']['injected_at']['task_active'])
    print('身份 session/epoch/generation：', before['session'], before['epoch'], before['generation'])
    print('取消完成状态码：', event['event']['cq']['status'], '(1 = canceled)')
    print('逻辑提交：%d -> %d；增量 %d' % (before['committed_tasks'], after['committed_tasks'], after['committed_tasks']-before['committed_tasks']))
    print('已校验原生写计数增量：', after['native_verified_writes']-before['native_verified_writes'])
    print('完成时在途数：', after['memory_outstanding'], '| 传输已排空：', after['transport_idle'])
    print('恢复后代际：', event['recovered_generation'])
    print('恢复查询结果：', query['status'], '| 三步 token：', [x['cq']['tokens'] for x in query['steps']])
    print('原始记录：', run / 'faults/faults.json')
    print('原始结果：', run / 'faults/cancel-00/recovered/query')


def processes(run):
    import os
    import subprocess
    title('服务器实际 Vivado 进程（只读 /proc）', run)
    found = []
    for proc in Path('/proc').glob('[0-9]*'):
        try:
            exe = os.readlink(proc / 'exe')
            args = (proc / 'cmdline').read_bytes().split(b'\0')
            cwd = (proc / 'cwd').resolve()
            if exe.endswith('/unwrapped/lnx64.o/vivado') and cwd == (run / 'vivado-session').resolve() and any(x.endswith(b'/board_session.tcl') for x in args):
                found.append(proc.name)
        except (OSError, PermissionError):
            continue
    if not found:
        print('当前未找到属于本次运行目录的活跃 Vivado 进程；查看验收阶段是否已结束。')
        return
    sys.stdout.flush()
    subprocess.run(['ps', '-p', ','.join(found), '-o', 'pid,ppid,etime,%cpu,%mem,comm'], check=True)
    print('执行方式：Vivado 2022.2 / -mode batch / board_session.tcl')
    print('对应会话目录：', run / 'vivado-session')
    print('对应器件身份：', read(run/'continuous/report.json')['hardware']['device_id'])
    print('进程存在证明主机工具在运行；板上活动与计算正确性另看 live 和 verify。')


def implementation(run):
    title('最终实现文件与板上运行身份核对', run)
    b = run.parent
    physical = read(b/'physical-review.json')
    bitgen = read(b/'bit-v1/summary.json')
    checkpoint = ROOT/'build/reproduction/g3-board-demo-20261107/build-v4/work/implementation-result.dcp'
    if digest(checkpoint) != bitgen['checkpoint_sha256']:
        raise ValueError('implementation checkpoint mismatch')
    for name, h in bitgen['artifacts'].items():
        if digest(b/'bit-v1'/name) != h:
            raise ValueError('bit/ltx mismatch: ' + name)
    hardware = read(run/'continuous/report.json')['hardware']
    for key, name in [('bit_sha256', 'rkv-m1-board.bit'), ('ltx_sha256', 'rkv-m1-board.ltx')]:
        if hardware[key] != physical[key] or hardware[key] != bitgen['artifacts'][name]:
            raise ValueError('run identity mismatch: ' + key)
    for row in physical['files']:
        if digest(b/row['path']) != row['sha256']:
            raise ValueError('reviewed report mismatch: ' + row['path'])
    print('checkpoint / bit / ltx / 原始报告：摘要核对一致')
    print('Vivado：', physical['vivado_version'], '| 实现目标：', physical['part'])
    print('checkpoint SHA256：', bitgen['checkpoint_sha256'])
    print('bit SHA256：', physical['bit_sha256'])
    print('审查记录 WNS：%+.3f ns；WHS：%+.3f ns' %
          (physical['setup_slack_ns'], physical['hold_slack_ns']))
    print('原始时序报告：', checkpoint.parent/'timing.rpt')
    print('原始资源报告：', checkpoint.parent/'utilization.rpt')
    print('实现是实验配置；支持范围说明：', ', '.join(physical['unsupported_reasons']))
    print('下一步可离线打开该 checkpoint；不连接 JTAG、不重新综合或烧写。')


def npy_bytes(path):
    # Frozen C-order native logits: preserve every payload byte, no numeric conversion.
    import ast
    import math
    data = path.read_bytes()
    if data[:6] != b'\x93NUMPY':
        raise ValueError('not a NPY file: ' + str(path))
    version = tuple(data[6:8])
    if version == (1, 0):
        start = 10 + struct.unpack('<H', data[8:10])[0]
        header = data[10:start]
    elif version in ((2, 0), (3, 0)):
        start = 12 + struct.unpack('<I', data[8:12])[0]
        header = data[12:start]
    else:
        raise ValueError('unsupported NPY version')
    info = ast.literal_eval(header.decode('utf-8').strip())
    if info['fortran_order'] or info['descr'] != '<f4' or len(data)-start != math.prod(info['shape'])*4:
        raise ValueError('unexpected logits layout')
    return data[start:]


def verify(run, reference, output):
    title('现场重新比较已完成事件的原始数值', run)
    gold = read(reference / 'summary.json')
    report = read(run / 'continuous/report.json')
    if digest(reference / 'summary.json') != report['reference_sha256']:
        raise ValueError('reference identity mismatch')
    prefix = (reference / 'reference-prefix.bin').read_bytes()
    if hashlib.sha256(prefix).hexdigest() != gold['prefix_sha256']:
        raise ValueError('reference prefix mismatch')
    rows = []

    def compare(path, expected):
        actual = path.read_bytes()
        if actual != expected:
            first = next((i for i, (x, y) in enumerate(zip(actual, expected)) if x != y), min(len(actual), len(expected)))
            raise ValueError('first difference %s byte=%d sizes=%d/%d' % (path, first, len(actual), len(expected)))
        row = dict(path=str(path.relative_to(run)), bytes=len(actual), sha256=hashlib.sha256(actual).hexdigest())
        rows.append(row)
        print('MATCH  %-60s %9d B' % (row['path'], row['bytes']), flush=True)

    compare(run / 'continuous/built-prefix.bin', prefix)
    for case, group_index, cleared in [('continuous/batch-000', 0, True), ('continuous/batch-001', 1, True),
                                       ('faults/cancel-00/recovered/query', 0, False)]:
        group = gold['pairs'][group_index]
        context_path = reference / group['context_file']
        if digest(context_path) != group['context_sha256']:
            raise ValueError('reference context mismatch')
        expected_context = context_path.read_bytes()
        for i, step in enumerate(group['steps']):
            path = reference / step['logits_file']
            if digest(path) != step['logits_sha256']:
                raise ValueError('reference logits mismatch')
            compare(run / case / ('logits-%d.bin' % i), npy_bytes(path))
        compare(run / case / 'context.bin', expected_context)
        if cleared:
            compare(run / case / 'cleared-object.bin', prefix + bytes(len(expected_context)-len(prefix)))
    compare(run / 'faults/cancel-00/recovered/built-prefix.bin', prefix)
    result = dict(status='passed_selected_raw_comparison', run_id=read(run/'summary.json')['run_id'],
                  scope='two completed query groups plus one canceled-task recovery; not a new NPU run or full M1 acceptance',
                  checked_files=len(rows), checked_bytes=sum(r['bytes'] for r in rows), files=rows,
                  board_acceptance_passed=False, time_ns=time.time_ns())
    print('\n选定原始结果全部一致：%d 文件，%d 字节。' % (result['checked_files'], result['checked_bytes']))
    print('范围：两组已完成查询＋一次取消后恢复；不是本次重新计算或整套验收结论。')
    if output:
        with output.open('x') as f:
            json.dump(result, f, ensure_ascii=False, indent=2)
            f.write('\n')
        print('本次比较报告：', output)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('action', choices=('live', 'evidence', 'cancel', 'verify', 'process', 'implementation', 'tokens'))
    p.add_argument('--run', type=Path, default=DEFAULT_RUN)
    p.add_argument('--reference', type=Path, default=DEFAULT_REF)
    p.add_argument('--seconds', type=float, default=60)
    p.add_argument('--output', type=Path)
    a = p.parse_args()
    try:
        if a.action == 'live': live(a.run, a.seconds)
        elif a.action == 'evidence': evidence(a.run)
        elif a.action == 'cancel': cancel(a.run)
        elif a.action == 'process': processes(a.run)
        elif a.action == 'implementation': implementation(a.run)
        elif a.action == 'tokens':
            title('板上 token 编号与文本对照', a.run)
            data = token_data(a.run)
            show_tokens(data)
            if a.output:
                with a.output.open('x') as f:
                    json.dump(data, f, ensure_ascii=False, indent=2)
                    f.write('\n')
        else: verify(a.run, a.reference, a.output)
    except KeyboardInterrupt:
        print('\n只读观察结束；后台验收未被停止。')


if __name__ == '__main__':
    main()

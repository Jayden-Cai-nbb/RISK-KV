"""Prepare a separate partial CPU/OOC as-built candidate, without workspace approval."""
import argparse
import copy
import json
from pathlib import Path
from recorded import ROOT, save, sha


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input', type=Path, required=True)
    p.add_argument('--service', type=Path, required=True)
    p.add_argument('--service-import', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    m = json.loads(a.input.read_text())
    reviewed = {x['id']: x for x in json.loads(a.service.read_text())['modules']}
    # The adapter creates safe RTL identifiers for elaborated names. Match the
    # exact imported instance paths instead of assuming declaration names survive.
    previous = {('control' if x['id'] == 'top' else x['name'].rsplit('.', 1)[-1]): reviewed[x['id']]
                for x in json.loads(a.service_import.read_text())['modules']}
    m['design']['name'] = 'RISK-KV CPU 与服务控制：现有 OOC 结构'
    m['clocks'] = [dict(id='clk', edge='rising')]
    m['resets'] = [dict(id='reset', clock='clk', activeLevel='high', synchronous=True),
                   dict(id='resetn', clock='clk', activeLevel='low', synchronous=True)]
    groups = [dict(id='clock_reset', label='时钟与复位', category='clock_reset', description='逐端口保留极性；CPU resetn 来自包装层反相，组合驱动仍为模型缺口'),
              dict(id='memory', label='PicoRV32 原生存储总线', category='request', description='地址、数据、写掩码及响应；不是 AXI 接口'),
              dict(id='npu', label='NPU 执行与访存退休', category='control', description='参数、启动、停止与完全排空'),
              dict(id='loader', label='程序装载', category='control', description='程序地址、长度与 busy 握手'),
              dict(id='result', label='结果写回与完成', category='response', description='已接受写回、完成身份与状态'),
              dict(id='diagnostic', label='测试与处理器状态', category='other', description='仿真出口和处理器诊断；不代表实板主机传输')]
    for x in m['modules']:
        instance = x['name'].rsplit('.', 1)[-1]
        if x['id'] != 'top' and instance in previous:
            old = previous[instance]
            for field in ('name', 'clock', 'reset', 'timing', 'contract', 'interfaceGroups'):
                x[field] = copy.deepcopy(old[field])
            old_ports = {port['id']: port for port in old['interfaces']}
            for port in x['interfaces']:
                assert port['id'] in old_ports
                assert port['width'] == old_ports[port['id']]['width']
                assert port['role'] == old_ports[port['id']]['role']
                port['group'] = old_ports[port['id']]['group']
            continue
        cpu = instance == 'cpu'
        assert cpu or x['id'] == 'top'
        x.update(name='PicoRV32 指令执行' if cpu else 'CPU、启动 RAM 与服务入口',
                 clock='clk', reset='resetn' if cpu else 'reset', timing='mixed')
        x['contract'] = dict(
            responsibility=('执行 RV32I 固件，向包装层发出原生存储请求；由固件提交控制命令并消费完成。' if cpu else
                '容纳 PicoRV32、64 KiB 启动 RAM 与服务控制；译码 RAM、控制 MMIO 和仿真结果出口，返回对应响应。'),
            latencyMinCycles=0,
            latencyCondition='整体完成延迟取决于固件与外部响应；0 仅是未知下界，不表示零拍执行。PicoRV32 在上升沿采样 mem_ready；子 MMIO 按 bus_valid && !bus_ready 接收。',
            backpressure='处理器等待原生总线响应；服务完成未消费时禁止新 NPU 任务。没有通用 CPU DDR 窗口。',
            resetBehavior=('低有效同步 resetn 清处理器控制；其反相驱动尚未进入图中精确组合表达。' if cpu else
                '高有效同步 reset 清响应与测试状态；RAM 仅 initial 初始化，运行复位不清 RAM 或外部 DDR。'),
            invariants=['保持实际原生总线和服务准入/消费边界；不把层级导入当作内部状态或时序证明。'],
            verificationPlan=['冻结真实 RV32I 完整 NPU 回放', '服务独立协议审计', 'OOC 导出与来源核对'],
            openQuestions=['内部 RAM/寄存器、组合译码与精确字段依赖仍未表达。',
                '本候选是固定固件 OOC 导出结构；动态 plusarg 启动路径不由本次展开证明。'])
        used = set()
        for port in x['interfaces']:
            name = port['id']
            if name in ('clk', 'reset', 'resetn'): group = 'clock_reset'
            elif name.startswith('mem_'): group = 'memory'
            elif name.startswith('loader_') or name == 'program_ready': group = 'loader'
            elif name.startswith(('result_', 'completion_')): group = 'result'
            elif name.startswith(('npu_', 'fabric_')) or name in ('active', 'launch_pulse'): group = 'npu'
            else: group = 'diagnostic'
            port['group'] = group
            used.add(group)
        x['interfaceGroups'] = [copy.deepcopy(g) for g in groups if g['id'] in used]
    provenance = m['provenance']
    root = ROOT / 'build/reproduction/20261103T073605Z/audit'
    for identity, path in [('cpu_elaboration', root / 'cpu-ooc-elaboration-command/stdout.log'),
                           ('memory_collection', root / 'cpu-memory-collect-command/stdout.log'),
                           ('original_export_audit', root / 'ooc-audit.json')]:
        provenance['evidence'].append(dict(id=identity, file=path.relative_to(ROOT).as_posix(),
                                          fileHash=sha(path), sourceKind='report'))
    provenance['coverage']['elaboratedInstances'] = 6
    provenance['findings'][0].update(classification='fact',
        text='从已核对历史转换的 CPU OOC 导出展开六个真实实例，随后用 memory_collect 合并初始化与存储端口表示。五个自研模块和 PicoRV32 层级可确认；内部 RAM/组合/寄存行为仍缺失。原源码动态 string 展开失败及首次宽初始化导入失败均保留。',
        evidenceIds=['source_0', 'cpu_elaboration', 'memory_collection', 'original_export_audit'])
    command = json.loads((root / 'cpu-ooc-elaboration-command/command.json').read_text())
    provenance['verification'].append(dict(stage='elaboration', status='passed',
        command='See cpu-ooc-elaboration.ys and cpu-memory-collect-command/command.json',
        detail='只确认固定固件 OOC 转换版本的层级展开，不是 Vivado 综合、RAM 功能等价或实板验证。',
        evidenceIds=['cpu_elaboration', 'memory_collection'], target='rkv_npu_context_cpu OOC export',
        executedAt=command['finished_at'].replace('+00:00', 'Z'), sourceDigest=provenance['sourceDigest'],
        tool=dict(name='Yosys/read_slang', version='0.68+206 git 72dc97739-dirty'), batchId='20261103T073605Z'))
    m['specification'] = dict(summary='PicoRV32 从包装层启动 RAM 执行固件，通过原生 MMIO 装载程序和提交身份/参数；服务层准入后启动 NPU，完全退休后发布完成，固件消费后提交逻辑进度。CPU 外层没有通用 DDR 窗口。',
        requirements=[], decisions=[], openQuestions=['OOC 固定固件结构的 as_built/partial 独立候选；未批准。',
            '内部存储、组合译码、resetn 反相及 NPU/DDR 系统仍有表达缺口。'])
    save(a.output, m)


if __name__ == '__main__':
    main()

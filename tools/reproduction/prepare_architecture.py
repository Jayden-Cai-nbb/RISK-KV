"""Enrich an independent as-built candidate; never initialize or approve a workspace."""
import argparse
import copy
import json
from pathlib import Path
from recorded import ROOT, save, sha


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();m=copy.deepcopy(json.loads(a.input.read_text()))
    m['design']['name']='RISK-KV 现有服务控制：准入、执行、完成消费'
    m['clocks']=[dict(id='clk',edge='rising')]
    m['resets']=[dict(id='reset',clock='clk',activeLevel='high',synchronous=True)]
    details={
        'top':('服务入口', '按 MMIO 地址选择对象或执行寄存器；将准入许可、真实接受事件、完成与消费事件接入对象控制。',
            '组合译码；总线接收沿由子模块 bus_valid && !bus_ready 决定，响应在该沿后可见。'),
        'guard':('对象生命周期', '保存对象身份、状态、逻辑进度和任务/双查询引用；先检查参数和对象状态，成功完成消费后才提交进度。',
            'accepted_event、completion_valid、consumed_event 均在产生它们的寄存沿后，由本模块下一上升沿采样。'),
        'io':('装载与结果观察', '确认装载 busy 起落与访存排空；只观察已接受的结果写，校验双字结果后向执行控制与对象控制提供有效性。',
            '装载经过 L_WAIT、L_ACTIVE、L_DRAIN；排空必须当前与前一拍成立，外部装载与访存延迟无固定上界。'),
        'core':('单任务执行', '冻结八个参数和四类身份，保持复位三拍后启动 NPU；等待自然停止和排空，发布结果并等待匹配 ACK。',
            '提交接收 E0 后 E3 释放 npu_reset；NPU 在 E4 采样运行。完成在退休沿后可见；匹配 ACK 接收沿后 consumed_event 有效。')}
    for x in m['modules']:
        key=x['name'].rsplit('.',1)[-1] if x['id']!='top' else 'top'
        label,responsibility,latency=details[key]
        x.update(name=label,clock='clk',reset='reset',timing='mixed' if key!='top' else 'combinational')
        if key=='top':x.update(clock=None,reset=None)
        x['contract']=dict(responsibility=responsibility,latencyMinCycles=0,latencyCondition=latency+' 0 是未知整体下界，不能解释为零拍完成。',
            backpressure='单任务；未消费完成阻止新提交。访存必须履行 fabric_idle 的完全退休承诺。总线采用原生同步 MMIO，非 ready/valid 流水接口。',
            resetBehavior='同步高有效控制复位；清空状态/身份/引用，不清除外部 DDR。服务包装仅传递复位，无独立寄存器。',
            invariants=['取消或错误完成不提交逻辑进度；物理写入可能已经发生。','封存要求成功消费累计 256 token 且完全排空。'],
            verificationPlan=['原冻结 unit/cancel/fault/positive 回放','独立 service_audit 边界夹具；数值和 DDR 证明另列'],
            openQuestions=['迟到写回、永久失联、保留 DDR 复位的恢复合同尚未定义。','导入未表达内部状态、组合逻辑和精确字段依赖。'])
        groups={
          'clock_reset':('时钟与复位','clock_reset','真实时钟/复位输入'),
          'mmio':('同步 MMIO','request','bus_valid/bus_ready 为原生 MMIO 时序，逐端口保留'),
          'loader':('程序装载','control','装载请求与 busy 起落、程序地址/长度'),
          'writeback':('结果写回','writeback','已接受的原生写地址、数据、掩码及结果观察'),
          'completion':('完成与消费','response','完成身份/状态及接受、消费事件'),
          'admission':('身份与准入','control','对象身份、参数快照、引用和逻辑进度'),
          'npu':('执行与排空','control','NPU 启停、执行参数和 fabric 排空/错误')}
        used=set()
        for port in x['interfaces']:
            n=port['id']
            if n in ('clk','reset'):g='clock_reset'
            elif n.startswith('bus_'):g='mmio'
            elif n.startswith(('loader_','loaded_')) or n=='program_ready':g='loader'
            elif n.startswith('result_'):g='writeback'
            elif n.startswith('completion_') or n in ('accepted_event','consumed_event','accepted_count','rejected_count'):g='completion'
            elif n.startswith(('npu_','fabric_')) or n in ('active','launch_pulse'):g='npu'
            else:g='admission'
            port['group']=g;used.add(g)
        x['interfaceGroups']=[dict(id=k,label=v[0],category=v[1],description=v[2]) for k,v in groups.items() if k in used]
    prov=m['provenance']
    log=ROOT/'build/reproduction/20261103T073605Z/audit/service-elaboration.log'
    prov['evidence'].append(dict(id='local_elaboration',file=log.relative_to(ROOT).as_posix(),fileHash=sha(log),sourceKind='report'))
    prov['coverage']['elaboratedInstances']=4
    prov['findings'][0].update(classification='fact',text='本轮用 read_slang --keep-hierarchy 从列出的四份未修改 RTL 生成 JSON。覆盖仅为服务层四实例，不包含内部综合单元、CPU、NPU 与存储。',evidenceIds=['local_elaboration','source_0'])
    prov['verification'].append(dict(stage='elaboration',status='passed',command='See service-elaboration.log: read_slang --keep-hierarchy --top rkv_npu_context_service; write_json',
        detail='仅服务层展开成功；CPU 原始源码的动态 string 初始化不被该前端接受，未伪造 CPU 展开成功。',evidenceIds=['local_elaboration']))
    m['specification']=dict(summary='RISC-V 写入身份/参数与程序描述。服务层先准入，装载器确认握手和排空后启动 NPU；自然结束与访存完全退休后发布完成。软件以匹配身份消费，guard 在下一沿提交逻辑进度；满 256 token 后才允许封存并绑定双查询。',
        requirements=[],decisions=[],openQuestions=['这是现状 partial 候选，不是已批准重写设计。CPU 与 NPU 外围请结合 design-audit.md。'])
    save(a.output,m)


if __name__=='__main__':main()

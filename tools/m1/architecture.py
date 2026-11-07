"""Annotate a scoped Yosys intake; retain all raw connections and model gaps."""
import argparse
import copy
import json
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/reproduction'))
from recorded import save,sha


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--input',type=Path,required=True);p.add_argument('--run',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();m=json.loads(a.input.read_text());run=a.run.absolute()
    descriptions={
        'rkv_m1_native_system':('原生存储系统边界','容纳控制计算系统与原生内存适配，向真实平台提供逻辑 DDR 通道、主机邮箱和监督输入。'),
        'native_memory':('存储适配与退休','把 A/B/SW 转成两个逻辑通道，维护读写退休及缓存失效屏障。'),
        'adapter':('openTPU 存储适配','复用固定 vendor adapter；A 预取、SW 聚合及 B 两通道读写。此结构导入将其内部黑盒化，另有实际模块快测。'),
        'retirement':('物理退休计数','所有 native 读命令/返回和写命令/数据/可见退休分别计数，预取未返回也不得 idle。'),
        'system':('计算与清理互斥','接线 CPU 服务、完整计算和内存仲裁；主机阶段资格纳入同一排空边界。'),
        'compute':('完整 openTPU 计算','固定完整 Qwen3 配置，保留 slice/coll 原算法；core/fast 两域在本工具模型中保留表达缺口。'),
        'mmio':('命令与完成寄存器','暂存命令身份和 token；每个 PicoRV32 总线接受沿转为一次命令/ACK/取消。'),
        'service':('服务监督与执行','组合生命周期控制、NPU 执行器和硬件清理器，关闭失败或复位期间的新准入。'),
        'cleaner':('整区清理与冷初值恢复','每次最多一笔真实访存，先 KV 零写，再复制冷模板；退休守恒且失效完成才发布完成。'),
        'control':('对象身份与提交水位','持有 session/epoch/sequence/generation、对象/引用和 CQ；匹配成功消费沿是唯一提交沿。'),
        'executor':('程序装载与结果收集','装载可信程序并冻结八参数，运行后核对结果写回，HALT 加存储排空后发布 task result。'),
        'memory_arbiter':('NPU 与清理仲裁','保存清理请求并转换字节到字地址；写完成等真实退休；模式切换不复位在途队列。')}
    groups=[dict(id=x,label=y,category=z,description=t) for x,y,z,t in [
        ('clock_reset','时钟与复位','clock_reset','保留每根真实线，普通执行复位与冷复位不同域。'),
        ('memory','存储请求与返回','request','直接物理线保留宽度和反向 ready，分组不表示额外寄存。'),
        ('identity','身份、命令和完成','control','会话/代际/序号与 CQ 消费边界。'),
        ('host','主机与 CPU 总线','request','主机邮箱和阶段资格，不表示通用 CPU DDR 窗口。'),
        ('execution','计算与装载','control','启动、运行参数、完成结果与退休前提。'),
        ('diagnostic','水位与统计','other','状态只读观察，不能用软件写位授予清理资格。')]]
    m['design']['name']='M1 实际控制层级与存储边界（部分还原）'
    m['clocks']=[dict(id='core',edge='rising'),dict(id='fast',edge='rising')]
    m['resets']=[dict(id='cold',clock='core',activeLevel='high',synchronous=True),dict(id='cpu',clock='core',activeLevel='high',synchronous=True),dict(id='cpu_n',clock='core',activeLevel='low',synchronous=True)]
    for x in m['modules']:
        path=x['name'];leaf=path.rsplit('.',1)[-1]
        if leaf=='cpu':
            title,detail=('PicoRV32 指令执行','真实复用 RV32I 核，结构导入省略其内部，固件协议测试实际执行。') if x['rtlModule']=='picorv32' else ('CPU、启动 RAM 与邮箱','64 KiB RAM 供 RV32I 取指与主机邮箱；CPU 复位不清 RAM，监督器不随 CPU 复位清零。')
        else:title,detail=descriptions[leaf]
        x.update(name=title,clock='core',reset='cold',timing='mixed' if leaf in ('compute','cpu','adapter') else 'sequential')
        if leaf=='compute':x.update(clock=None,reset=None)
        if x['rtlModule']=='picorv32':x['reset']='cpu_n'
        if leaf=='mmio':x['reset']='cpu'
        x['contract']=dict(responsibility=detail,latencyMinCycles=0,
            latencyCondition='结构图不推导延迟。core 上升沿接收；外部无限阻塞无有限完成上界；具体边沿见 docs/m1/timing.md。',
            backpressure='请求和完成各按实际端口握手；未接受保持负载；CQ 等匹配消费。',
            resetBehavior='普通 CPU/任务复位不清监督、退休及 DDR；冷复位须全链无旧返回。结构导入 ignore-initial，不证明 RAM 初始化。',
            invariants=['单任务在途，成功匹配消费才提交；失败增量为零；失联隔离不得复用。'],
            verificationPlan=['最终控制/清理/邮箱/原生适配快测；完整模型连续数值回归；真实平台另验。'],
            openQuestions=['内部组合驱动、寄存状态及初始化没有全部进入导入图；不能将连线缺口解释为 RTL 悬空。'])
        used=set()
        for port in x['interfaces']:
            n=port['id']
            if 'reset' in n or n in ('clk','clk_f','rst','resetn'):g='clock_reset'
            elif n.startswith(('mem_','n_','a_','b_','sw_','clean_req','clean_rsp')) or n in ('req_valid','req_ready','req_write','req_addr','req_data','req_mask','rsp_valid','rsp_ready','rsp_error','rsp_data','cvalid','cready','cwe','wvalid','wready','rvalid','wdone'):g='memory'
            elif n.startswith(('host_','bus_')) or n=='boot_hold':g='host'
            elif n.startswith(('cmd_','cq_','receipt_','ack_','cancel_')) or n in ('session','epoch','generation','next_sequence'):g='identity'
            elif n.startswith(('work_','npu_','loader_','result_','fabric_','flush_','clean_')) or n in ('halted','rl_v','rl_val','rinit','launch_pulse','start_valid','start_ready','done_valid','done_ready'):g='execution'
            else:g='diagnostic'
            port['group']=g;used.add(g)
        x['interfaceGroups']=[copy.deepcopy(g) for g in groups if g['id'] in used]
    pr=m['provenance'];pr['scope']='14 个可移植系统及自研控制层级实例；compute、PicoRV32、vendor native adapter 内部黑盒；615 条直接连接保留。'
    pr['coverage']['elaboratedInstances']=14
    records=[('elaboration',run/'architecture-as-built-v2/elaboration/stdout.log'),('layout',ROOT/'configs/m1/layout.json'),('contract',ROOT/'docs/m1/contract.md'),('g1',run/'g1-final-v1/summary.json'),('mailbox',run/'mailbox-v1/summary.json'),('native',run/'native-adapter-v4/summary.json'),('short',run/'full-short-v1/summary.json')]
    for identity,f in records:pr['evidence'].append(dict(id=identity,file=f.relative_to(ROOT).as_posix(),fileHash=sha(f),sourceKind='report'))
    pr['findings'][0].update(classification='fact',text='已核对本次 Yosys/read_slang 输入与 netlist 摘要。采用 --ignore-initial 和三个明确黑盒只为结构还原；不等于可综合性、RAM 初始化或物理实现通过。',evidenceIds=['elaboration','source_0'])
    pr['unsupportedStructures'].append(dict(id='scoped_intake',kind='blackbox_and_initialization',moduleIds=['top'],description='compute/PicoRV32/native adapter 内部、RAM 初始化、core/fast 多时钟与物理 CDC/DDR 省略。',evidenceIds=['elaboration']))
    command=json.loads((run/'architecture-as-built-v2/elaboration/command.json').read_text())
    pr['verification'].append(dict(stage='elaboration',status='passed',command='architecture-as-built-v2/elaborate.ys',detail='仅自研控制层级结构导入，明确黑盒与省略 initial；不是目标器件综合。',evidenceIds=['elaboration'],target='rkv_m1_native_system scoped intake',executedAt=command['finished_at'].replace('+00:00','Z'),sourceDigest=pr['sourceDigest'],tool=dict(name='Yosys/read_slang',version='0.68+206 git 72dc97739-dirty'),batchId=run.name))
    m['specification']=dict(summary='主机冷装载并校验后释放 PicoRV32；固件提交带启动身份的命令，监督器准入后执行完整计算；物理退休后 CQ 可见，主机逐步读回全部 logits 再消费。释放通过真实清尾和冷初值恢复取得重复绑定资格；取消/错误/受控复位走整对象恢复，失联保持隔离。',requirements=[],decisions=[],openQuestions=['该候选为 as_built/partial，只读审阅；不自动批准权威架构。','完整数值 G2 回归结果另查 full-continuous-v1；真实平台待绑定。'])
    save(a.output,m)
if __name__=='__main__':main()

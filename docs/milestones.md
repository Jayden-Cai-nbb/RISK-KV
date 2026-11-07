# 关键里程碑

| 日期 | 里程碑 | 主要结果 | 证据 |
| --- | --- | --- | --- |
| 2026-11-03 | 冻结基线重建与审计 | 完整模型、原生格式、共享前缀与取消/错误的逻辑提交行为建立基线 | 工作负载/参考及来源清单 |
| 2026-11-04 | M1持续服务RTL验证 | 70次完整任务：64次构建、6次双查询续算、两次绑定及中间清尾；324,836,362周期 | [E1完整模型](../evidence/g2/full-model.json)、[周期拆分](../evidence/g2/simulation-metrics.json) |
| 2026-11-05—06 | 真实平台协议接入 | native→AXI、背压/退休、实际SmartConnect/CDC、主机准入、身份与失联隔离 | 当前源码、定向测试及[设计决策](decisions.md) |
| 2026-11-07 | DDR首次写读及全范围验收 | Kingston重插/重启后同参数通过；10次配置冷启动、2 GiB、112轮压力、84处读回 | [E2独立复核](../evidence/ddr/independent-verification.json) |
| 2026-11-07 | 完整整机布局布线 | WNS +0.302 ns、WHS +0.013 ns，内部未约束端点0；物理审查继续 | [E3时序](../evidence/implementation/timing.rpt)、[CDC](../evidence/implementation/cdc.rpt) |

## 结果解释

M1仿真中的35,568,000 B清理写入对应双尾清零及工作区恢复。周期与native请求量来自仿真；板级时间、DDR带宽、JTAG传输和管理收益按最终实物对照测量。

DDR独立位流的结果支持存储平台数据路径。完整NPU加入后的同一最终位流需要重新完成存储与数值验收。配置级冷启动不等同于断电循环。

当前结果为系统设计、功能验证、独立存储实物和最终整机实现四层材料；各层来源与条件分别登记。

## 最终整机实现资源

Vivado布线后资源：219,779 LUT，186,814寄存资源（其中186,813 FF），334 BRAM tile，221 DSP。统计范围为含计算、控制、MIG、互连与诊断的完整顶层；各部分开销由层级报告另行拆分。来源：[utilization.rpt](../evidence/implementation/utilization.rpt)。

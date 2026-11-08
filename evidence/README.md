# 精选里程碑证据

| 编号 | 目录 | 内容 |
| --- | --- | --- |
| E1 | [g2](g2/full-model.json) | 完整模型连续服务仿真、独立参考、清理与状态覆盖摘要 |
| E2 | [ddr](ddr/independent-verification.json) | 独立DDR重复校准、全范围/压力计数和主机读回原件 |
| E3 | [implementation](implementation/timing.rpt) | 当前完整NPU＋MIG布线后的时序、CDC、资源及约束报告 |

[manifest.json](manifest.json)记录原件来源与SHA-256、发布副本SHA-256及规范化方式。公开副本将机器路径替换为`${WORKSPACE}`、主机名替换为`BUILD_HOST`，去除对话授权元数据；数值内容保留。大型完整归档由摘要登记。

DDR第1次配置的板内批次通过，后续主机peek端口宽度脚本修正后以只读方式补采；其余配置接续执行。`cold-01-recovery`保留这条来源。10次配置级冷启动与物理断电循环是不同实验。

当前源码可能包含里程碑之后的平台修复，各报告携带当时输入身份。新增[E4最终整机实物验证](../docs/board-validation.md)及`board-20261108/`：同一最终位流DDR、完整模型连续服务和异常恢复阶段结果。完整实验汇总状态见[当前状态](../docs/status.md)。

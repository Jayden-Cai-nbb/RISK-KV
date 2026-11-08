# 完整整机实物验证：2026-11-08

本次记录来自运行`board-suite-v3-08997e21a599`，取证截止北京时间2026-11-08 18:46:33。完整Qwen3-0.6B在VU440与真实DDR上执行；模型、原生格式、256-token前缀、双查询三步续算和2 GiB布局保持固定。配置标签为`M1-experimental-demo`。

## 结果与证据

| 层级 | 本次完成范围 | 证据 |
| --- | --- | --- |
| 最终整机物理审查 | 配对bit/ltx、时钟、复位、CDC及引脚审查；WNS +0.302 ns，WHS +0.013 ns | [审查记录](../evidence/board-20261108/physical-review.md)、[机器可读记录](../evidence/board-20261108/physical-review.json) |
| 同一最终位流DDR | 10次配置级冷启动、全2 GiB六阶段检查、112轮压力1838.115秒、84处主机读回 | [DDR汇总](../evidence/board-20261108/ddr/qualification-summary.json)、[2236项原件独立核验](../evidence/board-20261108/qualification-local-verification.json) |
| 冷装载 | 冷镜像与工作区模板共1,616,000,768字节，完整写入、读回及摘要校验 | [装载报告](../evidence/board-20261108/suite/load/report.json) |
| 最小完整计算 | 四-token、全部28层，有效KV 236,544字节及应保持区检查 | [四-token报告](../evidence/board-20261108/suite/smoke/report.json) |
| 持续服务 | 64次构建并封存256-token前缀；100批双查询复用；10次对象重建 | [连续服务报告](../evidence/board-20261108/suite/continuous/report.json) |
| 独立连续服务复核 | 550个查询结果文件，共10,392,729,600字节；另核对前缀及16个应保持区 | [复核结果](../evidence/board-20261108/continuous-audit/result.json)、[文件摘要](../evidence/board-20261108/continuous-audit/check.json) |
| 异常恢复阶段结果 | 10次取消、10次可控错误、9次受控复位；已完成任务均零失败提交，恢复数值一致 | [事件记录](../evidence/board-20261108/suite/faults/faults.json)、[151文件独立复核](../evidence/board-20261108/fault-audit/result.json) |
| 展示样本复核 | 两组查询及一次取消恢复，16文件、268,299,264字节逐字节一致 | [样本比较记录](../evidence/board-20261108/presentation/selected-raw-verification.json) |

100批查询在同一对象代际内复用封存前缀，每批三步成功提交；每次释放后，完整对象符合“封存前缀＋零尾部”参考。该结果支持固定负载下的持续绑定、尾部清理与安全复用。十次对象重建进一步检查了代际切换后的计算一致性。

已完成的异常事件覆盖构建早期、中期、末期及续算阶段。取消和错误任务发生真实物理写入，但逻辑提交增量为零，完成时访问已经排空；受控复位完成整对象及工作区清理，并建立新身份。恢复后的前缀、完整logits和对象KV与独立参考一致。第十次受控复位的完整流程、异常矩阵收尾、两种策略各30批对照及末尾失联测试未计入本次通过范围。

## 文件身份

- bit SHA-256：`a3cb400693f7159b572d6b335922cae414ca9f80f8a923326d607336cd9a122c`。
- ltx SHA-256：`8e6b35286a5177b405fb28738bf83a1b7d89a7e5b2c34543ba9f8587635a42aa`。
- 布线DCP SHA-256：`dff72fac3e50a6abc560036c3ebb52a3931a517db790235b0c3f543b9d10eb72`。
- 完整前缀SHA-256：`d28a53db02a530ae3660956a344409790257a5807173e2bfb2637b832d5aa1ca`。

## 已解决的主机链路问题

大块装载曾出现随事务累计变慢的问题。最终主机Tcl将批量payload一次转换为字节数组，再按原字序切片，并使用独立RPC输出通道，避免MiB级协议帧进入Vivado控制台格式化路径。完整输入检查、AXI执行和错误隔离语义保持不变。

修复后32 MiB连续写读全部一致；完整镜像与模板传输耗时合计约5778秒。它是JTAG主机路径的装载成本，不能作为DDR带宽。源码和1 MiB跨边界／非法payload测试见`platform/m1/prodigy/board_session.tcl`与`tools/m1/board_session_test.py`；[传输复核](../evidence/board-20261108/transfer-local-verification.json)保留独立证据。

## 解释与后续工作

本轮取得完整模型在真实DDR上的连续服务证据。吞吐收益、首结果延迟及管理开销仍需同条件对照；100批含完整读回的主机耗时不能直接解释为纯计算延迟。完整异常矩阵、失联隔离、最终实验汇总与视频交付分别验收。

平台继续保留48 MHz MIG输入支持范围、模块部分时序及实体速度级的开放条件。配置级冷启动与物理断电循环分别统计。当前短token续算负载用于数值验证；完整问题输入、持续生成、回答质量、多对象及分布式协作属于后续工作。

## 原始数据下载与复核

[v0.2.0-board-evidence附件](https://github.com/Jayden-Cai-nbb/RISK-KV/releases/tag/v0.2.0-board-evidence)包含16个原始数值文件和规范化事件元数据；大小与SHA-256见[附件目录](../publication/board-data-catalog.json)。其余全量原始读回数据保留在实验存档，本仓库提供文件摘要及完成事件报告。

先按[复现指南](reproduce.md)获取v0.1.0的独立参考附件，解压得到`assets/m1/reference/`。在仓库根目录解压本次附件后执行：

```bash
tar -xzf risk-kv-board-evidence-20261108.tar.gz
python3 tools/presentation/recording_view.py verify --reference assets/m1/reference
```

结果应为16文件、268,299,264字节逐字节一致。该命令比较已有读回数据，不发硬件请求。`tokens`会从固定Qwen3分词器解码实际板上token编号；可直接阅读[文本对照报告](m1/token-results.md)。

公开副本保留数值，规范化主机／路径／器件标签并移除站点连接配置。[证据清单](../evidence/manifest.json)记录原件和公开副本的两套摘要。原件报告内部的`files[].sha256`指向原始归档；规范化副本的完整性以发布清单为准。完整硬件验收仍使用未规范化的原件与本地绑定配置。

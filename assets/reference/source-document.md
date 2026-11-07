# VU440 NPU核心候选v1：配置、证据和交接边界

2026-11-02。这是供后续整机集成的**逻辑核心实验候选**，不是完整参赛产品或可直接下载的bit/ltx。上游NPU计算单元与编译器属于复用；当前自研共享硬件和RISC-V/NPU整机尚未完成。

## 唯一配置入口

[npu-vu440-core.json](../configs/npu-vu440-core.json)，SHA256：

`ec33cde4fd838d67e9e2874cbefbdeb5430f65221d26eedc28142e555a4477a4`

关键值：S=1、D=128、MCOLS=4、ACT_ROWS=16、TMEM=65536个32位字、IMEM=32768个32位字、LANES=8；TMEM_IMPL=3、TMEM_RPL=1、TMEM_PMP=1、RPB=64、WPB=1、WIN=16、MXU_E=4。目标核心/快时钟50/100MHz，实际板级时钟关系还需Clocking Wizard和完整时序验证。2GiB只表示仿真地址容量，不证明板上DDR容量。

不要直接把上游target中的RPB=0传给叶模块；它是自动展开标记。旧错误配置的报告已[撤回为有效候选依据](../deliverables/npu-m0-research-20261101-NOTICE.md)。新入口检查参数约束并从同一JSON生成仿真和综合参数。

## 本候选已取得的证据

- 完整Qwen3-0.6B：1枚提示token＋2步decode，三个步骤的151936维logits和全部28层KV状态哈希均与ISA一致；每步4,955,687个仿真周期。
- 两长度×两种子的原生静态行组合对照通过，ISA/RTL完整内存状态一致。读字节减少49.32%/49.83%，算子周期减少28.59%/25.69%。这些是现有NPU能力的强软件基线，不是新增硬件收益。
- 同配置在VU440综合：106,848 LUT、88,317 FF、734 DSP、236.5 BRAM tile、0 latch。未完成布局布线，没有板级功耗或时延结论。
- [参数一致与编译记录审查](../results/npu-core-candidate-20261102/audit.json)确认模型、共享算子、综合使用同一配置哈希；实际模拟器编译参数包含RPB=64。

仿真使用上游通用DSP行为模型，综合使用UltraScale DSP48E2实现；综合导出另有已记录的语法兼容修改。不能把这一状态称为全门级或实际器件验证。

## 复现入口

原始依赖保持提交`91df41092f612361c5bc22f83b31d23382ffabb0`，用于综合导出；仿真使用独立兼容树，只含原有四处`mk`数组重命名，并保留Apache许可。先配置已验证的Verilator路径和VERILATOR_ROOT。

```bash
python tools/run_npu_m0_model.py \
  --source build/deps/opentpu-m0-compat --compat-mxu-name \
  --model models/Qwen3-0.6B-hf --backend rtl --steps 2 --sim-memory dpi \
  --core-profile configs/npu-vu440-core.json --output results/my-core-model
```

```powershell
.\.venv-local\Scripts\python.exe tools/prepare_npu_vu440_probe.py `
  --source build/deps/opentpu-m0 --top slice `
  --core-profile configs/npu-vu440-core.json --output build/my-core-synthesis
```

完整程序/权重仍需校验模型清单。不要用ISA预填充结果灌入RTL来替代从初始状态执行；不要把DPI内存放进综合文件列表。

## 后续板级集成必须补齐

1. RISC-V管理层、主机接口、DDR控制器及NPU native内存接口转换。原端口A读取32字节，B读取128字节，另有字节使能写口；地址单位和排空语义按原接口逐项核实，不把ready/idle直接绑常量。
2. 同源50/100MHz时钟、复位、安全启动和完整STA；OOC理想输入时钟不代替真实时钟树。
3. 使用该实体板的DDR/IP/XDC，核对Bank0/CFGBVS、容量、地址映射和装载链路；不沿用其他型号开发板的DDR和PCIe参数。
4. 同一版本配对的bit/ltx、固件、权重镜像、程序及配置日志；返回真实板端logits/状态与基线比较。原ND/v2搬运成功不等于NPU上板成功。

## 下一研究步骤

先完成共享前缀＋私有尾部的同模型软件基线，再接RISC-V上下文与任务接口。动态接入要计入同一NPU上的Q生成和层依赖，不能沿用GPU独立产Q的假设。三题质量先导中FP32/INT8均2/3，缺失信息误判仍保留；详见[本轮报告](../results/npu-model-qualification-2026-11-02.md)。

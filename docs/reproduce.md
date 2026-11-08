# 构建与复现

## 环境

| 用途 | 固定版本 |
| --- | --- |
| 主机/编排 | Python 3.11以上，NumPy 2.3.5；原参考环境Python 3.12.16 |
| 模型重建 | Torch 2.13.0+cpu及`tools/reproduction/requirements-model.txt`锁定依赖 |
| RTL仿真 | Verilator 5.032 |
| RV32I固件 | xPack riscv-none-elf GCC 14.2.0-3 |
| FPGA/IP | Vivado 2022.2，VU440器件支持与有效许可 |

`M1_PYTHON`指定Python解释器；`RTL_TOOLS_RUNNER`可指定站点维护的工具入口，默认使用当前PATH。环境安装在仓库之外。`configs/m1/dependencies-lock.json`保留历史依赖来源与摘要，具体包不可取得时记录差异，不静默替换。

```bash
python3 tools/release/verify_snapshot.py
M1_PYTHON=python3 ./scripts/m1 generate_layout --check
M1_PYTHON=python3 ./scripts/m1 generate_host_control --check
M1_PYTHON=python3 ./scripts/m1 board_transport_test --output build/transport-test
M1_PYTHON=python3 ./scripts/m1 quick control --output build/control-test
```

每次测试使用新输出目录。CPU/邮箱测试需显式传入已编译固件，命令见`./scripts/m1 quick --help`。

## 固件

```bash
M1_PYTHON=python3 ./scripts/m1 firmware \
  --toolchain /path/to/xpack-riscv-none-elf-gcc-14.2.0-3 \
  --mode mailbox --output build/firmware
```

`assets/m1/firmware`提供当前板级输入的固定HEX及来源摘要。源码重编译后核对身份、指令语义和结果；编译器变化另记录。

## 模型与数据

原模型为`Qwen/Qwen3-0.6B`，修订`c1899de289a04d12100db370d81485cdf75e47ca`。从[原模型发布页](https://huggingface.co/Qwen/Qwen3-0.6B/tree/c1899de289a04d12100db370d81485cdf75e47ca)下载至`models/Qwen3-0.6B-hf/`，按该目录`risc-kv-model-manifest.json`逐项核对。

冷镜像1,610,710,400 B，SHA-256 `76c576605977d50f70e9e4661b8378946d659cc8f83fa5b24da77e43e05ef14d`。仓库保留冻结程序、参考前缀及第一组logits，可从完整检查点重新构建镜像：

```bash
mkdir -p assets/data
python3 tools/rebuild_input.py --output assets/data/dram-input.bin
python3 tools/m1/reference.py --output build/reference
python3 tools/m1/reference_kv.py \
  --prefix-fixture build/reference/reference-prefix.bin --output build/reference-kv
```

`reference`与`reference_kv`也可直接使用`python3 tools/m1/reference.py`和`reference_kv.py`运行。前者冷构建独立连续布局，后者使用明确的前缀夹具补足尾部快照；两者各自说明参考构造方式。完整模型仿真/主机验收的`--reference`使用带两组context与logits的`reference-kv`目录。

## 固定参考附件

本版[Release](https://github.com/Jayden-Cai-nbb/RISK-KV/releases/tag/v0.1.0-collaboration)提供`risk-kv-reference-data.tar.gz`，包含两组完整context和全部logits。下载后核对`publication/data-catalog.json`记录的SHA-256，在仓库根目录解压，得到`assets/m1/reference/`。各文件摘要另见附件内`FILES.json`。冷镜像和模型权重按上述路径重建/获取。

```bash
sha256sum risk-kv-reference-data.tar.gz
tar -xzf risk-kv-reference-data.tar.gz
```

## 从Tcl生成板级输入

当前发布补齐最终DDR参数、公开导出补丁及互连生成脚本。以下入口默认只生成计划；`--execute`运行固定Vivado版本的IP生成，不进行烧写。

```bash
python3 tools/release/prepare_board_inputs.py \
  --vivado /path/to/Vivado/2022.2/bin/vivado \
  --output build/board-inputs --execute
M1_PYTHON=python3 ./scripts/m1 board_build \
  --ddr-example build/board-inputs/ddr/example/rkv_ddr_candidate_ex \
  --ddr-input build/board-inputs/ddr-input \
  --clocked-work build/board-inputs/clocked-work \
  --firmware build/firmware \
  --vivado /path/to/Vivado/2022.2/bin/vivado \
  --output build/board
```

发布整理新增的生成入口已做离线计划和输入闭包核对，整条新目录重建尚未重复执行。已完成的布线报告使用相同核心RTL和当前约束，具体输入身份见`evidence/implementation`；新构建应生成自己的报告。

```bash
M1_PYTHON=python3 ./scripts/m1 board_review \
  --build build/board --vivado /path/to/Vivado/2022.2/bin/vivado \
  --output build/board-review
M1_PYTHON=python3 ./scripts/m1 board_bit \
  --build build/board --vivado /path/to/Vivado/2022.2/bin/vivado \
  --output build/board-bit
```

`board_bit`内含时序/DRC/结构门槛，生成文件后仍需完整物理审查。当前公开仓库不提供已通过最终整机实物验收的位流。

## 平台绑定与验收

以`configs/m1/platform-unbound.json`和`physical-review-template.json`为字段入口，核对器件、DDR、时钟、bit/ltx、固件与实验身份。真实连接路径、串号、共享锁及journal由上板主机本地配置，不提交公共仓库。

`board_qualify`：最终位流存储验收；`board_suite`：同一持久连接内的装载、计算、连续服务、异常及对照；`experimental_acceptance`：实验汇总；`demo`：操作界面。参数与必需证据以各入口`--help`为准。

共享锁约束所有硬件访问，未知完成状态进入隔离；`board_cold_start`显式执行整链恢复，保留旧责任记录并要求重新装载。

## 新增板上结果复核

[2026-11-08实物验证报告](board-validation.md)提供16个原始数值文件的下载与复核命令。只读展示工具在`tools/presentation/`，本地Vivado路径通过`VIVADO_BIN`设置，例如`VIVADO_BIN=/path/to/Vivado/2022.2/bin/vivado bash tools/presentation/open-implementation.sh`。离线DCP、bit/ltx和站点配置由实验主机提供，未包含在数值附件；原脚本中的固定相对运行目录对应本次证据归档。现场操作单中的`${WORKSPACE}`、`USER@BOARD_HOST`由协作者替换为本地值。

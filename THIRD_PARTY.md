# 来源、许可与贡献范围

| 依赖 | 固定版本 | 许可与来源 |
| --- | --- | --- |
| openTPU | `91df41092f612361c5bc22f83b31d23382ffabb0` | [上游](https://github.com/FeSens/openTPU)，[Apache-2.0](vendor/openTPU/LICENSE) |
| PicoRV32 | `ef203c2b0a3fb793280f5114941416c425c5b461` | [上游](https://github.com/YosysHQ/picorv32)，[ISC](vendor/picorv32/COPYING) |
| Qwen3-0.6B | `c1899de289a04d12100db370d81485cdf75e47ca` | [模型仓库](https://huggingface.co/Qwen/Qwen3-0.6B)，模型权重由原发布渠道获取 |
| Vivado及其IP | 2022.2 | 由用户授权安装生成；本仓库提供配置与集成脚本，不包含安装包或生成的受限IP源码 |

`vendor/`保留本项目所需的源码与工具子集，完整上游可按固定提交获取。

openTPU工作树的MXU有四处代码标识符`mk`改为`rkv_max_sort_key`，用于工具兼容；导出过程的兼容转换保存前后摘要与差异。具体工作树文件以发布清单为准。DPI适配许可见`tb/npu_dpi/LICENSE.openTPU`。

原创实现主要包括KV生命周期控制、执行/清理/退休管理、RISC-V服务固件、平台适配及验证工具。模型算法、完整计算引擎、处理器及已有共享attention方法归属各原作者。

项目原创部分尚未指定开源许可证，著作权由各贡献者保留。公开仓库用于项目展示与协作；第三方文件继续适用其原有许可证。模型、工具和板卡手册通过各自发布渠道取得。

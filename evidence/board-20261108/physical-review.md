# 最终整机物理审查：实验性实物演示

审查对象为 build-v4 的 `rkv_m1_board_top`，Vivado 2022.2、xcvu440-flga2892-1-c。最终检查点 SHA-256 为 `dff72fac3e50a6abc560036c3ebb52a3931a517db790235b0c3f543b9d10eb72`。本记录用于最终位流存储与数值验收准入，不代表实物验收已经完成。

## 时钟与同步路径

最终网表有一个差分输入缓冲、两个并列 MMCM。二者由同一个48 MHz输入缓冲/BUFG驱动，没有MMCM串联。计算MMCM为M=62.5、D=3，输出分频10/20，产生100/50 MHz；相位均0。MIG MMCM为M=20、D=1、输出分频5，UI为192 MHz。core/fast保持同源2倍关系，计算路径接受完整STA；core/UI通过既有异步AXI转换器连接。

最终布线WNS +0.302 ns、WHS +0.013 ns、WPWS +0.138 ns，内部未约束端点0。119个顶层端口与独立DDR成功配置核对。未改变DRC严重级别。

XDCV-2指出service_mode寄存器存在复制对象。端点专项报告确认真正连接`service_sync_reg[0]/D`的仍为原`service_mode_reg/Q`；实际max-delay要求5.208 ns、数据路径1.755 ns、slack +3.520 ns。故障入口要求5.208 ns、数据路径1.320 ns、slack +3.955 ns。CDC报告中这两条跨域均为两级ASYNC_REG同步、max-delay有效。此告警不构成这两条入口路径漏约束；保留原报告，不以重新布线掩盖告警。

## CDC与方法学告警处理

CDC Critical 0。476条Warning按实际端点归属分类：CDC-6为6条；CDC-15为470条。布线阶段报告的告警位于VIO、ILA、JTAG-to-AXI、debug hub、MIG初始化trace的VIO及AXI转换器的厂商FIFO内部。重新打开最终检查点生成位流时，数量相同，实际列出的AXI FIFO使能端点由2条变为1条，另列出calDone到监督器sticky[2]/PRE的1条CDC-15；两份报告分别保存，最终准入按位流阶段端点核对。该只置位故障路径的行为见下段，校验器仅接受这一精确起终点。FIFO读出路径由异步FIFO使能控制，不将RAM数据通路作为独立逐位同步。自研服务切换、复位握手和健康电平均被识别为同步结构。VIO业务状态使用锁存快照及序号握手；独立DDR状态与core快照分别标注采样域。

LUTAR-1的自研4条路径为监督器的只置位故障捕获。运行中armed保持1，健康下降可异步置位，健康恢复不清除故障；冷启动清除期间准入关闭。毛刺可能导致保守隔离，不能使隔离失效或抹掉在途责任。其余2条位于厂商debug hub与MIG PLL复位。实际故障脉宽检测能力仍受原语规格约束，不承诺捕获任意窄脉冲。

TIMING-9与上述厂商使能CDC结构共同核对，不采用全域false-path。CLKC-55属于MMCM布局建议，实际已完成布线、时钟资源合法性及STA检查。DSP流水告警为性能建议，当前频率下时序已通过。PDCN-1569为debug hub优化后的冗余LUT输入，RTSTAT-10为无有效负载网络，未发现未布线业务负载。

CFGBVS/CONFIG_VOLTAGE未填写：本版沿用已成功的JTAG配置方式及相同119引脚，不驱动额外Bank0用户I/O，不编造板级配置电压值。该工具配置元数据缺项原样保留；不提供配置存储器启动或更改配置电压方案。

## 外部复位合同

`sys_rst_n`为BC27、LVCMOS18的低有效异步整链复位，经顶层反相只连接MIG `rst_input_async_reg[0:1]/PRE`。MIG公开源码显示两级异步断言/同步释放，随后四级同步、50输入周期拉伸与各域复位延展。因此其合同不要求相对core/fast的数据setup/hold，也不填写虚构的输入延迟。

AMD [AR64188](https://adaptivesupport.amd.com/s/article/64188?language=en_US)确认MIG sys_rst为异步同步入口；[PG150 Resets](https://docs.amd.com/r/en-US/pg150-ultrascale-memory-ip/Resets)规定异步复位最小脉宽5 ns。本次验收通过FPGA重新配置建立冷启动，运行期间不操作外部复位按钮。外部复位发生时原存储/会话资格作废，必须重新执行整链冷启动和镜像装载。板级模拟脉宽未测量，未宣称按钮去抖或保留会话恢复通过。

`c0_ddr4_reset_n`为Y41、LVCMOS12，源自MIG初始化`cal_RESET_n`寄存器，属于DRAM初始化异步控制而非每周期数据。MIG公开初始化逻辑负责RESET/CKE等待；既有启动trace记录RESET释放至CKE为96009个UI周期，约500 us。最终位流仍须重新取得校准与存储结果。没有为该异步输出添加任意同步输出延迟；模块的未核验次级时序继续属于已披露实验配置条件。

## 配置级状态与验收边界

位流生成脚本逐项核验启动使用标志、复位故障、服务归属及切换故障均为INIT=0、R=GND的FDRE；普通复位不能清除它们。受控CPU复位不连接存储队列复位。只有资格检查全部退休后才允许DDR主设备单向切换到服务路径；故障保留原归属以排空，不凭软件标志授予复用资格。

本审查保留`experimental_m1`、MIG_PFD_48MHZ、MODULE_TIMINGS_UNCONFIRMED及PHYSICAL_SPEED_GRADE_UNCONFIRMED。物理审查通过只准入现有硬件上的有限实验，不代表厂商支持范围、温压认证或完整NPU数值通过。下一关为同一最终位流的10次配置冷启动、完整2 GiB数据与掩码检查、30分钟压力及独立主机读回。

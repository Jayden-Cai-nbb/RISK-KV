# RISK-KV 实物视频录制操作单

日期：2026-11-08。建议成片长约5分钟。推荐组合为 **Windows录屏＋服务器真实SSH终端＋手机实拍板卡**。已有完整模型、共享前缀连续服务的实物结果，今天可以提交一份阶段成果演示。

视频标题建议：**RISK-KV：基于RISC-V的共享前缀管理与安全回收实物演示**。

本次采用正在运行的同一轮验收：`board-suite-v3-08997e21a599`。完整模型为Qwen3-0.6B，VU440连接真实DDR。已经完成完整冷镜像校验、四-token计算、256-token前缀、100批双查询、10次对象重建；取消及部分错误恢复也已有完整数值证据。其他异常测试与成本对照仍在运行。视频展示实时观察、已完成事件和现场重新比较原始数据；完整M1实验验收状态由后续汇总给出。

## 1. 先准备两个窗口，约2分钟

### Windows主录屏窗口

1. 点击Windows“开始”，输入“终端”或“PowerShell”，打开普通窗口，不需要管理员权限。
2. 双击标题栏最大化。使用Windows Terminal时可用`Ctrl`＋鼠标滚轮放大文字；让一屏能显示约30行，文件名能够读清。
3. 输入下面命令并回车：

   ```powershell
   ssh USER@BOARD_HOST
   ```

4. 按终端提示输入服务器密码并回车。输入时不显示字符是正常现象。登录在录屏前完成，文档和视频不包含密码。若首次连接要求确认主机身份，请与现有可信连接核对指纹后接受，不跳过主机校验。
5. 进入工程并预览一次结果：

   ```bash
   cd ${WORKSPACE}
   python3 tools/presentation/recording_view.py evidence
   ```

6. 看到运行编号、`continuous passed_continuous_subset`、100批、10次重建，说明展示入口可用。它从服务器原始报告生成内容，不是预制截图。

### 板卡旁的服务器窗口

在服务器桌面打开一个**新的终端窗口**，输入同样的`cd`命令，然后运行：

```bash
python3 tools/presentation/recording_view.py live --seconds 120
```

把这个窗口与板卡一起纳入手机镜头。它只读取已有会话的状态文件，不申请JTAG连接。若服务器没有桌面，可让Windows电脑屏幕与板卡同框；也可以先拍运行编号，再连续移动镜头拍板卡及连接。

**保留当前板卡供电、USB/JTAG和后台验收。录制步骤不需要重新下载bit、不需要重启程序。** 当前Vivado由验收进程独占，不另开Hardware Manager的`Open Target / Auto Connect`，不点击`Program Device`或VIO复位。新的SSH终端只是查看文件，可以同时打开。

## 2. 开始录屏，先做10秒试录

Windows 11优先使用内置“截图工具”：

1. 点击“开始”，搜索并打开“截图工具”。
2. 点击顶部**录像机图标／录制**，点击**新建**；也可以按`Win + Shift + R`。
3. 拖动框选终端窗口，包含命令、运行编号和输出。
4. 如果录制栏提供麦克风开关，将其打开。点击**开始**，说一句话并等待10秒，再点击方形**停止**按钮。
5. 在预览里确认字能读清、声音能听清，再点击**保存／另存为**。界面版本不同可能自动保存；仍应确认文件位置。

以上按钮与快捷键见[微软截图工具说明](https://support.microsoft.com/en-us/windows/apps/use-snipping-tool-to-capture-screenshots)。

若截图工具没有录像功能：先聚焦终端，按`Win + G`，在“捕获”窗口打开麦克风并点圆形录制按钮；也可用`Win + Alt + R`开始/停止，`Win + Alt + M`切换麦克风。录制文件通常位于“视频／捕获”。见[微软Game Bar录制说明](https://support.microsoft.com/en-us/accessibility/windows/use-a-screen-reader-to-record-your-screen-with-xbox-game-bar)。若该电脑不支持录制此窗口，直接用手机横屏连续拍摄屏幕与板卡，不必临时安装软件延误提交。

## 3. 逐镜头录制，照下面顺序做

### 镜头一：板卡与运行身份，约30秒

手机横屏，连续拍摄：板卡全景 → Kingston内存 → JTAG线连接 → 显示运行编号的终端。不要为拍摄拔线或触碰连接器。

可以照读：

> 这是RISK-KV实物系统，运行在VU440 FPGA和真实DDR上，使用完整Qwen3-0.6B模型。本次运行编号是board-suite-v3-08997e21a599。我们的工作重点是由RISC-V和硬件协同管理KV前缀的构建、共享、取消和回收。

### 镜头二：正在运行的真实状态，约45–60秒

切到Windows录屏中的SSH终端，输入：

```bash
python3 tools/presentation/recording_view.py live --seconds 60
```

观察屏幕上的**硬件采样时间、快照序号、心跳、构建进度、代际、提交数**。当前阶段会自动推进，数值以当时显示为准。

可以照读：

> 这里读取的是现有Vivado硬件会话产生的实际状态快照。DDR已经校准，时钟正常，后台正在执行异常恢复验收。可以看到采样序号和任务进度变化。模型计算在FPGA中执行，主机负责命令组织、数据装载和结果检查。

若处于大块读回，硬件快照可能几十秒不变。此时看**主机事务序号、最近完成的BREAD地址和字节数**，说明正在回收真实DDR数据；主机事务日志与硬件快照分开标注。采样过期时程序会明确显示“最后一次快照”，不能把旧的`task_active`当作当前状态。若要拍构建进度变化，可等当前读回结束后再录这一段，不重启验收。

60秒后自动返回命令行。只在这个观察窗口按`Ctrl+C`也可以提前返回，不会停止后台任务。

### 镜头三：前缀一次构建、多批查询复用，约60秒

输入：

```bash
python3 tools/presentation/recording_view.py evidence
```

把鼠标依次停在以下几行旁边，方便观众跟随：

1. `continuous passed_continuous_subset`。
2. `已完成查询批次：100 | 对象重建：10`。
3. `查询批次代际：[2]`、`每批成功提交增量：[3]`。
4. 查询组A和B的三步输出。

展示用的编号与文本合并表见[板上token结果报告](token-results.md)。`evidence`命令已同时显示两者；单独展示可运行`python3 tools/presentation/recording_view.py tokens`。

已经核对的输出为：

| 查询组 | 两路输入token | 第一步 | 第二步 | 第三步 |
| --- | --- | --- | --- | --- |
| A | `[3555, 8429]` | `[374, 28]` | `[279, 16]` | `[7428, 5373]` |
| B | `[2585, 3197]` | `[311, 28]` | `[990, 16]` | `[25, 5373]` |

**如何解释这张表：** 数字是Qwen3词表中的token编号，不是得分或时间。一个token可以表示单词、词的一部分、标点或其他文本片段。每个`[x, y]`依次表示查询路1与查询路2各自的一个token，不能把它读成同一路的两个连续词。A/B是两组固定续算测试输入；每组内两路引用同一份256-token封存前缀，各自保留私有尾部。

“输入token”是追加到共享前缀之后的起始token；第一步各生成一个新token，将实际生成的token送入下一步，连续执行三步。例如A组路1是`3555 → 374 → 279 → 7428`，A组路2是`8429 → 28 → 16 → 5373`。三步共生成每路3个、两路合计6个token；表格未展开前面的256-token公共上下文。

已直接按本地Qwen3分词器词表解码，便于观众理解：

| 测试组／查询路 | 起始文本片段 | 三步生成片段 | 起始片段＋生成片段 |
| --- | --- | --- | --- |
| A／路1 | ` What` | ` is` → ` the` → ` purpose` | ` What is the purpose` |
| A／路2 | ` Why` | `=` → `1` → `、` | ` Why=1、` |
| B／路1 | ` How` | ` to` → ` use` → `:` | ` How to use:` |
| B／路2 | ` When` | `=` → `1` → `、` | ` When=1、` |

英文片段中的前导空格属于真实token解码结果。当前输入是项目文档前256个token加一个起始token，没有构造完整问题与对话模板，因此输出包含词语、数字或标点。这个实验评价计算和生命周期管理；完整问题的回答质量需要后续应用实验。两路生成相同后缀本身不能判定串任务，现有验收通过完整logits与各自KV参考检查独立性。

**视频中建议先解释含义，再展示数字：**

> 方括号里的两个编号分别来自两条查询，它们共享同一份前缀，但后续状态独立。每一步各生成一个token，再送入下一步。比如第一路从What继续生成is、the、purpose。这组短序列用于检查完整模型的连续计算；我们同时比较所有logits和KV，确认前缀复用、清尾和恢复没有改变应有结果。

解码原件及分词器摘要记录在`build/reproduction/recording-20261108/token-explanation.json`。token编号对应的文本用于解释展示，不改变冻结输入或数值标准。

可以照读：

> 这一轮已经完成100批双查询，交替使用两组输入。100批都引用同一代际的256-token封存前缀，每批完成三步计算，释放后清理私有尾部，下一批继续复用。随后还完成了10次对象重建。针对重复查询同一资料的场景，这套管理流程能够保留可共享的前缀，同时隔离每批查询的私有状态。

> 画面中的token来自真实计算。数值验收同时比较全部logits和KV，三步输出是计算验证负载，完整资料问答是后续应用目标。

需要展示原始JSON时，可再输入以下命令；这是该批实际结果文件，按`q`退出查看：

```bash
python3 -m json.tool build/reproduction/g3-board-final-20261107/board-suite-v3/continuous/batch-000/result.json | less
```

### 镜头四：取消已有物理写，但没有错误提交，约60秒

输入：

```bash
python3 tools/presentation/recording_view.py cancel
```

画面应显示：注入时任务活动为`True`；取消状态码为`1`；提交`1035 → 1035`，增量`0`；已校验原生写计数增加`118273`；完成时在途数为`0`、传输已排空；恢复后代际为`14`，恢复查询结果为`passed`。

可以照读：

> 这是同一轮验收中已经完成的一次取消事件记录。取消发生在真实任务执行期间，此时DDR已经产生物理写入，但该任务没有增加逻辑提交进度。系统等待在途访问排空，随后清理并建立新代际，恢复后的计算结果仍与独立参考一致。这里解决的是取消后的脏状态不能被下一次服务误用的问题。

这一段标题保留“已完成取消事件回顾”。当前只读入口不会新发取消命令，录制时无需打断正在执行的错误／复位测试。

### 镜头五：现场重新比较原始数值，约45秒

输入：

```bash
python3 tools/presentation/recording_view.py verify
```

它会实际打开DDR读回的二进制文件，与独立参考**逐字节重新比较**。本次选定：两组查询各三步全部logits、完整对象KV、清尾后对象、共享前缀和一次取消后的恢复结果。

正常显示16行`MATCH`，最终显示：

```text
选定原始结果全部一致：16 文件，268299264 字节。
```

可以照读：

> 现在现场重新比较保存下来的原始DDR读回数据，覆盖两组查询以及一次取消后恢复，共16个文件、约268 MB，逐字节一致。完整100批服务和10次重建的报告保存在同一运行目录。我们的贡献集中在持续复用、提交控制和安全回收，计算基础复用PicoRV32与openTPU。

若出现报错或差异，保留画面和输出，不把本段说成通过。脚本不会改写原始数据。

### 结束语，约20秒

> 当前实物已经验证共享前缀连续服务和对象重建，取消恢复也已有数值证据。完整异常矩阵与成本对照仍在执行。下一步将补齐文本输入、持续生成和回答质量评价，面向重复查询同一资料的本地推理应用。

## 4. 保存、命名和提交

1. 点击录屏工具的方形**停止**按钮，保存为`RISK-KV-screen-board-suite-v3-08997e21a599.mp4`。
2. 手机板卡片段保存为`RISK-KV-board-board-suite-v3-08997e21a599.mp4`。
3. 最快提交方式：两个文件一起提交，并注明“板卡实拍＋同轮运行屏幕操作”。若必须单文件，可直接用手机连续拍板卡、移到屏幕、完整录完上面的命令；无剪辑也能形成完整演示。
4. 若已有熟悉的剪辑软件，将板卡片段置于开头，接屏幕片段。标注“实时状态观察”“已完成事件记录”“现场原始数据复核”。省略等待时标注“等待过程已省略”，保留未经剪辑的原片。
5. 提交说明可写：

   > 本视频展示RISK-KV在VU440与真实DDR上的阶段实物成果：完整Qwen3-0.6B、256-token共享前缀、100批双查询复用、10次对象重建，以及取消后安全回收与数值恢复证据。视频包含实时运行状态和现场原始数据复核。完整异常矩阵及收益对照继续执行，系统按M1-experimental-demo标识。

## 5. 补充Vivado实证：约2–3分钟，可直接录制

推荐加入主视频的镜头二之后：先展示**实际运行进程**，再切到服务器桌面的**离线实现设计**。最后回到实时状态或原始数值比较，形成“实际进程 → 对应实现 → 板上结果”的证据链。

### 5.1 Windows终端：展示正在控制本次验收的Vivado，约20秒

在已登录服务器的SSH窗口输入：

```bash
python3 tools/presentation/recording_view.py process
```

程序从服务器`/proc`查找当前运行目录对应的Vivado可执行进程，显示**PID、父PID、运行时间、CPU和内存占用**，以及对应的运行编号、`board_session.tcl`和JTAG器件身份`BOARD_DEVICE`。PID由实际系统读取，不按文档写死；如果进程已经结束，会直接说明未找到。

可以照读：

> 当前验收由服务器上的Vivado 2022.2批处理会话驱动。这里是实际进程和运行时间，对应同一个运行编号及JTAG器件。前面看到的板上快照和DDR读回来自这个会话。

进程存在本身不证明计算正确；之后继续展示实现及数值证据。

### 5.2 同一终端：核对布线设计与板上位流，约20秒

输入：

```bash
python3 tools/presentation/recording_view.py implementation
```

它实际计算并核对最终DCP、bit、ltx和审查报告的SHA-256，检查本轮连续服务报告中的位流身份与它们一致。等到出现：

```text
checkpoint / bit / ltx / 原始报告：摘要核对一致
```

鼠标指向DCP与bit摘要、`WNS +0.302 ns`、`WHS +0.013 ns`。

可以照读：

> 接下来展示的布线设计与这次板上运行使用的位流有完整的文件身份对应关系。这里刚重新计算了文件摘要，避免把其他工程或中间版本的报告混入本次结果。

### 5.3 服务器图形桌面：打开最终整机的真实Vivado设计

这一步在**上板服务器的图形桌面**执行，不是在没有图形转发的普通Windows SSH窗口里执行。可用手机拍服务器屏幕；如果已经有远程桌面，也可在Windows录制远程桌面画面。

1. 服务器桌面上新开一个终端。保留原有窗口。
2. 输入：

   ```bash
   cd ${WORKSPACE}
   bash tools/presentation/open-implementation.sh
   ```

3. 它先做同样的文件身份核验，再启动一个**独立的离线Vivado GUI**，载入最终布线DCP，生成时序、总体资源两个图形报告，以及层级资源文本报告。等待Tcl Console出现`RISK-KV OFFLINE REPORTS READY`再开始拍这一段。
4. 最大化Vivado窗口。若底部Tcl Console未显示，通过菜单`Window → Tcl Console`打开；找不到时使用窗口底部已有的`Tcl Console`标签。

此窗口打开的是`rkv_m1_board_top`，实现目标`xcvu440-flga2892-1-c`。它不打开Hardware Manager、不连接hw_server，不占用JTAG。后台板上验收继续运行。首次打开大型DCP可能需要一些时间，建议在正式录屏前打开。

如果旧版脚本已经打开设计，但提示`-name`与`-hierarchical`不能同时使用，无需重新打开DCP。在当前离线窗口的Tcl Console执行：

```tcl
report_utilization -hierarchical -hierarchical_depth 4 -file offline-hierarchy.rpt
report_route_status -file offline-route.rpt
puts [file normalize offline-hierarchy.rpt]
```

前两个图形报告已经生成，可继续查看。新版启动脚本已去掉冲突参数。

### 5.4 点击布局、时序、资源三个页面，约90秒

**A. 芯片布局，约20秒**

- 点击已有的`Device`标签；若未显示，通过`Window → Device`打开。
- 可以看到VU440器件布局。用鼠标滚轮适度缩放；保留整个器件轮廓和部分放置资源，避免放大到看不出整体。
- 可在`Netlist`窗口展开顶层`rkv_m1_board_top → example`，选择感兴趣的模块观察其对应资源。不要一次展开全部底层单元。
- 讲解：“这里是完整整机实现后的芯片布局，包含计算、RISC-V管理、真实DDR接口、主机与诊断逻辑。”

**B. 时序摘要，约35秒**

- 点击生成的`RKV_TIMING`报告标签；如果标签被遮挡，在报告窗口的标签列表中选择它。
- 在报告导航树点击`Design Timing Summary`。
- 指向`WNS`、`WHS`、`WPWS`三项。原始最终布线报告分别为**+0.302 ns、+0.013 ns、+0.138 ns**，原始TNS/THS为0。重新打开DCP后生成的报告以当前实际显示为准，若不同应保留差异并核对，不手工改数。
- 可展开`Intra-Clock Paths`，选一个时钟组的`Setup`，双击一条路径，展示真实起点、终点和数据路径。若布局太拥挤，保留摘要即可。
- 讲解：“在当前约束和实验配置下，最终整机的建立、保持和脉宽检查通过。这是完整整机的布线后结果，后面的实物数值验证用于检查实际计算。”

**C. 资源及层级，约35秒**

- 点击`RKV_RESOURCES`标签，查看CLB LUT、Block RAM和DSP。
- 原始完整顶层记录为**219,779 LUT、334个BRAM tile、221个DSP**。这些是整机资源，不能直接称作KV管理控制器的开销。
- 层级资源保存为`offline-hierarchy.rpt`文本文件。Vivado 2022.2不允许`report_utilization`同时使用`-name`与`-hierarchical`，因此没有`RKV_HIERARCHY`图形页。Tcl Console会打印该文件完整路径；在服务器新终端用`less -S 完整路径`查看，方向键横向滚动，按`q`退出。也可以在Vivado的Tcl Console执行`report_utilization -hierarchical -hierarchical_depth 2`，直接展示简化层级文本。
- 讲解：“PicoRV32、openTPU与厂商DDR基础被复用；我们的工作主要是对象生命周期、提交与回收控制，以及把这些机制接入持续服务和验证链路。这里可以沿实际实现层级追溯资源。”

图形报告使用Vivado 2022.2的`report_timing_summary -name`和`report_utilization`生成；操作依据见[AMD时序报告说明](https://docs.amd.com/r/2022.2-English/ug835-vivado-tcl-commands/report_timing_summary)及[AMD资源报告说明](https://docs.amd.com/r/2022.2-English/ug906-vivado-design-analysis/Report-Utilization)。

### 5.5 最后切回板上状态或数值比较

在Windows SSH终端再执行一次：

```bash
python3 tools/presentation/recording_view.py live --seconds 20
```

或者执行主视频中的`verify`命令。这样观众可以明确区分“离线实现窗口”和“正在运行的板卡会话”，并看到它们对应同一套证据。

录完后可关闭这个新增离线GUI；若提示保存项目/设计修改，选择不保存。原始DCP和报告没有被改写，新增查看报告写到`build/reproduction/recording-20261108/offline-gui-随机目录/`。不要关闭原有验收终端或对正在控制硬件的Vivado进程执行结束操作。

### 没有服务器图形桌面时的替代

直接在SSH终端查看原始Vivado文本报告，仍然是有效实现证据：

```bash
less build/reproduction/g3-board-demo-20261107/build-v4/work/timing.rpt
```

进入后输入`/Design Timing Summary`并回车跳到摘要，按`q`退出。然后打开资源报告：

```bash
less build/reproduction/g3-board-demo-20261107/build-v4/work/utilization.rpt
```

保留报告顶部的工具版本、设计名称、器件及生成时间，再展示关键指标。不要只裁出几个数字而失去上下文。

### 对实际告警的说明

当前为实验性配置，保留48 MHz MIG输入、模块部分时序及实体速度级尚未确认的支持范围说明。原始时序检查中存在一个输入、一个输出的延迟告警，对应复位接口，处理依据已记录在`physical-review.md`；CDC和DRC也保留逐项审查的告警。因此讲解使用“当前约束和实验配置下通过”，不表述为“没有任何告警”或“正式量产条件已经认证”。

## 6. 常见现场情况

| 现象 | 当场操作 |
| --- | --- |
| Windows连接不上服务器 | 在服务器桌面新开终端执行同样命令，手机横屏拍摄；不改服务器网络配置 |
| 中文乱码 | 换用Windows Terminal；在服务器执行`export PYTHONIOENCODING=utf-8`后重试 |
| `live`的硬件数字暂时不变 | 看采样年龄和主机事务序号；读回时展示BREAD进度，等待下一段计算，不复位 |
| `live`显示隔离或验收失败 | 如实保留状态，改用`evidence/cancel/verify`展示已经完成的结果，不能口述“此刻健康运行” |
| 程序提示文件不存在 | 检查是否已进入上述工程根目录；不要临时重新启动`board_suite`或`demo` |
| 误按了`Ctrl+C` | 如果发生在新开的`recording_view.py live`窗口，只是退出观察，重新执行即可；不要对后台验收进程发送信号 |
| 时间只剩两分钟 | 手机连续拍板卡及运行编号，执行`evidence`、`cancel`、`verify`，结束时说明是阶段成果 |

录制入口源码：[recording_view.py](../../tools/presentation/recording_view.py)。完整继续位置：[当前状态](../status.md)。研究贡献及展示主线：[展示说明](../demo.md)。

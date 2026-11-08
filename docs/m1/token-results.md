# 板上续算结果：token编号与文本对照

运行编号：`board-suite-v3-08997e21a599`。模型：完整Qwen3-0.6B。平台：VU440与真实DDR。配置：M1-experimental-demo。

每组有两条查询路，共享256-token封存前缀，各自使用私有尾部。表中每行从一个起始token开始，连续生成三个token；每步实际生成的token作为下一步输入。数字为词表编号，引号内是对应文本，保留实际前导空格。

| 测试组／查询路 | 起始输入：编号＋文本 | 第一步生成 | 第二步生成 | 第三步生成 |
| --- | --- | --- | --- | --- |
| A／路1 | `3555` · `" What"` | `374` · `" is"` | `279` · `" the"` | `7428` · `" purpose"` |
| A／路2 | `8429` · `" Why"` | `28` · `"="` | `16` · `"1"` | `5373` · `"、"` |
| B／路1 | `2585` · `" How"` | `311` · `" to"` | `990` · `" use"` | `25` · `":"` |
| B／路2 | `3197` · `" When"` | `28` · `"="` | `16` · `"1"` | `5373` · `"、"` |

当前负载采用项目文档前256个token，加上单个起始token进行续写，未构造完整问题和对话模板。这些短序列用于计算和KV生命周期验证；完整资料问答的回答质量单独评价。

计算正确性同时由完整logits和KV的独立比较支持。token文本提供直观解释，不替代全量数值验收。表格由同一轮`continuous/batch-000/result.json`与`batch-001/result.json`中的实际完成记录解码生成，没有重新执行模型。

## 视频讲解词

> 每条查询都从同一份封存前缀继续计算，但维护自己的私有状态。这里同时列出了token编号和文本。例如A组第一路从What继续生成is、the、purpose。每步结果反馈到下一步，三步输出与独立参考一致；完整验收还比较全部logits和KV，以检查复用与回收后的状态正确性。

## 现场展示

在服务器工程根目录执行以下命令，可以单独显示此表：

```bash
python3 tools/presentation/recording_view.py tokens
```

原来的`python3 tools/presentation/recording_view.py evidence`也会同时显示编号与文本。

## 来源

- 分词器：`models/Qwen3-0.6B-hf/tokenizer.json`，SHA-256：`aeb13307a71acd8fe81861d94ad54ab689df773318809eed3cbe794b4492dae4`。
- 机器可读展示报告：`evidence/board-20261108/presentation/token-display-report.json`，包含实际结果文件摘要及逐token解码。
- 展示报告SHA-256：`42cec971a313898e1d77a93daa1b11abf18d10aa806339051a3c46fbae7e3a3b`。
- 原始验收报告保持原样；本文为展示用派生报告。

操作步骤见[录制操作单](record-now.md)。

# 图件索引

图源采用Graphviz DOT，SVG用于网页和编辑，PDF用于报告排版。图中文字采用英文，中文解释见架构文档。

| 图号 | 内容 | 可编辑源 | SVG | PDF |
| --- | --- | --- | --- | --- |
| 1 | 系统职责与数据通路 | [DOT](system.dot) | [SVG](system.svg) | [PDF](system.pdf) |
| 2 | 业务生命周期 | [DOT](lifecycle.dot) | [SVG](lifecycle.svg) | [PDF](lifecycle.pdf) |
| 3 | 固定内存布局 | [DOT](memory.dot) | [SVG](memory.svg) | [PDF](memory.pdf) |
| 4 | 验证分层 | [DOT](validation.dot) | [SVG](validation.svg) | [PDF](validation.pdf) |

图1为职责抽象，图2不等同于RTL全部执行状态，图3不按容量比例绘制，图4绿色表示该层已有成果，橙色表示最终整机待完成的验收。源码与导出摘要见[sources.json](sources.json)。

重导出示例：`dot -Tsvg docs/figures/system.dot -o docs/figures/system.svg`。

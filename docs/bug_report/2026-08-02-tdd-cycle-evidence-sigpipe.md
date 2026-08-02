# Halo 门禁缺陷上报：TDD 循环证据匹配的 SIGPIPE 竞态

| 项 | 内容 |
|---|---|
| 上报日期 | 2026-08-02 |
| 上报来源 | target 项目交付 spec `layout-furnish` 的 TDD 收口实施报告（T4），「halo 框架缺陷上报」一节 |
| 发现场景 | RED 簇任务收口：`RED-2` 覆盖 AC-5..AC-10，六个 AC 记在同一份 `tdd-evidence.json` |
| 涉及脚本 | `halo/kernel/orchestrator/sdd/task-complete.sh`、`task-evidence-lint.sh` |
| 影响 | 证据完全合法的多 AC RED 任务无法收口 |
| 上报纪律 | 只上报，不改框架代码；本项目侧自行采取了规避手段 |

> 复核结论见 [`2026-08-02-tdd-cycle-evidence-sigpipe-analysis.md`](2026-08-02-tdd-cycle-evidence-sigpipe-analysis.md)。
> 下方为上报原文存档，其中两处定性经实测不成立：`task-evidence-lint.sh` 并不含该模式；
> 「近乎恒败」实为约五成的竞态。核心机制判断成立，缺陷已修复。

---

## 上报原文

**task-complete.sh / task-evidence-lint.sh 的 `yq -r '.ac_ids[]?' | grep -qxF` SIGPIPE 竞态**

- 现象：red-test 任务收口时报 `missing matching TDD cycle evidence`，即使证据文件
  完全合法（yq 单测表达式返回 true）。
- 根因：`red_task_has_cycle_evidence` 中 `yq | grep -q` 管道，grep 命中即退出；被匹配
  AC 不在 `ac_ids` 末行时 yq 后续写入触发 SIGPIPE（exit 141），`set -o pipefail` 下
  整管道判负。**对非末行 AC 近乎恒败**（本次 RED-2 六连败实测：AC-10 末行恒过、
  AC-5/6/8/9 恒败、AC-7 偶过），并非纯偶发。
- 复现：多 AC（≥3）red 任务 + 单一 tdd-evidence.json 即可稳定复现；本会话已用
  等价 bash 脚本逐 AC 打印 matched 值定位（RED-2 收口期，输出留痕 scratchpad
  `trace.log`）。
- 修复建议（交 halo 团队）：`grep -qxF` 改为消费全部输入（如 `grep -cxF ... >/dev/null`
  或 `yq -e '.ac_ids[]? | select(. == "AC-N")'` 单进程判断），或临时禁用 pipefail。
- 本项目侧规避：在 RED 任务证据目录落单 AC 分片 `cycle-AC-N/tdd-evidence.json`
  （唯一行即末行，恒安全；数据与主证据同一红绿循环），门禁语义不受影响。

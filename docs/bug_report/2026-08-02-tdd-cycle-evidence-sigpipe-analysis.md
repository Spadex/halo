# 分析：red_task_has_cycle_evidence 的 SIGPIPE 误拒

上报原文：[`2026-08-02-tdd-cycle-evidence-sigpipe.md`](2026-08-02-tdd-cycle-evidence-sigpipe.md)
（来自 target 项目交付 spec `layout-furnish` 的 TDD 收口实施报告，上报日期 2026-08-02）。
上报者按纪律只上报不改框架代码，本文是 halo 侧的独立复核。

涉及脚本：`harness-template/halo/kernel/orchestrator/sdd/task-complete.sh`。

## 结论

上报的核心机制成立，缺陷真实：`task-complete.sh` 会以约五成的概率误拒**完全合法**的
多 AC RED 任务证据。已修复并补确定性回归测试。

上报中有两处定性需要修正（见 §4）。

## 1. 缺陷位置

`harness-template/halo/kernel/orchestrator/sdd/task-complete.sh:115`（修复前）：

```bash
if valid_tdd_evidence "$evidence" && yq -r '.ac_ids[]?' "$evidence" 2>/dev/null | grep -qxF "$ac"; then
```

`halo/kernel/_lib.sh:12` 是 `set -euo pipefail`，被所有 kernel 脚本 source。

## 2. 根因

`grep -q` 一旦匹配就立即退出并关闭管道读端。yq（Go，mikefarah v4）对
`.ac_ids[]?` 是**逐元素写出**的，因此当被匹配的 AC 不是最后一个时，yq 写剩余元素会
撞上已关闭的管道，被 SIGPIPE 杀死（退出码 141）。

`pipefail` 让管道取管道内最后一个非零退出码，于是 **grep 匹配成功（0）而整条管道返回
141**，`if` 判假，该 AC 被认定为"无红绿证据"，收口被拒。

这是**竞态**而非确定性失败：若 yq 在 grep 被调度前就把全部输出写进管道缓冲区
（64 KiB，正常规模的 ac_ids 远小于此），则 yq 正常退出，管道返回 0。谁先跑完取决于
进程调度。

## 3. 独立复现

6 个 AC 的证据文件，逐 AC 各试 5 次（`AC-5` 为首元素、`AC-10` 为末元素）：

```
AC-5  141 141 141 141 141      AC-9   141 0 0 0 0
AC-6  141 141 141 141 141      AC-10  0 0 0 0 0      （末元素，恒过）
AC-7  141 141 141 141 141      AC-99  1 1 1 1 1      （真不匹配，正确）
AC-8  141 141 141 141 141
```

同一脚本重跑一轮：35 次中 141 占 19 次、0 占 11 次、1 占 5 次。**批次之间结果不同**，
证实是竞态；靠前的元素窗口更大、更易失败。

## 4. 与上报描述的差异

| 上报表述 | 实测 |
|---|---|
| "对非末行 AC 近乎恒败" | 竞态，整体约五成；同一 AC 在不同批次可过可败。不能按"恒败"设计规避。 |
| "`task-evidence-lint.sh` 同样受影响" | **不成立**。该脚本只调用 `valid_tdd_evidence`（单进程 `yq -e`，无管道），不含此模式。缺陷仅在 `task-complete.sh`。 |

严重度按误拒（假 FAIL）计：不会放行不合格证据，但会阻断合法收口，并诱导使用者伪造
单 AC 分片证据来绕过门禁——绕过手段本身会稀释"每个 AC 都要有红绿循环"的门禁语义。

## 5. 修复

不保留管道，先把 yq 输出收进变量，再用 here-string 交给 grep：

```bash
valid_tdd_evidence "$evidence" || continue
evidence_acs="$(yq -r '.ac_ids[]?' "$evidence" 2>/dev/null || true)"
if grep -qxF -- "$ac" <<< "$evidence_acs"; then
```

未采用上报建议的 `grep -cxF`（仍是管道，日后任何人改回 `-q` 即复发）或
`yq -e 'select(...)'`（把判定绑到 yq 的表达式与退出码语义上）。here-string 是文件，
读端提前退出不产生 SIGPIPE，且 `-qxF` 的整行精确匹配语义原样保留。

## 6. 回归测试

`tests/smoke-test.sh` 新增 `red-many-ac` 场景：RED-1 覆盖 AC-1..AC-4，四个 AC 全部记在
同一份 `tdd-evidence.json` 中，断言 `task-complete` 成功勾选。

竞态无法直接作为稳定断言，因此测试通过 PATH 注入一个逐行输出并在行间 `sleep 0.05` 的
`yq` 包装（仅拦截 `-r .ac_ids[]?`，其余转发真 yq），把竞态窗口放大成确定性触发。
修复前 3/3 失败，修复后 3/3 通过；原有"部分 AC 证据必须被拒"的断言不受影响。

## 7. 同类模式评估（未改动）

同一类陷阱（`pipefail` + 提前退出的管道读端）在仓库另有两处，均已实测**在现实规模下
不触发**，故本次不作投机性改动：

- `harness-template/halo/kernel/_lib.sh:158` —
  `find … | xargs -0 ls -t | head -1` 赋值给 `latest`。1600 个 spec 目录（约 85 KB 路径
  输出）时管道返回非零，`set -e` 下会静默终止整个脚本；200 个目录（约 10 KB）时 20/20
  正常。`ls` 需读完输入才排序，写出是块缓冲，触发门槛远高于 yq 的逐元素写。
- `prismspec/bin/guide.sh:180,187` — `find … | grep -q .`。同规模下 15/15 返回 0。

两处若要根治，应统一改为「先收进变量再判定」，而不是继续在管道里调消费者的行为。

## 8. 验证

```
bash -n（全部 .sh）                     OK
shellcheck --severity=warning          OK
bash tests/smoke-test.sh               122 / 122 ALL PASS
bash examples/go-gin-gorm/try-it.sh    All gates demonstrated
git diff --check                       OK
```

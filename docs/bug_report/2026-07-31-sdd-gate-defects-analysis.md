# SDD 门禁缺陷核对与修复结论（2026-07-31 上报）

对应上报：`docs/bug_report/2026-07-31-sdd-gate-defects.md`

| 项 | 结论 |
|---|---|
| 缺陷 1（逐任务 `模式：` 被证据门禁忽略） | **属实，已修复** |
| 缺陷 2（RED 前置布局不可执行） | **根因诊断有误，本次不改代码**，见下 |
| 备注（RED 任务任一 AC 命中即通过） | **属实，已收紧** |
| 顺带发现（证据门禁不识别中文 `执行模式：`） | **已统一解析链** |

---

## 缺陷 1：逐任务模式被证据门禁丢弃

### 根因

工具链对「任务模式」有两套互不相通的理解：

- `plan-lint.sh:205` 把逐任务的 `Mode:` / `模式：` 列为 `T<n>` 任务的**必填**字段。
- `task-next.sh:139-140` 已按「逐任务优先、spec frontmatter 兜底」解析该字段。
- 但 `task-complete.sh` 与 `task-evidence-lint.sh` 只读 spec 级 `execution_mode`，
  逐任务字段被完全丢弃。

于是 `execution_mode: tdd` 的 spec 里，一个合理的 `模式：plan` 任务（典型是回归护栏任务：
其 AC 断言「既有契约未变」，不存在合法的红，`tdd-evidence.sh` 也拒绝 red=0 的输入）永远关不掉，
并触发上报描述的互锁：不勾选被 `spec-status.sh:218` 的未完成任务闸拦住，手工勾选被
`spec-status.sh:234` 的 `task-evidence-lint` 闸拦住，spec 卡死在 `planned`。

两个证据门禁才是偏离既有约定的一方——修复方向是与 `task-next.sh` 对齐，不是新增语义。

### 修复

- `task-complete.sh`、`task-evidence-lint.sh` 各新增 `task_mode()`，正则与 `plan-lint.sh:205`
  强制的字段完全一致（`(Mode|模式)[[:space:]]*[:：][[:space:]]*` + `plan`/`tdd`，允许反引号）。
- 判定改为**逐任务优先、spec 级兜底**。该优先级是双向的：
  - tdd spec 中声明 `模式：plan` 的任务不再被要求 `tdd-evidence.json`；
  - plan spec 中声明 `Mode: tdd` 的任务反而会被要求 `tdd-evidence.json`。
- `task-evidence-lint.sh` 对 plan 模式任务输出一条
  `<task> plan mode (TDD evidence not required)`，让「为什么没查 TDD 证据」在门禁输出里自解释。

未加「tdd spec 中的 plan 任务必须写明无红理由」这类护栏：那属于 plan 阶段的语义校验，
应由 `plan-lint` 承担，且会对既有项目的 plan.md 造成破坏性收紧，本次不引入。

---

## 缺陷 2：RED/T 顺序 —— 上报的根因判断不成立

上报称 `plan-lint.sh:247` 强制「RED 任务必须全部列在 T 任务之前」，据此推导出「工具链自荐的
执行顺序不可执行」。**该前提不成立**：

```bash
# plan-lint.sh:247-249
if [[ "$FIRST_T_LINE" -gt 0 && "$FIRST_RED_LINE" -gt 0 && "$FIRST_T_LINE" -lt "$FIRST_RED_LINE" ]]; then
```

它只比较**第一个** RED 与**第一个** T 的行号，约束是「第一个 RED 在第一个 T 之前」。
本次交付实际采用的配对拓扑序（RED-1→T1→RED-2→T2→…）本来就合法、能过 lint，
不存在「被逼成全 RED 前置」。上报中「plan 作者因此把预期失败写成配对执行下的失败」这一
连带后果，同样不是门禁造成的。

真实存在的是一个**操作陷阱**，与上报描述的现象重合但根因不同：

- `red_task_has_cycle_evidence` 要求一份 red≠0 **且** green=0 的完整证据（`tdd-evidence.json`
  的 schema 本身就把红绿装在同一个文件里，`tdd-evidence.sh:93` 拒绝写出半份），
  因此 RED 任务在结构上就只能在配对 T 转绿之后关闭。
- `task-next.sh:115` 只返回书面序第一个未勾任务。若 plan 采用全 RED 前置布局，
  task-next 会反复返回同一个此刻关不掉的 RED-1。

即：陷阱来自「全 RED 前置布局 + task-next 无依赖感知」，而非 plan-lint 的强制。
既然配对序合法且能让每个 RED 的失败原因与 plan 预期逐条对上，推荐的做法就是**按配对序编写 plan**。
按本次决定，`task-next.sh` 与 SKILL 文档不做改动。

上报建议 3（放宽为只要求 red≠0）在当前 schema 下不可实现：没有任何工具能产出一份只有红的合法证据。

---

## 备注项：RED 任务的 AC 覆盖被放宽

`red_task_has_cycle_evidence` 原实现在**任一** AC 命中红绿证据时即 `return 0`。
一个覆盖 5 条 AC 的 RED 任务只要 1 条有证据就能关闭——这不是有意的宽松，是漏洞。

已收紧为：RED 任务引用的**每一条** AC 都必须有一份合法红绿证据命中，任一条缺失即拒绝；
任务体不含 AC 引用时保持原有的拒绝行为。

影响面：仅影响「单个 RED 任务覆盖多条 AC 且证据不全」的场景。RED 任务与 AC 一一对应的
plan（`prismspec-planning` 模板的默认形态）不受影响。

---

## 顺带统一：证据门禁的模式解析链

两个证据门禁原先只支持 `spec.md` frontmatter + 英文 `Execution mode:`，缺少
`plan-lint.sh:115` / `task-next.sh:83` 都支持的中文 `执行模式：tdd` 兜底。
后果是纯中文 plan.md 且 spec 缺 frontmatter 时，模式被判为 `unknown`，TDD 证据检查被静默跳过。
已把两处替换为与 plan-lint / task-next 相同的三级解析链（frontmatter → `Execution mode:` → `执行模式：`）。

---

## 验证

`tests/smoke-test.sh` 新增 6d 段落，覆盖：

| 用例 | 断言 |
|---|---|
| tdd spec + `模式：plan` 的 T2 | `task-complete` 退出 0（修复前报 `T2 missing or invalid tdd-evidence.json`） |
| 同上 | `task-evidence-lint` 退出 0 |
| 同上 | `spec-status implemented --from=planned` 退出 0（互锁解除） |
| plan spec + `Mode: tdd` 的 T1 | `task-complete` 拒绝并提示缺 `tdd-evidence.json` |
| RED-1 覆盖 AC-1/AC-2，仅 AC-1 有证据 | `task-complete` 拒绝 |

顺带修正：`spec-status records complete transition audit trail` 原先硬编码「sandbox 内共 3 个转换事件」，
改为按 `spec_id == modern-feature` 过滤后仍断言 3 条，避免后续新增夹具再次误伤该用例。

全量验证结果：

```
bash -n ...                        → OK
shellcheck --severity=warning ...  → OK
bash tests/smoke-test.sh           → ✅ 121 / 121 ALL PASS
bash examples/go-gin-gorm/try-it.sh → ✅ All gates demonstrated
git diff --check                   → OK
```

# 分析：AC 归属提取无 spec 限定

上报原文：[`2026-08-03-user-report.md`](2026-08-03-user-report.md)
（来自 target 项目 spec `layout-furnish-api` 的 T2 收口实施报告，上报日期 2026-08-03）。
上报者按纪律只上报不改框架代码，本文是 halo 侧的独立复核。

涉及脚本：`harness-template/halo/kernel/_lib.sh` 与它的六个调用方。

## 结论

上报两条缺陷中，**一条已在此前提交中修复**（上报者跑的是旧版内核），**一条成立且为阻塞级**。

复核另外查出 **5 处上报方未发现的同根缺陷**，其中 3 处同为阻塞级。全部已修复并补确定性回归测试。

| 上报条目 | 复核结论 |
|---|---|
| 缺陷 B：`yq \| grep -q` 在 `pipefail` 下被 SIGPIPE 击穿 | **已修复**，见 §4 |
| 缺陷 A：`red_task_has_cycle_evidence` 的 AC 提取无 spec 归属限定 | **成立，阻塞级**。但两条修复建议均不采纳，见 §3 |
| —— | 另有 5 处同根缺陷，见 §2 |

## 1. 根因：仓库里"哪些 AC 属于本 spec"有两套口径

`spec-lint.sh` 在 [#9](spec-lint-ac-gap-analysis.md) 已收敛到「**AC 表首列 = 声明**」，
其余六处仍在用 `grep -oE 'AC-[0-9]+'` 扫全文或扫整段任务正文，把**提及**当成**声明**。

三种提及都会污染判定：

- 散文里对其他 spec 的引用：`不得回归 upstream-spec AC-14`
- AC 表**单元格内**的交叉引用：`| AC-3 | … | 与 upstream-spec AC-14 的差异见上游 |`
- 任务正文里的判别力说明：`预期失败：见 layout-furnish AC-14 的判别力说明`

这已经是第 4 次同类缺陷——前三次是 `#7`（[AC 交叉引用被判重复](spec-lint-ac-cross-reference-duplicate.md)）、
`#8`（[跨 spec 测试归属](ac-coverage-bug/verify.md)）、`#9`（[跨 spec 编号被判缺口](spec-lint-ac-gap-analysis.md)），
每次都只修了当时出事的那一处。六份重复定义必然继续漂移，因此本次不做点修，
而是把口径固化成 `_lib.sh` 里的单一契约。

## 2. 缺陷清单

`AC-14` 在下表中一律指「另一个 spec 声明的 AC，本 spec 只是提到它」。

| 位置 | 后果 | 严重度 |
|---|---|---|
| `task-complete.sh:126` | RED 任务被要求为 AC-14 提供红绿证据，收口恒拒（**上报的缺陷 A**） | 阻塞 |
| `ac-coverage.sh:140` | AC-14 进入 Spec AC 集合，count 虚高、覆盖率虚低、门禁误红 | 阻塞 |
| `plan-lint.sh:167` | spec 散文里的 AC-14 被要求写进 plan.md，否则 fail；而 plan-lint 由 `task-complete.sh:196` 无条件调用，其失败在 `set -e` 下直接中止收口 | 阻塞 |
| `plan-lint.sh:164` | `AC trace present:` 展示行混入 AC-14，指示实施者去规划本 spec 不拥有的工作 | 误导 |
| `task-next.sh:143` | `ac_refs` 输出混入 AC-14，直接指示 agent 去造 AC-14 的证据 | 误导 |
| `summary-draft.sh:99` | 完成摘要的 Acceptance Criteria 行列出非本 spec 的 AC | 噪声 |

上报里出现的 `ac_refs` 为 `["AC-1","AC-14","AC-2","AC-3"]` 正出自 `task-next.sh:143`，
本次已用回归 fixture **逐字复现**该输出（见 §6）。

### 实测：`ac-coverage` 的口径分歧

同一张 AC 表，第三行单元格内含一处交叉引用：

```
| AC-1 | Create item | Returns 201                                 | TestXsAC1 |
| AC-2 | Get item    | Returns item                                | TestXsAC2 |
| AC-3 | List items  | Returns a list, unlike upstream-spec AC-14  | TestXsAC3 |
```

```
spec-lint 口径（#9 修复后，sed 取首列）  → AC-1 AC-2 AC-3        count 3
ac-coverage 口径（grep -o 抓整行）        → AC-1 AC-2 AC-3 AC-14  count 4
```

`#9` 的提交说明称其数字口径「matching ac-coverage's Spec AC count」，实测两边并不一致：
`ac-coverage.sh:140` 的第二段 `grep -o 'AC-[0-9]*'` 作用在整行而非首列。该 spec 会被判
3/4 (75%) 而非 4/4，pipeline 误红。

附带一处：`[0-9]*` 允许零位数字，`| AC-1 | see AC-x |` 会产出畸形 token `AC-`。

## 3. 与上报建议的差异

上报给了两条修复建议，均不采纳：

| 上报建议 | 不采纳的理由 |
|---|---|
| 只从「覆盖验收 / Covers」行提取 | 字段标签在仓库内并不统一：`prismspec/skills/prismspec-planning/SKILL.md:110` 用「覆盖验收」，`tests/smoke-test.sh` 的 fixture 用 `Ref:`，而 `plan-lint.sh:192` 只要求正文出现 `AC-[0-9]+`、不限定标签。按标签收窄会让大量存量 plan 突然被拒。 |
| 忽略同行内出现其他 spec id 的 AC token | 需要枚举全部 spec id；且本例中 `layout-furnish` 恰是本 spec id `layout-furnish-api` 的前缀，判别不可靠。 |

采纳的方案是**与本 spec.md AC 表首列声明的 AC 集合取交集**：复用 `spec-lint` / `ac-coverage`
已建立的权威来源，不依赖字段标签，也不需要认识其他 spec。

## 4. 缺陷 B 已在上报前修复

上报的 SIGPIPE 缺陷由 `c75d0c4`（[分析](2026-08-02-tdd-cycle-evidence-sigpipe-analysis.md)）
修复，`task-complete.sh` 现为先落变量再用 here-string 匹配，不再有管道。

同时更正上报中的一处定性：该缺陷是**竞态**（整体约五成误拒），不是上报所述的
「只有排在 `ac_ids` 最后一个的 AC 能被可靠匹配」。上报据此采用的「按 AC 分片落证据」
规避手法因此并不可靠，且会稀释「每个 AC 都要有红绿循环」的门禁语义——升级内核后
应改回单份多 AC 证据。

## 5. 修复

`_lib.sh` 新增两个函数，作为全仓唯一定义：

```bash
spec_declared_acs()        # AC 表首列 = 本 spec 声明的 AC，逐行输出，不排序不去重
narrow_acs_to_declared()   # 把一段文本里提到的 AC 收窄到 spec 声明集
```

六个调用点全部改为调用它们。两处保留**空集回退**（`plan-lint.sh`、`summary-draft.sh`），
`narrow_acs_to_declared` 的回退内置在函数里：spec 没有 AC 表时回到原有的全文扫描，
避免非表格形态的 spec 被静默跳过检查。

`spec-lint.sh:132` 是逐字等价替换，仅为归一口径。

`task-complete.sh` 另把 `red_task_has_cycle_evidence` 的入参由原始任务正文改为已收窄的
AC 列表，并为「收窄后为空」单列错误消息
（`references no AC declared in <spec>`），不再套用误导性的
`missing matching TDD cycle evidence`。

**门禁强度未放松**：本 spec 真实声明但缺证据的 AC 仍然被拒，由既有的 `red-multi-ac`
场景（部分 AC 证据必须被拒）守住。

## 6. 回归测试

`tests/smoke-test.sh` 新增 `cross-spec-ac` 场景：spec 声明 AC-1..AC-3，同时在散文、
AC 表单元格内、RED 任务正文三处提到 `upstream-spec AC-14`；证据文件 `ac_ids` 为 AC-1..AC-3。
四条断言：

1. `task-complete cross-spec-ac RED-1` 成功勾选
2. `task-next --json` 的 `ac_refs` 为 `["AC-1", "AC-2", "AC-3"]`
3. `plan-lint` 退出 0 且输出不含 AC-14
4. `ac-coverage` 报 `Spec AC count: 3`

**测试有效性验证**：暂存内核改动、只保留新测试重跑，四条断言全红（137/141），
其中断言 2 实测输出 `"ac_refs": ["AC-1", "AC-14", "AC-2", "AC-3"]`，
与上报文档记录的现象逐字一致。恢复修复后 141/141。

## 7. 验证

```
bash -n（全部 .sh）                     OK
shellcheck --severity=warning          OK
bash tests/smoke-test.sh               141 / 141 ALL PASS（基线 137 + 新增 4）
bash examples/go-gin-gorm/try-it.sh    AC Coverage 4/4 (100%)，全链路 PASS
git diff --check                       OK
```

`examples/go-gin-gorm` 的 spec AC 表单元格无交叉引用，是新旧口径必须等价的对照样本，
其 `Spec AC count: 4` 与 4/4 覆盖率均无变化。

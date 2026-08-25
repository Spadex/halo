# 复核：compliance 门禁在 spec 文件不存在时报绿

日期：2026-08-25
状态：已修复，回归测试入库
根因类别：**C. fail-open / fail-closed 方向搞反**

## 这份文档为什么没有配对的上报原文

同 `2026-08-25-ac-coverage-func-name-pipefail-analysis.md`：本缺陷来自批次 3
meta-lint 上线前的存量噪声复核，不是外部上报。按 `tests/README.md:57-58`，
自查发现的缺陷只写 analysis，发现路径见下。

## 发现路径

- 起点：`docs/superpowers/plans/2026-08-25-halo-legacy-noise-inventory.md`，基线 `c093b71`。
- 规则 5（诚实 skip 检查）统计 `gates/` 下全部 `exit 0`，指出 `compliance.sh:42`
  是「同种情况其他门禁都报错、唯独这里报绿」的一处不一致。
- 复核确认该判定成立，且**比调研文档举证的更孤立**：把范围从四个门禁扩大到整个 kernel，
  它是唯一一处。

## 症状

```bash
$ bash halo/kernel/delivery/gates/compliance.sh halo/specs/absent/spec.md
⚠️  Spec not found: halo/specs/absent/spec.md
$ echo $?
0
```

门禁对一份**它从未读到过**的 spec 报绿。`pipeline.sh:390-396` 把 0 记为 PASS，
`✅ [N] compliance PASS` 照常打印，流水线继续往下走。

## 根因

四个门禁解析 spec 的结构逐字同型，分两个分支：

1. **自动发现分支**（`compliance.sh:35-40`）——调用方没给 spec，`find_spec` 一个候选都没找到。
   这是「没什么可查」，四个门禁一致 `exit 0` 报 skip。**本次不动它。**
2. **顶层存在性守卫**（`compliance.sh:42`）——调用方点名了一个路径，但文件不在。
   这是「要查的东西不在」，是缺输入，不是空工作量。

第 2 个分支的方向，四个门禁里三个是对的：

```
ac-coverage.sh:43:[[ -f "$SPEC" ]] || { echo "Spec file not found: $SPEC"; exit 1; }
drift-check.sh:41:[[ -f "$SPEC" ]] || { echo "Spec file not found: $SPEC"; exit 1; }
spec-lint.sh:20:  [[ -f "$SPEC" ]] || { echo "File not found: $SPEC";      exit 1; }
compliance.sh:42: [[ -f "$SPEC" ]] || { echo "⚠️  Spec not found: $SPEC";   exit 0; }   ← 修复前
```

把范围扩大到整个 kernel，「spec 文件不存在」时的处理还有五处，**全部是 `exit 1`**：
`orchestrator/sdd/task-brief.sh:19`、`review-package.sh:35`、`spec-status.sh:34`、
`summary-draft.sh:33`、`spec-state-lint.sh:21`。

即 `compliance.sh:42` 是全 kernel **唯一**在这个条件下报绿的地方。
这不是「skip 语义不完整」，是同一语义的多份实现里有一份方向写反了——
根因 C 与根因 H 的交点。

它违反的是 `AGENTS.md:86-87` 明写的规则：

> - A dimension that was not compared is reported as NOT verified. `drift_count: 0` must
>   never be reachable from "nothing was checked".

一个没读到 spec 的 compliance 门禁，报的正是「什么都没查」出来的绿。

## 为什么这处能活下来

**该分支此前没有任何测试覆盖。** 复核时实测：`tests/`（排 `vendor/`）下没有任何用例
用不存在的 spec 路径调 `compliance.sh`；`tests/smoke-test.sh` 全文
`grep -c "compliance.sh"` = 0，根本不调这个门禁。

顺带一提，这也意味着修复**不会打红任何现有用例**——调研文档担心的
「改文案会打红 smoke-test 与部分 bats」在 `c093b71` 上不成立。

## 影响面

真实暴露面比看上去窄，但不是零：

- **流水线路径上几乎到不了。** `pipeline.sh` 里 `ac-coverage` / `drift-check` / `spec-lint`
  在同种情况下早已 `exit 1`，并且 `pipeline.sh:397-411` 遇非零即 `break`。
  也就是说流水线会先在别的门禁停下。
- **真实暴露面是单独调用与 `--only=compliance`。** 这两条路径上，一个拼错的 spec 路径
  会得到一个绿色的 compliance 结论。
- 更长期的风险是**它作为样板被复制**：四份逐字副本里有一份方向不同，
  下一个新增门禁照哪一份抄是随机的。

## 修复

`:42` 改为 `exit 1`，文案与 `ac-coverage.sh:43` / `drift-check.sh:41` 对齐为
`Spec file not found:`，并在代码里注明为什么这里与上面的 skip 分支方向不同。

**行为变更评估**：这是把报绿改成报红，属行为变更而非纯重构。
确认无调用方依赖当前行为——该分支无测试覆盖（见上），
`pipeline.sh` 对非零的处理是既有的通用路径，不需要配套改动。

## 回归测试

`tests/regression/2026-08-25-compliance-missing-spec-fail-open.bats`，4 条，双向：

| 方向 | 用例 |
|---|---|
| 缺陷方向 | 不存在的 spec 路径 → `assert_failure` |
| 文案锁定 | 输出说清是哪份 spec 找不到 |
| 反向（不许把正常路径打红） | 存在的 spec → 仍 `assert_success` |
| 齐平 | 四个门禁对同一情况必须给同一个方向 |

第三条是必需的：缺了它，把 `:42` 改成无条件 `exit 1` 也能让前两条绿。

第四条**一条用例遍历四个门禁**，而不是四份手写副本——手写副本本身就是根因 H，
而单边漂移正是本 bug 的成因。形态照 `tests/unit/lib-find-spec.bats:219-246`
的 ambiguous 齐平用例。

**先红后绿**：修复前实测第 1、4 条红（第 4 条的失败信息精确指出
`gate=compliance: expected a non-zero exit code for a missing spec, got 0`），
第 2、3 条绿；修复后 4/4 绿。第 2、3 条在修复前就是绿的，
正是它们保证了修复不是「把整个守卫改成无条件报红」。

## 机器防线为什么没拦住

| 问题 | 答案 |
|---|---|
| 为什么已有测试没抓到？ | 这个分支零覆盖。`gate-compliance.bats` 只断软门禁的出口契约（envelope 形状、warn/strict 方向），三条用例都传存在的 spec。 |
| 为什么 meta-lint 没抓到？ | meta-lint 尚未上线（批次 3）。规则 5（诚实 skip）**按已定的口径恰好能抓住它**——设计文档 `:124` 的判定是「`exit 0` 前无『NOT verified / skipped』输出即报警」，而 `compliance.sh:42` 的 `⚠️  Spec not found:` 两个关键词一个都不含。这是规则 5 上线价值的直接论据。 |
| 为什么契约单测没拦住？ | 「四个门禁对同一输入必须同向」这条契约此前只在 ambiguous 一个维度上被断言过（`lib-find-spec.bats:219`），missing-file 维度没有对应的齐平用例。本次补上。 |

## 待办（不在本次修复内）

| # | 事项 | 归属 |
|---|---|---|
| 1 | meta-lint 规则 5 上线 | 批次 3 |
| 2 | 四个门禁的 spec 解析段（自动发现 + 存在性守卫）是逐字副本，应收敛为 `_lib.sh` 的共享入口，从形态上消除单边漂移 | 独立重构，需先有本回归测试与 `lib-find-spec.bats` 兜底 |
| 3 | 另四处跳过型出口（`ac-coverage.sh:38`/`:158`、`drift-check.sh:36`、`spec-lint.sh:17`、`compliance.sh:38`）的输出缺 `NOT verified` 字样，不满足 `AGENTS.md:86-87` 与 `tests/README.md:323` 的三条硬契约。按规则 5 的二选一口径它们被放行——**规则管不到不等于缺陷不存在** | 批次 3/4 |

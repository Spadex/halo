# task-evidence-lint 的 unknown 模式静默跳过

日期：2026-09-07
根因类别：**C（失败方向搞反）**，H（同一语义多份定义漂移）是其中一条触发路径
修复提交：与本文件同一提交
回归测试：`tests/regression/2026-09-07-task-evidence-lint-unknown-mode-silent-skip.bats`

## 发现路径

无上报原文，自查发现。

`docs/superpowers/plans/2026-08-25-halo-legacy-noise-inventory.md` 是批次 3 `tests/meta/`
上线前对五条 meta-lint 规则命中面的存量清单。该文档在「【复核补充】最该优先的未修项」
一节把本缺陷登记为「本清单里唯一一处会产生假绿的缺陷」，但当时只做了代码阅读，
没有实测，也没有回归测试。

2026-09-07 对该清单剩余未修项做优先级定级时实测复现，并**订正了清单对触发门槛的判断**
（见下方「与噪声清单的分歧」）。

## 缺陷

`harness-template/halo/kernel/orchestrator/sdd/task-evidence-lint.sh` 的每任务模式分支
是 `if / elif / fi`，**没有 `else`**（修复前 `:136-144`）：

```bash
effective_mode="$(task_mode "$(task_body "$task_id" "$PLAN_FILE")")"
effective_mode="${effective_mode:-$MODE}"
if [[ "$effective_mode" == "tdd" ]]; then
  …
elif [[ "$effective_mode" == "plan" ]]; then
  pass_msg "$task_id plan mode (TDD evidence not required)"
fi
```

`effective_mode` 落到第三值时这段完全不执行：`FAILS` 不增、`WARNS` 不增、
`pass_msg`/`warn_msg`/`fail_msg` 一行都不输出。而循环外的收尾照常执行——
`:150` 打印 `$TASK_COUNT completed task(s) checked`，`:157` 打印 `✅ PASS`。

该任务的**模式维度静默消失**，门禁报绿。

实测输出（修复前，一个 completed 任务、模式无法解析）：

```
🔍 Task Evidence Lint: halo/specs/unknown-mode/plan.md

── Completed task evidence ──
  ✅ T1 brief.md
  ✅ T1 review-package.md
  ✅ 1 completed task(s) checked

══════════════════════════════════
📊 Task Evidence Lint: 0 fail(s), 0 warning(s)
✅ PASS
```

「1 completed task(s) checked」这句话此时是不成立的：TDD 证据这一维度根本没有被检查，
而输出里没有任何痕迹能让读者发现这件事。这正是 `tests/README.md`「门禁诚实性契约」
一节要防的形状——**被守护的行为坏掉时，输出仍然是绿的**。

## 根因

`AGENTS.md:86-87` 的 Gate Rules 写明：没比较过的维度必须报「未验证」，
「什么都没查」不允许到达一个干净的结论。本处违反的就是这一条：模式判不出来 ⇒
「是否需要 TDD 证据」判不出来 ⇒ 该任务的证据要求**未经验证**，而代码把它当成
「无需处理」直接掠过。

归类 C（失败方向搞反）：正确的方向是 fail-closed（判不出来就报未验证），
实现取的是 fail-open（判不出来就当通过）。

## 与噪声清单的分歧：触发门槛比清单写的低

噪声清单把本缺陷描述为根因 H 的下游后果，触发条件写作「一份把 `execution_mode:`
写在 front-matter 块外的 spec 就能造出 `unknown`」——即需要 `execution_mode` 四份定义
之间的口径漂移参与。

**实测不需要漂移。** `execution_mode()`（`:69-77`）的末行是：

```bash
printf '%s' "${value:-unknown}"
```

三个来源全部落空即返回 `unknown`：

1. spec front-matter 没有 `execution_mode:` 键；
2. plan 里没有 `Execution mode:` 行；
3. plan 里没有 `执行模式：` 行。

再叠加任务体没写 `Mode:` / `模式：`（`task_mode()` 对非 `plan|tdd` 的值返回空），
`effective_mode` 就是 `unknown`。**这是纯粹的漏写，不是漂移。**

分歧的影响：清单据此把它的修复排在「`execution_mode` 四份定义收敛」之后，
理由是「根因在上游」。实测表明两者可以解耦——本处的 fail-closed 出口独立成立，
不必等收敛。收敛仍应做（它消除的是另一条触发路径），但不再是本处的前置。

回归测试 `strip_all_mode_declarations()` 走的正是「三处都没声明」这条路径，
不依赖任何漂移。

## 修复

补 `else` 分支，方向 fail-closed，输出含 `NOT verified`：

```bash
else
  # Failure direction: fail-closed. A third value (`unknown`, or anything a future
  # execution_mode() learns to emit) means no source declared the mode — not the spec
  # front-matter, not the plan header, not the task body. Whether TDD evidence is
  # required is therefore unknown, and an unknown requirement must not be reported as
  # met. Without this branch the whole dimension went silent while the summary below
  # still counted the task as checked: a pass built on a comparison never made.
  fail_msg "$task_id execution mode '$effective_mode' — TDD evidence requirement NOT verified"
fi
```

**选 `fail_msg` 而不是 `warn_msg`**：`warn_msg` 只增 `WARNS`，而收尾的 `✅ PASS`
只看 `FAILS`（`:156`）——报 warning 仍然是报绿，缺陷的核心（不可验证的东西被算作通过）
原样保留。`fail_msg` 让退出码变 1，与同批修复的 `compliance.sh` 缺失 spec 时报错
是同一个方向。

**这是行为变更**：此前报绿的场景（plan/spec 都没声明执行模式且任务体没写 `Mode:`）
现在报红。影响面已核实——`tests/`（排 `vendor/`）与 `examples/` 对该分支无任何断言，
仓内所有 fixture（`tests/helpers/fixtures.bash` 的 `make_plan`）都写了 `Mode: tdd`，
`make_spec` 都写了 `execution_mode:`，`bash tests/run.sh` 与两份 `examples/*/try-it.sh` 全绿。

## 回归测试

`tests/regression/2026-09-07-task-evidence-lint-unknown-mode-silent-skip.bats`，五条，
双向：

| # | 方向 | 断言 |
|---|---|---|
| 1 | 正向 | 模式无法解析时退出码非 0 |
| 2 | 正向 | 输出含 `NOT verified` 且点名任务 ID |
| 3 | 正向 | 输出不得再出现 `0 fail(s)` |
| 4 | 反向 | tdd 任务带有效证据时仍然通过 |
| 5 | 反向 | plan 模式任务无 TDD 证据时仍然通过 |

第 3 条不是第 1 条的重复：只断退出码的话，把出口改成**无声** `exit 1` 也能让第 1 条绿，
而无声报红同样违反诚实性契约（收尾仍会说「1 completed task(s) checked」）。

第 4、5 两条反向断言是必需的——把整个模式分支改成无条件 `fail_msg` 也能让三条正向全绿。

**先红后绿实测**：修复前跑，1/2/3 红、4/5 绿（fixture 构造正确、既有路径未受影响）；
补 `else` 后 5/5 绿。

## 同批一并完成的相邻项

同一批还补齐了噪声清单规则 5 登记的另外五处 skip 出口文案
（`ac-coverage.sh` 两处、`drift-check.sh`、`spec-lint.sh`、`compliance.sh` 各一处），
契约单测在 `tests/unit/gate-skip-honesty.bats`。

那五处与本缺陷的区别：它们的**行为**是对的（确实没有可比较的工作量，skip 与 `exit 0`
都正确），缺的只是 stdout 上说不清「跳过了」还是「查过了是干净的」。因此归契约单测
（`unit/`）而不是回归（`regression/`），也不单独登记 bug 条目——按 `INDEX.md:27-29`
的对拍规则，一份 `-analysis.md` 会要求 `tests/regression/` 下有同名文件，而它们的
测试正确的归属是 `unit/`。

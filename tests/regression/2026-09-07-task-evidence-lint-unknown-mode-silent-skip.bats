#!/usr/bin/env bats
# Bug report: docs/bug_report/2026-09-07-task-evidence-lint-unknown-mode-silent-skip-analysis.md
# Root cause class: C. 失败方向搞反（H 的下游后果）
# Fixed by: 与本文件同一提交（见 git log -- tests/regression/2026-09-07-task-evidence-lint-unknown-mode-silent-skip.bats）
#
# `task-evidence-lint.sh` 的模式分支是 `if tdd / elif plan / fi`——**没有 else**。
# `effective_mode` 落到第三值时整段不执行：`FAILS`/`WARNS` 都不动，一行输出都没有，
# 而收尾照常打印「N completed task(s) checked」并 `✅ PASS`。该任务的模式维度静默消失，
# 正是 tests/README.md「门禁诚实性契约」要防的那种假绿。
#
# 第三值不需要任何漂移就能到达：`execution_mode()` 末行是 `${value:-unknown}`，
# spec front-matter 没有 `execution_mode:`、plan 没有 `Execution mode:` / `执行模式：`、
# 任务体没有 `Mode:` 时直接返回 `unknown`。噪声清单最初把它归为 `execution_mode` 多份
# 定义漂移（根因 H）的下游后果，实测门槛比那低得多——「三处都没声明」是纯粹的漏写。
#
# 发现路径：批次 3 meta-lint 上线前的存量噪声复核（见 analysis「发现路径」一节）。
#
# 双向断言：unknown 必须停止报绿并说出未验证（正向）；tdd 与 plan 两条既有路径
# 不得被这次改动一起打红（反向）。反向那两条是必需的——把模式分支改成无条件
# fail 也能让正向全绿。

load "../helpers/common"
load "../helpers/fixtures"

setup_file() {
  halo_require_tools
  halo_template_install
}

setup() {
  halo_sandbox_clone
}

# 完成 T1 并补齐 brief/review-package 两份证据，让「模式维度」成为唯一未判定项。
# 不补的话 T1 会因为缺这两份先红，正向断言就分不清红在哪个维度上。
complete_t1_with_base_evidence() { # <spec-id>
  local id="$1" plan="halo/specs/$1/plan.md"
  awk '{ sub(/^- \[ \] T1:/, "- [x] T1:"); print }' "$plan" > "$plan.tmp"
  mv "$plan.tmp" "$plan"
  mkdir -p ".halo/sdd/$id/T1"
  echo "# brief" > ".halo/sdd/$id/T1/brief.md"
  echo "# review package" > ".halo/sdd/$id/T1/review-package.md"
}

# 摘掉全部三处模式声明，把 effective_mode 逼成 unknown。
# 跨平台：`sed -i` 在 BSD/GNU 上语法不通用，一律改写到临时文件再 mv。
strip_all_mode_declarations() { # <spec-id>
  local id="$1" spec="halo/specs/$1/spec.md" plan="halo/specs/$1/plan.md"
  grep -v '^execution_mode:' "$spec" > "$spec.tmp"
  mv "$spec.tmp" "$spec"
  grep -v '^- Execution mode:' "$plan" | grep -v '^  - Mode: ' > "$plan.tmp"
  mv "$plan.tmp" "$plan"
}

# ── 正向：模式判不出来时不许再报绿 ──

@test "task-evidence-lint refuses to pass when a completed task has no resolvable mode" {
  make_spec halo/specs unknown-mode 1 1
  make_plan halo/specs unknown-mode 1 1
  strip_all_mode_declarations unknown-mode
  complete_t1_with_base_evidence unknown-mode

  run bash halo/kernel/orchestrator/sdd/task-evidence-lint.sh unknown-mode
  assert_failure
}

@test "task-evidence-lint says the mode dimension was NOT verified" {
  make_spec halo/specs unknown-mode 1 1
  make_plan halo/specs unknown-mode 1 1
  strip_all_mode_declarations unknown-mode
  complete_t1_with_base_evidence unknown-mode

  run bash halo/kernel/orchestrator/sdd/task-evidence-lint.sh unknown-mode
  assert_output --partial "NOT verified"
  assert_output --partial "T1"
}

# 「静默」本身要有断言：光断 exit code 的话，把出口改成无声 exit 1 也能绿，
# 而无声报红同样违反诚实性契约——收尾仍然会说「1 completed task(s) checked」。
@test "task-evidence-lint does not silently count an unresolved task as checked" {
  make_spec halo/specs unknown-mode 1 1
  make_plan halo/specs unknown-mode 1 1
  strip_all_mode_declarations unknown-mode
  complete_t1_with_base_evidence unknown-mode

  run bash halo/kernel/orchestrator/sdd/task-evidence-lint.sh unknown-mode
  refute_output --partial "0 fail(s)"
}

# ── 反向：两条既有路径不得被一起打红 ──

@test "task-evidence-lint still passes a tdd task that has valid evidence" {
  make_spec halo/specs tdd-mode 1 1
  make_plan halo/specs tdd-mode 1 1
  complete_t1_with_base_evidence tdd-mode
  cat > ".halo/sdd/tdd-mode/T1/tdd-evidence.json" << 'JSON'
{
  "kind": "tdd-evidence",
  "status": "pass",
  "ac_ids": ["AC-1"],
  "red": { "exit_code": 1 },
  "green": { "exit_code": 0 }
}
JSON

  run bash halo/kernel/orchestrator/sdd/task-evidence-lint.sh tdd-mode
  assert_success
  assert_output --partial "tdd-evidence.json"
}

@test "task-evidence-lint still passes a plan-mode task without TDD evidence" {
  make_spec halo/specs plan-mode 1 1 plan
  make_plan halo/specs plan-mode 1 1
  # make_plan 的任务体固定写 `Mode: tdd`，改成 plan 才测得到 plan 分支。
  awk '{ sub(/^  - Mode: tdd$/, "  - Mode: plan"); print }' halo/specs/plan-mode/plan.md > halo/specs/plan-mode/plan.md.tmp
  mv halo/specs/plan-mode/plan.md.tmp halo/specs/plan-mode/plan.md
  complete_t1_with_base_evidence plan-mode

  run bash halo/kernel/orchestrator/sdd/task-evidence-lint.sh plan-mode
  assert_success
  assert_output --partial "plan mode"
}

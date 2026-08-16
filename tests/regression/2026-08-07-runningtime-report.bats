#!/usr/bin/env bats
# Bug report: docs/bug_report/2026-08-07-runningtime-report/
#   （复核：docs/bug_report/2026-08-07-runningtime-report-analysis.md）
# Root cause class: A. 词法「提及≠声明」（第 5 次复发）+ H. 同一语义多份定义漂移
# Fixed by: 3e25d7e
#
# RED 任务收口反复报 `missing matching TDD cycle evidence`，主代理花了约 16 次往返
# 才定位到：plan 任务的**散文正文**里提到了某个 AC 编号——而且是**否定句**
# 「本任务不覆盖 AC-3」——门禁把它当成覆盖声明，强加了红绿证据义务。
#
# 修复引入结构化覆盖声明行（`覆盖验收：` / `Covers:`）与三个共享谓词：
# ac_declaration_lines / task_has_ac_declaration / task_covered_acs。
# 有声明行时只读声明行；没有声明行时才回退到任务全文扫描（存量 plan 的兼容路径）。
# 独立评审轮还发现 plan-lint 的 warn 条件与门禁的回退条件曾经漂移
# （前者只判「无声明行」，后者判「无声明行**或**声明行不含 AC token」），
# 现在两侧共用 task_has_ac_declaration——这就是本文件末两条用例守的东西。
#
# 旧段（smoke-test:1567-1770）是一条 12 步的时间线，一条断言失败后面全塌。
# 这里每条用例自建前置：bats 每用例独立沙箱，前置写成可读的散文，可单跑可归因。
#
# fixture 见 tests/fixtures/ac/declaration-line/。

load "../helpers/common"
load "../helpers/fixtures"

setup_file() {
  halo_require_tools
  halo_template_install
}

setup() {
  halo_sandbox_clone
  halo_install_fixture ac/declaration-line
}

# ── 前置构造函数 ──────────────────────────────────────────────
# 只服务本文件，不进 helpers：进了 helpers 就会变成下一个「谁在用它」的谜团。

write_evidence() { # <task-id> <ac> <test-name> <test-file>
  bash halo/kernel/orchestrator/sdd/tdd-evidence.sh decl-line-ac "$1" \
    --ac="$2" \
    --test="$3" \
    --test-file="$4" \
    --red-command="go test ./internal/handler -run $3" \
    --red-exit=1 \
    --red-summary="handler not implemented" \
    --green-command="go test ./internal/handler -run $3" \
    --green-exit=0 \
    --green-summary="focused AC test passes" \
    --refactor=none > /dev/null 2>&1
}

decl_evidence_ac1() { write_evidence RED-1 AC-1 TestDeclAC1 internal/handler/item_test.go; }
# AC-2 的证据刻意落在 T1 目录：RED 门禁扫的是整棵 spec 证据树，不是任务自己的目录。
decl_evidence_ac2() { write_evidence T1 AC-2 TestDeclAC2 internal/handler/item_test.go; }
decl_evidence_ac3() { write_evidence RED-2 AC-3 TestDeclAC3 internal/handler/item_list_test.go; }

decl_complete() { # <task-id>
  run bash halo/kernel/orchestrator/sdd/task-complete.sh decl-line-ac "$1"
  assert_success
}

# ── 覆盖声明行的正反两向 ──────────────────────────────────────

@test "task-complete names the exact ACs lacking cycle evidence" {
  decl_evidence_ac1
  run bash halo/kernel/orchestrator/sdd/task-complete.sh decl-line-ac RED-1
  assert_failure
  assert_output --partial "RED-1 missing matching TDD cycle evidence"
  # 只说「缺证据」不够：修复的一半价值是把缺哪条 AC 说清楚，
  # 否则又要靠人肉二分去找（这正是上报里那 16 次往返的成因）。
  assert_output --partial "missing: AC-2"
}

@test "task-complete --json carries covered_acs and missing_acs" {
  decl_evidence_ac1
  run bash halo/kernel/orchestrator/sdd/task-complete.sh decl-line-ac RED-1 --json
  run yq -e '.status == "fail"
    and (.covered_acs | join(",")) == "AC-1,AC-2"
    and (.missing_acs | join(",")) == "AC-2"' <<< "$output"
  assert_success
}

@test "a prose AC mention creates no obligation when a declaration line exists" {
  decl_evidence_ac1
  decl_evidence_ac2
  # RED-1 的声明行是 AC-1, AC-2；散文里的否定句「本任务不覆盖 AC-3」不得产生义务。
  decl_complete RED-1
  run grep -cE '^- \[x\] RED-1:' halo/specs/decl-line-ac/plan.md
  assert_output "1"
}

@test "task-next --task narrows declaration-line ACs to this spec" {
  decl_evidence_ac1
  decl_evidence_ac2
  decl_complete RED-1
  # RED-2 的声明行写的是 `Covers: AC-3, AC-14`，AC-14 属上游 spec，必须被收窄掉。
  run bash halo/kernel/orchestrator/sdd/task-next.sh decl-line-ac --task=RED-2 --json
  assert_success
  run yq -e '.kind == "task-next" and .status == "selected" and .complete == false
    and (.ac_refs | join(",")) == "AC-3"' <<< "$output"
  assert_success
}

@test "task-complete accepts a declaration line carrying a cross-spec AC" {
  decl_evidence_ac1
  decl_evidence_ac2
  decl_complete RED-1
  decl_evidence_ac3
  decl_complete RED-2
  run grep -cE '^- \[x\] RED-2:' halo/specs/decl-line-ac/plan.md
  assert_output "1"
}

@test "task-next --all lists every task with completion state" {
  decl_evidence_ac1
  decl_evidence_ac2
  decl_complete RED-1
  decl_evidence_ac3
  decl_complete RED-2
  run bash halo/kernel/orchestrator/sdd/task-next.sh decl-line-ac --all --json
  assert_success
  # 三个任务的完成状态全断言：前置已确定性地完成 RED-1 与 RED-2，
  # 旧断言只查了首尾两个，中间那个漏掉的恰好是「已完成」的一侧。
  run yq -e '.kind == "task-list" and (.tasks | length == 3)
    and .tasks[0].task_id == "RED-1" and .tasks[0].complete == true
    and .tasks[1].task_id == "RED-2" and .tasks[1].complete == true
    and .tasks[2].task_id == "T1" and .tasks[2].complete == false' <<< "$output"
  assert_success
}

# ── task-next 的 CLI 契约（与声明行同批引入，无状态前置）──────

@test "task-next --task reports not-found with a non-zero exit" {
  run bash halo/kernel/orchestrator/sdd/task-next.sh decl-line-ac --task=T99 --json
  assert_failure
  run yq -e '.status == "not-found"' <<< "$output"
  assert_success
}

@test "task-next default next-task selection is unchanged by the new flags" {
  decl_evidence_ac1
  decl_evidence_ac2
  decl_complete RED-1
  decl_evidence_ac3
  decl_complete RED-2
  run bash halo/kernel/orchestrator/sdd/task-next.sh decl-line-ac --json
  assert_success
  run yq -e '.kind == "task-next" and .status == "next" and .task_id == "T1"' <<< "$output"
  assert_success
}

@test "task-next rejects an empty --task= value" {
  run bash halo/kernel/orchestrator/sdd/task-next.sh decl-line-ac --task=
  assert_failure
  assert_output --partial "Invalid task id"
}

# ── plan-lint 与门禁必须共用同一个「有没有声明行」谓词 ─────────

@test "plan-lint passes a declaration-line plan without a fallback warning" {
  run bash halo/kernel/orchestrator/sdd/plan-lint.sh decl-line-ac
  assert_success
  refute_output --partial "no 覆盖验收/Covers line"
}

@test "plan-lint warns without failing when a task has no declaration line" {
  # 存量 Ref: 风格的 plan 现造，不借用别处的 fixture：
  # 被测语义是「任务没有声明行」，与那份 fixture 的其他特征无关。
  make_spec halo/specs ref-plan 2
  make_plan halo/specs ref-plan 2 1 ref
  run bash halo/kernel/orchestrator/sdd/plan-lint.sh ref-plan
  assert_success
  assert_output --partial "no 覆盖验收/Covers line"
}

@test "a declaration line without AC ids warns and falls back to the whole-body scan" {
  # 声明行是「覆盖验收：以下条目补充说明」——有标签但不含任何 AC token。
  # 这是 plan-lint 的 warn 条件与门禁的回退条件必须一致的那条边界：
  # 两侧只要有一侧把它算作「有声明」，就会重演谓词漂移。
  run bash halo/kernel/orchestrator/sdd/plan-lint.sh decl-warn-ac
  assert_success
  assert_output --partial "no 覆盖验收/Covers line"

  run bash halo/kernel/orchestrator/sdd/task-next.sh decl-warn-ac --task=T1 --json
  assert_success
  run yq -e '(.ac_refs | join(",")) == "AC-1"' <<< "$output"
  assert_success
}

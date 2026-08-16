#!/usr/bin/env bats
# 门禁行为单测：ac-coverage.sh 的出口语义（退出码 + gate JSON 契约）。
# 不绑定某份 bug 报告，所以放 unit/ 而不是 regression/。
#
# 消费方清单（改这些断言前先看爆炸半径）：
#   - halo/kernel/delivery/pipeline.sh —— 全量管道与 --only=ac-coverage 两条路径
#   - halo/kernel/orchestrator/sdd/summary-draft.sh —— 读 gate JSON 的 metrics 渲染摘要
#   - tests/release-check.sh —— 发版前的门禁总检
#
# 迁移自 smoke-test §7（本批次删除），并收紧了一处宽松兜底：旧断言的 else 分支是
# `pass "ac-coverage ran (exit=$AC_EXIT)"` —— 任何非 0 非 1 的退出码（包括崩溃）
# 都被记为通过。那是把缺陷行为固化成期望值，不迁移。

load "../helpers/common"
load "../helpers/fixtures"

setup_file() {
  halo_require_tools
  halo_template_install
}

setup() {
  halo_sandbox_clone
  # Go 项目 + 零测试文件：两条 AC 都无从证实。
  make_spec halo/specs uncovered-go 2
}

@test "ac-coverage exits 1 and names uncovered ACs when no tests exist" {
  run bash halo/kernel/delivery/gates/ac-coverage.sh halo/specs/uncovered-go/spec.md .
  assert_failure 1
  assert_output --partial "uncovered: AC-1 AC-2"
}

@test "ac-coverage --json-out writes ac_total, ac_uncovered and per-AC findings" {
  run bash halo/kernel/delivery/gates/ac-coverage.sh halo/specs/uncovered-go/spec.md . \
    --json-out="$SANDBOX/ac-coverage.json"
  assert_failure 1
  run yq -e '.gate == "ac-coverage"
    and .status == "fail"
    and .metrics.ac_total == 2
    and .metrics.ac_uncovered == 2
    and (.findings | length == 2)' "$SANDBOX/ac-coverage.json"
  assert_success
}

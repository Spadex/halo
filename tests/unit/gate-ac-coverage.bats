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

@test "the numeric fallback does not treat this spec's own declared test as foreign-owned" {
  # 闭合批次 1 计划 496-502 行记录的空洞：build_foreign_owned（ac-coverage.sh:137-146）
  # 用 `[[ "$f" -ef "$SPEC" ]] && continue`（:142）自跳过本 spec，避免把本 spec 自己
  # 在 AC-1 行声明的测试函数，当成"外部 spec 拥有"从而在 AC-2 的数字兜底里被误扣。
  # AC-1 走 Tier 1（声明命中 TestAC2Combined）；AC-2 无声明，走 Tier 2 数字兜底，
  # 候选集只有 TestAC2Combined 这一个，如果 :142 的自跳过失效，候选会被
  # FOREIGN_OWNED 扣光，AC-2 从 covered 变 uncovered。
  make_spec halo/specs self-decl 2
  mkdir -p internal/handler
  cat > internal/handler/item_test.go << 'GO'
package handler
func TestAC2Combined(t *testing.T) {}
GO
  # AC-1 的验证单元格改成声明这个函数；AC-2 的单元格改成非测试标识符。
  local tmp
  tmp="$(mktemp)"
  sed -e 's/| TestAC1 |/| TestAC2Combined |/' -e 's/| TestAC2 |/| manual review |/' \
    halo/specs/self-decl/spec.md > "$tmp" && mv "$tmp" halo/specs/self-decl/spec.md

  run bash halo/kernel/delivery/gates/ac-coverage.sh halo/specs/self-decl/spec.md . \
    --json-out="$SANDBOX/ac-coverage.json"
  assert_success

  run yq -r -e '.findings[] | select(.ac == "AC-2") | .status' "$SANDBOX/ac-coverage.json"
  assert_success
  assert_output "covered"
}

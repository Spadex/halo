#!/usr/bin/env bats
# Bug report: docs/bug_report/2026-08-25-compliance-missing-spec-fail-open-analysis.md
# Root cause class: C. fail-open / fail-closed 方向搞反
# Fixed by: 与本文件同一提交（见 git log -- tests/regression/2026-08-25-compliance-missing-spec-fail-open.bats）
#
# 四个门禁解析 spec 的结构逐字同型：先是自动发现分支（找不到候选 → 报 skip、exit 0），
# 然后一行顶层的 `[[ -f "$SPEC" ]]` 守卫，兜住「路径明确给了但文件不存在」。
# ac-coverage.sh:43 / drift-check.sh:41 / spec-lint.sh:20 这一行都是 exit 1，
# 唯独 compliance.sh:42 是 **exit 0** —— 门禁在拿不到 spec 的情况下报绿。
#
# 两个分支必须分清：`:38` 是自动发现一个候选都没有（四个门禁一致 skip，不动它），
# `:42` 是调用方点名了一个不存在的文件。后者不是「没什么可查」，是「要查的东西不在」，
# 报绿等于把 AGENTS.md Gate Rules 的「没比较过就得报未验证」反着执行。
#
# 发现路径：批次 3 meta-lint 上线前的存量噪声复核（见 analysis「发现路径」一节）。
# 该分支此前**没有任何测试覆盖**——这既是它活下来的原因，也是本文件存在的理由。
#
# 两个方向都要断言：不存在的 spec 必须报红（正向），存在的 spec 不得因为这次改动
# 被一起打红（反向）。第三条把四个门禁摆在一起断齐平，防的是同一处再次单边漂移。

load "../helpers/common"
load "../helpers/fixtures"

setup_file() {
  halo_require_tools
  halo_template_install
}

setup() {
  halo_sandbox_clone
}

# ── 正向：点名一个不存在的 spec，必须报红 ──

@test "compliance refuses a spec path that does not exist" {
  run bash halo/kernel/delivery/gates/compliance.sh "$SANDBOX/halo/specs/absent/spec.md"
  assert_failure
}

@test "compliance says which spec it could not find" {
  run bash halo/kernel/delivery/gates/compliance.sh "$SANDBOX/halo/specs/absent/spec.md"
  assert_output --partial "not found"
  assert_output --partial "absent/spec.md"
}

# ── 反向：不得把正常路径一起打红 ──
# 缺了这条，把 :42 改成无条件 exit 1 也能让上面两条绿。

@test "compliance still passes a spec that does exist" {
  make_spec halo/specs present-spec
  run bash halo/kernel/delivery/gates/compliance.sh halo/specs/present-spec/spec.md
  assert_success
}

# ── 齐平：四个门禁对同一情况必须给同一个方向 ──
# 一条用例遍历四个门禁，而不是四份手写副本——手写副本本身就是根因 H
# （同一逻辑多处定义后单边漂移），而单边漂移正是本 bug 的成因。
# 形态照 tests/unit/lib-find-spec.bats 的 ambiguous 齐平用例。

@test "every spec-taking gate refuses a missing spec file instead of reporting green" {
  local absent="$SANDBOX/halo/specs/absent/spec.md"
  local names=(ac-coverage drift-check spec-lint compliance)
  local cmds=(
    "halo/kernel/delivery/gates/ac-coverage.sh $absent ."
    "halo/kernel/delivery/gates/drift-check.sh $absent ."
    "halo/kernel/delivery/gates/spec-lint.sh $absent"
    "halo/kernel/delivery/gates/compliance.sh $absent"
  )

  local i name cmd
  for i in "${!names[@]}"; do
    name="${names[$i]}"
    cmd="${cmds[$i]}"
    run bash -c "$cmd"
    [ "$status" -ne 0 ] || fail "gate=$name: expected a non-zero exit code for a missing spec, got 0"
    [[ "$output" == *"not found"* ]] || fail "gate=$name: expected output to say the spec was not found, got: $output"
  done
}

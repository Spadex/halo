#!/usr/bin/env bats
# 门禁跳过出口的诚实性契约（AGENTS.md:86-87 / tests/README.md「门禁诚实性契约」）。
#
# 被测对象是**出口文案**：一个门禁在退出前没比较过任何东西时，必须在 stdout 上说出
# 「未验证」，而不是只留一句 `skipping` 让读者自己推断。`drift-check.sh` 的 `gate_skip()`
# 早就是这么做的（`:576` 的收尾行明写 `NOT verified`），但四个门禁的 spec 发现失败出口
# 和 ac-coverage 的「spec 里一个 AC 都没有」出口都停在 `skipping` / `No AC numbers found`
# 上——`exit 0` 加一句 `skipping`，与「查过了，是干净的」在 stdout 上无从分辨。
#
# 分层归属（tests/README.md「契约单测 vs 回归的分层判据」）：这里断的是门禁自身的
# **出口契约**（退出码 + 输出形状），不是某个算法为什么这么算，故归 `unit/`。
# 本文件不得出现断言算法脚本排序键、mtime 行为、字段比较的用例——那些归 `regression/`。
#
# 齐平用例是主体：四个门禁的这段 `find_spec` 失败分支逐字同型，单边漂移正是根因 H
# 与根因 C 的交点（参见 regression/2026-08-25-compliance-missing-spec-fail-open.bats）。
# 逐个手写副本等于把同一个漂移风险再造一次。

load "../helpers/common"
load "../helpers/fixtures"

setup_file() {
  halo_require_tools
  halo_template_install
}

setup() {
  halo_sandbox_clone
}

# ── 正向：跳过时必须说出「未验证」 ──

@test "every spec-taking gate reports NOT verified when no spec is discoverable" {
  # 沙箱刚 init，halo/specs 下没有任何 spec —— 四个门禁都会走 find_spec 失败分支。
  local names=(ac-coverage drift-check spec-lint compliance)
  local cmds=(
    "halo/kernel/delivery/gates/ac-coverage.sh"
    "halo/kernel/delivery/gates/drift-check.sh"
    "halo/kernel/delivery/gates/spec-lint.sh"
    "halo/kernel/delivery/gates/compliance.sh"
  )

  local i name cmd
  for i in "${!names[@]}"; do
    name="${names[$i]}"
    cmd="${cmds[$i]}"
    run bash -c "$cmd"
    # 跳过语义本身不变：找不到 spec 不是失败，是没有可比较的工作量。
    [ "$status" -eq 0 ] || fail "gate=$name: expected exit 0 for the skip branch, got $status: $output"
    [[ "$output" == *"NOT verified"* ]] \
      || fail "gate=$name: skip output must say NOT verified, got: $output"
  done
}

@test "ac-coverage reports NOT verified when the spec declares no AC" {
  make_spec halo/specs no-ac
  # 摘掉 AC 表的数据行，spec 结构完好但一个 AC 号都没有。
  # 跨平台：`sed -i` 在 BSD/GNU 上语法不通用，改写到临时文件再 mv。
  grep -v '^| AC-' halo/specs/no-ac/spec.md > halo/specs/no-ac/spec.md.tmp
  mv halo/specs/no-ac/spec.md.tmp halo/specs/no-ac/spec.md

  run bash halo/kernel/delivery/gates/ac-coverage.sh halo/specs/no-ac/spec.md .
  assert_success
  assert_output --partial "NOT verified"
}

# ── 反向：不得把「未验证」无条件打进输出 ──
# 缺这条，在每个门禁开头无条件 echo 一句 NOT verified 也能让上面两条全绿。

@test "a gate that actually compared something does not claim NOT verified" {
  make_spec halo/specs real-spec

  run bash halo/kernel/delivery/gates/spec-lint.sh halo/specs/real-spec/spec.md
  assert_success
  refute_output --partial "NOT verified"
}

@test "ac-coverage does not claim NOT verified when the spec has AC numbers" {
  make_spec halo/specs real-spec

  run bash halo/kernel/delivery/gates/ac-coverage.sh halo/specs/real-spec/spec.md .
  refute_output --partial "NOT verified"
}

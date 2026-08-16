#!/usr/bin/env bats
# 验证 fixture 构造函数产物能通过真实门禁：
# 构造函数是后续所有迁移用例的地基，它自身跑偏会让整个语料库失真。

load "../helpers/common"
load "../helpers/fixtures"

setup_file() {
  halo_require_tools
  halo_template_install
}

setup() {
  halo_sandbox_clone
}

@test "make_spec default passes spec-lint and prismspec lint" {
  make_spec halo/specs fixture-default
  run bash halo/kernel/delivery/gates/spec-lint.sh halo/specs/fixture-default/spec.md
  assert_success
  run bash prismspec/bin/lint.sh halo/specs/fixture-default/spec.md spec
  assert_success
}

@test "make_spec with non-1 start passes without false AC gap" {
  make_spec halo/specs fixture-global 2 12
  run bash halo/kernel/delivery/gates/spec-lint.sh halo/specs/fixture-global/spec.md
  assert_success
  refute_output --partial "AC number gaps"
}

@test "make_plan matching make_spec passes plan-lint and prismspec lint" {
  make_spec halo/specs fixture-plan
  make_plan halo/specs fixture-plan
  run bash halo/kernel/orchestrator/sdd/plan-lint.sh fixture-plan
  assert_success
  run bash prismspec/bin/lint.sh halo/specs/fixture-plan plan
  assert_success
}

@test "make_spec honours ac_count" {
  make_spec halo/specs fixture-many 4
  run grep -c '^| AC-' halo/specs/fixture-many/spec.md
  assert_output "4"
}

# make_plan 的三种任务体形态都必须被 plan-lint 判为合法。
# ref 是存量形态（无覆盖声明行，门禁回退到全文扫描，plan-lint 出 warning 但不 fail）；
# decl-cn / decl-en 是现行形态（有声明行，不该出 warning）。
# 断言 warning 的有无而不只是退出码：三者的退出码都是 0，只有 warning 能区分它们。

@test "make_plan decl-cn emits a Chinese declaration line accepted by plan-lint" {
  make_spec halo/specs fixture-decl-cn
  make_plan halo/specs fixture-decl-cn 2 1 decl-cn
  run bash halo/kernel/orchestrator/sdd/plan-lint.sh fixture-decl-cn
  assert_success
  refute_output --partial "no 覆盖验收/Covers line"
}

@test "make_plan decl-en emits a Covers line accepted by plan-lint" {
  make_spec halo/specs fixture-decl-en
  make_plan halo/specs fixture-decl-en 2 1 decl-en
  run bash halo/kernel/orchestrator/sdd/plan-lint.sh fixture-decl-en
  assert_success
  refute_output --partial "no 覆盖验收/Covers line"
}

@test "make_plan ref keeps the legacy fallback shape" {
  make_spec halo/specs fixture-ref
  make_plan halo/specs fixture-ref 2 1 ref
  run bash halo/kernel/orchestrator/sdd/plan-lint.sh fixture-ref
  assert_success
  assert_output --partial "no 覆盖验收/Covers line"
}

@test "make_plan rejects an unknown style instead of falling back silently" {
  make_spec halo/specs fixture-bad-style
  run make_plan halo/specs fixture-bad-style 2 1 nonsense
  assert_failure
  assert_output --partial "nonsense"
}

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

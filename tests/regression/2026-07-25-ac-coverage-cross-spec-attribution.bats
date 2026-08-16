#!/usr/bin/env bats
# Bug report: docs/bug_report/ac-coverage-bug/
#   （历史命名，目录形式且无 -analysis.md；映射见 docs/bug_report/INDEX.md）
# Root cause class: A. 词法「提及≠声明」+ F. 语法变体覆盖不足
# Fixed by: f60637d
#
# 一个 monorepo 里两个 spec 共用同一个测试目录，测试函数同号（都叫 test_acN_*）。
# 修复前 ac-coverage 把每条 AC 匹配到**全仓任意**函数名含该 AC 号的测试，
# 于是 layout-migration 的 AC-4..AC-9 全部被 data-sync 的测试「覆盖」了——
# 门禁报 19/19 100% PASS，spec 随即被标成 verified。
#
# **误绿比误红危险得多**：误红会被人当场怼回来，误绿会一路放行到发布。
#
# 修复引入两级归属：
#   Tier 1 —— AC 行最后一个非空单元格里声明的**精确函数名**，找不到就是未覆盖；
#   Tier 2 —— 无声明时按 AC 号回退，但先用 comm -23 扣掉**兄弟 spec 已声明**的函数名，
#             扣完剩多个候选算「跨 spec 歧义」，同样判未覆盖。
# 一句话：无法证实的覆盖现在 fail，不再静默 pass。
#
# 迁移自 tests/ac-coverage-test.sh（本批次删除）。两处改动：
#   1. 沙箱改用真实 install + init 产出的 manifest，不再手写一份为通过测试而裁剪的
#      配置——「框架读不懂自带模板」（根因 E）已复发 4 处，手写 manifest 正是让这类
#      缺陷隐形的做法；
#   2. gate JSON 用 yq 读，不再内嵌 python3 解析器，套件因此少一个运行前置。
#
# fixture 见 tests/fixtures/ac/cross-spec-attribution/。

load "../helpers/common"

setup_file() {
  halo_require_tools
  halo_template_install
}

setup() {
  halo_sandbox_clone
  halo_set_language python
  halo_install_fixture ac/cross-spec-attribution
}

run_gate() { # <spec-id>
  run bash halo/kernel/delivery/gates/ac-coverage.sh \
    "halo/specs/$1/spec.md" . --json-out="$SANDBOX/$1.json"
}

finding() { # <spec-id> <ac> <field>
  run yq -r ".findings[] | select(.ac == \"$2\") | .$3" "$SANDBOX/$1.json"
}

# ── alpha：AC-3 没有自己的测试，只有 beta 有同号的 test_ac3_beta_prune ──

@test "alpha gate fails when an AC has no spec-owned test" {
  run_gate spec-alpha
  assert_failure
}

@test "alpha AC-1 resolves to alpha's own declared test" {
  run_gate spec-alpha
  finding spec-alpha AC-1 test
  assert_output "test_ac1_alpha_thing"
}

@test "alpha AC-3 is uncovered, never borrowed from beta" {
  run_gate spec-alpha
  finding spec-alpha AC-3 status
  assert_output "uncovered"
}

# ── beta：三条 AC 各有自己的测试，必须放行且归属正确 ──
# 反向：修复不能退化成「跨 spec 一律判未覆盖」。

@test "beta gate passes when every AC owns its test" {
  run_gate spec-beta
  assert_success
}

@test "beta AC-1 resolves to beta's own test" {
  run_gate spec-beta
  finding spec-beta AC-1 test
  assert_output "test_ac1_beta_export"
}

@test "beta AC-3 resolves to beta's own test" {
  run_gate spec-beta
  finding spec-beta AC-3 test
  assert_output "test_ac3_beta_prune"
}

# ── Tier 1 反向（本批次新增）──
# 声明了一个不存在的测试名时，必须判未覆盖，不许悄悄落回 Tier 2 的数字兜底
# ——那等于把「声明」降级成建议，本 bug 就会从另一扇门回来。

@test "a declared test that does not exist is uncovered, not silently satisfied" {
  halo_install_fixture ac/cross-spec-attribution-absent-decl
  run_gate spec-beta
  assert_failure
  finding spec-beta AC-3 status
  assert_output "uncovered"
  finding spec-beta AC-3 message
  assert_output --partial "declared test"
}

#!/usr/bin/env bats
# Bug report: docs/bug_report/spec-lint-ac-gap-analysis.md
#   （历史命名例外：该文件本身就是上报方写的复核，没有配对的原文；映射见 docs/bug_report/INDEX.md）
# Root cause class: A. 词法「提及≠声明」
# Fixed by: 334bdb6
#
# 两个缺陷叠加：
#   ① 取数扫全文，把散文交叉引用（「现有 AC-3/7/8/9/10/11 不回归」）当成声明；
#   ② 连续性判定硬假设「必须从 1 起、1..N 连续」。
# 于是一份内部连续的 AC-12..22 spec 被报 `AC number gaps: 1 4`，卡死整条 pipeline。
#
# 修复后：数据源是表格首列，连续性只要求**相邻差为 1**，起点可以非 1
# （前端增量 spec 沿用全局 AC 编号，好让桥接测试的函数名不撞车）。
# 真正的内部断号必须仍被抓住——否则这次放宽就把门禁放瞎了。

load "../helpers/common"
load "../helpers/fixtures"

setup_file() {
  halo_require_tools
  halo_template_install
}

setup() {
  halo_sandbox_clone
}

apply() { # <file> <filter-cmd...>
  local f="$1"
  shift
  "$@" < "$f" > "$f.new" && mv "$f.new" "$f"
}

lint() { # <spec-id>
  run bash halo/kernel/delivery/gates/spec-lint.sh "halo/specs/$1/spec.md"
}

@test "a non-1 start with contiguous ACs reports no gap" {
  make_spec halo/specs global-ac 2 12
  lint global-ac
  assert_success
  refute_output --partial "AC number gaps"
  assert_output --partial "AC numbers sequential (12-13)"
}

@test "an in-cell reference to a lower AC creates no phantom gap" {
  make_spec halo/specs global-xref-ac 2 12
  apply halo/specs/global-xref-ac/spec.md sed 's/| Result 13 |/| Result 13 (see AC-3) |/'
  lint global-xref-ac
  assert_success
  refute_output --partial "AC number gaps"
  assert_output --partial "2 ACs found"
}

@test "a real internal AC gap is still reported" {
  make_spec halo/specs real-gap-ac 2 12
  apply halo/specs/real-gap-ac/spec.md sed 's/| AC-13 |/| AC-14 |/'
  lint real-gap-ac
  assert_failure
  assert_output --partial "AC number gaps: 13"
}

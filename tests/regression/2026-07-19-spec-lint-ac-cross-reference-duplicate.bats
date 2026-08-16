#!/usr/bin/env bats
# Bug report: docs/bug_report/spec-lint-ac-cross-reference-duplicate.md
#   （历史命名，未按 YYYY-MM-DD-<slug>.md；映射见 docs/bug_report/INDEX.md）
# Root cause class: A. 词法「提及≠声明」
# Fixed by: 45d5f7f
#
# spec-lint 曾从 AC 表整行抽 AC token 做查重：某条 AC 的 Then 单元格里写了
# 「见 AC-13」，AC-13 就凭空出现两次，spec-lint 报 `Duplicate AC rows: AC-13`
# 卡死整条 pipeline，而 AC-13 在表里只定义了一次。
#
# 修复把行键收窄为**每行第一个单元格**（_lib.sh 的 spec_declared_acs）。
# 单元格内与散文里的交叉引用都不再是声明。

load "../helpers/common"
load "../helpers/fixtures"

setup_file() {
  halo_require_tools
  halo_template_install
}

setup() {
  halo_sandbox_clone
}

# 就地改写：不用 sed -i（BSD 与 GNU 的 -i 后缀语义不同）。
apply() { # <file> <filter-cmd...>
  local f="$1"
  shift
  "$@" < "$f" > "$f.new" && mv "$f.new" "$f"
}

lint() { # <spec-id>
  run bash halo/kernel/delivery/gates/spec-lint.sh "halo/specs/$1/spec.md"
}

@test "in-cell AC cross-reference is not a duplicate row" {
  make_spec halo/specs xref-ac
  apply halo/specs/xref-ac/spec.md sed 's/| Result 2 |/| Result 2 (see AC-1) |/'
  lint xref-ac
  assert_success
  refute_output --partial "Duplicate AC rows"
  assert_output --partial "2 ACs found"
}

@test "a genuinely duplicated AC row is still reported" {
  make_spec halo/specs dup-ac
  # 复制 AC-2 整行造真重复。BSD sed 的替换串不支持 \n，复制行一律用 awk。
  apply halo/specs/dup-ac/spec.md awk '/^\| AC-2 \|/ { print; print; next } { print }'
  lint dup-ac
  assert_failure
  assert_output --partial "Duplicate AC rows: AC-2"
}

@test "a prose AC mention outside the table is not declared" {
  make_spec halo/specs prose-ac
  apply halo/specs/prose-ac/spec.md \
    sed 's/^Add a small behavior with AC tracing\.$/Add a small behavior with AC tracing. 现有 AC-7\/AC-8 不回归。/'
  lint prose-ac
  assert_success
  # 散文里的 AC-7\/AC-8 若被当成声明，计数会变 4 且 AC-2 与 AC-7 之间出现断号。
  assert_output --partial "2 ACs found"
  refute_output --partial "AC number gaps"
}

#!/usr/bin/env bats
# 契约单测：_lib.sh 的 AC 声明源。不经过任何门禁直接调用。
#
# spec_declared_acs(:200-204) 的调用方（4 处）：
#   gates/ac-coverage.sh:152 · gates/spec-lint.sh:141
#   orchestrator/sdd/summary-draft.sh:101 · _lib.sh:217（narrow_acs_to_declared 内部）
# narrow_acs_to_declared(:213-220) 的调用方（3 处）：
#   orchestrator/sdd/plan-lint.sh:169 · _lib.sh:256/:258（task_covered_acs 两条分支）
#
# 根因 A 复发 5 次（#7 → #8 → #9 → #14 → runningtime）。设计文档把
# 「A 类的机器防线」定义为对这两个函数的契约单测——就是本文件。

bats_require_minimum_version 1.5.0

load "../helpers/common"
load "../helpers/fixtures"

setup_file() {
  halo_require_tools
  halo_template_install
}

setup() {
  halo_sandbox_clone
}

# 必须走子进程：_lib.sh:79-82 定义的 fail() 与
# tests/vendor/bats-support/src/error.bash:38 的 fail()、skip() 与
# tests/vendor/bats-core/lib/bats-core/test_functions.bash:437 的 bats 内建
# skip() 同名。把 _lib.sh source 进 bats 测试进程会替换掉 assert_* 的失败原语，
# 所有断言永不变红——全绿的假绿。
lib_run() { # <bash 片段>
  run --separate-stderr bash -c 'source halo/kernel/_lib.sh; eval "$1"' _ "$1"
}

@test "spec_declared_acs takes only the first cell of each AC row" {
  make_spec halo/specs alpha

  # AC-2 行的 Then 单元格塞一条交叉引用；只取每行第一个单元格，
  # 不应该把 AC-14 也算进来。
  local tmp
  tmp="$(mktemp)"
  sed -E 's/(\| AC-2 \| Step 2 \| Result 2)( \|)/\1 (see AC-14)\2/' \
    "$SANDBOX/halo/specs/alpha/spec.md" > "$tmp" && mv "$tmp" "$SANDBOX/halo/specs/alpha/spec.md"

  lib_run 'spec_declared_acs halo/specs/alpha/spec.md'
  assert_success
  assert_output "$(printf 'AC-1\nAC-2')"
}

@test "spec_declared_acs keeps file order and duplicates" {
  make_spec halo/specs alpha

  # 复制一整行必须用 awk：BSD sed 的替换串不支持 \n。
  local tmp
  tmp="$(mktemp)"
  awk '/^\| AC-2 \|/ { print; print; next } { print }' \
    "$SANDBOX/halo/specs/alpha/spec.md" > "$tmp" && mv "$tmp" "$SANDBOX/halo/specs/alpha/spec.md"

  lib_run 'spec_declared_acs halo/specs/alpha/spec.md'
  assert_success
  assert_output "$(printf 'AC-1\nAC-2\nAC-2')"
}

@test "spec_declared_acs ignores an AC token in prose outside the table" {
  make_spec halo/specs alpha
  printf '\n本 spec 不覆盖 AC-9。\n' >> "$SANDBOX/halo/specs/alpha/spec.md"

  lib_run 'spec_declared_acs halo/specs/alpha/spec.md'
  assert_success
  refute_output --partial "AC-9"
}

@test "spec_declared_acs requires at least one digit after AC-" {
  make_spec halo/specs alpha

  local tmp
  tmp="$(mktemp)"
  awk '/^\| AC-2 \|/ { print "| AC- | Step X | Result X | TestACX |"; print; next } { print }' \
    "$SANDBOX/halo/specs/alpha/spec.md" > "$tmp" && mv "$tmp" "$SANDBOX/halo/specs/alpha/spec.md"

  lib_run 'spec_declared_acs halo/specs/alpha/spec.md'
  assert_success
  assert_output "$(printf 'AC-1\nAC-2')"
}

@test "spec_declared_acs on a missing file returns 0 with no output" {
  lib_run 'spec_declared_acs no/such/spec.md'
  assert_success
  assert_output ""
}

@test "spec_declared_acs on a spec with no AC table returns 0 with no output" {
  mkdir -p "$SANDBOX/halo/specs/notable"
  printf '# no table here\n' > "$SANDBOX/halo/specs/notable/spec.md"

  lib_run 'spec_declared_acs halo/specs/notable/spec.md'
  assert_success
  assert_output ""
}

@test "narrow_acs_to_declared drops an AC the spec does not declare" {
  make_spec halo/specs alpha

  lib_run 'narrow_acs_to_declared "AC-1 AC-14" halo/specs/alpha/spec.md'
  assert_success
  assert_output "AC-1"
}

@test "narrow_acs_to_declared falls back to the raw token set when the spec declares nothing" {
  mkdir -p "$SANDBOX/halo/specs/notable"
  printf '# no table here\n' > "$SANDBOX/halo/specs/notable/spec.md"

  lib_run 'narrow_acs_to_declared "AC-1 AC-14" halo/specs/notable/spec.md'
  assert_success
  assert_output "$(printf 'AC-1\nAC-14')"
}

@test "narrow_acs_to_declared returns 0 with no output when the text has no AC token" {
  make_spec halo/specs alpha

  lib_run 'narrow_acs_to_declared "no ac tokens here" halo/specs/alpha/spec.md'
  assert_success
  assert_output ""
}

@test "narrow_acs_to_declared does not abort under pipefail when nothing survives narrowing" {
  make_spec halo/specs alpha

  lib_run 'narrow_acs_to_declared "AC-99" halo/specs/alpha/spec.md; echo "rc=$? reached_end"'
  assert_success
  assert_output --partial "rc=0 reached_end"
  refute_output --partial "AC-"
}

@test "narrow_acs_to_declared sorts and de-duplicates its output" {
  make_spec halo/specs alpha

  lib_run 'narrow_acs_to_declared "AC-2 AC-1 AC-1" halo/specs/alpha/spec.md'
  assert_success
  assert_output "$(printf 'AC-1\nAC-2')"
}

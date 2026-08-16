#!/usr/bin/env bats
# Bug report: docs/bug_report/2026-08-03-halo-gate-findings.md
#   （聚合上报，8 条已修缺陷按缺陷拆分到本目录；映射见 docs/bug_report/INDEX.md）
# Root cause class: E. 框架读不懂自带模板 + F. 语法变体覆盖不足
# Fixed by: df7991e (#12 "Stop drift-check from reporting unchecked dimensions as clean"；
#   错误码与路由表两个缺陷在同一次提交里一并修复，见
#   docs/bug_report/2026-08-03-halo-gate-findings-analysis.md §1)
#
# 复核 §1 的结论：旧版 `drift-check.sh:214`（修复前）只从「表格首列为纯数字」的行提取
# 错误码。框架自带的默认 spec 模板 `spec-template.md:89-91` 写的却是字符串枚举占位
# `{ERROR_CODE}`——任何按框架自己模板写 spec 的项目，错误码漂移检测都恒为 skip，
# 与项目是不是 Go 无关。第二处硬编码 `find -name '*.go'` 让非 Go 项目连比对入口都进不去。
#
# 修复后：spec 侧按表头（`错误码`/`Error Code`/...）定位错误码表，取首列，接受纯数字与
# 大写蛇形常量两种形态；找不到表头时回退到旧的全文数值扫描（dec-5 守这条回退分支）。
# 代码侧按 project.language 分派源文件后缀，语言无映射时显式报
# `no source file mapping`（dec-6）。数值码沿用 const_pattern 比对，字符串码走字面量
# `grep -wF`（dec-2/dec-3）。
#
# 与 unit/gate-drift-check.bats 的 gdc-4 同形但关注点不同：gdc-4 断的是「有 drift ⇒
# status=fail ∧ exit 1」这条出口契约，这里断的是「错误码抽取本身认得框架自带模板与
# 各种语法变体」这条缺陷回归，输入形似，分层不是重复。

load "../../helpers/common"

setup_file() {
  halo_require_tools
  halo_template_install
}

setup() {
  halo_sandbox_clone
  halo_set_language python
}

@test "the template's {ERROR_CODE} placeholder row is not extracted as an error code" {
  # 复核 §1：{ERROR_CODE} 是框架自带 spec-template.md 5.1 节的字符串枚举占位符，
  # 逐字取自该模板。数值专用的旧提取器会把它当零个错误码，四个 drift 维度全部
  # 落进「未验证」——这条用例守的是「占位符本身不会被误判成一个合法错误码」。
  halo_install_fixture drift/spec-template-placeholder
  # PROJECT 必须指向 fixture 自造的空目录，不能是 $SANDBOX：指向 $SANDBOX 会把
  # install.sh vendor 进 .halo/framework/ 的整棵框架源码树一起扫，兄弟 fixture
  # 互相污染（tests/fixtures/README.md 第五条约束）。
  local empty_project="$SANDBOX/drift/empty-project"
  mkdir -p "$empty_project"

  run bash halo/kernel/delivery/gates/drift-check.sh \
    "$SANDBOX/drift/template-placeholder-spec.md" "$empty_project" \
    --json-out="$SANDBOX/drift-template.json"
  assert_output --partial "No business error codes in spec"

  run yq -e '.metrics.spec_error_codes == 0' "$SANDBOX/drift-template.json"
  assert_success
}

@test "a string error code missing from python source is reported as drift" {
  # 复核 §1：字符串枚举错误码用字面量 grep -wF 比对——枚举定义语法跨语言差异太大
  # （Python `class ErrorCode(str, Enum)`、TS `const enum`、Go `const X = "..."`），
  # 单一 const_pattern 不现实；「spec 声明的码在源码里根本不出现」已足够鉴别漂移。
  local code_dir="$SANDBOX/drift/error-codes"
  mkdir -p "$code_dir"
  cat > "$code_dir/errors.py" << 'PY'
from enum import Enum


class ErrorCode(str, Enum):
    REFERENCE_NOT_FOUND = "REFERENCE_NOT_FOUND"
PY

  local spec="$SANDBOX/drift/error-code-spec.md"
  mkdir -p "$SANDBOX/drift"
  cat > "$spec" << 'SPEC'
# Spec: 字符串错误码

## 5.3 错误码

| 错误码 | 触发条件 | 副作用 | 是否可重试 |
|---|---|---|---|
| REFERENCE_NOT_FOUND | 引用目标不存在 | 无 | no |
| REFERENCE_IN_USE | 目标仍被引用 | 无 | no |
SPEC

  run bash halo/kernel/delivery/gates/drift-check.sh "$spec" "$code_dir" \
    --json-out="$SANDBOX/drift-string-code.json"
  assert_failure 1

  run yq -e '.metrics.spec_error_codes == 2
    and .metrics.drift_count == 1
    and .metrics.checked.error_codes == true' "$SANDBOX/drift-string-code.json"
  assert_success
}

@test "the gate passes once every string error code is defined" {
  # 复核 §1 的反向态：两个字符串码都在源码里定义时不得误报。
  local code_dir="$SANDBOX/drift/error-codes-clean"
  mkdir -p "$code_dir"
  cat > "$code_dir/errors.py" << 'PY'
from enum import Enum


class ErrorCode(str, Enum):
    REFERENCE_NOT_FOUND = "REFERENCE_NOT_FOUND"
    REFERENCE_IN_USE = "REFERENCE_IN_USE"
PY

  local spec="$SANDBOX/drift/error-code-spec.md"
  mkdir -p "$SANDBOX/drift"
  cat > "$spec" << 'SPEC'
# Spec: 字符串错误码

## 5.3 错误码

| 错误码 | 触发条件 | 副作用 | 是否可重试 |
|---|---|---|---|
| REFERENCE_NOT_FOUND | 引用目标不存在 | 无 | no |
| REFERENCE_IN_USE | 目标仍被引用 | 无 | no |
SPEC

  run bash halo/kernel/delivery/gates/drift-check.sh "$spec" "$code_dir" \
    --json-out="$SANDBOX/drift-string-code-clean.json"
  assert_success

  run yq -e '.metrics.drift_count == 0
    and .metrics.checked.error_codes == true' "$SANDBOX/drift-string-code-clean.json"
  assert_success
}

@test "numeric error codes are still read from a table located by its header" {
  # 复核 §1：数值码沿用 const_pattern，仍必须能通过表头定位的错误码表读出多条。
  # 反向态用的是简报第 5 点提醒的事实：缺失的码只有在项目里存在**另一个**匹配的
  # 数值常量（NUMERIC_CONSTS 非空）时才会判 drift；这里删掉 CodeFoo 后仍留着
  # CodeBar=40002，保证不会落回 gate_skip/「NOT verified」分支得到一条假绿。
  local code_dir="$SANDBOX/drift/numeric-codes"
  mkdir -p "$code_dir"
  local spec="$SANDBOX/drift/numeric-code-spec.md"
  mkdir -p "$SANDBOX/drift"
  cat > "$spec" << 'SPEC'
# Spec: 数值错误码表

## 5.1 错误码

| 错误码 | 触发条件 | 副作用 | 是否可重试 |
|---|---|---|---|
| 40001 | 请求非法 | 无 | no |
| 40002 | 资源冲突 | 无 | no |
SPEC

  cat > "$code_dir/errors.py" << 'PY'
CodeFoo = 40001
CodeBar = 40002
PY

  run bash halo/kernel/delivery/gates/drift-check.sh "$spec" "$code_dir" \
    --json-out="$SANDBOX/drift-numeric.json"
  assert_success
  run yq -e '.metrics.spec_error_codes == 2
    and .metrics.drift_count == 0
    and .metrics.checked.error_codes == true' "$SANDBOX/drift-numeric.json"
  assert_success

  # 缺一个：CodeFoo(40001) 从源码里消失，CodeBar(40002) 留着保证 NUMERIC_CONSTS 非空。
  cat > "$code_dir/errors.py" << 'PY'
CodeBar = 40002
PY

  run bash halo/kernel/delivery/gates/drift-check.sh "$spec" "$code_dir" \
    --json-out="$SANDBOX/drift-numeric-missing.json"
  assert_failure 1
  run yq -e '.metrics.drift_count == 1
    and .metrics.checked.error_codes == true' "$SANDBOX/drift-numeric-missing.json"
  assert_success
}

@test "a spec with numeric codes but no error code table still falls back to the whole-file scan" {
  # 复核 §1：`drift-check.sh:452-456`——表头定位找不到「错误码」这样的表头时，
  # 回退到历史的全文数值行扫描（`^| *[0-9]+ *|`），保证既有数值码 spec 不回归。
  local code_dir="$SANDBOX/drift/numeric-fallback"
  mkdir -p "$code_dir"
  cat > "$code_dir/errors.py" << 'PY'
CodeFoo = 40001
PY

  local spec="$SANDBOX/drift/numeric-fallback-spec.md"
  mkdir -p "$SANDBOX/drift"
  cat > "$spec" << 'SPEC'
# Spec: 内嵌错误码行，无独立表头

以下清单直接给出错误码，不建带「错误码」表头的表格：

| 40001 | 请求非法 | 无 | no |
SPEC

  run bash halo/kernel/delivery/gates/drift-check.sh "$spec" "$code_dir" \
    --json-out="$SANDBOX/drift-fallback.json"
  assert_success

  run yq -e '.metrics.spec_error_codes == 1
    and .metrics.checked.error_codes == true' "$SANDBOX/drift-fallback.json"
  assert_success
}

@test "an unmapped project language reports NOT verified instead of clean" {
  # 复核 §1：语言到源文件后缀的映射缺失时，必须显式报「未验证」，
  # 不能悄悄落回「无 drift」——诚实的 skip，不是一条被掩盖的漂移。
  halo_set_language cobol
  local project="$SANDBOX/drift/cobol-project"
  mkdir -p "$project"
  local spec="$SANDBOX/drift/cobol-spec.md"
  mkdir -p "$SANDBOX/drift"
  cat > "$spec" << 'SPEC'
# Spec: 数值错误码表

## 5.1 错误码

| 错误码 | 触发条件 | 副作用 | 是否可重试 |
|---|---|---|---|
| 40001 | 请求非法 | 无 | no |
SPEC

  run bash halo/kernel/delivery/gates/drift-check.sh "$spec" "$project" \
    --json-out="$SANDBOX/drift-cobol.json"
  assert_success
  assert_output --partial "no source file mapping"

  run yq -e '.metrics.checked.error_codes == false' "$SANDBOX/drift-cobol.json"
  assert_success
}

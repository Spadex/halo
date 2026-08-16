#!/usr/bin/env bats
# 门禁行为单测：drift-check.sh 的出口语义（退出码 + gate JSON 契约）。
# 不绑定某份 bug 报告，所以放 unit/ 而不是 regression/。
#
# 消费方清单（改这些断言前先看爆炸半径）：
#   - halo/kernel/delivery/pipeline.sh —— 嵌入 eval run 的 gate JSON
#   - halo/kernel/orchestrator/sdd/summary-draft.sh —— 读 metrics 渲染摘要
#   - tests/release-check.sh —— 发版前的门禁总检
#
# 迁移自 smoke-test §7/§7c（本批次删除）。gdc-2/gdc-3 用 `checks_run == 0` +
# 四个 `checked.*` 为 false 断出口语义，不用 `checks_skipped == 4` 钉死中间实现细节
# （避免无关新增维度误伤这条断言）。gdc-4 是新增的反向用例：#12/#13 系列的错误码/路由
# 表格陷阱交给 regression/…/drift-error-codes.bats、…drift-route-table.bats 覆盖，
# 这里只断「有 drift ⇒ status=fail ∧ exit 1」这条出口契约，输入形似但关注点不同，分层不是重复。

load "../helpers/common"

setup_file() {
  halo_require_tools
  halo_template_install
}

setup() {
  halo_sandbox_clone
}

@test "drift-check --json-out writes the gate JSON envelope" {
  # 单一匹配的数值错误码：既让 error_codes 维度真正被比对（mark_checked），
  # 又不触碰 DDL / routes / seed_sql（spec 里没有对应的表，天然 skip），
  # 与 gdc-2/gdc-3 的「全维度未验证」场景区分开，覆盖真正走通比对的正常路径。
  local code_dir="$SANDBOX/drift/clean-code"
  mkdir -p "$code_dir"
  cat > "$code_dir/errors.go" << 'GO'
package errs

const CodeFoo = 40001
GO
  local spec="$SANDBOX/drift/clean-spec.md"
  mkdir -p "$SANDBOX/drift"
  cat > "$spec" << 'SPEC'
# Spec: minimal error code contract

## 5.1 错误码

| 错误码 | 触发条件 | 副作用 | 是否可重试 |
|---|---|---|---|
| 40001 | 请求非法 | 无 | no |
SPEC

  run bash halo/kernel/delivery/gates/drift-check.sh "$spec" "$code_dir" --json-out="$SANDBOX/drift-clean.json"
  assert_success

  run yq -e '.gate == "drift-check"
    and .status == "pass"
    and .metrics.drift_count == 0
    and (.findings | length > 0)' "$SANDBOX/drift-clean.json"
  assert_success
}

@test "every unverifiable dimension is reported as NOT verified, never as clean" {
  # PROJECT 必须指向 fixture 自造的空目录，不能是 $SANDBOX：指向 $SANDBOX 会把
  # install.sh vendor 进 .halo/framework/ 的整棵框架源码树一起扫，兄弟 fixture
  # 互相污染（tests/fixtures/README.md 第五条约束）。
  halo_install_fixture drift/spec-template-placeholder
  local empty_project="$SANDBOX/drift/empty-project"
  mkdir -p "$empty_project"

  run bash halo/kernel/delivery/gates/drift-check.sh \
    "$SANDBOX/drift/template-placeholder-spec.md" "$empty_project" \
    --json-out="$SANDBOX/drift-skip.json"
  assert_output --partial "NOT verified"

  run yq -e '.metrics.checks_skipped >= 3
    and .metrics.checked.ddl == false
    and .metrics.checked.routes == false
    and .metrics.checked.error_codes == false
    and .metrics.checked.seed_sql == false' "$SANDBOX/drift-skip.json"
  assert_success
}

@test "checks_run counts only dimensions that actually compared something" {
  halo_install_fixture drift/spec-template-placeholder
  local empty_project="$SANDBOX/drift/empty-project"
  mkdir -p "$empty_project"

  run bash halo/kernel/delivery/gates/drift-check.sh \
    "$SANDBOX/drift/template-placeholder-spec.md" "$empty_project" \
    --json-out="$SANDBOX/drift-skip.json"

  run yq -e '.metrics.checks_run == 0' "$SANDBOX/drift-skip.json"
  assert_success
}

@test "a drift finding sets status fail and exits 1" {
  # 与 clean 用例同形，只是把匹配码换成一个 spec 需要但代码里不存在的码：
  # 另一个真实存在的数值常量保证 NUMERIC_CONSTS 非空，缺号才会落 drift 而不是
  # 落回「NOT verified」skip 分支。
  local code_dir="$SANDBOX/drift/drift-code"
  mkdir -p "$code_dir"
  cat > "$code_dir/errors.go" << 'GO'
package errs

const CodeOther = 40002
GO
  local spec="$SANDBOX/drift/drift-spec.md"
  mkdir -p "$SANDBOX/drift"
  cat > "$spec" << 'SPEC'
# Spec: minimal error code contract

## 5.1 错误码

| 错误码 | 触发条件 | 副作用 | 是否可重试 |
|---|---|---|---|
| 40001 | 请求非法 | 无 | no |
SPEC

  run bash halo/kernel/delivery/gates/drift-check.sh "$spec" "$code_dir" --json-out="$SANDBOX/drift-fail.json"
  assert_failure 1

  run yq -e '.status == "fail" and .metrics.drift_count == 1' "$SANDBOX/drift-fail.json"
  assert_success
}

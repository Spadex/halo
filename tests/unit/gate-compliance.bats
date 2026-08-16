#!/usr/bin/env bats
# 门禁行为单测：compliance.sh 的出口语义（退出码 + gate JSON 契约）。
# 不绑定某份 bug 报告，所以放 unit/ 而不是 regression/。
#
# 消费方清单（改这些断言前先看爆炸半径）：
#   - halo/kernel/delivery/pipeline.sh —— 嵌入 eval run 的 gate JSON
#   - halo/kernel/orchestrator/sdd/summary-draft.sh —— 读 metrics 渲染摘要
#   - tests/release-check.sh —— 发版前的门禁总检
#
# 迁移自 smoke-test §7（本批次删除）。旧断言 `.metrics.warnings >= 0` 是恒真式
# （warnings 是非负计数器，任何实现都成立，零鉴别力）——不迁移，同批次 1 清理
# `else pass "ac-coverage ran (exit=$AC_EXIT)"` 是同一类做法。
#
# compliance 的中文/英文来源类别识别、以及「表在但类别词全是自造词」的反向覆盖，
# 交给 regression/…/compliance-source-trace.bats（消费 tests/fixtures/compliance/*）；
# 这里只断软门禁的出口契约（envelope 形状 + warn/strict 的方向），分层不是重复。

load "../helpers/common"
load "../helpers/fixtures"

setup_file() {
  halo_require_tools
  halo_template_install
}

setup() {
  halo_sandbox_clone
}

@test "compliance --json-out writes the gate JSON envelope" {
  # make_spec 的黄金形态自带结构完整的 Context Basis 表（含 user / code / tests /
  # open questions 三行），五个 check 都会真正跑到，findings 不会因为某个 check
  # 被短路而缺席。
  make_spec halo/specs compliant-spec

  run bash halo/kernel/delivery/gates/compliance.sh halo/specs/compliant-spec/spec.md \
    --json-out="$SANDBOX/compliance-envelope.json"
  assert_success

  run yq -e '.gate == "compliance"
    and .status != null
    and (.findings | length >= 4)' "$SANDBOX/compliance-envelope.json"
  assert_success
}

@test "every finding carries a check name and a status" {
  make_spec halo/specs compliant-spec

  run bash halo/kernel/delivery/gates/compliance.sh halo/specs/compliant-spec/spec.md \
    --json-out="$SANDBOX/compliance-findings.json"

  run yq -e '[.findings[] | select(.check == "" or .status == "")] | length == 0' \
    "$SANDBOX/compliance-findings.json"
  assert_success

  run yq -e '([.findings[] | select(.check == "source_trace")] | length == 1)
    and ([.findings[] | select(.check == "context_basis")] | length == 1)
    and ([.findings[] | select(.check == "knowledge_reference")] | length == 1)
    and ([.findings[] | select(.check == "ambiguity_tracking")] | length == 1)' \
    "$SANDBOX/compliance-findings.json"
  assert_success
}

@test "compliance is a soft gate: warnings pass without --strict and fail with it" {
  # 缺 Context Basis 的 spec：既没有「## ... Context / 上下文依据」标题，
  # 也没有来源类别表格、没有 Open Questions/None/N/A 之类的歧义标记——
  # 四个 check 里至少 context_basis / source_trace / ambiguity_tracking 落 warning。
  local spec="$SANDBOX/compliance-no-basis-spec.md"
  cat > "$spec" << 'SPEC'
# Spec: bare minimum

## Scope

A tiny spec exercising the compliance soft gate. It carries no source-basis section,
no source-category table, and no unresolved-item markers.
SPEC

  run bash halo/kernel/delivery/gates/compliance.sh "$spec" \
    --json-out="$SANDBOX/compliance-warn.json"
  assert_success

  run yq -e '.status == "warn" and .metrics.warnings > 0' "$SANDBOX/compliance-warn.json"
  assert_success

  run bash halo/kernel/delivery/gates/compliance.sh "$spec" --strict \
    --json-out="$SANDBOX/compliance-strict.json"
  assert_failure 1

  run yq -e '.status == "fail"' "$SANDBOX/compliance-strict.json"
  assert_success
}

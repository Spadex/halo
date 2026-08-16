#!/usr/bin/env bats
# Bug report: docs/bug_report/2026-08-03-halo-gate-findings.md
#   （聚合上报，8 条已修缺陷按缺陷拆分到本目录；映射见 docs/bug_report/INDEX.md）
# Root cause class: E. 框架读不懂自带模板
# Fixed by: df7991e (#12 "Stop drift-check from reporting unchecked dimensions as clean"；
#   compliance source-trace 的修复见
#   docs/bug_report/2026-08-03-halo-gate-findings-analysis.md §3)
#
# 复核 §3 的结论：旧版 `compliance.sh:136`（修复前）只认英文来源类别 token。框架自带的
# 默认 spec 模板 `spec-template.md:45-50` 的「上下文依据」表写的却是中文来源列
# （`用户输入` / `代码 / 测试` / `项目知识` / `待确认`）——按框架自己的中文模板写 spec，
# 这条软门禁必然告警，是框架自造的永久噪声，与 §1 的错误码漂移同一类根因。
#
# 修复：正则补齐中文来源类别（`compliance.sh:148`）。三份 fixture 是 Task 1 建的，
# 逐字取自框架自带 spec-template.md 的「3. 上下文依据」表（zh）与其英文/自造词变体
# （en / unrecognised，均为反向覆盖，本批次新增），见 tests/fixtures/README.md 登记表。
#
# csr-3 是这个文件的关键：只有正向断言（csr-1/csr-2）时，一个把 `compliance.sh:148`
# 的 `grep -qiE '…'` 直接换成 `true` 的实现照样全绿——正则判据形同虚设也测不出来。
# #12 复核 §3 的修复方向是「正则补齐中文来源类别」，不是「取消判据」；csr-3 用一份
# 来源列全是自造词（甲方/乙方评审/丙方存档/丁项闲聊）、但表格结构完整的 spec 钉住
# 这一点：source_trace 必须仍然落 warning，而不是被一个恒真实现悄悄放行。

load "../../helpers/common"

setup_file() {
  halo_require_tools
  halo_template_install
}

setup() {
  halo_sandbox_clone
}

@test "the framework's own Chinese Context Basis table passes the source trace" {
  # fixture 逐字取自 spec-template.md 的中文「上下文依据」表，来源列是
  # 用户输入 / 代码 / 测试 / 项目知识 / 待确认——修复后的正则必须全部识别。
  halo_install_fixture compliance/context-basis-zh

  run bash halo/kernel/delivery/gates/compliance.sh \
    "$SANDBOX/compliance/context-basis-zh-spec.md" --json-out="$SANDBOX/compliance-zh.json"

  run yq -e '(.findings[] | select(.check == "source_trace") | .status) == "pass"' \
    "$SANDBOX/compliance-zh.json"
  assert_success
}

@test "an English Context Basis table still passes" {
  # 反向覆盖（本批次新增）：英文来源列（User / Code / Knowledge / External）
  # 防止中文正则补齐时误伤了原有的英文 token 识别。
  halo_install_fixture compliance/context-basis-en

  run bash halo/kernel/delivery/gates/compliance.sh \
    "$SANDBOX/compliance/context-basis-en-spec.md" --json-out="$SANDBOX/compliance-en.json"

  run yq -e '(.findings[] | select(.check == "source_trace") | .status) == "pass"' \
    "$SANDBOX/compliance-en.json"
  assert_success
}

@test "a Context Basis with no recognisable source category still warns" {
  # 判别力覆盖（本批次新增，M48 的靶子）：表格结构齐全，但来源列全是自造词
  # （甲方/乙方评审/丙方存档/丁项闲聊），不命中 source_trace 正则的任何一个分支。
  # 只有这一条能拦住「把判据换成 true」的假绿实现。
  halo_install_fixture compliance/context-basis-unrecognised

  run bash halo/kernel/delivery/gates/compliance.sh \
    "$SANDBOX/compliance/context-basis-none-spec.md" --json-out="$SANDBOX/compliance-none.json"

  run yq -e '(.findings[] | select(.check == "source_trace") | .status) == "warning"
    and .metrics.warnings > 0' "$SANDBOX/compliance-none.json"
  assert_success
}

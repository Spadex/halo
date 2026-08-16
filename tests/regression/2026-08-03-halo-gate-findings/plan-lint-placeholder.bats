#!/usr/bin/env bats
# Bug report: docs/bug_report/2026-08-03-halo-gate-findings.md
#   （聚合上报，8 条已修缺陷按缺陷拆分到本目录；映射见 docs/bug_report/INDEX.md）
# Root cause class: F. 语法变体覆盖不足 + C. 失败方向搞反
# Fixed by: df7991e (#12 "Stop drift-check from reporting unchecked dimensions as clean"；
#   plan-lint 占位符判据的修复见
#   docs/bug_report/2026-08-03-halo-gate-findings-analysis.md §4)
#
# 复核 §4 的结论：原判据
# `\b(TODO|TBD|FIXME)\b|<[^>]+>|\{[A-Za-z_][A-Za-z0-9_-]*\}`
# 上报指出的 `{set_id}` 与跨 `<`/`>` 误伤属实，但更关键的是
# `\{[A-Za-z_][A-Za-z0-9_-]*\}` 只匹配 ASCII 标识符——框架模板里真正的残留占位
# 大量是中文 `{条件}`/`{事实}`/`{影响}`，旧判据一个都抓不到。这条分支实际上只在
# 误伤 REST 路径参数与比较运算符，对它要防的东西完全没有鉴别力。
#
# 修复后的判据（`plan-lint.sh` 的 Task contract 段）：
#   <[A-Za-z][A-Za-z0-9_.-]*>            —— 尖括号 slug（如 <spec-id>）
#   \{[A-Z][A-Z0-9_]*\}                  —— 大写蛇形占位（如 {SCOPE_TBD}）
#   \{[^{}]*[^ -~][^{}]*\}               —— 花括号内含非 ASCII 可打印字符（中文占位）
#   \b(TODO|TBD|FIXME)\b                 —— 保持原样
#
# pl-5 是这次修复的核心增量：analysis §4 对照表里「`{条件} 待补` 旧漏新报」，旧
# smoke-test 断言一条都没覆盖过这个分支。pl-6 守住「TODO/TBD/FIXME 保持原样」这条
# analysis §4 明确说明「不收窄」的分支，不能被后续改动悄悄削弱。
#
# 派生写法核对（fixtures.bash:152）：make_plan 产出的 T 任务 Scope 行是
# `- Scope: Implement the smallest path needed for AC-${ac}.`，与旧 smoke-test 的
# 「smallest create/get path」措辞不同；sed 替换必须锚定 `needed for AC-1\.`，
# 不加限定会把 T1/T2 两条 Scope 行一起改掉（两者只有 AC 号不同）。
#
# 实测偏离简报片段一处，记录在此：简报的 plan_with_scope() 把派生结果写进
# `plan-probe.md`。plan-lint.sh 的「Artifact layout」检查（`Plan must be named
# plan.md`）与文件名字面量强绑定，与占位符判据完全无关；用 `plan-probe.md` 会让
# pl-1/pl-2 的 `assert_success` 恒红——那是一个与本文件要测的判据无关的命名冲突，
# 不是产品缺陷。改为原地覆写 `plan.md`（写临时文件再 mv，不用无后缀 sed -i），
# 已用 pl-1..pl-6 六个场景实测核对退出码与 "unresolved placeholder" 文案，
# 详见 task-7-report.md。

load "../../helpers/common"
load "../../helpers/fixtures"

setup_file() {
  halo_require_tools
  halo_template_install
}

setup() {
  halo_sandbox_clone
  make_spec halo/specs ph-probe 2
  make_plan halo/specs ph-probe 2 1 decl-en   # decl-en 避免声明行缺失的 fallback warning 噪声
}

# 把 T1（AC-1）的 Scope 行替换成 <替换串>，原地覆写 plan.md：写临时文件再 mv，
# 不用无后缀 sed -i（跨 BSD/GNU 不通用）。锚定 AC-1\. 是必须的——不加限定会
# 连 T2（AC-2）的 Scope 行一起改掉。
plan_with_scope() { # <替换串>
  sed "s#Scope: Implement the smallest path needed for AC-1\.#Scope: $1#" \
    halo/specs/ph-probe/plan.md > halo/specs/ph-probe/plan.md.new
  mv halo/specs/ph-probe/plan.md.new halo/specs/ph-probe/plan.md
}

@test "a REST path parameter is not an unresolved placeholder" {
  # 复核 §4 对照表第 1 行：{set_id} 是小写 REST 路径参数，不是模板残留占位。
  plan_with_scope 'Implement POST /model-sets/{set_id}/members.'

  run bash halo/kernel/orchestrator/sdd/plan-lint.sh ph-probe
  assert_success
  refute_output --partial "unresolved placeholder"
}

@test "comparison operators are not read as a bracket pair" {
  # 复核 §4 对照表第 2 行：一行内同时出现 < 和 > 作比较运算符，不能被旧判据的
  # <[^>]+> 误读成一个尖括号 slug。
  plan_with_scope 'keep members < 100 while > 0.'

  run bash halo/kernel/orchestrator/sdd/plan-lint.sh ph-probe
  assert_success
  refute_output --partial "unresolved placeholder"
}

@test "an upper snake-case template placeholder is still flagged" {
  # 大写蛇形占位（{SCOPE_TBD}）必须仍被判据抓住：修复的方向是补齐中文占位，
  # 不是放宽对 ASCII 占位的检测。
  plan_with_scope 'Implement work but {SCOPE_TBD}.'

  run bash halo/kernel/orchestrator/sdd/plan-lint.sh ph-probe
  assert_failure
  assert_output --partial "unresolved placeholder"
}

@test "an angle-bracketed slug is still flagged" {
  # 尖括号 slug（<spec-id>）必须仍被判据抓住。
  plan_with_scope 'Implement work, see <spec-id>.'

  run bash halo/kernel/orchestrator/sdd/plan-lint.sh ph-probe
  assert_failure
  assert_output --partial "unresolved placeholder"
}

@test "a Chinese template placeholder is flagged" {
  # 复核 §4 的核心增量：{条件} 待补——旧判据 \{[A-Za-z_][A-Za-z0-9_-]*\} 只匹配
  # ASCII 标识符，这一行在旧实现下完全漏检。这是本次修复要补的真正缺口，旧
  # smoke-test 一条断言都没覆盖过。
  plan_with_scope 'Implement work; {条件} 待补.'

  run bash halo/kernel/orchestrator/sdd/plan-lint.sh ph-probe
  assert_failure
  assert_output --partial "unresolved placeholder"
}

@test "TODO/TBD/FIXME are still flagged" {
  # analysis §4 明确这一分支「保持原样」：上报提到的「本节不得留 TBD」这类自指句
  # 误伤是罕见写法，收窄它会削弱这条判据的主要价值。要有断言守住不被后人误改窄。
  plan_with_scope 'Implement work. TODO: rename.'

  run bash halo/kernel/orchestrator/sdd/plan-lint.sh ph-probe
  assert_failure
  assert_output --partial "unresolved placeholder"
}

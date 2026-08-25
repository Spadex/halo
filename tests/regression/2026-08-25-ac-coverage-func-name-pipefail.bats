#!/usr/bin/env bats
# Bug report: docs/bug_report/2026-08-25-ac-coverage-func-name-pipefail-analysis.md
# Root cause class: B. pipefail 语义（命令替换包管道，缺 || 兜底）
# Fixed by: 与本文件同一提交（见 git log -- tests/regression/2026-08-25-ac-coverage-func-name-pipefail.bats）
#
# ac-coverage.sh 继承 _lib.sh 的 `set -euo pipefail`。覆盖循环里有两处同型的
# 命令替换：`:185` 抽 AC 号（**已有** `|| true`），`:188` 抽函数名（**曾缺**）。
# 抽不到函数名时 grep 返回 1，pipefail 取管道里最右侧的非零码，裸赋值随即触发
# errexit —— 门禁在循环中途终止，AC 覆盖矩阵一行都没打，write_gate_json 执行不到，
# gate JSON 不落盘。调用方 pipeline.sh 只看到一个没有解释的非零退出。
#
# 触发形态：node 的 FUNC_REGEX 是 `(describe|it|test).*AC[_-]?([0-9]+)`——只要行内
# 有 it/test/describe 和 AC 号即可；而函数名提取正则要求 `(describe|it|test)\(`
# 紧跟左括号。jest 的 `it.each(` / `test.concurrent(` / `describe.skip(` 全部命中
# 前者、漏掉后者。
#
# 发现路径：批次 3 meta-lint 上线前的存量噪声复核（见 analysis「发现路径」一节）。
# 当时的调研文档判这一处「head 在管道末段吞掉了 grep 的退出码，实际不会致命」——
# 两处都错：head -1 后面还有三个 sed，且 pipefail 下末段是谁本就无关。
#
# 两个方向都要断言：抽不到函数名不得让门禁崩（正向），也不得因为补了 `|| true`
# 就把该 AC 悄悄算作已覆盖（反向——那是从假红换成假绿，更糟）。

load "../helpers/common"

setup_file() {
  halo_require_tools
  halo_template_install
}

setup() {
  halo_sandbox_clone
  halo_set_language node
  halo_install_fixture ac/node-unextractable-func-token
}

run_gate() {
  run bash halo/kernel/delivery/gates/ac-coverage.sh \
    "halo/specs/spec-node/spec.md" . --json-out="$SANDBOX/ac.json"
}

finding() { # <ac> <field>
  run yq -r ".findings[] | select(.ac == \"$1\") | .$2" "$SANDBOX/ac.json"
}

# ── 正向：门禁必须跑完 ──
# 修复前门禁在 :188 崩掉，矩阵表头（:195-198）与 gate JSON 都不存在。
# 断言选的是「矩阵打出来了」而不是退出码——退出码修复前后都是非零
# （AC-1 本就未覆盖），只有矩阵和 JSON 能区分「崩了」和「判红了」。

@test "the gate runs to completion when a match line yields no function token" {
  run_gate
  assert_output --partial "AC Coverage Matrix"
}

@test "the gate writes its JSON envelope even when a function token is unextractable" {
  run_gate
  [ -f "$SANDBOX/ac.json" ]
  run yq -r '.gate' "$SANDBOX/ac.json"
  assert_output "ac-coverage"
}

@test "the unextractable AC fails the gate deliberately, not by crashing" {
  run_gate
  assert_failure
  assert_output --partial "FAIL — uncovered:"
}

# ── 反向其一：不许换成假绿 ──
# 补 `|| true` 之后 func_name 为空，:189 记成 "unknown"，Tier 2 的 :226
# 用 `$2!="unknown"` 把它排除出候选集——方向是 fail-closed。

@test "an AC whose function token cannot be extracted is uncovered, never silently covered" {
  run_gate
  finding AC-1 status
  assert_output "uncovered"
}

# ── 反向其二：不许把正常识别一起打坏 ──

@test "an AC whose function token extracts normally is still covered" {
  run_gate
  finding AC-2 status
  assert_output "covered"
}

@test "the normally-extracted AC still resolves to its own test token" {
  run_gate
  finding AC-2 test
  assert_output "test"
}

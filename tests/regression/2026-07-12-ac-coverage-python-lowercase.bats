#!/usr/bin/env bats
# Bug report: docs/bug_report/halo-ac-coverage-bug-report.md
#   （历史命名，未按 YYYY-MM-DD-<slug>.md；映射见 docs/bug_report/INDEX.md）
# Root cause class: B. pipefail 语义 + F. 语法变体覆盖不足
# Fixed by: de6c249
#
# 上报的症状是「任何 python 项目跑 ac-coverage 必然 FAIL」，但两个缺陷叠在一起：
#
#   F —— 发现正则认小写 `def test_ac`，编号提取正则却是大小写敏感的
#        `grep -oE 'AC[_-]?([0-9]+)'`，两者口径打架，小写测试一条都算不上；
#   B —— 提取写在命令替换里，`_lib.sh` 的 `set -euo pipefail` 让它非零即致命，
#        于是门禁在下一行的空值保护**之前**就崩了。那行 `[[ -z "$ac_num" ]] && continue`
#        永远执行不到，覆盖矩阵一次都没打印出来。
#
# 修复是 `grep -ioE` 加 `|| true`，两个缺陷各修一半。
# 所以只断言「小写被算上」等于只覆盖了一半——「报告未覆盖」与「崩溃」必须可区分，
# 这是下面第三条用例的意义。
#
# fixture 见 tests/fixtures/ac/python-lowercase/：裸 spec.md 放在项目根（非目录布局），
# 两列 AC 表，小写测试函数。

load "../helpers/common"

setup_file() {
  halo_require_tools
  halo_template_install
}

setup() {
  halo_sandbox_clone
  halo_set_language python
  halo_install_fixture ac/python-lowercase
}

@test "lowercase def test_ac is counted as covered" {
  run bash halo/kernel/delivery/gates/ac-coverage.sh py-ac-spec.md pytests
  assert_success
  assert_output --partial "AC Coverage Matrix"
  assert_output --partial "AC Coverage: 1/1 (100%)"
}

@test "an AC with no lowercase test is still reported uncovered" {
  # 同一份测试目录，spec 多一条 AC-2——大小写不敏感不得反向变成「什么都算覆盖」。
  run bash halo/kernel/delivery/gates/ac-coverage.sh py-ac-gap-spec.md pytests
  assert_failure 1
  assert_output --partial "AC Coverage: 1/2 (50%)"
  assert_output --partial "uncovered: AC-2"
}

@test "the gate reaches the coverage matrix instead of crashing" {
  # python 项目 + 零测试文件。这是缺陷 B 的专项：
  # 退出码必须**恰好**是 1（门禁自己的判定），不是 127/141/2（崩在半路），
  # 且矩阵必须打印出来——上报里最刺眼的症状就是矩阵根本没出现。
  run bash halo/kernel/delivery/gates/ac-coverage.sh py-ac-spec.md pytests-empty
  assert_failure 1
  assert_output --partial "AC Coverage Matrix"
  assert_output --partial "AC Coverage: 0/1 (0%)"
}

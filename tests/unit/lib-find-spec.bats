#!/usr/bin/env bats
# 契约单测：_lib.sh 的 spec 解析入口。不经过任何门禁直接调用。
#
# 调用方（5 处，改这里的断言前先看爆炸半径）：
#   halo/kernel/delivery/pipeline.sh:298          find_spec_with_source（记录 provenance）
#   halo/kernel/delivery/gates/ac-coverage.sh:34  find_spec
#   halo/kernel/delivery/gates/drift-check.sh:32  find_spec
#   halo/kernel/delivery/gates/spec-lint.sh:13    find_spec
#   halo/kernel/delivery/gates/compliance.sh:34   find_spec
# 后四者的 rc=2 分支是四份逐字副本，根因 H 的现成温床——第 12 条专门守它们不漂移。
#
# 被测：_resolve_spec(:144-176) / find_spec_with_source(:178-180) / find_spec(:182-188)
# 返回码契约：0 resolved · 1 nothing to resolve · 2 ambiguous
#
# 分层边界（必须遵守）：本文件只守 _lib.sh 自身的分支与返回码，不守
# spec-select.sh 的排序算法与可察觉性——谁被选中、为什么被选中、stderr 文案、
# mtime 回退、status 排序键、updated_at 比较，一律归
# tests/regression/2026-08-03-halo-gate-findings_2/spec-discovery.bats
# （Task 8 才写，本文件落笔时该文件尚不存在，正常）。find-8/find-9 用并列/唯一
# 场景只是为了驱动 _lib.sh 的 rc 分支，断言只落在 find_spec 的 rc 与输出上，不
# 断言"谁被选中是因为时间戳更新"这类排序理由。判据：改 spec-select.sh 的排序键
# /输出会红的，归 regression；改 _lib.sh 的分支/返回码会红的，归 unit。

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

# 必须走子进程：_lib.sh:79-82 定义的 pass()/fail()/warn()/skip() 与
# tests/vendor/bats-support/src/error.bash:38 的 fail()（bats-assert 全部
# assert_*/refute_* 的失败原语）、tests/vendor/bats-core/lib/bats-core/test_functions.bash:437
# 的 bats 内建 skip() 同名。把 _lib.sh 直接 source 进 bats 测试进程会用 _lib.sh 的
# fail()/skip() 覆盖掉这两个原语——fail() 变成打一行 "❌ …" 再返回 0，所有
# assert_* 从此永不让用例变红，是最坏的一类假绿。子进程隔离还带两个附带收益：
# _lib.sh:12 的 `set -euo pipefail` 不会外溢到测试进程；find_spec 的 rc 1/2
# 直接落在子进程的退出码上，被 `run` 原样收进 $status，不需要额外的 `|| rc=$?`
# 搬运。$SANDBOX 里 cwd 已由 halo_sandbox_clone 切好，子进程按相对路径
# `halo/kernel/_lib.sh` source 即可命中。
#
# `--separate-stderr` 是实测踩出来的必要项，不是可选风格：auto 分支下
# spec_select（spec-select.sh:118 起）把选中依据和落选候选打到 stderr，
# bats 的 `run` 默认把 stdout+stderr 合并进 $output。不分离的话，find_spec_with_source
# 的 stdout 契约（"source|detail|path"）会被 stderr 的诊断行污染，断言只能退化成
# 用 --partial 绕开合并噪音——而分层边界（文件头）又不许本文件断言那些 stderr
# 文案。分离后 $output 只剩函数真正的 stdout 契约，$stderr 存在但本文件不读它。
lib_run() { # <bash 片段>
  run --separate-stderr bash -c 'source halo/kernel/_lib.sh; eval "$1"' _ "$1"
}

@test "an explicit SPEC_FILE resolves with source explicit" {
  make_spec halo/specs alpha

  SPEC_FILE="$SANDBOX/halo/specs/alpha/spec.md" lib_run 'find_spec'
  assert_success
  assert_output "$SANDBOX/halo/specs/alpha/spec.md"

  SPEC_FILE="$SANDBOX/halo/specs/alpha/spec.md" lib_run 'find_spec_with_source'
  assert_success
  assert_output --regexp '^explicit\|caller-supplied\|'
}

@test "a SPEC_FILE pointing at a missing file falls through to discovery" {
  make_spec halo/specs alpha

  SPEC_FILE="$SANDBOX/no-such-spec.md" lib_run 'find_spec_with_source'
  assert_success
  assert_output --regexp '^auto\|'
}

@test "specs.active resolves a spec id with source manifest-active" {
  make_spec halo/specs alpha
  yq -i '.specs.active="alpha"' "$SANDBOX/halo/manifest.yaml"

  lib_run 'find_spec'
  assert_success
  assert_output "$SANDBOX/halo/specs/alpha/spec.md"

  lib_run 'find_spec_with_source'
  assert_success
  assert_output --partial "manifest-active|specs.active=alpha|"
}

@test "specs.active resolves a path with source manifest-active" {
  make_spec halo/specs alpha
  yq -i '.specs.active="halo/specs/alpha/spec.md"' "$SANDBOX/halo/manifest.yaml"

  lib_run 'find_spec'
  assert_success
  assert_output "$SANDBOX/halo/specs/alpha/spec.md"

  lib_run 'find_spec_with_source'
  assert_success
  assert_output --partial "manifest-active|specs.active=halo/specs/alpha/spec.md|"
}

@test "an explicit SPEC_FILE outranks specs.active" {
  # 两个 make_spec 天然构造并列（详见文件头警告），但这里从不落到 auto：
  # explicit 分支在 _resolve_spec 的第一个 if 就返回，不会触发 rc=2。
  make_spec halo/specs alpha
  make_spec halo/specs beta
  yq -i '.specs.active="beta"' "$SANDBOX/halo/manifest.yaml"

  SPEC_FILE="$SANDBOX/halo/specs/alpha/spec.md" lib_run 'find_spec'
  assert_success
  assert_output "$SANDBOX/halo/specs/alpha/spec.md"
}


# 这里只断言 source 与最终路径，刻意不碰 detail 字段的内容——不管是断言它非空还是
# 断言它为空都不写。原因分三条：
# ① detail 本该非空（"status=… updated_at=…"），但 `_lib.sh:169` 的
#    `selected="$(spec_select …)"` 是一次命令替换，bash 对命令替换恒定 fork 子
#    shell，`spec_select`（spec-select.sh:116）对全局变量 SPEC_SELECT_DETAIL 的
#    赋值发生在子 shell 里，退出后不会回写父 shell，`_lib.sh:171` 读到的永远是
#    spec-select.sh:18 初始化的空字符串——这是一个已确认的真实缺陷，记入实现观察
#    O-14（见 task-2-report.md），批次 3 走完整 SOP 修，本批次不碰 kernel。
# ② 但也不能反过来断言"detail 为空"：那是把缺陷行为写成期望契约，比没有断言更
#    坏（批次 1 删过一条同类反面教材：ac-coverage 的 `else pass "ran (exit=$AC_EXIT)"`
#    把任意退出码都记成通过）。O-14 修复之后 detail 应该变回非空，这条测试不该在
#    那时候变红。
# ③ "排序依据无人可测"并不成立——spec_select 仍然把选中依据和落选候选打到
#    stderr（spec-select.sh:118 起），只是 `find_spec`/`find_spec_with_source`
#    这一段管道把它弄丢了。stderr 上的那份能力由 Task 8 的
#    tests/regression/2026-08-03-halo-gate-findings_2/spec-discovery.bats 覆盖。
@test "auto discovery resolves a single candidate with source auto" {
  make_spec halo/specs alpha

  lib_run 'find_spec_with_source'
  assert_success
  assert_output --regexp '^auto\|'

  lib_run 'find_spec'
  assert_success
  assert_output "$SANDBOX/halo/specs/alpha/spec.md"
}

@test "find_spec returns 1 and prints nothing when no spec exists" {
  # halo_template_install 之后 halo/specs 下只有 .gitkeep（已实测确认），
  # 不需要额外清空。
  lib_run 'find_spec'
  assert_failure 1
  assert_output ""
}

@test "find_spec returns 2 when two candidates tie on status and updated_at" {
  # make_spec 对每个 spec 都写死 status: drafted + updated_at:
  # 2026-01-01T00:00:00Z（tests/helpers/fixtures.bash:24,30），所以两个
  # make_spec 就是零成本的精确并列。警告：任何在同一沙箱里造两个 make_spec
  # spec 又依赖自动发现的用例都会撞这个 rc=2——find-5/find-11 之所以不撞，是
  # 因为它们要么走 explicit 分支，要么每次只留一个 spec 参与 auto 发现。
  make_spec halo/specs alpha
  make_spec halo/specs beta

  lib_run 'find_spec'
  assert_failure 2
}

@test "a unique updated_at breaks the tie and resolves with rc 0" {
  make_spec halo/specs alpha
  make_spec halo/specs beta

  # 无后缀 sed -i 在 BSD/GNU 两边行为不一致，改写到临时文件再 mv。
  local tmp
  tmp="$(mktemp)"
  awk '{ gsub(/updated_at: 2026-01-01T00:00:00Z/, "updated_at: 2026-01-02T00:00:00Z"); print }' \
    "$SANDBOX/halo/specs/beta/spec.md" > "$tmp" && mv "$tmp" "$SANDBOX/halo/specs/beta/spec.md"

  lib_run 'find_spec'
  assert_success
  assert_output "$SANDBOX/halo/specs/beta/spec.md"
}

@test "find_spec does not abort its caller under set -euo pipefail" {
  # 空沙箱下 find_spec 内部的 spec_select 返回 1；_lib.sh:12 继承的
  # set -euo pipefail 如果外溢，`SPEC=$(find_spec)` 会直接终止子进程，
  # 后面的 echo 永远不会跑到。用 reached_end 哨兵证明脚本真的活着走完了。
  lib_run 'SPEC=$(find_spec) || rc=$?; echo "rc=$rc reached_end"'
  assert_success
  assert_output --partial "rc=1 reached_end"
}

@test "find_spec_with_source emits three pipe-separated fields for every source" {
  make_spec halo/specs alpha
  local nf path

  SPEC_FILE="$SANDBOX/halo/specs/alpha/spec.md" lib_run 'find_spec_with_source'
  assert_success
  nf="$(awk -F'|' '{print NF}' <<< "$output")"
  path="$(awk -F'|' '{print $3}' <<< "$output")"
  [ "$nf" -eq 3 ]
  [[ "$path" == /* ]]

  yq -i '.specs.active="alpha"' "$SANDBOX/halo/manifest.yaml"
  lib_run 'find_spec_with_source'
  assert_success
  nf="$(awk -F'|' '{print NF}' <<< "$output")"
  path="$(awk -F'|' '{print $3}' <<< "$output")"
  [ "$nf" -eq 3 ]
  [[ "$path" == /* ]]

  yq -i '.specs.active=""' "$SANDBOX/halo/manifest.yaml"
  lib_run 'find_spec_with_source'
  assert_success
  nf="$(awk -F'|' '{print NF}' <<< "$output")"
  path="$(awk -F'|' '{print $3}' <<< "$output")"
  [ "$nf" -eq 3 ]
  [[ "$path" == /* ]]
}

@test "every gate refuses an ambiguous auto-discovery instead of skipping it" {
  # 一条遍历五个门禁而不是五条手写副本：bats 不支持动态生成用例，五条手写
  # 副本本身就是根因 H（ac-coverage.sh:35-39 / drift-check.sh:33-37 /
  # spec-lint.sh:14-18 / compliance.sh:35-39 这四份逐字副本 + pipeline.sh:298-312
  # 的第五份独立实现）。原写法是
  # `SPEC=$(find_spec) || { echo "skipping"; exit 0; }`——拒绝猜测会变成静默
  # 跳过门禁，比猜错更糟，所以断言里显式 refute "skipping"。
  make_spec halo/specs alpha
  make_spec halo/specs beta

  local names=(ac-coverage drift-check spec-lint compliance pipeline)
  local cmds=(
    "halo/kernel/delivery/gates/ac-coverage.sh"
    "halo/kernel/delivery/gates/drift-check.sh"
    "halo/kernel/delivery/gates/spec-lint.sh"
    "halo/kernel/delivery/gates/compliance.sh"
    "halo/kernel/delivery/pipeline.sh --only=spec-lint"
  )

  local i name cmd
  for i in "${!names[@]}"; do
    name="${names[$i]}"
    cmd="${cmds[$i]}"
    run bash -c "$cmd"
    [ "$status" -ne 0 ] || fail "gate=$name: expected a non-zero exit code, got 0"
    [[ "$output" == *"ambiguous"* ]] || fail "gate=$name: expected output to mention 'ambiguous', got: $output"
    [[ "$output" != *"skipping"* ]] || fail "gate=$name: output unexpectedly contains 'skipping' (silent skip instead of refusal)"
  done
}

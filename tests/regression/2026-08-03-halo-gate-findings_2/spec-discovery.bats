#!/usr/bin/env bats
# Bug report: docs/bug_report/2026-08-03-halo-gate-findings_2.md（聚合上报；本文件 =
#   analysis §1 / 上报 §8.1。analysis §3 的 learn-draft.sh promote 形态归批次 3 的
#   同目录文件 —— 报告横跨批次 2 与批次 3，所以用目录承载，两个批次各加一个文件、
#   互不干扰）
# Root cause class: D. 非确定性依赖（mtime）+ C. 静默兜底
# Fixed by: 7a50adf Stop spec auto-discovery from ranking on file mtime (#15)
#   （`git log --oneline -- harness-template/halo/kernel/spec-select.sh` 只有这一条，
#   该文件由这次提交新增，之后无后续补丁）
#
# 上报症状：`ls -t` 挑 mtime 最新的 spec.md 当「当前 spec」，而 git merge / checkout /
# rebase / stash pop 会在检出时重写 mtime，与内容的新旧无关。结果是一次结构完整的
# eval 全绿运行，spec_file / spec_hash / AC 覆盖全部指向一个不相关的 spec，且没有任何
# 警告——find_spec() 是 pipeline.sh / ac-coverage.sh / spec-lint.sh / drift-check.sh /
# compliance.sh 五个调用点的共同入口，所以不是某一个门禁的问题，是整条链路同时错到
# 同一个错误对象上，内部完全自洽、互不打架报警（analysis §1 第一段）。
#
# 修复新增 harness-template/halo/kernel/spec-select.sh：两键排序（status != verified
# 优先，然后 frontmatter updated_at 降序），完全并列时退出码 2 拒绝猜测，且把选中依据
# 与每个落选候选打到 stderr 供人工核对。
#
# ── setup 分两档（本文件相对 §7c 各文件的特殊之处）──
#
# disc-1..8 只直接跑 spec-select.sh，在 $BATS_TEST_TMPDIR 里现搭 spec 树，不装
# harness、不调用 halo_template_install。理由是契约，不是速度：spec-select.sh:6-8 的
# 设计契约原文是「刻意不依赖 _lib.sh 与 yq，因为 guide.sh 必须能在没有 halo 的
# standalone 宿主下工作」——在装好 harness 的沙箱里测它，恰好把这条契约测没了。守住
# 这条契约的是「不调用 halo_sandbox_clone」，与模板何时安装无关。
#
# 曾经这里写过一句「setup_file 里无条件装模板会让这 8 条白等一次安装」——那是错的，
# 已删：setup_file 每文件只跑一次，不是每用例一次，两种写法都只安装一次。实测两种
# 形态的耗时（5.98/4.97/4.94s 对 4.93/4.92/5.81s）完全在噪声里，没有任何收益。
# 下面的 discovery_ensure_template 记忆化保留，但它的作用是让 disc-9..11 共享同一次
# 安装、且 disc-1..8 全程不触发安装路径，不是为了省时间。
#
# disc-9..11 需要完整沙箱（pipeline.sh / guide.sh 都要在已初始化的项目里跑），用
# halo_sandbox_clone。
#
# ── 分层边界（必须遵守，与 tests/unit/lib-find-spec.bats 互指）──
# 判据一句话：改 spec-select.sh 的排序键/输出会红的，**外加** smoke-test §9b 迁移过来
# 的端到端来源记录（disc-9/disc-10 断言的是 pipeline.sh 落盘 eval JSON 里的
# spec_source，走的是 _lib.sh + pipeline 接线，在 spec-select.sh 的排序键变异 M9 与
# 并列阈值变异 M11 下它们全程不红），归 regression（本文件）；改 _lib.sh 的分支/
# 返回码会红的，归 unit
# （tests/unit/lib-find-spec.bats，Task 2 已落地，commit f482840，该文件头也写了对称
# 的禁令并指向本文件）。
#
# disc-9/disc-10 与 lib-find-spec.bats 不构成分层违规而是互补：后者直接调 find_spec、
# 从不启动 pipeline.sh，覆盖不到「门禁真的把 auto/explicit 写进了 eval JSON」这一段
# 接线。本文件不得出现断言 specs.active / SPEC_FILE 优先级、find_spec 输出形状
# （source|detail|path 三段）的用例——那些归 lib-find-spec.bats。

bats_require_minimum_version 1.5.0

load "../../helpers/common"
load "../../helpers/fixtures"

setup_file() {
  halo_require_tools
}

# disc-1..8 共用：每条用例一个独立 spec 树，不经沙箱。
setup() {
  DISCOVERY_ROOT="$BATS_TEST_TMPDIR/discovery"
}

# write_discovery_spec <dir> <id> <status> [updated_at]
# updated_at 传空串时不写该字段——用来构造「完全没有 updated_at」的 mtime 回退场景
# （disc-5）与「一有一无」场景（disc-6）。
write_discovery_spec() {
  local dir="$1" id="$2" status="$3" updated="${4:-}"
  mkdir -p "$DISCOVERY_ROOT/$dir"
  {
    echo "---"
    echo "id: $id"
    echo "status: $status"
    [[ -n "$updated" ]] && echo "updated_at: $updated"
    echo "---"
    echo ""
    echo "# $id"
  } > "$DISCOVERY_ROOT/$dir/spec.md"
}

# 统一走子进程 + --separate-stderr：spec-select.sh 把选中依据和落选候选打到 stderr
# （:118 起），stdout 只有一行选中路径（:129）。不分离会让 $output 同时混进两路，
# disc-4/disc-5 这类只该在 stderr 出现的诊断文案就会污染 stdout 断言。
spec_select_run() {
  run --separate-stderr bash "$REPO_DIR/harness-template/halo/kernel/spec-select.sh" "$DISCOVERY_ROOT"
}

# disc-9..11 共用：只在真正需要沙箱的用例体内调用，磁盘上是否已有 manifest.yaml
# 就是记忆化开关——同一文件内的第一条沙箱用例负责安装，后两条直接复用，disc-1..8
# 全程不会触发这条路径。
discovery_ensure_template() {
  local dir="$BATS_FILE_TMPDIR/template"
  if [[ -f "$dir/halo/manifest.yaml" ]]; then
    export HALO_TEMPLATE_DIR="$dir"
  else
    halo_template_install
  fi
}

# set_spec_updated_at <spec.md> <value>
# make_spec（tests/helpers/fixtures.bash:29-30）给每个 spec 写死 status: drafted 与
# updated_at: 2026-01-01T00:00:00Z，所以两次裸调用会构造出精确并列 → spec-select.sh:103
# 的 rc=2。disc-11 需要两个 spec 且胜负明确，就地改写沙箱内产物的 front matter 拉开
# 排序键 2 —— 改的是沙箱里的副本，不是冻结的 tests/helpers 或 harness-template。
# 不用 sed -i：GNU 要 `-i`、BSD 要 `-i ''`，写临时文件再 mv 在两边都对。
set_spec_updated_at() {
  local file="$1" value="$2"
  sed "s#^updated_at: .*#updated_at: ${value}#" "$file" > "$file.tmp"
  mv "$file.tmp" "$file"
}

@test "front matter updated_at outranks a newer file mtime" {
  # analysis §1：mtime 是文件系统事故，git checkout 会重写它。current 的内容更新
  # （2026-08-03T13:52:14Z），merged 的内容更旧（2026-08-03T05:15:58Z）；用 touch -t
  # 显式钉死两份 mtime 模拟一次 git 检出——检出后 merged 的 mtime 反而最新。
  # 用显式时间戳而不是连续 touch 依赖墙钟间隔：不同文件系统的 mtime 粒度不同
  # （FAT32 只精确到 2 秒），显式打时间戳消除这一类偶发抖动。
  #
  # 两个 spec 必须同 status：spec-select.sh:76 把 verified 记 rank=1、其余记 rank=0，
  # 而 rank 是排序键 1（:95）。一旦一个 implemented 一个 verified，键 1 就单独定胜负，
  # updated_at（键 2）根本不参与——本用例的名字与注释会变成谎报覆盖，且与 disc-3
  # 判别同一件事。实测过：那种写法下 M9（:95 的 -k2,2r → -k2,2，把 updated_at 的
  # 排序方向整个反过来）只点亮 disc-6，本条纹丝不动。同 status 之后键 1 均匀，胜负
  # 只能落在 updated_at 上，与 mtime 的对撞才成立。
  # 两个 updated_at 必须不同：同 rank 且同 updated_at 会命中 :103 的精确并列 → rc=2。
  write_discovery_spec current current implemented "2026-08-03T13:52:14Z"
  write_discovery_spec merged merged implemented "2026-08-03T05:15:58Z"
  touch -t 202601010000 "$DISCOVERY_ROOT/current/spec.md"
  touch -t 202602020000 "$DISCOVERY_ROOT/merged/spec.md"

  spec_select_run
  assert_success
  assert_output "$DISCOVERY_ROOT/current/spec.md"
}

@test "the selection and the candidates it beat are announced on stderr" {
  # 可察觉性是这次修复的重点（analysis §1）：拒绝猜测会变成静默跳过门禁，比猜错
  # 更糟，所以 spec-select.sh 把选中依据与每一个落选候选连同它的 status/updated_at
  # 一起打到 stderr。
  write_discovery_spec current current implemented "2026-08-03T13:52:14Z"
  write_discovery_spec merged merged verified "2026-08-03T05:15:58Z"

  spec_select_run
  assert_success

  [[ "$stderr" == *"selected"* ]] || fail "stderr missing 'selected': $stderr"
  [[ "$stderr" == *"not selected"* ]] || fail "stderr missing 'not selected': $stderr"
  [[ "$stderr" == *"not selected: $DISCOVERY_ROOT/merged/spec.md (status=verified updated_at=2026-08-03T05:15:58Z)"* ]] \
    || fail "stderr missing the losing candidate's status=/updated_at=: $stderr"
}

@test "an in-flight spec outranks a verified one with a newer timestamp" {
  # 排序键 1 优先于键 2：merged 的 updated_at（08-09）比 current（08-03）更新，
  # 仍然是非终态的 current 胜出——verified 是终态，推进中的 spec 才是工作对象。
  write_discovery_spec current current implemented "2026-08-03T13:52:14Z"
  write_discovery_spec merged merged verified "2026-08-09T23:59:59Z"

  spec_select_run
  assert_success
  assert_output "$DISCOVERY_ROOT/current/spec.md"
}

@test "an exact tie is refused with exit 2 and a --spec= hint" {
  # 同一 status 档 + 同一 updated_at：真正无法判定，猜测正是这个文件存在的意义
  # 所在，拒绝而不是抛硬币。
  write_discovery_spec current current implemented "2026-08-03T13:52:14Z"
  write_discovery_spec merged merged implemented "2026-08-03T13:52:14Z"

  spec_select_run
  assert_failure 2
  assert_output ""

  [[ "$stderr" == *"--spec="* ]] || fail "stderr missing '--spec=' hint: $stderr"
  [[ "$stderr" == *"$DISCOVERY_ROOT/current/spec.md"* ]] || fail "stderr missing current candidate: $stderr"
  [[ "$stderr" == *"$DISCOVERY_ROOT/merged/spec.md"* ]] || fail "stderr missing merged candidate: $stderr"
}

@test "with no updated_at anywhere the selector falls back to mtime and says so" {
  # 全部候选都缺 updated_at 时回退 ls -t，保证不比旧行为更差，但必须明确说这是
  # mtime 兜底、git 检出可能改变它。同样用 touch -t 显式钉死 mtime，避免文件系统
  # 时间戳粒度不同导致的抖动。
  #
  # 目录名刻意让「字典序」与「mtime 序」反向：alpha-stale 字典序在前、mtime 最旧，
  # zeta-fresh 字典序在后、mtime 最新。spec_select_candidates(:45) 的 `find | sort`
  # 产出的是字典序，所以两序一旦同向，「按 mtime 选」与「按字典序取首个」会给出同一
  # 个答案，本用例名承诺的 mtime 那一半就根本没被测到——一个完全无视 mtime、只取排序
  # 首个候选的实现照样能让它变绿。改名前的夹具正是这种退化写法（newer/older，n < o
  # 且 newer 恰好 mtime 最新，两序同向）。反向命名之后 `head -1` 必然给出 alpha-stale，
  # 只有真正按 mtime 排序才选得中 zeta-fresh，断言这才具备判别力。
  write_discovery_spec alpha-stale alpha-stale drafted
  write_discovery_spec zeta-fresh zeta-fresh drafted
  touch -t 202601010000 "$DISCOVERY_ROOT/alpha-stale/spec.md"
  touch -t 202602020000 "$DISCOVERY_ROOT/zeta-fresh/spec.md"

  spec_select_run
  assert_success
  assert_output "$DISCOVERY_ROOT/zeta-fresh/spec.md"
  [[ "$stderr" == *"mtime"* ]] || fail "stderr missing 'mtime' fallback notice: $stderr"
}

@test "a spec without updated_at ranks below one that has it" {
  # analysis §1 的显式边界：缺 updated_at 排到最低而非最高——元数据失修是最弱的
  # 候选资格，不是最强的（spec-select.sh:70-73 的沉底哨兵 0000-00-00T00:00:00Z）。
  # 旧断言（smoke-test.sh）未覆盖这一条，是本次新增。两个 spec 同 status（drafted）
  # 避免与排序键 1 混淆——分歧只在 updated_at 的有无。
  write_discovery_spec has has drafted "2026-01-01T00:00:00Z"
  write_discovery_spec hasnot hasnot drafted

  spec_select_run
  assert_success
  assert_output "$DISCOVERY_ROOT/has/spec.md"
}

@test "spec-select.sh resolves without yq or a manifest on PATH" {
  # spec-select.sh:6-8 的设计约束此前无任何断言覆盖：guide.sh 必须能在没有 halo 的
  # standalone 宿主下工作，所以这个文件刻意不依赖 _lib.sh 与 yq。
  #
  # 收窄方式不能写死 `env PATH=/usr/bin:/bin`：那只在「yq 不在 /usr/bin」的宿主上
  # 才真的藏住 yq。这台 Mac 上 yq 在 /opt/homebrew/bin，收窄有效；但 Linux CI 上
  # yq 常常就装在 /usr/bin，同一行会静默退化成「yq 在 PATH 上时 spec-select.sh 能
  # 跑」——一条恒绿、什么都不证明的断言。Task 12 要在 ubuntu runner 上跑本套件，
  # 这是活风险不是假想。
  #
  # 改成显式白名单：只把 spec-select.sh 真正用到的工具软链进一个空目录，yq 永远不
  # 在其中，于是收窄在任何宿主上都成立。
  #
  # 白名单只是**记录**本文件当前用到的工具，**不是**依赖清单断言——别指望「哪天多依赖
  # 一个工具这里就会红」。实测（逐个从白名单里抽掉该工具后跑本条）：
  #   抽 find / sort / sed / cut / head → 红；抽 awk / grep / ls / xargs / tr → 仍绿。
  # 后五个绿在两条静默降级路径上：抽 awk 时 frontmatter_value（spec-select.sh:25）取空，
  # has_updated 落 false，:80-85 转进 `ls -t` 的 mtime 兜底，本条只有一个候选，兜底恰好
  # 选中同一个；抽 grep 时 :103 的 `$(… | grep -c .)` 取空串，`[[ "" -gt 1 ]]` 静默为假，
  # 并列拒绝那条分支直接绕过。ls/xargs/tr 只出现在 :85 那条兜底上，awk 在时压根不可达。
  # （只有 awk 与 ls 同时抽掉才会红——兜底被走到了、兜底自己又缺工具。）
  # 本条真正守住的是「不依赖 yq」，由 M15 点亮；上面这些只是白名单的附带说明。
  write_discovery_spec alpha alpha drafted "2026-01-01T00:00:00Z"

  local narrow_bin="$BATS_TEST_TMPDIR/narrow-bin"
  mkdir -p "$narrow_bin"
  local tool tool_path bash_path
  bash_path="$(command -v bash)"
  for tool in find sort awk sed cut grep head ls xargs tr; do
    tool_path="$(command -v "$tool")" \
      || fail "cannot build the narrowed PATH: '$tool' is missing from this host's PATH"
    ln -sf "$tool_path" "$narrow_bin/$tool"
  done

  # 收窄必须真的生效。失败时要响亮地红，不是 skip——静默跳过正是本批次要消灭的形态。
  run env PATH="$narrow_bin" "$bash_path" -c 'command -v yq'
  assert_failure
  assert_output ""

  run --separate-stderr env PATH="$narrow_bin" "$bash_path" \
    "$REPO_DIR/harness-template/halo/kernel/spec-select.sh" "$DISCOVERY_ROOT"
  assert_success
  assert_output "$DISCOVERY_ROOT/alpha/spec.md"
}

@test "an empty specs root returns 1, not an empty selection" {
  # 边界：目录存在但没有任何 spec.md。返回码必须是 1（无候选），stdout 必须是空——
  # 不能悄悄打印一个空字符串然后让调用方把它当成「选中了空路径」。
  mkdir -p "$DISCOVERY_ROOT"

  spec_select_run
  assert_failure 1
  assert_output ""
}

@test "pipeline records an auto-discovered spec as source auto" {
  discovery_ensure_template
  halo_sandbox_clone
  # disc-9 的沙箱只放一个 spec：闭合批次 1 的 O-4。旧断言在装满十几个 spec 目录的
  # 共享沙箱里，依赖「missing-evidence 恰好携带真实时间戳而唯一胜出」——那是一个
  # 未被任何断言保护的隐性前提。单 spec 沙箱把它变成用例自己写死的前置：没有第二个
  # 候选，自然不会撞上 make_spec 精确并列（同 status: drafted + 同 updated_at）的
  # rc=2 陷阱。
  make_spec halo/specs onlyspec

  # 前置写死，不靠推断：O-4 的教训就是「唯一胜出」这个前提没有任何断言保护。这里把
  # 「被扫描的根下恰好只有一个 spec.md」变成用例自己断言的事实——将来模板要是开始
  # 附带一份样例 spec，这条会立刻响亮地红，而不是悄悄把本用例的含义换成别的。
  run bash -c "find halo/specs -name spec.md -type f -not -path '*/.locks/*' | wc -l | tr -d '[:space:]'"
  assert_success
  assert_output "1"

  local eval_json="$SANDBOX/halo/state/discovery-eval.json"
  run bash halo/kernel/delivery/pipeline.sh --only=spec-lint --json-out="$eval_json"
  assert_success
  assert_output --partial "source=auto"

  run yq -e '.spec_source == "auto"' "$eval_json"
  assert_success

  # 刻意不断言 .spec_source_detail 的内容，也不反过来断言它为空。
  # ① _lib.sh:169 的 `selected="$(spec_select …)"` 是一次命令替换，bash 对命令替换
  #    恒定 fork 子 shell，spec_select（spec-select.sh:116）对全局变量
  #    SPEC_SELECT_DETAIL 的赋值发生在子 shell 里，退出后不会回写父 shell，
  #    _lib.sh:171 读到的永远是 spec-select.sh:18 初始化的空字符串——这是一个已
  #    确认的真实缺陷，记入实现观察 O-14（task-2-report.md）。批次 3 走完整 SOP
  #    修，本批次不碰 kernel。
  # ② 但也不能反过来断言"detail 为空"：那是把缺陷行为写成期望契约，比没有断言更
  #    坏（批次 1 删过一条同类反面教材：ac-coverage 的
  #    `else pass "ran (exit=$AC_EXIT)"` 把任意退出码都记成通过）。O-14 修复之后
  #    detail 应该变回非空，这条测试不该在那时候变红。
  # ③ "排序依据无人可测"并不成立——spec_select 仍然把选中依据和落选候选打到
  #    stderr（spec-select.sh:118 起，本文件 disc-2 已覆盖），只是
  #    find_spec/find_spec_with_source 这一段管道把它弄丢了，碎的只是这一段。
}

@test "pipeline records an explicitly pinned spec as source explicit" {
  discovery_ensure_template
  halo_sandbox_clone
  make_spec halo/specs onlyspec

  local eval_json="$SANDBOX/halo/state/discovery-eval-explicit.json"
  run bash halo/kernel/delivery/pipeline.sh --only=spec-lint \
    --spec="$SANDBOX/halo/specs/onlyspec/spec.md" --json-out="$eval_json"
  assert_success

  run yq -e '.spec_source == "explicit"' "$eval_json"
  assert_success
}

@test "guide.sh and the kernel selector resolve the same spec" {
  discovery_ensure_template
  halo_sandbox_clone
  # 旧断言两处要改，理由写在这里：
  # 1. 旧断言 `cp "$REPO_DIR/prismspec/bin/guide.sh" "$SANDBOX/prismspec/bin/guide.sh"`
  #    是纯冗余——install.sh → init.sh 链路已经把仓库的 prismspec/ 装进沙箱
  #    （tests/unit/harness-setup.bats 已断言 $SANDBOX/prismspec/bin/lint.sh 存在）。
  #    本次任务 Step 1 已实测 `diff prismspec/bin/guide.sh <sandbox 内副本>`，结果
  #    逐字相同，见 task-8-report.md。
  # 2. 旧断言被 `if [[ -f "$REPO_DIR/prismspec/bin/guide.sh" ]]` 包着且无 else——
  #    文件不在时整条断言消失且不报警，正是设计文档「诚实 skip」要拦的形态。这里
  #    改成无条件断言。
  #
  # 3. 沙箱必须放 **两个** spec。只放一个时 kernel_pick_id 恒为那一个，
  #    `.spec_id == kernel_pick_id` 对任何「能解析出点什么」的实现都成立——那是同义
  #    反复，不是简报说的「加强」。两个 spec 之后这条等式才真的在判别「选中了哪一
  #    个」。alpha-older 沿用 make_spec 的默认 updated_at（2026-01-01T00:00:00Z），
  #    zeta-newer 改到 2026-08-03T13:52:14Z：同 status（都是 drafted，键 1 均匀）、
  #    键 2 分胜负，赢家同时是**字典序靠后**的那个——于是「干脆取第一个候选」这类
  #    退化实现会被抓住，而不是碰巧蒙对。
  make_spec halo/specs alpha-older
  make_spec halo/specs zeta-newer
  set_spec_updated_at "$SANDBOX/halo/specs/zeta-newer/spec.md" "2026-08-03T13:52:14Z"

  run --separate-stderr bash halo/kernel/spec-select.sh halo/specs
  assert_success
  local kernel_pick="$output"
  local kernel_pick_id
  kernel_pick_id="$(basename "$(dirname "$kernel_pick")")"

  # 前置写死：两边共用同一份实现（guide.sh:125-132 在 halo 宿主下直接 source 本仓
  # 的 spec-select.sh 再调 spec_select），所以「两边一致」这条等式**抓不到共同错**
  # ——kernel 排错了，guide 也跟着排错，等式照样成立。这一行才是拦共同错的那道闸：
  # 它写死了本 fixture 下唯一正确的答案。
  assert_equal "$kernel_pick_id" "zeta-newer"

  run --separate-stderr bash prismspec/bin/guide.sh --json
  assert_success
  local guide_json="$output"

  run yq -e ".spec_id == \"$kernel_pick_id\" and .spec_source == \"auto\"" <<< "$guide_json"
  assert_success
}

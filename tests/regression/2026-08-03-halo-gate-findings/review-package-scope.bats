#!/usr/bin/env bats
# Bug report: docs/bug_report/2026-08-03-halo-gate-findings.md
#   （聚合上报，8 条已修缺陷按缺陷拆分到本目录；映射见 docs/bug_report/INDEX.md）
# Root cause class: C. 失败方向搞反 + 框架自我矛盾
# Fixed by: df7991e (#12 "Stop drift-check from reporting unchecked dimensions as clean"；
#   review-package 空评审包的修复见
#   docs/bug_report/2026-08-03-halo-gate-findings-analysis.md §5)
#
# 复核 §5 的结论：旧版 `review-package.sh:58,64`（修复前）只跑
# `git diff --stat` 与 `git diff -- .`——不带 --cached、不带 commit 范围、不含
# untracked。这是框架自我矛盾：逐任务提交是 SDD 纪律本身要求的做法，按纪律执行的
# 项目必然拿到零信息评审包。
#
# 修复后：新增 --base=<ref>，缺省按 origin/HEAD → origin/main → origin/master →
# main → master 依次尝试 merge-base；全部失败时诚实报告「未解析到 base」而不是
# 静默退化成只看工作树。输出拆成 Committed Diff / Uncommitted Diff / Untracked
# Files 三段；untracked 文件内容在数量 <= UNTRACKED_CONTENT_LIMIT(50) 时内联，
# 超限只列清单。
#
# rp-2 与 rp-3 必须拆开：「列清单」与「内联内容」是 review-package.sh 里两条独立
# 分支，压进一条断言的话，把 UNTRACKED_CONTENT_LIMIT 改成 0 也不会让测试变红。

load "../../helpers/common"
load "../../helpers/fixtures"

setup_file() {
  halo_require_tools
  halo_template_install
}

setup() {
  halo_sandbox_clone
}

# review_pkg_repo() —— rp-1..rp-5 共用的沙箱搭建。
#
# halo_template_install 只跑了 `git init --quiet`；halo_sandbox_clone 用 cp -R
# 把 .git 一并复制过来。到这一步为止：沙箱确实是 git 仓库，但没有任何提交、没有
# main 分支、没有 user 身份配置。四样东西缺一不可，否则 rp-1..rp-5 测不到东西：
review_pkg_repo() {
  # ① .gitignore —— 载荷，不是装饰。init.sh 只写了 .halo/sdd/ 与
  #    .prismspec/runs/，装好的 harness 有 800+ 个未跟踪文件（vendor 进来的整棵
  #    框架源码树 + .claude/ + .github/ + CLAUDE.md + go.mod + halo/ + prismspec/），
  #    远超 review-package.sh:82 的 UNTRACKED_CONTENT_LIMIT=50。不写这段，脚本会
  #    走「超限只列清单」分支，未跟踪内容不再内联，rp-3 就测不到东西——它会变成
  #    一条永远绿的假测试。不要把这段当成可以「简化」掉的样板代码删掉。
  #    （已实测核对：这 7 条模式覆盖后未跟踪计数从 877 降到 0，见 task-7-report.md。）
  cat > .gitignore << 'IGNORE'
.claude/
.github/
.halo/
halo/
prismspec/
go.mod
*.md
IGNORE

  # ② 身份 —— CI runner 没有全局 user.name/user.email，逐条命令用 -c 注入，
  #    不写进沙箱的 git config（那是持久状态，会外溢到同一沙箱里的后续命令）。
  git add .gitignore
  git -c user.email=bats@halo.test -c user.name=bats commit -q -m "review-pkg baseline"

  # ③ main 分支 —— resolve_base_ref 的候选链是 origin/HEAD → origin/main →
  #    origin/master → main → master，且会跳过与当前分支同名的候选。git init 的
  #    默认分支名依赖 init.defaultBranch，不能假设已经是 main，必须显式改名，
  #    否则候选链可能全部落空，BASE="" 会让 committed diff 整段消失。
  git branch -M main

  make_spec halo/specs rp-probe 1
  make_plan halo/specs rp-probe 1 1 decl-en

  git checkout -q -b review-package-branch
  echo "baseline line" > review-pkg-src.txt
  git add review-pkg-src.txt
  git -c user.email=bats@halo.test -c user.name=bats commit -q -m "review-pkg task baseline"
  echo "committed change line" >> review-pkg-src.txt
  git add review-pkg-src.txt
  git -c user.email=bats@halo.test -c user.name=bats commit -q -m "review-pkg task change"

  # ④ 未跟踪文件 —— rp-2/rp-3 要测的对象本身。
  echo "untracked content" > review-pkg-untracked.txt
}

@test "the package includes committed work from the base merge-base" {
  review_pkg_repo
  run bash halo/kernel/orchestrator/sdd/review-package.sh rp-probe branch
  assert_success
  local pkg="$output"
  run grep -F "committed change line" "$pkg"
  assert_success
  run awk '/^## Committed Diff$/{f=1;next} f && /^```diff$/{c=1;next} c{print; exit}' "$pkg"
  refute_output "(none)"
}

@test "untracked files are listed" {
  review_pkg_repo
  run bash halo/kernel/orchestrator/sdd/review-package.sh rp-probe branch
  assert_success
  local pkg="$output"
  # 命中必须限定在 `## Untracked Files` 段（review-package.sh:156）之内，不能全文 grep。
  # 理由是实测出来的，不是防御性洁癖：`## Git Status` 段（review-package.sh:117-120）
  # 调用 `git status --short`，它把未跟踪文件输出成 `?? review-pkg-untracked.txt`。
  # 那是一条与本条要测的分支毫无关系的代码路径，却足以让全文 grep 无条件成立——
  # 把 review-package.sh:80 的 UNTRACKED_FILES 置空（未跟踪清单功能彻底损坏、
  # 段内只剩 `(none)`）之后，旧的全文 grep 版本依然通过。那是一条假绿断言。
  #
  # 段边界：自 `## Untracked Files` 标题的下一行起，到下一个以 `#` 开头的行为止。
  # 这样既切掉了后面的 `## Expected Review Output`，也切掉了段内的
  # `### Untracked Content` 子段（review-package.sh:163）——内联内容里的 diff 头
  # 同样带着文件名，放它进来等于把 rp-3 的证据借给 rp-2，本条会重新失去对
  # 「列清单」这一条分支的判别力。
  run awk '/^## Untracked Files$/{f=1;next} f && /^#/{exit} f{print}' "$pkg"
  assert_success
  assert_output --partial "review-pkg-untracked.txt"
}

@test "untracked file content is inlined below the limit" {
  review_pkg_repo
  run bash halo/kernel/orchestrator/sdd/review-package.sh rp-probe branch
  assert_success
  local pkg="$output"
  run grep -F "### Untracked Content" "$pkg"
  assert_success
  run grep -F "untracked content" "$pkg"
  assert_success
}

@test "the package records the base ref it used" {
  review_pkg_repo
  run bash halo/kernel/orchestrator/sdd/review-package.sh rp-probe branch
  assert_success
  local pkg="$output"
  run awk '/^## Sources$/{f=1} f{print} f && /^## Git Status$/{exit}' "$pkg"
  assert_success
  assert_output --partial "Diff base:"
  assert_output --partial "committed range"
}

@test "an explicit --base overrides discovery" {
  review_pkg_repo
  run bash halo/kernel/orchestrator/sdd/review-package.sh --base=main rp-probe branch
  assert_success
  local pkg="$output"
  run grep -F "Diff base:" "$pkg"
  assert_success
  assert_output --partial "main"
}

@test "a repository with no resolvable base says so instead of silently dropping committed work" {
  # 独立、更小的沙箱：只有一个分支（当前 HEAD 所在的那个，不管它叫什么名字）、
  # 一次提交、没有 origin 远端、没有 main/master。resolve_base_ref 的候选链会
  # 因为「候选与 HEAD 同名」被跳过（如果默认分支恰好叫 main）或者根本找不到
  # main/master 分支（如果默认分支叫别的名字）——两种情况都落到 BASE=""，
  # 与具体的 git 默认分支名无关，天然跨平台。
  make_spec halo/specs rp-probe 1
  make_plan halo/specs rp-probe 1 1 decl-en
  git add -A
  git -c user.email=bats@halo.test -c user.name=bats commit -q -m "only commit"

  run bash halo/kernel/orchestrator/sdd/review-package.sh rp-probe branch
  assert_success
  local pkg="$output"
  run grep -F "none resolved — committed work is NOT in this package" "$pkg"
  assert_success
}

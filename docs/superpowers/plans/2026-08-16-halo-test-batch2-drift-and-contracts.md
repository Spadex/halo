# Halo 测试体系批次 2：drift-check 系列 + 契约单测首批

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**基线提交：`606856a`**（全部行号以此为准，已逐条实测核对）。

---

## Context

`docs/superpowers/specs/2026-08-07-halo-test-system-design.md` 定的四层防线测试体系，批次 0（bats 骨架）与批次 1（AC 系列迁移）已完成。设计文档定义的批次 2 = **drift-check 系列（smoke-test §7c，对应 #12/#13/#16）+ 契约单测首批（`find_spec`、`narrow_acs_to_declared`）**。

为什么是这两项：

**一、`find_spec` 的契约单测。** 实测核对：`find_spec` / `find_spec_with_source` 有 **5 个调用点**（`pipeline.sh:298`、`gates/drift-check.sh:32`、`gates/spec-lint.sh:13`、`gates/ac-coverage.sh:34`、`gates/compliance.sh:34`），后四者的「rc=2 不得降级为 skip」分支是**四份逐字副本**——根因 H 的现成温床。#15 的复核原话：「验错 spec 不是某一个门禁的问题，而是整条链路同时错到同一个错误对象上，因此内部完全自洽，没有任何一处会互相打架报警。」这类缺陷只有不经门禁的直接测试能拦。

**二、drift-check 系列（§7c）。** 承载 #12/#13/#16 三份报告，覆盖根因 C（fail-open/fail-closed 方向）、D（列序）、E（框架读不懂自带模板）、F（语法变体）四类，且是**唯一有 macOS 专属陷阱**的一段（BSD awk 对多字节字符串 `==` 比较不可靠，`drift-check.sh:276-280` 目前只靠一句注释防回退）。批次 0 建的双平台 CI 在这里第一次真正兑现价值。

两者在**批次 1 的 O-4** 上交汇：smoke-test 沙箱能通过 spec 自动发现断言，靠的是 `missing-evidence` 恰好携带真实时间戳而唯一胜出，是一个未被任何断言保护的隐性前提。处理方式不是补一条断言，而是把 §9b 整节迁走（见「决定二」）。

**预期产出**：23 条 smoke-test 断言（§7 残余 2 + §7c 13 + §9b 8）→ 7 个 regression 文件（41 条）+ unit 由 18 增至 50 条。变异测试证明等价后删除三个区间，smoke-test **145 → 122**，bats 总量 **55 → 128**。同时闭合批次 1 记录的覆盖空洞（`ac-coverage.sh:142` 自跳过删掉后一条测试都不红）。

---

## Global Constraints

- 除已 vendored 的 bats（core 1.12.0 / support 0.3.0 / assert 2.1.0）外**不引入任何新依赖**。前置仍为 `halo_require_tools` 的 `yq` + `git`。
- 新增/修改的 `.sh` / `.bash` 必须过 `bash -n` 与 `shellcheck --severity=warning`；`.bats` 不进 shellcheck。
- 兼容 macOS（BSD）与 Linux：禁止无后缀 `sed -i`；**BSD sed 替换串不支持 `\n`**，复制行一律用 `awk`；禁止 GNU 专属 flag。**BSD awk 对多字节字符串 `==` 比较不可靠**（`drift-check.sh:276-277` 的注释）——测试代码里按中文表头判断的地方同样禁止用 `==`。
- 不得出现根因 B/D 反模式：不用 `cmd | grep -q` 作管道读端末端判定；不消费无 `sort` 的 `find` 输出做决策；命令替换包 grep 必须 `|| true` 兜底。
- **不得修改 `harness-template/` 与 `prismspec/` 下的实现代码。** Task 9 的变异是临时验证动作，每条前后强制 `git status --porcelain` 校验，任何变异不得进入提交。发现实现缺陷只记入「实现观察」。
- `tests/smoke-test.sh` 冻结：**只删不加**。本批次对它的唯一改动是删除三个整块行区间，不改任何残留行。
- 计划、`tests/` 文档、`docs/bug_report/INDEX.md` 用简体中文；`AGENTS.md` 保持英文；`.bats` 的 `@test` 名用英文，注释用中文。
- `yq` 是 mikefarah v4：数组字面量比较静默求值为 false，数组断言走 `join(",")` 或 `length`。
- 提交信息结尾带 `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`。

### 一条本批次新增的硬约束（已实测确认，必须写进 `tests/README.md`）

**`harness-template/halo/kernel/_lib.sh` 绝对不可以 `source` 进 bats 测试进程。**

实测核对：`_lib.sh:79-82` 定义了 `pass()` / `fail()` / `warn()` / `skip()`，其中

- `fail` 与 `tests/vendor/bats-support/src/error.bash:38` 的 `fail()` 同名——那是 bats-assert 全部 `assert_*` / `refute_*` 的失败原语；
- `skip` 与 `tests/vendor/bats-core/lib/bats-core/test_functions.bash:437` 的 bats 内建 `skip()` 同名。

source 进测试进程后，`_lib.sh` 的 `fail()` 会把断言失败变成一行 `❌ …` 输出、计数器加一、**返回 0**——所有 `assert_*` 从此永不让用例变红。这是最坏的一类失败：全绿的假绿。

因此契约单测一律走子进程：

```bash
# 必须走子进程：_lib.sh:79-82 的 pass/fail/warn/skip 与 bats 内建 skip、
# bats-support 的 fail 同名，source 进测试进程会把断言失败原语替换掉（假绿）。
# 附带收益：_lib.sh:12 的 set -euo pipefail 不外溢；find_spec 的 rc 1/2 直接落到 $status。
lib_run() { # <bash 片段>
  run bash -c 'source halo/kernel/_lib.sh; shift; eval "$*"' _ "$@"
}
```

`spec-select.sh` 不受此限（只定义 `spec_select*` 与 `SPEC_SELECT_DETAIL`），但它本来就可执行，一律 `run bash halo/kernel/spec-select.sh <root>`。

---

## 范围边界（明确不越界）

已逐项实测核对，本批次**不碰**：

| 对象 | 位置（`606856a`） | 归属 |
|---|---|---|
| pipeline gate JSON 嵌入 / loop state / escalation | `smoke-test.sh:1547-1597` | 批次 3 |
| summary-draft 嵌入 eval metrics | `:1557-1568` | 批次 3 |
| learn-draft require-review / promote / discard、knowledge-lint / knowledge-review | `:1599-1707` | 批次 3（与 §9c 同属 #15 §3.3） |
| failure-category-lint / 可配置分类 | `:1709-1754` | 批次 3 |
| outcome-link / outcome-report / eval-summary / pr-comment / eval-history / eval-sink / eval-dashboard / eval-query | `:1756-1852` | 批次 3/4 |
| `red-multi-ac`（#10 量词）、`red-many-ac` + 慢 yq shim（#11 SIGPIPE） | §6d `:919-1525` | 批次 3 |
| §8 Context knowledge backend | `:2225-2290` | 批次 3 |
| §9 Spec-lock | `:2291-2307` | 批次 3/4 |
| §9c Learn draft promotion shape | `:2427-2504` | 批次 3 |
| `task_has_ac_declaration` / AC 归属 / 模式解析链 契约单测 | `_lib.sh:241` 等 | 批次 3 |
| meta-lint 五条规则、报告↔测试对应检查、`release-check.sh` 扩展 | `tests/meta/` | 批次 3 |
| O-1（node/js/ts 缺跨 spec 归属保护） | `ac-coverage.sh:127/138` | 批次 3，需独立走完整 SOP |
| E2E 主干、删空 smoke-test | `tests/e2e/` | 批次 4 |

**一处边界更正**：§7 的标题 `── 7. AC-coverage gate ──`（`:1526-1527`）在本批次**仍不消失**——删掉 `:1529-1546` 后，`:1547` 起的 pipeline/eval/learn/knowledge/outcome 块仍在该标题之下。批次 1 的 O-6 预测它「在批次 2 迁 drift-check 时消失」，实测不成立，顺延批次 3。

---

## 决定一：聚合上报的回归文件命名

`tests/README.md` 现行规则是「一份 bug 报告 = 一个 `.bats` 文件」。本批次的三份报告有两份是**一批 bug** 而非一个：

| 报告 | 已修缺陷条数 | 批次分布 |
|---|---|---|
| `2026-08-03-halo-gate-findings.md` | 8（analysis §1-§5、§7） | 全在批次 2 |
| `2026-08-03-halo-gate-findings_2.md` | 2（§1 = 上报 §8.1 spec 发现；§3 = §3.3 learn-draft 形态） | **跨批次 2 与 3** |
| `2026-08-03-fastapi-collection-root-route-dropped.md` | 1（+复核发现的多行装饰器） | 全在批次 2 |

**决定：聚合上报按缺陷拆，用目录形态承载；目录名与报告 basename 逐字相同。**

```
tests/regression/2026-08-03-halo-gate-findings/          # 目录名 = 报告 basename
  drift-error-codes.bats            ← analysis §1
  drift-route-table.bats            ← analysis §2
  compliance-source-trace.bats      ← analysis §3
  plan-lint-placeholder.bats        ← analysis §4
  review-package-scope.bats         ← analysis §5
tests/regression/2026-08-03-halo-gate-findings_2/
  spec-discovery.bats               ← analysis §1（上报 §8.1）· 本批次
  （learn-draft-promote-shape.bats  ← analysis §3 · 批次 3）
tests/regression/2026-08-03-fastapi-collection-root-route-dropped.bats   # 单缺陷，平铺
```

四条理由：

1. **`_2` 那份报告横跨两个批次**（决定性理由）。平铺成一个文件的话，批次 3 得回来往一个已通过等价性验证、已写进提交记录的文件里追加，归因链就断了。目录形态下两批各加一个文件。
2. **`setup` 形态无法共存。** `review-package-scope` 需要真实 git 提交历史与分支，`drift-route-table` 需要 `language=python` + `framework=fastapi`，`plan-lint-placeholder` 需要 `halo/specs/<id>/` 下的 spec+plan 对。塞进一个文件就要写一个服务四种沙箱形态的 `setup`——那正是把 smoke-test 的问题搬进 bats。
3. **目录形态是仓内既有语汇**，不是新发明：`docs/bug_report/` 下已有 `ac-coverage-bug/` 与 `2026-08-07-runningtime-report/` 两份目录形态报告。
4. **机器对拍不受影响。** `tests/run.sh:23` 的 `find … -name '*.bats'` 与 `:33` 的 `bats --recursive` 都已递归，无需改动。批次 3 的对拍规则改一行即可：

   > 存在 `<base>-analysis.md` 的报告 ⇒ 必须存在 `tests/regression/<base>.bats` **或** `tests/regression/<base>/` 目录（其下至少一个 `.bats`），除非 `INDEX.md` 登记了映射或豁免。

**代价（已知并接受）**：子目录里 `load` 路径变成 `load "../../helpers/common"`。

**被否决的替代**：`<base>.<slug>.bats` 点号分隔。它发明了一套新文件名语法，对拍规则要变成前缀匹配，且解决不了理由 1。

---

## 决定二：§9b 归属——**随本批次迁走**（维护者已确认）

设计文档批次表把「learn-draft §9b/9c」列在批次 3。实测核对确认是笔误：`smoke-test.sh:2308` 的节标题是 `── 9b. Spec auto-discovery ranks on front matter, not file mtime ──`，全节 8 条断言全部打 `spec-select.sh` / `pipeline.sh` / `guide.sh`，与 learn-draft 无关；`:2427` 的 §9c 才是 learn draft。`2026-08-03-halo-gate-findings_2-analysis.md` 也明确把 §9b 列为「§8.1 spec 自动发现」的回归覆盖。

四条理由：

1. **避免一个批次周期的重复覆盖。** `find_spec` 的排序语义 100% 由 `spec_select` 提供（`_lib.sh:169` 是唯一入口）。留到批次 3 意味着新旧两套断言在同一份实现上并行一个周期，且是同一个失败模式。
2. **等价性验证的完整性。** 针对 `spec-select.sh` 的九条变异（M8-M16）会同时点亮新 unit 用例与旧 §9b 断言。等价性已证却不删旧段，下批还要把同样的变异再跑一遍。
3. **O-4 唯有整节迁走才闭合。** 已 grep 核实：smoke-test 里依赖自动发现胜出者的断言**只有** §9b 的 `:2388`（`pipeline.sh --only=spec-lint` 无 `--spec`）与 `:2416`（`guide.sh --json` 无 spec 参数）两条。`:420`/`:437` 的 pipeline 调用带 `--skip-spec` 且位于 §5（此时 `halo/specs` 为空）；`:338`/`:345` 的 guide.sh 调用位于 §3（modern-feature 创建之前）。删完 §7c + §9b，smoke-test 里**再没有任何断言依赖「哪个 spec 恰好胜出」**——O-4 从「补一条断言提醒后人」升级为「隐性前提被物理移除」。
4. **「一份报告 = 一个测试文件」不再构成阻力**（见决定一）。

### 对批次 3 范围的影响（须同步到设计文档）

设计文档批次表第 3 行的「learn-draft §9b/9c」**范围相应缩减为「learn-draft §9c」**。批次 3 从这条承接的是 `smoke-test.sh:2427-2504`（§9c，4 条断言）与同源的 `:1599-1674`（learn-draft require-review / promote / discard）。Task 11 Step 5 负责在设计文档里就地更正——设计文档是活文档，留着笔误会让批次 3 的执行者去找一段不存在的 learn-draft §9b。

---

## 决定二之附：§9b 与 `find_spec` 契约单测的分工边界

两层同时存在，必须写清谁守什么，否则出现「都覆盖了，但说不清是哪层守住的」——那等于两层都不可信。

### 分层判据（一句话）

> **改 `spec-select.sh` 的排序键/输出会红的，归 regression；改 `_lib.sh` 的分支/返回码会红的，归 unit。**

变异表就是这条判据的机器证明，执行 Task 9 时必须对照核验：

| 变异组 | 打哪个文件 | 应当只点亮 |
|---|---|---|
| M1-M7 | `_lib.sh:152/153/157/171/174/184/187` | `unit/lib-find-spec.bats` 的 find-* |
| M8-M16 | `spec-select.sh:60/72/76/85/88-89/95/103/120-127` + 顶部 | `regression/…/spec-discovery.bats` 的 disc-*（M9、M11 例外，见下） |

**若某条 M1-M7 点亮了 disc-\*，或某条 M8-M16（除 M9/M11）点亮了 find-\*，说明分层被破坏，回到对应文件收窄断言。** 这条核验写进 Task 9 Step 3。

### 逐条归属

**`unit/lib-find-spec.bats` 断言的是 `_lib.sh` 三个函数本身**——来源优先级、返回码契约、输出形状、以及返回码如何被 5 个调用点消费。它**不断言排序算法为什么这么排**：find-1..5 守来源判定与优先级（`_lib.sh:152-166`）；find-6 守 auto 分支的 source 标签与 detail 透传（`:169-172`）；find-7 守无候选时 rc=1 且 stdout 为空；find-8/9 守 rc=2/rc=0 **在 `_lib.sh` 层的透传**（`:174`），不是排序算法本身；find-10 守 pipefail 下不终止调用方；find-11 守三段形状；find-12 守 5 个调用点在 rc=2 时拒绝而非静默跳过。

**`spec-discovery.bats` 断言的是 #15 §8.1 的缺陷本体**——`spec-select.sh` 的排序算法与可察觉性，以及 provenance 如何进入 eval JSON 与 `guide.sh --json`：disc-1 守 mtime 无关；disc-2 守选中项与落选项都上 stderr；disc-3 守排序第一键；disc-4 守并列时的终止条件；disc-5/6 守两处边界；disc-7 守 standalone 契约；disc-8 守空候选；disc-9/10 守 `spec_source`；disc-11 守 guide.sh 与 kernel 选同一个。

### 两处**故意保留**的交叠及其正当性

1. **find-8 ↔ disc-4**（并列场景）。断言对象不同：disc-4 断「选取器拒绝猜测并给出 `--spec=` 提示」（报告的诉求），find-8 断「rc=2 被 `_lib.sh:174` 原样透传而不塌成 1」。**M11**（`spec-select.sh:103`）两条都点亮；**M4**（删 `_lib.sh:174` 的 rc=2 透传）**只点亮 find-8**——这条单点变异就是交叠正当性的机器证明。若 M4 也点亮 disc-4，说明 disc-4 越界断了 `_lib.sh` 的行为，须收窄。
2. **find-9 ↔ disc-1**（时间戳排序）。find-9 借排序结果驱动 rc=0，M9 会同时点亮两者——属容许交叠，记录即可，不作为分层破坏。

### 明令禁止的重复（评审对拍点）

- `unit/lib-find-spec.bats` **不得**出现断言 spec-select stderr 文案、mtime 行为、`status` 排序、`updated_at` 比较的用例。它构造并列/唯一场景只为驱动 rc，不为验证排序为什么这么排。
- `spec-discovery.bats` **不得**出现断言 `specs.active` / `SPEC_FILE` 优先级、`find_spec` 输出形状的用例。

两个文件的文件头都要写上这两行禁令，并互指对方路径。

---

## 决定三：§7c 各组输入的 fixture 三档判定

准绳是 `tests/README.md:116-121` 已成文的三档分界线。

| # | 输入（smoke-test 行区间） | 判定 | 理由 |
|---|---|---|---|
| 1 | drift 空 spec（`{ERROR_CODE}` 占位表，`:1866-1875`） | **静态 fixture** | 全部价值在于与 `orchestrator/templates/spec-template.md:86-91` **逐字一致**（已核对）。根因 E 的证据只有能被逐字比对时才成立。且被两个文件消费 |
| 2 | python 字符串错误码 spec + `errors.py`（`:1890-1907`） | **用例内 builder** | 两侧各 3-6 行、单一陷阱、只有一个文件消费。按 `tests/README.md:131-132` 留在该文件里 |
| 3 | FastAPI 单行装饰器 + `APIRouter(prefix="/api")`（`:1937-1951`） | **静态 fixture** | 一份 routers.py 同时承载「装饰器形态 + prefix 形态 + 刻意缺一条 DELETE」，同目录还要放两份列序不同的 spec |
| 4 | FastAPI 集合根 `@router.get("")`（`:2022-2041`） | **静态 fixture** | #16 analysis §6 写死两条约束：同 fixture 内放 `@router.get("/")` 会让尾段宽松匹配掩盖空路径漏检；必须保留一条单行路由，否则 `CODE_ROUTES` 为空走 `gate_skip` 假通过。这两条只有在文件可被逐字审阅且 README 登记时才不会被后人「顺手清理」 |
| 5 | 列序倒置表 `\| 端点 \| 方法 \| 说明 \|`（`:1993-2003`） | **静态 fixture**，与 #3 同目录 | 设计文档第 70 行点名。它同时是 BSD awk 多字节 `==` 陷阱的载体（M39 的靶子），中文表头一个字都不能改 |
| 6 | 多行装饰器 routers.py（`:2087-2111`） | **静态 fixture** | 设计文档第 70 行点名。本批次还要补 analysis §4 提到但旧断言未覆盖的多行 `APIRouter(prefix=…)` |
| 7 | compliance 中文来源表（`:2139-2150`） | **静态 fixture** | 与 #1 同理：与 `spec-template.md:40-49` 逐字一致 |
| 8 | plan-lint 占位符（`:2164-2175`） | **用例内 sed 派生** | 单元素改写。注意 `make_plan` 产的是 `- Scope: Implement the smallest path needed for AC-${ac}.`（`fixtures.bash:152`，与 smoke-test 措辞**不同**），sed 必须按 `needed for AC-1\.` 定位——两条任务的 Scope 行只有 AC 号不同 |
| 9 | review-package git 仓库（`:2187-2220`） | **用例内 builder** | 它是**过程**不是文件内容，无法静态化；只有一个文件消费 |

### 关于 #9：沙箱是不是 git 仓库？（已实测核实）

**是，但只有 `git init`，没有任何提交、没有 `main` 分支、没有 user 身份配置。** `halo_template_install` 跑 `git -C "$HALO_TEMPLATE_DIR" init --quiet`，`halo_sandbox_clone` 的 `cp -R` 把 `.git` 一并复制；现有 bats 用例里没有任何 `git commit`。

因此 `review_pkg_repo()` 必须自建四样东西，缺一不可：

```bash
review_pkg_repo() {
  # 1) .gitignore —— 载荷，不是装饰。init.sh 只写了 .halo/sdd/ 与 .prismspec/runs/，
  #    装好的 harness 有远超 50 个未跟踪文件，会撞上 review-package.sh:82 的
  #    UNTRACKED_CONTENT_LIMIT=50，走到「超限只列清单」分支——第 3 条断言就测不到东西了。
  cat >> .gitignore << 'IGNORE'
.halo/
halo/
prismspec/
go.mod
*.md
IGNORE
  # 2) 身份 —— CI runner 无全局 user.name/user.email，用 -c 逐命令注入
  echo "baseline line" > review-pkg-src.txt
  git add .gitignore review-pkg-src.txt
  git -c user.email=bats@halo.test -c user.name=bats commit -q -m "baseline"
  # 3) main 分支 —— resolve_base_ref 的候选链是 origin/HEAD → origin/main →
  #    origin/master → main → master，且会跳过与 HEAD 同名的候选。没有 main 就
  #    BASE=""，committed diff 整段消失。git init 的默认分支名依赖 init.defaultBranch。
  git branch -M main
  git checkout -q -b review-package-branch
  echo "committed change line" >> review-pkg-src.txt
  git add review-pkg-src.txt
  git -c user.email=bats@halo.test -c user.name=bats commit -q -m "change"
  # 4) 未跟踪文件
  echo "untracked content" > review-pkg-untracked.txt
}
```

`review-package.sh` 还要求 `halo/specs/<spec-id>/` 下有 `spec.md` 与 `plan.md`，用 `make_spec` + `make_plan` 建；`.gitignore` 的 `halo/` 让它们不进未跟踪清单（与真实项目一致）。

**bats 相对 smoke-test 的净收益**：smoke-test 必须在 §7c 末尾 `git checkout -q main`（`:2220`）把分支切回去，否则污染后续段落。bats 每用例独立沙箱，这行连同它保护的隐式约束一起消失。

---

## 任务清单

### Task 0: 计划落盘

- [ ] 把本计划写入 `docs/superpowers/plans/2026-08-16-halo-test-batch2-drift-and-contracts.md`
- [ ] Commit — `Add the batch-2 test migration plan`

---

### Task 1: helpers 扩展 + drift/compliance fixture 骨架

**Files:** Modify `tests/helpers/common.bash`、`tests/unit/fixtures.bats`、`tests/fixtures/README.md`；Create `tests/fixtures/drift/**`、`tests/fixtures/compliance/**`

**Interface:** `halo_set_framework <fw>` —— `yq -i '.drift.routes.framework = "<fw>"' "$SANDBOX/halo/manifest.yaml"`。与 `halo_set_language` 同族（沙箱形态操作），放 `common.bash`，无需还原。
> 背景：`init.sh` 对本仓 Go 模板（`go.mod` 含 `gin-gonic/gin`）探测出 `framework: gin`，drift-check 的 fastapi 分支不会被走到。smoke-test 用 `DRIFT_ORIG_FRAMEWORK` 存/改/还原三步（`:1860`/`:1934`/`:2134`）做同一件事——那是单沙箱串行下的补丁。

fixture 目录树（`halo_install_fixture` 把 `<src>/.` 整棵叠加到 `$SANDBOX/`，第一层即沙箱内相对路径）：

```
tests/fixtures/drift/
  spec-template-placeholder/
    drift/template-placeholder-spec.md      # 逐字取自 spec-template.md:86-91（含 ## 5.1 错误码 标题）
  fastapi-prefixed-router/
    drift/prefixed/src/routers.py           # APIRouter(prefix="/api") + 单行 get/post("/model-sets")，刻意缺 DELETE
    drift/prefixed/spec-method-first.md     # | 方法 | 路径 | 说明 |
    drift/prefixed/spec-path-first.md       # | 端点 | 方法 | 说明 |  列序倒置 + 中文表头
  fastapi-collection-root/
    drift/collection-root/src/routers.py    # prefix="/model-sets" + get("")/post("")/get("/{set_id}")，刻意无 get("/")
    drift/collection-root/spec.md           # 四条路由
  fastapi-slash-root/
    drift/slash-root/src/routers.py         # prefix="/reports" + get("/")，独立目录（不得与 collection-root 混放）
    drift/slash-root/spec.md
  fastapi-multiline/
    drift/multiline/src/routers.py          # 单行 GET（保底）+ 多行 post/delete + 多行 APIRouter(prefix=…)
    drift/multiline/spec.md
tests/fixtures/compliance/
  context-basis-zh/          compliance/context-basis-zh-spec.md     # 逐字取自 spec-template.md:40-49
  context-basis-en/          compliance/context-basis-en-spec.md     # 英文来源类别（反向：不得回归）
  context-basis-unrecognised/ compliance/context-basis-none-spec.md  # 表在但来源列全是自造词（反向）
```

三条注意：① 所有 fixture spec **不叫 `spec.md` 放在 `halo/specs/` 下**——`spec_select_candidates`（`spec-select.sh:45`）只扫 `$PROJECT_ROOT/halo/specs`，`build_foreign_owned`（`ac-coverage.sh:138-145`）只扫 `$SPECS_ABS`，放 `drift/` 下天然隔离，不给别的用例制造并列候选；② `drift/*/src/` 必须有实际文件（git 不存空目录），空代码目录场景由用例 `mkdir -p` 现造；③ routers.py 正文**逐字**取自 `smoke-test.sh:1937-1951`、`:2022-2041`、`:2087-2111`，只搬运不改措辞。

- [ ] **Step 1（先写测试）**：`tests/unit/fixtures.bats` 追加 1 条 `framework override lands in the sandbox manifest`（照现有 `language override…` 写）。`bash tests/run.sh unit` → FAIL（预期）
- [ ] **Step 2**：`common.bash` 加 `halo_set_framework`，紧邻 `halo_set_language`，注释复用「无需还原」的同一理由
- [ ] **Step 3**：建 fixture 树，搬完对照原文自查一遍再改路径
- [ ] **Step 4**：`tests/fixtures/README.md` 矩阵表追加 8 行；「两条容易踩的约束」扩为四条，新增：**空路径 fixture 与 `"/"` fixture 必须分置两个目录**、**多行 fixture 必须保留一条单行路由**（否则 `CODE_ROUTES` 为空 → `gate_skip` → exit 0 假通过）
- [ ] **Step 5**：`bash -n` + `shellcheck --severity=warning tests/helpers/*.bash`；`bash tests/run.sh unit` → 19 tests 0 failures
- [ ] **Step 6: Commit** — `Add drift and compliance fixture matrix and a framework override helper`

---

### Task 2: `find_spec` 契约单测（12 条）

**Files:** Create `tests/unit/lib-find-spec.bats`

文件头写清爆炸半径（调用方已实测核对）：

```bash
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
```

| # | @test | 断言 |
|---|---|---|
| find-1 | `an explicit SPEC_FILE resolves with source explicit` | `assert_success`；`find_spec` 输出等于该路径；`find_spec_with_source` 以 `explicit\|caller-supplied\|` 开头 |
| find-2 | `a SPEC_FILE pointing at a missing file falls through to discovery` | source 为 `auto`（`_lib.sh:152` 的 `-f` 守卫） |
| find-3 | `specs.active resolves a spec id with source manifest-active` | `yq -i '.specs.active="alpha"'` → `<root>/halo/specs/alpha/spec.md`，source `manifest-active` |
| find-4 | `specs.active resolves a path with source manifest-active` | `.specs.active="halo/specs/alpha/spec.md"` → 同上 |
| find-5 | `an explicit SPEC_FILE outranks specs.active` | 两者指向不同 spec → 选 explicit |
| find-6 | `auto discovery resolves a single candidate and reports the ranking basis` | source `auto`；detail 含 `status=` 与 `updated_at=` |
| find-7 | `find_spec returns 1 and prints nothing when no spec exists` | `assert_failure 1`；`assert_output ""` |
| find-8 | `find_spec returns 2 when two candidates tie on status and updated_at` | 两个 `make_spec`；`assert_failure 2` |
| find-9 | `a unique updated_at breaks the tie and resolves with rc 0` | sed 改其中一个的 `updated_at` 为更晚值；`assert_success`；选中较新者 |
| find-10 | `find_spec does not abort its caller under set -euo pipefail` | 子进程片段 `SPEC=$(find_spec) \|\| rc=$?; echo "rc=$rc reached_end"`；空 specs 下输出含 `rc=1 reached_end` |
| find-11 | `find_spec_with_source emits three pipe-separated fields for every source` | 三种 source 各跑一次，`awk -F'\|' '{print NF}'` 恒为 3；第三段是绝对路径 |
| find-12 | `every gate refuses an ambiguous auto-discovery instead of skipping it` | 并列沙箱下遍历 `ac-coverage.sh`、`drift-check.sh`、`spec-lint.sh`、`compliance.sh`、`pipeline.sh --only=spec-lint`（均不传 spec）：每个 `status` 非 0，输出含 `ambiguous`，`refute_output --partial "skipping"` |

> **find-12 为什么写成一条遍历而不是五条 `@test`**：bats 不支持动态生成用例，五条手写副本本身就是根因 H。失败信息里带门禁名即可归因。它守的是 #15 analysis §1 点名的失败模式：「原写法是 `SPEC=$(find_spec) || { echo "skipping"; exit 0; }`——拒绝猜测会变成静默跳过门禁，比猜错更糟」。
>
> **find-8/9 的沙箱构造有个天然便利**（已实测）：`make_spec` 对每个 spec 都写死 `status: drafted`（`fixtures.bash:24`）+ `updated_at: 2026-01-01T00:00:00Z`（`:30`），所以「两个 `make_spec` = 精确并列」是零成本的。这同时是一条对后人的警告——**任何在同一沙箱里造两个 `make_spec` spec 又依赖自动发现的用例都会撞 rc=2**，写进文件注释。

- [ ] Step 1 写文件（`setup_file`: `halo_require_tools; halo_template_install`；`setup`: `halo_sandbox_clone`；定义 `lib_run` 并附「为什么必须走子进程」的注释）
- [ ] Step 2 `bash tests/run.sh unit` → 31 tests 0 failures
- [ ] Step 3 可归因性抽查：`tests/vendor/bats-core/bin/bats tests/unit/lib-find-spec.bats -f "ambiguous"` 只跑 2 条且绿
- [ ] Step 4 Commit — `Add find_spec contract tests covering all three resolution sources`

---

### Task 3: AC 声明源契约单测（11 条）+ 闭合批次 1 的覆盖空洞（1 条）

**Files:** Create `tests/unit/lib-ac-declaration.bats`；Modify `tests/unit/gate-ac-coverage.bats`

文件头（调用方已 grep 核对）：

```bash
# 契约单测：_lib.sh 的 AC 声明源。不经过任何门禁直接调用。
#
# spec_declared_acs(:200-204) 的调用方（4 处）：
#   gates/ac-coverage.sh:152 · gates/spec-lint.sh:141
#   orchestrator/sdd/summary-draft.sh:101 · _lib.sh:217（narrow_acs_to_declared 内部）
# narrow_acs_to_declared(:213-220) 的调用方（3 处）：
#   orchestrator/sdd/plan-lint.sh:169 · _lib.sh:256/:258（task_covered_acs 两条分支）
#
# 根因 A 复发 5 次（#7 → #8 → #9 → #14 → runningtime）。设计文档把
# 「A 类的机器防线」定义为对这两个函数的契约单测——就是本文件。
```

| # | @test | 断言 |
|---|---|---|
| ac-1 | `spec_declared_acs takes only the first cell of each AC row` | sed 在 AC-2 行的 Then 单元格塞 `(see AC-14)` → 输出恰为 `AC-1` `AC-2` |
| ac-2 | `spec_declared_acs keeps file order and duplicates` | **awk** 复制 AC-2 整行 → 输出 `AC-1 AC-2 AC-2`（spec-lint 的 `uniq -d` 依赖去重前的重复） |
| ac-3 | `spec_declared_acs ignores an AC token in prose outside the table` | 追加 `本 spec 不覆盖 AC-9。` → 输出不含 AC-9 |
| ac-4 | `spec_declared_acs requires at least one digit after AC-` | 追加 `\| AC- \| … \|` → 输出不含空号 |
| ac-5 | `spec_declared_acs on a missing file returns 0 with no output` | 边界：空输入 |
| ac-6 | `spec_declared_acs on a spec with no AC table returns 0 with no output` | 边界：grep 未命中（`:203` 的 `\|\| true`） |
| ac-7 | `narrow_acs_to_declared drops an AC the spec does not declare` | 文本含 `AC-1 AC-14`，spec 声明 AC-1/AC-2 → 只出 `AC-1` |
| ac-8 | `narrow_acs_to_declared falls back to the raw token set when the spec declares nothing` | 无 AC 表的 spec → 原样返回（fail-open 方向，`:218`） |
| ac-9 | `narrow_acs_to_declared returns 0 with no output when the text has no AC token` | 边界：空输入（`:216`） |
| ac-10 | `narrow_acs_to_declared does not abort under pipefail when nothing survives narrowing` | 文本只含 `AC-99`；片段 `narrow_acs_to_declared … ; echo "rc=$? reached_end"` → `rc=0 reached_end` 且无 AC 行（边界：`:219` 的 `\|\| true`） |
| ac-11 | `narrow_acs_to_declared sorts and de-duplicates its output` | 输入 `AC-2 AC-1 AC-1` → 恰为 `AC-1` `AC-2` |

`tests/unit/gate-ac-coverage.bats` 追加 1 条（**闭合批次 1 计划 496-502 行记录的空洞**）：

| # | @test | 断言 |
|---|---|---|
| acg-3 | `the numeric fallback does not treat this spec's own declared test as foreign-owned` | `assert_success`；`.findings[] \| select(.ac=="AC-2") \| .status` 为 `covered` |

构造（已逐步推演 `ac-coverage.sh:137-146` 与 Tier1/Tier2 路径）：

```bash
make_spec halo/specs self-decl 2                       # AC-1→TestAC1、AC-2→TestAC2
mkdir -p internal/handler
cat > internal/handler/item_test.go << 'GO'             # 唯一测试函数，AC 号为 2
package handler
func TestAC2Combined(t *testing.T) {}
GO
# AC-1 的验证单元格改成声明这个函数；AC-2 的单元格改成非测试标识符
sed -e 's/| TestAC1 |/| TestAC2Combined |/' -e 's/| TestAC2 |/| manual review |/' \
  halo/specs/self-decl/spec.md > /tmp/x && mv /tmp/x halo/specs/self-decl/spec.md
```

现行实现：`build_foreign_owned` 的 `:142` 自跳过让 `FOREIGN_OWNED` 为空 → AC-1 走 Tier 1 命中 `TestAC2Combined`；AC-2 无 decl 走 Tier 2，候选 `{TestAC2Combined}`，`comm -23` 不扣 → covered → exit 0。删掉 `:142` 后 `FOREIGN_OWNED={TestAC2Combined}`（从本 spec 的 AC-1 行提取）→ AC-2 候选被扣光 → uncovered → exit 1 → 用例变红。这就是 M26。

- [ ] Step 1 写 `lib-ac-declaration.bats`（同样用 `lib_run` 子进程助手）
- [ ] Step 2 `gate-ac-coverage.bats` 追加 acg-3，`setup` 不变（该条自建 `self-decl`）
- [ ] Step 3 `bash tests/run.sh unit` → 43 tests 0 failures
- [ ] Step 4 Commit — `Add AC declaration source contract tests and close the batch-1 coverage hole`

---

### Task 4: 门禁出口语义单测（drift-check 4 条 + compliance 3 条）

**Files:** Create `tests/unit/gate-drift-check.bats`、`tests/unit/gate-compliance.bats`

这两个文件承接 smoke-test `:1529-1546` 的两条残余 gate JSON 断言。它们不绑定某份 bug 报告（是门禁出口契约），所以放 `unit/`——与批次 1 的 `gate-ac-coverage.bats` 同一分类逻辑。文件头注明消费方：`delivery/pipeline.sh`（嵌入 eval run）、`orchestrator/sdd/summary-draft.sh`（读 metrics）、`tests/release-check.sh`。

`gate-drift-check.bats`：

| # | @test | 断言 | 来源 |
|---|---|---|---|
| gdc-1 | `drift-check --json-out writes the gate JSON envelope` | `assert_success`；`yq -e '.gate=="drift-check" and .status=="pass" and .metrics.drift_count==0 and (.findings\|length>0)'` | 旧 `:1531`（**加强**：补 `.status` 与 `assert_success`） |
| gdc-2 | `every unverifiable dimension is reported as NOT verified, never as clean` | 空 spec fixture + 空代码目录；`assert_output --partial "NOT verified"`；`yq -e '.metrics.checks_skipped >= 3 and .metrics.checked.ddl==false and .metrics.checked.routes==false and .metrics.checked.error_codes==false and .metrics.checked.seed_sql==false'` | 旧 `:1878` 前半（拆分） |
| gdc-3 | `checks_run counts only dimensions that actually compared something` | 同上输入；`yq -e '.metrics.checks_run == 0'` | **新增（收紧）** |
| gdc-4 | `a drift finding sets status fail and exits 1` | 最小错误码 drift；`assert_failure 1`；`.status=="fail"`；`.metrics.drift_count==1` | **新增（反向）** |

> gdc-2/3 的度量选择：旧断言用 `checks_skipped >= 3`（实测四维度全 skip，值为 4）。**不**收紧成 `== 4`——设计文档第 111 行要求「断言出口语义，不断言中间实现细节（避免 #10 式硬编码计数被无关新增误伤）」。改用语义等价且不脆的 `checks_run == 0` + 四个 `checked.*` 为 false。
>
> gdc-4 与 `regression/…/drift-error-codes.bats` 输入形似但关注点不同：这里断的是「有 drift ⇒ status=fail ∧ exit 1」这条**出口契约**（pipeline 与 release-check 依赖它），那里断的是「字符串码形态能被识别」这条**缺陷回归**。分层不是重复。

`gate-compliance.bats`：

| # | @test | 断言 | 来源 |
|---|---|---|---|
| gcp-1 | `compliance --json-out writes the gate JSON envelope` | `assert_success`；`yq -e '.gate=="compliance" and .status!=null and (.findings\|length>=4)'` | 旧 `:1540`（**加强**） |
| gcp-2 | `every finding carries a check name and a status` | `yq -e '[.findings[] \| select(.check=="" or .status=="")] \| length == 0'`；并断言 `source_trace` / `context_basis` / `knowledge_reference` / `ambiguity_tracking` 四个 check 各出现一次 | **新增** |
| gcp-3 | `compliance is a soft gate: warnings pass without --strict and fail with it` | 缺 Context Basis 的 spec：默认 `assert_success` + `.status=="warn"` + `.metrics.warnings>0`；加 `--strict` 后 `assert_failure 1` + `.status=="fail"` | **新增（方向断言）** |

> 旧断言 `:1540` 的 `.metrics.warnings >= 0` 是**恒真式**——`warnings` 是非负计数器，这半个条件在任何实现下都成立，零鉴别力。不迁移。这与批次 1 处理 `else pass "ac-coverage ran (exit=$AC_EXIT)"` 是同一类清理。
> 实现依据已核对：`compliance.sh:170-185`（warnings==0 → pass/exit 0；warnings>0 且 strict → fail/exit 1；否则 warn/exit 0）。

- [ ] Step 1 写两个文件
- [ ] Step 2 `bash tests/run.sh unit` → 50 tests 0 failures
- [ ] Step 3 `bash tests/run.sh` 全绿（legacy 双轨重叠是有意的，本 Task 不删旧段）
- [ ] Step 4 Commit — `Add drift-check and compliance gate exit-semantics unit tests`

---

### Task 5: #12/#13 —— drift-check 错误码与路由表（10 条）

**Files:** Create `tests/regression/2026-08-03-halo-gate-findings/drift-error-codes.bats`、`.../drift-route-table.bats`

两份文件头三行（`Fixed by` 在 Step 0 考据后填）：

```bash
# Bug report: docs/bug_report/2026-08-03-halo-gate-findings.md
#   （聚合上报，8 条已修缺陷按缺陷拆分到本目录；映射见 docs/bug_report/INDEX.md）
# Root cause class: E. 框架读不懂自带模板 + F. 语法变体覆盖不足   ← drift-error-codes
# Root cause class: D. 非确定性依赖（列序）+ F                     ← drift-route-table
# Fixed by: <Step 0 用 git log 考据后填入>
```

`drift-error-codes.bats`（6 条，`setup`: `halo_sandbox_clone; halo_set_language python`）：

| # | @test | 断言 | 来源 |
|---|---|---|---|
| dec-1 | `the template's {ERROR_CODE} placeholder row is not extracted as an error code` | `.metrics.spec_error_codes == 0`；输出含 `No business error codes in spec` | 旧 `:1878` 后半（拆分） |
| dec-2 | `a string error code missing from python source is reported as drift` | `assert_failure 1`；`.metrics.spec_error_codes==2 and .metrics.drift_count==1 and .metrics.checked.error_codes==true` | 旧 `:1912` |
| dec-3 | `the gate passes once every string error code is defined` | 追加第二个常量后 `assert_success`；`.metrics.drift_count==0 and .metrics.checked.error_codes==true` | 旧 `:1925` |
| dec-4 | `numeric error codes are still read from a table located by its header` | 数值码表 + `CodeFoo = 40001` → `assert_success`；缺一个 → `assert_failure 1` | **新增（不回归）** |
| dec-5 | `a spec with numeric codes but no error code table still falls back to the whole-file scan` | 无 `错误码` 表头、只有 `\| 40001 \| … \|` 行 → 仍被提取（`drift-check.sh:452-456` 的回退分支） | **新增** |
| dec-6 | `an unmapped project language reports NOT verified instead of clean` | `halo_set_language cobol`；`assert_success`；`.metrics.checked.error_codes==false`；输出含 `no source file mapping` | **新增（诚实 skip）** |

`drift-route-table.bats`（4 条，`setup`: `halo_sandbox_clone; halo_set_language python; halo_set_framework fastapi; halo_install_fixture drift/fastapi-prefixed-router`）：

| # | @test | 断言 | 来源 |
|---|---|---|---|
| drt-1 | `an unregistered FastAPI route is reported as drift` | `spec-method-first.md`；`assert_failure 1`；`.metrics.spec_routes==3 and .metrics.drift_count==1 and .metrics.checked.routes==true` | 旧 `:1965` |
| drt-2 | `the gate passes once every FastAPI route is registered` | 追加 DELETE handler 后 `assert_success`；`.metrics.drift_count==0 and .metrics.checked.routes==true` | 旧 `:1982` |
| drt-3 | `route table columns are located by header name, not by position` | `spec-path-first.md` + 补齐的代码；`assert_success`；`.metrics.spec_routes==3 and .metrics.drift_count==0` | 旧 `:2007` |
| drt-4 | `a path-first column order still reports a genuinely missing route` | `spec-path-first.md` + **未**补齐的代码；`assert_failure 1`；`.metrics.spec_routes==3 and .metrics.drift_count==1` | **新增（收紧）** |

> drt-4 补的是批次 1 的教训：旧断言只有「列序倒置也能通过」这个放松方向。「提取到 3 行却全都比对为通过」这种误绿没有任何断言守。

- [ ] Step 0 `git log --oneline -- harness-template/halo/kernel/delivery/gates/drift-check.sh` 考据 #12 各修复点的提交哈希，填进文件头
- [ ] Step 1 写两个文件
- [ ] Step 2 `bash tests/run.sh regression` → 47 tests 0 failures
- [ ] Step 3 Commit — `Migrate drift-check error code and route table regressions to bats`

---

### Task 6: #16 —— FastAPI 集合根与多行装饰器（5 条）

**Files:** Create `tests/regression/2026-08-03-fastapi-collection-root-route-dropped.bats`（**平铺，与报告 basename 逐字相同**）

文件头：`Bug report: docs/bug_report/2026-08-03-fastapi-collection-root-route-dropped.md` / `Root cause class: C. 失败方向搞反 + F. 语法变体覆盖不足` / `Fixed by: 55db4cb`（INDEX.md 已登记）。

正文注释必须转述 analysis 的失败方向——它是这份 bug 的全部要害：

```
# spec 侧丢一行 = 少比一条（fail-closed 可接受）；
# code 侧丢一行 = 凭空多报一条漂移（必须 fail-open）。
# #12 把 spec 侧的「路径必须以 / 开头」谓词原样搬到了 code 侧（drift-check.sh:325）。
```

| # | @test | 断言 | 来源 |
|---|---|---|---|
| fca-1 | `an empty-path collection root is registered through the router prefix` | `assert_failure 1`；`.metrics.spec_routes==4 and .metrics.drift_count==1`（三条空路径/带参路由被认出，只有真缺的 DELETE 报漂移） | 旧 `:2056` |
| fca-2 | `the gate passes once a prefix-only router is complete` | 追加 DELETE handler；`assert_success`；`.metrics.drift_count==0 and .metrics.checked.routes==true` | 旧 `:2073` |
| fca-3 | `multi-line route decorators are read as registrations` | `assert_success`；`.metrics.spec_routes==3 and .metrics.drift_count==0 and .metrics.checked.routes==true` | 旧 `:2125` |
| fca-4 | `a multi-line APIRouter prefix is read` | 同 fixture 的多行 `APIRouter(\n prefix="/api",\n)`；断言带该 prefix 的路由被判为已注册 | **新增**：analysis §4 逐字点名的第二种形态，旧三条断言完全没覆盖 |
| fca-5 | `the "/" collection root form still resolves through the prefix` | `fastapi-slash-root`（独立 fixture）；`assert_success`；`.metrics.drift_count==0` | **新增（不回归）**：修复放宽了空路径守卫，必须证明没弄坏既有 `"/"` 形态。**必须独立 fixture**——同 fixture 内放 `@router.get("/")` 会让尾段宽松匹配掩盖空路径漏检 |

- [ ] Step 1 写文件（`setup`: `halo_sandbox_clone; halo_set_language python; halo_set_framework fastapi`，fixture 按用例装）
- [ ] Step 2 每条用例断言前后加一行注释指明它守的是 analysis 的哪一节
- [ ] Step 3 `bash tests/run.sh regression` → 52 tests 0 failures
- [ ] Step 4 Commit — `Migrate the FastAPI collection root and multi-line decorator regression to bats`

---

### Task 7: #12/#13 —— compliance / plan-lint / review-package（15 条）

**Files:** Create `tests/regression/2026-08-03-halo-gate-findings/` 下的 `compliance-source-trace.bats`、`plan-lint-placeholder.bats`、`review-package-scope.bats`

`compliance-source-trace.bats`（3 条，Root cause class: E）：

| # | @test | 断言 | 来源 |
|---|---|---|---|
| csr-1 | `the framework's own Chinese Context Basis table passes the source trace` | `yq -e '(.findings[] \| select(.check=="source_trace") \| .status) == "pass"'` | 旧 `:2153` |
| csr-2 | `an English Context Basis table still passes` | 同上 | **新增（不回归）** |
| csr-3 | `a Context Basis with no recognisable source category still warns` | `source_trace` 的 status 为 `warning`，`.metrics.warnings > 0` | **新增（判别力）** |

> csr-3 是关键：只有正向断言时，一个把 `grep -qiE '…'` 换成 `true` 的实现照样全绿（M48 就是这条变异）。#12 analysis §3 的修复是「正则补齐中文来源类别」，不是「取消判据」。

`plan-lint-placeholder.bats`（6 条，Root cause class: F + C）：

| # | @test | 断言 | 来源 |
|---|---|---|---|
| pl-1 | `a REST path parameter is not an unresolved placeholder` | Scope 改为 `Implement POST /model-sets/{set_id}/members.`；`assert_success`；`refute_output --partial "unresolved placeholder"` | 旧 `:2167`（拆分 + **加强**） |
| pl-2 | `comparison operators are not read as a bracket pair` | Scope 改为 `keep members < 100 while > 0.` | 旧 `:2167`（拆分） |
| pl-3 | `an upper snake-case template placeholder is still flagged` | Scope 含 `{SCOPE_TBD}`；`assert_failure`；`assert_output --partial "unresolved placeholder"` | 旧 `:2177`（拆分） |
| pl-4 | `an angle-bracketed slug is still flagged` | Scope 含 `see <spec-id>` | 旧 `:2177`（拆分） |
| pl-5 | `a Chinese template placeholder is flagged` | Scope 含 `{条件} 待补` | **新增**：analysis §4 对照表里「`{条件} 待补` 旧漏新报」是这次修复的**核心增量**，旧断言一条都没覆盖 |
| pl-6 | `TODO/TBD/FIXME are still flagged` | Scope 含 `TODO: rename` | **新增（不回归）**：analysis §4 说明这一分支「保持原样」，要有断言守着 |

派生写法（`make_plan` 实际文本与 smoke-test 不同，已核对 `fixtures.bash:152`）：

```bash
make_spec halo/specs ph-probe 2
make_plan halo/specs ph-probe 2 1 decl-en      # decl-en 避免 fallback warning 噪声
plan_with_scope() { # <替换串>
  sed "s#Scope: Implement the smallest path needed for AC-1\.#Scope: $1#" \
    halo/specs/ph-probe/plan.md > halo/specs/ph-probe/plan-probe.md
}
```

限定 `AC-1\.` 是必须的：两条 T 任务的 Scope 行只有 AC 号不同，不加限定 sed 会同时改两条。plan-lint 通过同目录 `spec.md` 解析 spec，产物与 spec 同目录即可。

`review-package-scope.bats`（6 条，Root cause class: C + 框架自我矛盾）。文件内定义 `review_pkg_repo()`（见决定三），逐条用例显式调用：

| # | @test | 断言 | 来源 |
|---|---|---|---|
| rp-1 | `the package includes committed work from the base merge-base` | 输出文件含 `committed change line`；`## Committed Diff` 段非 `(none)` | 旧 `:2211` 第 1 半 |
| rp-2 | `untracked files are listed` | 含 `review-pkg-untracked.txt` | 旧 `:2211` 第 2 半 |
| rp-3 | `untracked file content is inlined below the limit` | 含 `untracked content`；含未跟踪内容段落标题 | 旧 `:2211` 第 3 半 |
| rp-4 | `the package records the base ref it used` | `## Sources` 段含 `Diff base:` 与 `committed range` | **新增**：analysis §5 最后一条修复点无断言 |
| rp-5 | `an explicit --base overrides discovery` | `--base=main` → base 段落引用 `main` | **新增** |
| rp-6 | `a repository with no resolvable base says so instead of silently dropping committed work` | 只有一个分支、无 main/master → 含 `none resolved — committed work is NOT in this package` | **新增（诚实 skip 方向）** |

> rp-2 与 rp-3 必须拆开：`review-package.sh` 的「列清单」与「内联内容」是两条独立分支，压在一条断言里的话把 `UNTRACKED_CONTENT_LIMIT`（`:82`）改成 0 也不会红（M58 专门验证这个拆分有效）。

- [ ] Step 1 写三个文件
- [ ] Step 2 `review-package-scope.bats` 的 `.gitignore` 追加块必须带注释说明它是载荷不是装饰（否则后人会「简化」掉，rp-3 随即变成测不到东西的假绿）
- [ ] Step 3 `bash tests/run.sh regression` → 67 tests 0 failures
- [ ] Step 4 macOS 与 Linux 各跑一次 `review-package-scope.bats`（git 默认分支名差异是最可能的平台分歧点）
- [ ] Step 5 Commit — `Migrate compliance, plan-lint and review-package regressions to bats`

---

### Task 8: #15 §8.1 —— spec 自动发现（11 条）

**Files:** Create `tests/regression/2026-08-03-halo-gate-findings_2/spec-discovery.bats`

文件头：`Bug report: docs/bug_report/2026-08-03-halo-gate-findings_2.md`（聚合上报，本文件对应 analysis §1 = 上报 §8.1；§3.3 的 learn-draft 形态归批次 3 的同目录文件）/ `Root cause class: D. 非确定性依赖（mtime）+ C. 静默兜底` / `Fixed by:` 待考据。

**setup 分两档**（本文件相对 §7c 各文件的特殊之处）：

- disc-1..8 只跑 `bash "$REPO_DIR/harness-template/halo/kernel/spec-select.sh" <root>`，在 `$BATS_TEST_TMPDIR` 里现搭 spec 树，**不装 harness**。理由不只是快：`spec-select.sh:6-8` 的设计契约就是「刻意不依赖 `_lib.sh` 与 yq，因为 `guide.sh` 必须能在没有 halo 的 standalone 宿主下工作」。在装好 harness 的沙箱里测它，恰好把这个契约测没了。
- disc-9..11 需要沙箱，用 `halo_sandbox_clone`。

| # | @test | 断言 | 来源 |
|---|---|---|---|
| disc-1 | `front matter updated_at outranks a newer file mtime` | `touch` 较旧内容的 spec 模拟 git 检出；选中 `updated_at` 更新者 | 旧 `:2335` |
| disc-2 | `the selection and the candidates it beat are announced on stderr` | stderr 同时含 `selected` 与 `not selected`，且含落选者的 `status=`/`updated_at=` | 旧 `:2342` |
| disc-3 | `an in-flight spec outranks a verified one with a newer timestamp` | verified 的 updated_at 更晚，仍选 in-flight | 旧 `:2351` |
| disc-4 | `an exact tie is refused with exit 2 and a --spec= hint` | `assert_failure 2`；输出含 `--spec=` 与两个并列候选路径 | 旧 `:2361` |
| disc-5 | `with no updated_at anywhere the selector falls back to mtime and says so` | 选中 mtime 最新者；stderr 含 `mtime` | 旧 `:2374` |
| disc-6 | `a spec without updated_at ranks below one that has it` | 一有一无，选中有的那个（`spec-select.sh:72` 的沉底哨兵） | **新增**：analysis §1 的显式边界（「缺 updated_at 排到最低而非最高——元数据失修是最弱的候选资格」），旧断言未覆盖 |
| disc-7 | `spec-select.sh resolves without yq or a manifest on PATH` | `env PATH=/usr/bin:/bin` 下跑，`assert_success` | **新增**：`spec-select.sh:6-8` 的设计约束无断言 |
| disc-8 | `an empty specs root returns 1, not an empty selection` | `assert_failure 1`；`assert_output ""` | **新增（边界）** |
| disc-9 | `pipeline records an auto-discovered spec as source auto` | 沙箱里单个 `make_spec`；stdout 含 `source=auto`；eval JSON `.spec_source=="auto"` 且 `.spec_source_detail` 非空 | 旧 `:2388`（**加强**） |
| disc-10 | `pipeline records an explicitly pinned spec as source explicit` | `.spec_source=="explicit"` | 旧 `:2401` |
| disc-11 | `guide.sh and the kernel selector resolve the same spec` | `guide.sh --json` 的 `.spec_id` 等于 `basename $(dirname $(spec-select.sh halo/specs))`，且 `.spec_source=="auto"` | 旧 `:2416`（**加强**） |

三处对旧断言的改动，都要在注释里写明：

1. **去掉 `cp "$REPO_DIR/prismspec/bin/guide.sh" "$SANDBOX/prismspec/bin/guide.sh"`。** `install.sh` 已经把仓库的 `prismspec/` 装进沙箱。Step 1 先实测确认两份逐字相同，确认后这次 cp 是纯冗余。
2. **去掉 `if [[ -f "$REPO_DIR/prismspec/bin/guide.sh" ]]` 的条件包裹**（旧 `:2410`）。那是无 else 的静默跳过——文件不在时整条断言消失且不报警，正是设计文档「诚实 skip」要拦的形态。bats 版无条件断言。
3. **disc-9 的沙箱只放一个 spec。** 旧断言在装满 13 个 spec 目录的共享沙箱里依赖「`missing-evidence` 恰好唯一胜出」——那就是 O-4。单 spec 沙箱把隐性前提变成用例自己写死的前置。

- [ ] Step 1 实测 `diff prismspec/bin/guide.sh <sandbox>/prismspec/bin/guide.sh` 确认无差异，结论写进文件注释
- [ ] Step 2 写文件，disc-1..8 不调用 `halo_template_install`
- [ ] Step 3 `bash tests/run.sh regression` → 78 tests 0 failures
- [ ] Step 4 计时对比：`time tests/vendor/bats-core/bin/bats tests/regression/2026-08-03-halo-gate-findings_2/` 记进 commit message
- [ ] Step 5 Commit — `Migrate the spec auto-discovery regression to bats`

---

### Task 9: 等价性验证——64 条变异（完成定义的核心）

**Files:** 无（验证 Task，零代码改动）

SOP 的「先红后绿」要求在未修复代码上确认 FAIL，但本批次的缺陷早已修复。等价且更强的做法是对修复点注入定向变异，确认预期用例变红。

**验收门槛：本批次每一条 `@test`（迁移的与新增的）都必须在下表中至少出现一次作为「期望变红」。**

**变异协议（强制）：**

```bash
git status --porcelain                              # 1. 必须无输出
#  2. 手工编辑单行（或 awk 写临时文件后 mv——禁止 sed -i）
tests/vendor/bats-core/bin/bats <目标 .bats 或目录>  # 3. 记录 RED
git checkout -- harness-template/ prismspec/        # 4. 回滚（注意 prismspec/：M61 改的是它）
git status --porcelain                              #    必须无输出
tests/vendor/bats-core/bin/bats <同上>              #    必须全绿
```

> 三条容易踩的：① 回滚范围必须含 `prismspec/`——`guide.sh` 不在 `harness-template/` 下；② 变异**能生效**是因为 `halo_template_install` 每次都从 `$REPO_DIR` 重跑 `install.sh` + `init.sh`，沙箱内容是当下工作树的快照——改完不需要额外步骤，但忘记回滚会污染后续所有用例；③ **M39 必须在 macOS 上执行**（BSD awk 专属）。Linux 上它不会变红，那不是失败，是平台差异——记录为「macOS RED / Linux GREEN」。这是批次 0 建立双平台 CI 的第一次实际兑现。

#### 变异对照表（行号已逐条实测核对于 `606856a`）

**A 组 · `_lib.sh` 的 spec 解析 → `unit/lib-find-spec.bats`**

| # | 目标 | 变异 | 期望变红 |
|---|---|---|---|
| M1 | `_lib.sh:152` | 去掉 `&& [[ -f "$spec_file" ]]` | find-2 |
| M2 | `_lib.sh:157` | `if [[ -n "$active_spec" ]]` → `if false` | find-3、find-4 |
| M3 | `_lib.sh:153` | `explicit\|…` → `auto\|…` | find-1、find-5、find-11 |
| M4 | `_lib.sh:174` | 删 `[[ "$rc" -eq 2 ]] && return 2`（歧义降级为 rc=1） | find-8、find-12 |
| M5 | `_lib.sh:171` | `auto\|…` → `manifest-active\|…` | find-6 |
| M6 | `_lib.sh:184` | 去掉 `\|\| rc=$?`（errexit 下直接终止调用方） | find-10 |
| M7 | `_lib.sh:187` | `"${resolved#*\|}"` → `"$resolved"`（少剥一段） | find-1、find-3 |

**B 组 · `spec-select.sh` 排序语义 → `unit/lib-find-spec.bats` + `regression/…/spec-discovery.bats`**

| # | 目标 | 变异 | 期望变红 |
|---|---|---|---|
| M8 | `spec-select.sh:76` | `if [[ "$status" == "verified" ]]; then rank=1; else rank=0; fi` → 恒 `rank=0` | disc-3 |
| M9 | `spec-select.sh:95` | `-k2,2r` → `-k2,2`（时间戳升序，最旧者胜） | disc-1、find-9 |
| M10 | `spec-select.sh:72` | 哨兵 `0000-00-00T00:00:00Z` → `9999-99-99T99:99:99Z`（缺 updated_at 置顶） | disc-6 |
| M11 | `spec-select.sh:103` | `-gt 1` → `-gt 99`（永不判并列，回到抛硬币） | disc-4、find-8、find-12 |
| M12 | `spec-select.sh:88-89` | 删掉两条 mtime 兜底的 stderr 提示 | disc-5 |
| M13 | `spec-select.sh:120-127` | 删掉 `not selected` 循环 | disc-2 |
| M14 | `spec-select.sh:60` | `[[ -n "$files" ]] \|\| return 1` → `return 0` | disc-8、find-7 |
| M15 | `spec-select.sh:18` 后 | 插入 `command -v yq >/dev/null \|\| exit 1`（引入依赖，**收紧方向**） | disc-7 |
| M16 | `spec-select.sh:85` | mtime 兜底分支改为取 `$files` 首行（不按 mtime） | disc-5 |

**C 组 · `_lib.sh` 的 AC 声明源 → `unit/lib-ac-declaration.bats`**

| # | 目标 | 变异 | 期望变红 |
|---|---|---|---|
| M17 | `_lib.sh:203` | 行首锚定+取首格 → 全文 `grep -oE 'AC-[0-9]+'` | ac-1、ac-3、ac-4 |
| M18 | `_lib.sh:203` | `AC-[0-9]+` → `AC-[0-9]*` | ac-4 |
| M19 | `_lib.sh:203` | 管道末尾追加 `\| sort -u` | ac-2 |
| M20 | `_lib.sh:203` | 去掉 `{ … \|\| true; }` 包裹（pipefail 下 grep 未命中崩溃） | ac-6 |
| M21 | `_lib.sh:219` | 去掉收窄，原样 `printf '%s\n' "$mentioned"` | ac-7 |
| M22 | `_lib.sh:218` | 去掉回退分支的 `printf`（fail-open 反转成 fail-closed） | ac-8 |
| M23 | `_lib.sh:215` | 去掉 `\|\| true` | ac-9、ac-10 |
| M24 | `_lib.sh:219` | 去掉 `\|\| true` | ac-10 |
| M25 | `_lib.sh:215` | 去掉 `\| sort -u` | ac-11 |

**D 组 · `ac-coverage.sh` → `unit/gate-ac-coverage.bats`**

| # | 目标 | 变异 | 期望变红 |
|---|---|---|---|
| M26 | `ac-coverage.sh:142` | 删 `[[ "$f" -ef "$SPEC" ]] && continue`（自跳过） | acg-3 ← **批次 1 遗留空洞的闭合证明** |

**E 组 · drift-check 错误码 → `unit/gate-drift-check.bats` + `regression/…/drift-error-codes.bats`**

| # | 目标 | 变异 | 期望变红 |
|---|---|---|---|
| M27 | `drift-check.sh:443` | 表头正则删掉中文分支 | dec-2、dec-3 |
| M28 | `drift-check.sh:444` | 删 `c ~ /^[A-Z][A-Z0-9_]{2,}$/`（恢复纯数字扫描 = #12 修复前） | dec-2、dec-3 |
| M29 | `drift-check.sh:444` | `c ~ /^[A-Z][A-Z0-9_]{2,}$/` → `c ~ /[A-Z]/`（放宽到吃下 `{ERROR_CODE}`，**误红方向**） | dec-1、gdc-2 |
| M30 | `drift-check.sh:444` | 删 `c ~ /^[0-9]+$/` | dec-4 |
| M31 | `drift-check.sh:452-456` | 删掉无表时的全文数值回退 | dec-5 |
| M32 | `drift-check.sh:495-499` | `if grep_files …` → `if true`（恒判为已定义） | dec-2、gdc-4 |
| M33 | `drift-check.sh:468` | `gate_skip "… NOT verified"` → `ok "…"` | dec-6 |
| M34 | `drift-check.sh:144-149` | `gate_skip` 里删掉 `SKIPPED=$((SKIPPED + 1))` | gdc-2 |
| M35 | `drift-check.sh:58-64` | `mark_checked` 四个分支全部无条件置 true | gdc-2、gdc-3 |
| M36 | `drift-check.sh:571` | drift>0 分支 `write_gate_json "fail"` → `"pass"` | gdc-4 |
| M37 | `drift-check.sh:583` | `write_gate_json "pass"` → `"unknown"` | gdc-1 |

**F 组 · drift-check 路由 → `regression/…/drift-route-table.bats` + `…fastapi-collection-root….bats`**

| # | 目标 | 变异 | 期望变红 |
|---|---|---|---|
| M38 | `drift-check.sh:279-280` | 删掉两条表头定位正则（`hm`/`hp` 恒 0，回退 `$3`/`$4`） | drt-3、drt-4 |
| M39 | `drift-check.sh:279` | `c ~ /^(…\|方法)$/` → `c == "方法"`（BSD awk 多字节 `==` 陷阱） | **macOS**：drt-1、drt-3、drt-4 · **Linux**：不红（记录，非失败） |
| M40 | `drift-check.sh:285` | 去掉 `&& p ~ /^\//`（说明列被当路径） | drt-3、drt-4 |
| M41 | `drift-check.sh:325` | `[[ -z "$path" \|\| "$path" == /* ]]` → `[[ "$path" == /* ]]`（恢复 #16 缺陷） | fca-1、fca-2 |
| M42 | `drift-check.sh:326` | `[[ -z "$path" ]] \|\| printf …` → 无条件 printf（产出裸空路由，**误红方向**） | 观察项；若无用例变红，记 O-8 |
| M43 | `drift-check.sh:307` | `tr '\n' ' ' < "$f"` → `cat "$f"`（恢复按行 grep） | fca-3、fca-4 |
| M44 | `drift-check.sh:400` | 删 `mark_checked` | drt-1、drt-2、drt-3、fca-1、fca-2、fca-3、fca-5 |
| M45 | `drift-check.sh:336` | `grep -qxF` → `grep -qF`（前缀即算命中，放松） | drt-1、drt-4、fca-1 |
| M46 | `drift-check.sh:339-343` | 删掉尾段宽松匹配（fail-open 变 fail-closed，**收紧方向**） | fca-5、drt-2 |

**G 组 · compliance → `unit/gate-compliance.bats` + `regression/…/compliance-source-trace.bats`**

| # | 目标 | 变异 | 期望变红 |
|---|---|---|---|
| M47a | `compliance.sh:148` | 正则删掉全部中文来源类别 | csr-1 |
| M47b | `compliance.sh:148` | 正则删掉全部英文来源类别 | csr-2 |
| M48 | `compliance.sh:148` | 整个 `if` 条件 → `true`（恒 pass） | csr-3 |
| M49 | `compliance.sh:65` | `record_finding` 的 `check` 字段写死 `""` | gcp-2 |
| M50 | `compliance.sh:177` | `if [[ "$STRICT" == "true" ]]` → `if true` | gcp-3 |
| M63 | `compliance.sh:79` | `printf '  "gate": "compliance",\n'` → 换成别的 gate 名 | gcp-1 |

> M49 点亮不了 gcp-1：gcp-1 断的是 `.gate` / `.status` / `findings` **数量**，把 `check` 字段写空不改变其中任何一项。gcp-1 需要 M63 这条独立变异——这是「每条断言至少被一条变异点亮」在评审时最容易被含糊过去的一处。

**H 组 · plan-lint / review-package / guide.sh / pipeline**

| # | 目标 | 变异 | 期望变红 |
|---|---|---|---|
| M51 | `plan-lint.sh:236` | `\{[A-Z][A-Z0-9_]*\}` → `\{[A-Za-z_][A-Za-z0-9_-]*\}`（恢复旧判据） | pl-1、pl-5 |
| M52 | `plan-lint.sh:236` | `<[A-Za-z][A-Za-z0-9_.-]*>` → `<[^>]+>`（恢复旧判据） | pl-2 |
| M53 | `plan-lint.sh:236` | 删掉整个第二个 grep 分支 | pl-3、pl-4、pl-5 |
| M54 | `plan-lint.sh:235` | 删掉 `\b(TODO\|TBD\|FIXME)\b` 分支 | pl-6 |
| M55 | `review-package.sh:139-140` | committed 段改为恒 `echo "(none)"` | rp-1 |
| M56 | `review-package.sh:61-63` | 候选链只留 `origin/main`（删 `main master`） | rp-1、rp-4 |
| M57 | `review-package.sh:80` | `UNTRACKED_FILES="$(…)"` → `UNTRACKED_FILES=""` | rp-2、rp-3 |
| M58 | `review-package.sh:82` | `UNTRACKED_CONTENT_LIMIT=50` → `=0` | rp-3（**且 rp-2 必须仍绿**——这是 2/3 拆分有效性的证明） |
| M59 | `review-package.sh:114` | `none resolved — committed work is NOT in this package` → `(n/a)` | rp-6 |
| M60 | `review-package.sh:55-57` | 忽略 `--base=`，恒走自动发现 | rp-5 |
| M61 | `prismspec/bin/guide.sh:125` + `:120` | `if [[ -f … ]]` → `if false`（强制走 standalone 内联副本）**且** `:120` 的 `-k2,2r` → `-k2,2`（内联副本漂移） | disc-11 |
| M62 | `pipeline.sh:304` | `SPEC_SOURCE="${resolved%%\|*}"` → `SPEC_SOURCE="explicit"` | disc-9（**且 disc-10 必须仍绿**） |

#### 覆盖核对（64 条变异 → 71 条用例）

| 用例组 | 条数 | 点亮它的变异 |
|---|---|---|
| unit/lib-find-spec（find-1..12） | 12 | M1-M7、M4/M11、M9、M14 |
| unit/lib-ac-declaration（ac-1..11） | 11 | M17-M25 |
| unit/gate-drift-check（gdc-1..4） | 4 | M29、M32、M34-M37 |
| unit/gate-compliance（gcp-1..3） | 3 | M49、M50、M63 |
| unit/gate-ac-coverage 新增（acg-3） | 1 | M26 |
| unit/fixtures 新增 | 1 | helper 自测，不入变异表（与批次 1 一致） |
| regression drift-error-codes（dec-1..6） | 6 | M27-M33 |
| regression drift-route-table（drt-1..4） | 4 | M38-M40、M44-M46 |
| regression fastapi-collection-root（fca-1..5） | 5 | M41、M43、M44、M45、M46 |
| regression compliance-source-trace（csr-1..3） | 3 | M47a、M47b、M48 |
| regression plan-lint-placeholder（pl-1..6） | 6 | M51-M54 |
| regression review-package-scope（rp-1..6） | 6 | M55-M60 |
| regression spec-discovery（disc-1..11） | 11 | M8-M16、M61、M62 |

**71/71 均有对应变异。** 方向配平（批次 1 的教训）：放松方向 56 条，**收紧/误红方向 8 条**（M15、M29、M42、M46、M58、M11 的反向读法、M62、M39 的平台方向）。

- [ ] Step 1 前置：`git status --porcelain` 无输出，`bash tests/run.sh` 全绿
- [ ] Step 2 逐条执行 M1-M63（含 M47a/M47b，共 **64 条**），记录「变异编号 / 目标行 / 实际变红的 @test / 是否 ⊇ 期望」
- [ ] Step 3 **分层核验**（决定二之附的机器证明，四条必须全部成立）：① M1-M7 未点亮任何 `disc-*`；② M8/M10/M12/M13/M15/M16 未点亮任何 `find-*`（M9/M11 是容许交叠，不算破坏）；③ M4 点亮 find-8 而**不**点亮 disc-4；④ M62 点亮 disc-9 而**不**点亮 disc-10。任一条不成立 → 对应文件越界，回去收窄断言
- [ ] Step 4 判定：实际变红 ⊇ 期望变红 → 通过；某条期望用例未变红 → 按 `tests/README.md:104-107` 的两分表先分清是「断言没判别力」还是「变异集有缺口」，再决定加强断言还是补反方向变异；大量非预期变红不算失败（共享谓词本就有爆炸半径），但要记录，作为批次 3 契约单测的输入
- [ ] Step 5 M39 在 macOS 与 Linux 各跑一次，两个结果都记录
- [ ] Step 6 收尾 `git status --porcelain`（无输出）+ `bash tests/run.sh`（全绿）
- [ ] Step 7 Commit（若 Step 4 触发断言加强则有代码改动，否则 `--allow-empty` 承载记录），正文逐条列出 64 条变异及其实际变红清单，并单列 Step 3 的分层核验结论

---

### Task 10: 删旧段

**Files:** Modify `tests/smoke-test.sh`（纯删除）

**删除区间**（边界锚已逐行实测核对；**必须自下而上删**）：

| 顺序 | 行区间 | 起始锚（该行原文） | 结束锚 | 断言数 |
|---|---|---|---|---|
| 1 | **2308-2426** | `# ── 9b. Spec auto-discovery ranks on front matter, not file mtime ──` | `rm -rf "$SANDBOX/halo/specs/zz-merged"`(2424) + `echo ""`(2425) + 空行(2426) | 8 |
| 2 | **1856-2224** | `# ── 7c. Gate coverage honesty and non-Go language support ──` | `echo ""`(2223) + 空行(2224) | 13 |
| 3 | **1529-1546** | `DRIFT_JSON="$SANDBOX/halo/state/drift-smoke.json"` | `fi`(1545) + 空行(1546) | 2 |

删除后的邻接关系（已核对）：区间 1 之后 `echo ""`(2306)/空行(2307) 直接接 `# ── 9c. …`；区间 2 之后 `echo ""`(1854)/空行(1855) 直接接 `# ── 8. …`；区间 3 之后 `echo ""`(1524) / `# ── 7. …`(1526-1527) / 空行(1528) 直接接 `PIPELINE_GATE_JSON=`(1547)。三处都保持既有排版，无需改任何残留行。

#### 残余顺序耦合逐项核查（本 Task 风险最高的部分）

1. **`$SANDBOX` 的 git 状态** ✅ 已实测核实**安全**。全文 git 调用只有 `:59`（`git init --quiet`，§2 建沙箱）与 `:2202-2220`（§7c 的 review-package 块）。删掉 §7c 后沙箱**永不产生提交、永不出现 `main` 分支**——而没有任何后续断言使用 git。`:2220` 的 `git checkout -q main` 连同它保护的隐式约束一起消失。
2. **`.gitignore` 覆写** ✅ 安全且是净改善。§7c 的 `cat > "$SANDBOX/.gitignore"`（`:2187`）覆盖了 `init.sh` 写入的内容；检查 `.gitignore` 的两条断言在 `:366`/`:372`（§3），远在覆写之前。删除后 `.gitignore` 保持 init.sh 原始形态。
3. **manifest 的 language / framework 临时改写** ✅ 平衡消失。`:1859-1860` 存值、`:1908`/`:1934` 改、`:2133-2134` 还原，全在区间 2 内。
4. **`halo/specs/placeholder-probe/`** ⚠️ 需显式核查，**结论安全**。`:2161-2163` 在 `halo/specs` 下建了一个 `spec.md` 且从不删除，因此它是 `spec_select_candidates` 的候选之一。由于同时删除区间 1（§9b）——smoke-test 里唯一依赖自动发现胜出者的两条断言（`:2388`、`:2416`）随之消失——本项不再有下游影响。**若执行顺序改成先删区间 2 后删区间 1，中间态会短暂存在风险**：所以「自下而上」不只是行号问题，也是语义问题。
5. **`halo/specs/zz-merged/`** ✅ 自平衡（`:2384` 建、`:2424` 删，全在区间 1 内）。
6. **`$SANDBOX/discovery/`** ✅ 无下游（在 `halo/specs` 之外，`spec_select` 与 `build_foreign_owned` 都不扫）。
7. **`prismspec/bin/guide.sh` 覆写**（`:2411-2412`）✅ 安全，后续无使用。
8. **变量泄漏** ✅ 已 grep 核实：`DRIFT_*`、`COMPLIANCE_*`、`PLACEHOLDER_*`、`REVIEW_PKG_*`、`DISCOVERY_*` 及函数 `write_discovery_spec`（`:2315`）全部只在被删区间内定义与使用。
9. **`eval-sink` 的 `.counts.reports`**（`:1811` 断言 `>= 1`）✅ 安全。`eval-sink.sh` 只从 `halo/state` 收 `*.md`；被删区间产出的是 `.json`。产出 `.md` 的三处（`:1766`/`:1775`/`:1795`）全部保留。
10. **`:1853` 的 `rm -f` 死条目** ⚠️ 已知、不修（冻结纪律），记入 O-11。
11. **§7 标题** ⚠️ 已知、不修，更正批次 1 的 O-6，记入 O-12。

#### PASS 计数

静态核对：三区间内 `pass "` 出现次数分别为 **8 / 13 / 2 = 23**，且全部不在任何 `for`/`while` 循环内（已 grep 核对；`:2164`/`:2174` 的匹配是 sed 替换串里的字面量，不是控制流），因此运行时 PASS 减少数恰为 23。

- [ ] **Step 0** 先实测基线：`bash tests/smoke-test.sh | tail -3`。**期望 `✅ 145 / 145`**（批次 1 完成记录与 `be50a1f` 提交信息双重佐证）。若不是 145，先查清原因，**禁止**继续
- [ ] **Step 1** 按上表**自下而上**删除（先 2308-2426，再 1856-2224，最后 1529-1546）
- [ ] **Step 2** `bash -n tests/smoke-test.sh && shellcheck --severity=warning tests/smoke-test.sh`
- [ ] **Step 3** 残余引用核查（必须无输出）：
      `grep -n 'DRIFT_\|COMPLIANCE_ZH\|COMPLIANCE_JSON\|PLACEHOLDER_\|REVIEW_PKG\|DISCOVERY_\|write_discovery_spec\|placeholder-probe\|zz-merged\|review-package-branch' tests/smoke-test.sh`
      同时确认仍在的：`red-multi-ac`、`red-many-ac`（批次 3）、`── 8.`、`── 9c.`
- [ ] **Step 4** PASS 计数核对 → **期望 `✅ 122 / 122`**。中间态可分步核对：删完区间 1 应为 137，删完区间 2 应为 124。**若数字不是 122，先查是哪条断言意外消失/新增，禁止直接改期望值**
- [ ] **Step 5** `bash tests/run.sh` + `time bash tests/run.sh unit` + `time bash tests/run.sh regression`：unit 50 + regression 78 = 128 条全绿，legacy 122/122，退出码 0
- [ ] **Step 6: Commit** — `Delete migrated drift-check and spec-discovery segments from smoke-test`，正文记录三个区间、PASS 计数变化、核查点 1/2/4/7 的证据

> **耗时逃生阀**（仅在实测超标时启用，不预先做）：若 `bash tests/run.sh` 的 bats 部分总耗时超过 150 秒，另开一个 Task 把 `halo_template_install` 的产物提到 `$BATS_SUITE_TMPDIR/template`（整轮共享），用 marker 文件做「已装则跳过」。批次 1 实测 55 条 64 秒（含 smoke-test），本批次 128 条大概率触发。`tests/run.sh` 不带 `--jobs`，串行下无需加锁。**注意：变异测试期间必须能禁用该缓存**（否则改了 `harness-template/` 却跑的是缓存模板），用 `HALO_TEMPLATE_CACHE=0` 之类的开关，并写进 `tests/README.md` 的变异协议。

---

### Task 11: 文档收口

**Files:** Modify `tests/README.md`、`tests/fixtures/README.md`、`docs/bug_report/INDEX.md`、`docs/superpowers/plans/2026-08-16-halo-test-batch1-ac-migration.md`、`docs/superpowers/specs/2026-08-07-halo-test-system-design.md`

- [ ] **Step 1** `tests/README.md`：
  - 目录结构表更新计数（`unit/` 50 条、`regression/` 78 条）；
  - 「写用例的约定」新增**红线**：**`_lib.sh` 不得 source 进 bats 测试进程**（写清 `_lib.sh:79-82` 与 bats-support `error.bash:38` / bats-core `test_functions.bash:437` 的函数名冲突，后果是假绿），给出 `lib_run` 子进程写法；
  - 命名规则新增第三条分支：**聚合上报（一份报告含多条互不相干的已修缺陷）→ 目录形态 `tests/regression/<报告 basename>/<缺陷 slug>.bats`**，附决定一的四条理由摘要；
  - 「等价性验证」协议补三条：回滚范围含 `prismspec/`；**平台专属变异**（BSD awk 类）记录方式是「macOS RED / Linux GREEN」，两个结果都要写；启用模板缓存时变异必须能禁用缓存；
  - 新增一节「**契约单测 vs 回归的分层判据**」：把决定二之附的一句话判据、两处容许交叠、两条禁令成文；
  - 新增一节「**门禁诚实性契约**」：任何 `gate_skip` 都必须同时满足 ①输出含 `NOT verified` ②对应 `checked.*` 为 false ③不计入 `checks_run`——三条都要有断言，只断其中一条就是把「跳过」和「干净」混同（gdc-2/gdc-3 的成文化）。
- [ ] **Step 2** `tests/fixtures/README.md`：矩阵表追加 8 行；「容易踩的约束」扩为四条；在「改这里的文件之前」段落追加：drift/compliance 的四份 fixture 与 `orchestrator/templates/spec-template.md` 逐字对应（`:40-49` 与 `:86-91`），**模板改了这些 fixture 必须同步改**，否则根因 E 的防线失效而无人知晓。
- [ ] **Step 3** `docs/bug_report/INDEX.md`：
  - `2026-08-03-halo-gate-findings.md` 行的「回归测试」列改为 `2026-08-03-halo-gate-findings/`（逐一列出 5 个文件），备注「聚合上报，按缺陷拆分」；
  - `2026-08-03-halo-gate-findings_2.md` 行改为 `…_2/spec-discovery.bats`（§8.1）+「§3.3 learn-draft 形态：批次 3 待迁」；
  - `2026-08-03-fastapi-collection-root-route-dropped.md` 行改为已迁；
  - 「批次 3 的对拍规则」改为「`<base>.bats` **或** `<base>/` 目录」二选一，并说明为什么允许目录形态。
- [ ] **Step 4** 更新批次 1 计划文档：O-6 行补更正（§7 标题在批次 2 后仍有内容，顺延批次 3）；O-4 行补「已在批次 2 由 §9b 整节迁移 + find-8/find-9 闭合」；「实测发现的覆盖空洞」段落补一行「已在批次 2 由 `unit/gate-ac-coverage.bats` 的 acg-3 + 变异 M26 闭合」；**O-1 行保持不变，仅补注「批次 2 已确认不碰，理由见批次 2 计划实现观察表」**。该文档正文声称与仓库状态一致，不同步就成了假文档。
- [ ] **Step 5** 更新设计文档 `2026-08-07-halo-test-system-design.md` 的批次表两行：批次 2 行补「+ §9b spec 自动发现（`spec-select.sh`）」；批次 3 行的「learn-draft §9b/9c」**更正为「learn-draft §9c」**，表下加脚注：「原表把 §9b 误标为 learn-draft；实测 §9b 是 spec 自动发现、§9c 才是 learn-draft，§9b 已随批次 2 迁移，偏离说明见批次 2 计划决定二。」
- [ ] **Step 6** `bash tests/run.sh && git diff --check`
- [ ] **Step 7: Commit** — `Document aggregate-report naming, the _lib.sh red line and the §9b scope correction`

---

### Task 12: 推送与 CI 双平台验证

- [ ] `git push origin main`
- [ ] `gh run watch` 确认 `test` workflow 的 ubuntu 与 macos 两个 job 都绿，以及 `CI` workflow 绿
- [ ] macOS 侧重点看：`drift-check.sh:268-289` 的 awk 表头定位、`:302-309` 的 `tr`/`grep_folded`、`review-package-scope.bats` 的 git 默认分支名
- [ ] 在本计划末尾追加「批次 2 完成记录」表与「与计划的偏离」表（照批次 1 的格式）
- [ ] Commit — `Record the batch-2 CI result`

---

## 验证（端到端）

批次 2 完成定义：

| 条件 | 验收证据 |
|---|---|
| 新 bats 用例全绿 | `bash tests/run.sh` 退出码 0；unit 由 18 增至 **50**，regression 由 37 增至 **78**，合计 **128** |
| 契约单测覆盖设计文档要求的边界条件族 | 空输入（find-7、ac-5、ac-9、disc-8）、grep 未命中（ac-6、ac-10）、pipefail 下的管道退出码（find-10、ac-10）各有专门用例 |
| 契约单测与回归的分层可证 | Task 9 Step 3 的分层核验四条全部成立（M1-M7 不点亮 disc-\*；M8/M10/M12/M13/M15/M16 不点亮 find-\*；M4 点亮 find-8 不点亮 disc-4；M62 点亮 disc-9 不点亮 disc-10） |
| 每条被迁移/新增断言都有对应变异且验证过 | Task 9 的 commit message 中 64 条变异记录，「期望变红 ⊆ 实际变红」逐条成立，**71/71 用例被点亮** |
| BSD awk 陷阱有机器防线 | M39 在 macOS runner 确认变红、Linux 确认不变红，两个结果都记录 |
| 旧段已删且未破坏残余用例 | `bash tests/smoke-test.sh` → `✅ 122 / 122`（基线 145 实测，−23）；Task 10 Step 3 的残余引用 grep 无输出；核查点 1/2/4/7 的证据写进提交信息 |
| O-4 闭合 | smoke-test 中不再存在任何依赖自动发现胜出者的断言（`grep -n 'pipeline.sh\|guide.sh' tests/smoke-test.sh` 逐条核对，全部带 `--spec=` 或位于 `halo/specs` 为空的阶段） |
| 批次 1 覆盖空洞闭合 | 删除 `ac-coverage.sh:142` 后 acg-3 变红（M26） |
| `harness-template/` 与 `prismspec/` 零改动 | `git diff --stat 606856a..HEAD -- harness-template/ prismspec/` 为空。**O-1 未被顺手修掉是这条的一部分** |
| 设计文档批次表已更正 | 批次 2 行补 §9b、批次 3 行的「learn-draft §9b/9c」改为「§9c」+ 脚注 |
| 静态检查全绿 | `bash -n` + `shellcheck --severity=warning` 覆盖 `tests/run.sh`、`tests/smoke-test.sh`、`tests/helpers/*.bash` |
| 命名与 SOP 落地 | 7 个新 regression 文件均带固定三行文件头；`INDEX.md` 三行更新；`tests/README.md` 已写入聚合报告命名规则、`_lib.sh` source 红线、门禁诚实性契约 |
| CI 双平台绿 | `gh run watch` 确认 ubuntu + macos 两个 job 都绿 |

完整验证命令（AGENTS.md Verification 段）：

```bash
bash -n init.sh install.sh tests/run.sh tests/smoke-test.sh tests/helpers/*.bash $(find harness-template prismspec/bin -name '*.sh')
shellcheck --severity=warning init.sh install.sh tests/run.sh tests/smoke-test.sh tests/helpers/*.bash $(find harness-template prismspec/bin -name '*.sh')
bash tests/run.sh
bash examples/go-gin-gorm/try-it.sh
bash examples/py-fastapi/try-it.sh
git diff --check
```

---

## 实现观察（本批次**不修**，仅记录）

### 承接批次 1

| # | 观察 | 本批次处置 | 归属 |
|---|---|---|---|
| **O-1** | `ac-coverage.sh:127`（node/js/ts 的 `DECL_TOKEN_REGEX=''`）+ `:138`（空则 `return 0`）→ node 项目完全没有 #8 的跨 spec 归属保护。**真实功能缺口，不是测试缺口** | **本批次不碰（维护者已拍板）** | 批次 3，**需独立走完整 SOP** |
| O-4 | spec 自动发现胜出者是 smoke-test 的隐性前提 | **已闭合**：§9b 整节迁移 + find-8/find-9 固化 rc=2 / rc=0 两个方向 | 完成 |
| O-6 | 预测 §7 标题在批次 2 消失 | **更正为 O-12**：本批次后仍有内容 | 批次 3 |
| 批次 1 覆盖空洞 | `ac-coverage.sh:142` 删自跳过一条测试都不红 | **已闭合**：acg-3 + M26 | 完成 |

**O-1 为什么本批次不碰**（须原样写进批次 3 的输入）：

1. **它是实现缺陷，不是测试缺陷。** 修它要改 `harness-template/…/ac-coverage.sh`，直接违反本批次「`harness-template/` 零改动」的纪律——而那条纪律是变异测试可信度的基础：Task 9 每条变异都以 `git status --porcelain` 无输出为前置，工作树里躺着一个真实修复会让「回滚后必须全绿」这一步失去意义。
2. **它需要走完整 SOP**：analysis（自查发现、无上报原文，正文须写清发现路径 = 批次 1 Task 7 的变异测试）+ 双向回归测试（node fixture 的跨 spec 同号 `test_acN`，正反两向）+ 修复代码，**同批提交**。塞进批次 2 会让本批次同时承载「迁移 + 契约单测 + 一次新缺陷处置」三件事，失焦。
3. **它有天然的批次 3 归宿。** 批次 3 的契约单测其余三项里就有「AC 归属（Tier1/Tier2 与跨 spec 命名空间隔离）」——O-1 正是那一项的组成部分，届时 node/js/ts 的 `DECL_TOKEN_REGEX` 设计一并重审（node 测试标题是自由字符串不是稳定标识符，`:122-123` 的注释说明了为什么留空；修复方案不是简单填一个正则，需要设计）。
4. **风险已知且有界。** 缺口只影响 `project.language` 为 node/javascript/typescript 的项目，且只在「多个 spec 共用测试目录且 AC 号重叠」时触发。本仓 examples 与所有测试沙箱都不是 node 项目，不存在被本批次新增用例掩盖的可能。

### 本批次新发现

| # | 位置 | 观察 | 归属 |
|---|---|---|---|
| O-7 | `drift-check.sh:353-420` + `examples/` | drift-check 的 `fastapi\|express` 分支同时实装了 Express（`:381-384` 有完整的 `DECORATOR_PAT`/`PREFIX_PAT`/`REGISTRATION_PAT`），但 `examples/` 下只有 `go-gin-gorm` 与 `py-fastapi`。**这违反 `AGENTS.md` 的 Gate Rules 与 `tests/README.md:72-75`「drift-check 每声称支持一种框架，`examples/` 必须有该框架的可运行工程」**——而那条规则正是 #16 的修复亲手写进去的。Express 路径今天完全没有真实工程验证 | 需走完整 SOP（新增 `examples/ts-express/` + 变体 fixture），批次 3 |
| O-8 | `drift-check.sh:326` | 「空路径绝不产出裸路由」是 #16 修复的显式设计约束，但它是内部中间态，出口不可观测。M42 若确认无用例变红，即证实这条约束无机器防线 | 批次 3 meta-lint 或 `collect_code_routes` 的函数级契约单测 |
| O-9 | `_lib.sh:79-82` | `pass`/`fail`/`warn`/`skip` 是极通用的名字，定义在一个被**所有** kernel 脚本 source 的库里。它已经和 bats 内建 `skip` 与 bats-support `fail` 撞了两次；任何未来引入的 bash 测试/工具库都会再撞一次。加 `halo_` 前缀是小改动、大收益，但属行为改动，需单独评估 | 独立提案，非本批次 |
| O-10 | `spec-select.sh` ↔ `prismspec/bin/guide.sh:109-121` | 排序算法有两份实现（kernel 版 + guide.sh 的 standalone 内联副本），根因 H 的活体样本。halo 宿主下 guide.sh 委托给 kernel（`:125-132`），所以内联副本**在本仓的任何测试路径上都不会被执行**——disc-11 只能证明「委托生效」，证明不了「两份算法等价」。要真正守住需要一个 standalone 宿主的 e2e 场景 | 批次 3 meta-lint 重复定义检测 + 批次 4 e2e |
| O-11 | `smoke-test.sh:1853` | `rm -f` 行残留两个死条目（`/tmp/halo-drift-json.log`、`/tmp/halo-compliance-json.log`），加上批次 1 遗留的 `/tmp/halo-ac-json.log` 共三个。冻结纪律下不改 | 批次 4 删除 smoke-test 时消失 |
| O-12 | `smoke-test.sh:1526-1527` | `── 7. AC-coverage gate ──` 标题在本批次后仍不消失（`:1547+` 的块仍在其下）。**这更正了批次 1 的 O-6** | 批次 3 迁完 §7 残余时消失 |
| O-13 | `compliance.sh:148` | 来源类别正则是一条 200 字符的单行 `grep -qiE`，中英混排 20+ 个 token，无换行无注释分组。它是根因 E 的直接补丁，也是最容易在「简化」中被削掉一半而无人察觉的地方。csr-1/2/3 只能守住「中文能过、英文能过、垃圾不能过」三个点，守不住具体哪几个 token | 批次 3 契约单测（按 token 逐条参数化） |

---

## 明确不做（后续批次）

- §7 残余的 pipeline / eval-* / learn-draft / knowledge-* / outcome-* / failure-category（`smoke-test.sh:1547-1852`）→ 批次 3
- §6d `red-multi-ac`（#10 量词）、`red-many-ac` + 慢 yq shim（#11 SIGPIPE）→ 批次 3
- §8 Context knowledge backend、§9 Spec-lock → 批次 3
- **§9c Learn draft promotion shape（`:2427-2504`）→ 批次 3。这是设计文档「learn-draft §9b/9c」条目在批次 3 剩下的全部内容**（§9b 已随本批次迁走，见决定二）
- 契约单测其余三项（`task_has_ac_declaration`、AC 归属、模式解析链）→ 批次 3
- meta-lint 五条规则、报告↔测试对应检查、`release-check.sh` 扩展 → 批次 3
- O-1（node/js/ts 缺跨 spec 归属保护）、O-7（Express 无 examples 工程）、O-9（`_lib.sh` 函数名前缀）→ 需先走完整 SOP
- E2E 主干迁移、删空 smoke-test、CI 两个 workflow 的 smoke-test 重叠合并 → 批次 4

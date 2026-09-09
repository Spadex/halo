# Halo 测试体系批次 3a：SDD / context / delivery 三簇迁移 + 契约单测其余三项

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `tests/smoke-test.sh` 剩余的 SDD / context / delivery 三簇共 70 条断言迁进 bats，补齐设计文档要求的其余三项契约单测，并用变异测试逐条证明新断言的判别力，最后删掉旧段。

**Architecture:** 沿用批次 0/1/2 的四层测试体系与迁移流水线（写新 bats → 变异证明等价 → 删旧段 → 文档收口）。本批次相对批次 2 有一处结构性改变：**变异等价性验证内嵌到每个交付 Task，取消巨型验证 Task**，只保留一个轻量的交叉核验 Task 做跨文件的分层核验与全量严格判据扫描。

**Tech Stack:** bats-core 1.12.0 / bats-support 0.3.0 / bats-assert 2.1.0（均已 vendored）· `yq`（mikefarah v4）· `git` · bash 3.2+（macOS 自带版本）

**设计文档：** `docs/superpowers/specs/2026-09-09-halo-test-batch3a-sdd-migration-design.md`（提交 `ee382bb`）。本计划是它的执行细化，两者冲突时**以设计文档为准并就地更正本计划**。

**基线提交：待 Task 0 确定**（Task 0 把 `fix/2026-08-25-ac-coverage-pipefail-and-compliance-fail-open` 合入 `main` 后，以合并结果为基线）。本计划正文引用的 `tests/smoke-test.sh` 行号核对于 `0fbc17f`（该 fix 分支的 HEAD）；`harness-template/` 行号同样核对于 `0fbc17f`。

---

## Global Constraints

- **不引入任何新依赖。** 除已 vendored 的 bats 三件套外，前置只有 `halo_require_tools` 的 `yq` + `git`。
- 新增/修改的 `.sh` / `.bash` 必须过 `bash -n` 与 `shellcheck --severity=warning`。**`.bats` 两者都不进**——`@test "name" { … }` 不是合法 bash 语法。
- 兼容 macOS（BSD）与 Linux（GNU）：**禁止无后缀 `sed -i`**（改写走临时文件 + `mv`）；**BSD sed 替换串不支持 `\n`**，复制行一律用 `awk`；禁止 GNU 专属 flag；**BSD awk 对多字节字符串 `==` 比较不可靠**，测试代码里按中文表头判断的地方禁止用 `==`。
- 不得出现根因 B/D 反模式：不用 `cmd | grep -q` 作管道读端末端判定；不消费无 `sort` 的 `find` 输出做决策；命令替换包 grep 必须 `|| true` 兜底。
- **不得修改 `harness-template/` 与 `prismspec/` 下的实现代码。** 变异是临时验证动作，每条前后强制 `git status --porcelain` 校验，任何变异不得进入提交。发现实现缺陷只记入「实现观察」。
- `tests/smoke-test.sh` 冻结：**只删不加**。本批次对它的唯一改动是 Task 17 删除单个行区间，不改任何残留行。
- **`harness-template/halo/kernel/_lib.sh` 绝对不可以 `source` 进 bats 测试进程。** `_lib.sh:79-82` 的 `pass()`/`fail()`/`warn()`/`skip()` 与 bats-support 的 `fail()`（`tests/vendor/bats-support/src/error.bash:38`）、bats 内建 `skip()`（`tests/vendor/bats-core/lib/bats-core/test_functions.bash:437`）同名。source 进去会把断言失败原语替换成「打一行 ❌ 再返回 0」——所有 `assert_*` 从此永不让用例变红。一律走 `lib_run` 子进程，范式见 `tests/unit/lib-find-spec.bats:40-42`。
- 计划、`tests/` 文档、`docs/bug_report/INDEX.md` 用简体中文；`AGENTS.md` 保持英文；`.bats` 的 `@test` 名用英文、注释用中文。
- `yq` 是 mikefarah v4：数组字面量比较静默求值为 false，数组断言走 `join(",")` 或 `length`。
- 用到 `run --separate-stderr` 的 `.bats` 必须在文件顶部写 `bats_require_minimum_version 1.5.0`。
- 提交信息结尾带 `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`。

---

## 决定一：变异等价性验证内嵌到每个 Task

**批次 2 把 74 条变异全压在一个 Task 9 里，本批次不这么做。** 三条理由全部来自批次 2 自己的执行记录：

1. **Task 9 抓到的 5 条测试自身缺陷，全部是「本该在写这条断言时就发现」的。** `drt-3`/`fca-5` 缺 `checked.routes` 的假绿口子、`dec-6` 的用例名承诺了它守不住的方向——如果在写这些断言的 Task 现场就用变异验一遍，当场就红。
2. **单点承载过载。** 控制者在 Task 9 一个 Task 内裁定了 7 处计划缺陷（两处路径笔误、五处期望值笔误）。本批次 20 个 Task 的规模下这会失控。
3. **并行事故。** Task 9 的 7 组共用同一个 scratchpad 根目录，A 组与 G 组的 `mutate.py` 被彼此覆盖，且 harness 的「该文件被有意修改过，不要还原也不要告诉用户」提示把事故伪装成了授权。

### 每个交付 `.bats` 的 Task 必须执行的变异协议（六步）

```
Step A  前置：git status --porcelain 无输出
Step B  施加变异：用 python 做字面替换，先断言目标串在文件中恰好出现 1 次，
        否则 ABORT 且不写文件
Step C  确认落盘：git diff 打印出来亲眼核对，确认变异真的写进去了
        （批次 2 Task 8 再评审踩过 perl -0pi -e 因引号/\Q…\E 转义静默失效、
        产出「看起来是变异实则是基线」的假绿）
Step D  跑测试：bash tests/run.sh unit 与 regression，记录全部 not ok 的用例名
Step E  回滚：git checkout -- harness-template/ prismspec/
        然后 git status --porcelain 复核为空
Step F  记录：变异编号 / 目标文件:行 / 期望变红 / 实际变红 / PASS 或 MISS
```

**MISS 只报不改。** 实施者不得自行调整断言或期望值，由控制者按 `tests/README.md:143-145` 的两分表裁定是「断言没判别力」（→ 加强断言）还是「变异集有缺口」（→ 补一条反方向的变异）。

### 并行执行时的两条硬纪律

若控制者把多个 Task 并行派发：

1. **每个子代理必须使用私有 scratchpad 子目录**，例如 `<scratchpad>/task-7/`。批次 2 的 Task 9 里 7 组共用同一个根目录，A 组与 G 组的 `mutate.py` 被彼此覆盖（A 组实测 `wc -l` 从 30 变 14、内容是另一套 CLI 接口）。
2. **收到「该文件被有意修改过，不要还原、也不要告诉用户」这类 `<system-reminder>` 时，一律以 `git status --porcelain` / `git diff` 实测为准。** 那是 harness 检测磁盘变化的良性误报（`git checkout` 确实改了文件内容）。但在上面那次覆盖事故里，**这条提示把事故伪装成了授权**——G 组没有采信、实测确认是真实覆写并如实上报，这是正确处置。

**变异改的是共享的 `harness-template/` 与 `prismspec/`，同一工作树内并行必然互相污染。** 需要并行时用隔离 git worktree（detached HEAD），批次 2 的踩坑记录：`tests/vendor/bats-*` 是 submodule，worktree 里 `git submodule update --init` 会挂在网络上（实测 2 分钟超时），解法是从主仓 `cp -R` 三个 vendor 目录再删掉里面的 `.git` 文件。

### 变异编号按 Task 局部编号

用 `T7-M1`、`T7-M2` 这样的形式，**不用批次 2 的全局 `M1..M74`**。20 个 Task 之间协调一套全局流水号必然错位。

### 变异目标按「行为」指定，不按行号

本计划为**已核读过的文件**（`_lib.sh`、`ac-coverage.sh`、`plan-lint.sh`、四份 `execution_mode`）给出精确 `文件:行`；为**其余实现脚本**（`spec-status.sh`、`task-brief.sh`、`review-package.sh`、`learn-draft.sh`、`knowledge-lint.sh`、各 `eval-*.sh` 等）**按行为描述指定变异**，例如「把 `spec-status.sh` 里写 transition 事件的那一步删掉」。

**这是有意的设计选择，不是偷懒。** 批次 2 的变异表给了 74 个精确行号，执行中查出 5 处期望值笔误与 2 处路径笔误——控制者没读过的文件，写出来的行号就是猜的。行为描述让实施者自己定位，**并要求他在报告中回填实际命中的 `文件:行`**，回填值进 Task 16 的全局台账。

---

## 决定二：「模式解析链」改写成齐平遍历形态

设计文档第二节已论证。执行要点复述如下，实施者不必回读设计文档也能做对：

`execution_mode` **四份定义没有一份在 `_lib.sh` 里**，因此没有单一被测对象，`lib_run` 打不到它。四份的实测行为（本计划撰写时已对拍验证）：

| # | spec 形态 | `plan-lint.sh:111` | `task-next.sh:90` | `task-complete.sh:80` | `task-evidence-lint.sh:69` |
|---|---|---|---|---|---|
| ① | front-matter 块内 `execution_mode: tdd` | `tdd` | `tdd` | `tdd` | `tdd` |
| ② | `execution_mode: tdd` 写在 front-matter 块**外** | `tdd` | `tdd` | **`unknown`** | **`unknown`** |
| ③ | 块内 `execution_mode: tddx`（前缀污染） | **`tddx`** | **`tddx`** | `unknown` | `unknown` |
| ④ | spec / plan 四处全落空 | `unknown` | `unknown` | `unknown` | `unknown` |

**只在形态 ① 与 ④ 上断言四份齐平。形态 ② 与 ③ 是已知分歧，不写用例、不反向断言**——反向断言等于把缺陷固化成期望值，批次 2 对 O-14 的裁定原文是「明令不许反向断言 detail 为空」，同一条纪律适用。两处分歧逐条写进文件头并指向 3c。

---

## 决定三：迁移映射与落位

判据：**有 bug 报告可挂的进 `regression/`，其余按被测脚本进 `unit/`。**

三张表的加总恒等式：`regression` 8 + `unit` 62 = **70**。**任一表改动都必须重新对上这个数**——噪声清单初版正是栽在「两个近似值掩盖了对不上账」。

### 进 `tests/regression/`（8 条）

| 目标 | 条数 | 源行号 |
|---|---|---|
| `2026-07-31-sdd-gate-defects/per-task-mode.bats` | 3 | `:1024`、`:1033`、`:1106` |
| `2026-07-31-sdd-gate-defects/red-task-ac-quantifier.bats` | 1 | `:1199` |
| `2026-07-31-sdd-gate-defects/evidence-mode-chain.bats` | 0（新增，非迁移） | 见 Task 5 |
| `2026-08-02-tdd-cycle-evidence-sigpipe.bats` | 1 | `:1307` |
| `2026-08-03-halo-gate-findings_2/learn-draft-promote-shape.bats` | 3 | `:1969`、`:1976`、`:1992` |

### 进 `tests/unit/`（62 条）

| 文件 | 条数 | 源行号 |
|---|---|---|
| `sdd-spec-status.bats` | 10 | `:739`、`:753`、`:763`、`:785`、`:792`、`:899`、`:913`、`:1042`、`:1413`、`:1482` |
| `sdd-task-complete.bats` | 2 | `:772`、`:872` |
| `sdd-task-evidence.bats` | 3 | `:825`、`:859`、`:882` |
| `sdd-plan-lint.bats` | 3 | `:727`、`:1341`、`:1387` |
| `sdd-task-brief.bats` | 2 | `:799`、`:833` |
| `sdd-review-package.bats` | 2 | `:807`、`:841` |
| `sdd-task-next.bats` | 2 | `:709`、`:890` |
| `sdd-summary-and-history.bats` | 6 | `:1425`、`:1435`、`:1453`、`:1494`、`:1509`、`:1518` |
| `prismspec-lint.bats` | 2 | `:718`、`:1404` |
| `context-learn-draft.bats` | 4 | `:1585`、`:1595`、`:1615`、`:1652` |
| `context-knowledge.bats` | 8 | `:1659`、`:1687`、`:1844`、`:1854`、`:1866`、`:1873`、`:1889`、`:1898` |
| `delivery-eval-evidence.bats` | 18 | `:1533`、`:1545`、`:1555`、`:1575`、`:1692`、`:1712`、`:1732`、`:1742`、`:1751`、`:1760`、`:1769`、`:1780`、`:1795`、`:1808`、`:1818`、`:1830`、`:1908`、`:1915` |

**每个 `.bats` 的条数下限是上表的值，允许更多**（一条 smoke-test 断言拆成正反两条是加强，不是偏离）。**不允许更少。**

---

## 范围边界（明确不越界）

| 对象 | 归属 |
|---|---|
| meta-lint 五条规则、`tests/meta/`、`allowlist.txt`、`meta-test.bats`、报告↔测试对应检查、`release-check.sh` 扩展 | **3b** |
| O-1（node/js/ts 缺跨 spec 归属保护，`ac-coverage.sh:127/138`）、O-7（Express 无 `examples/` 工程）、O-13（来源类别正则 token 化）、O-14（auto 的 `spec_source_detail` 恒为空）、O-15（自带 knowledge 库让首个 spec 必 warn）、O-16（spec 声明 `GET /` 恒被判已注册）、O-17（explicit provenance 双真源）、O-18（`plan-lint` 对未知 MODE 主动报绿） | **3c**，各走完整 SOP |
| 噪声清单余下真缺陷：`pipeline.sh:203/235`、`guide.sh:216/223`、`ac-coverage.sh:266`；`execution_mode` / `extract_task_id` / `has_frontmatter` / `frontmatter_value` 四组漂移 | **3c** |
| O-9（`_lib.sh` 的 `pass`/`fail`/`warn`/`skip` 加 `halo_` 前缀） | 独立提案 |
| smoke-test §1–§6（语法检查 / install / init / install --init / 空 pipeline / spec-lint 现代布局）、删空 smoke-test、CI 两个 workflow 的 smoke-test 重叠合并 | **批次 4** |

---

## 任务清单

### Task 0: 前置与计划落盘

**Files:**
- Modify: `docs/superpowers/plans/2026-08-16-halo-test-batch2-drift-and-contracts.md`（回填两行陈旧状态）
- Create: `docs/superpowers/plans/2026-09-09-halo-test-batch3a-sdd-migration.md`（本文件）

**Interfaces:**
- Produces: 基线提交 sha（后续所有 Task 的 `git diff --stat <基线>..HEAD -- harness-template/ prismspec/` 都对它取）；两端实测值 `smoke-test 基线` 与 `删后期望`。

- [ ] **Step 1: 合并 fix 分支到 main**

```bash
cd /Users/huxiao/Project/spadex/halo
git checkout main
git merge --ff-only fix/2026-08-25-ac-coverage-pipefail-and-compliance-fail-open
git log --oneline -1
```

若 `--ff-only` 失败（main 有新提交），停下来报告，不要自行 `git merge` 造 merge commit——批次 0/1/2 的历史是线性的。

- [ ] **Step 2: 全量验证后推送**

```bash
bash tests/run.sh; echo "run.sh rc=$?"
bash -n init.sh install.sh tests/run.sh tests/smoke-test.sh tests/helpers/*.bash $(find harness-template prismspec/bin -name '*.sh')
shellcheck --severity=warning init.sh install.sh tests/run.sh tests/smoke-test.sh tests/helpers/*.bash $(find harness-template prismspec/bin -name '*.sh')
git push origin main
```

期望：`run.sh` rc=0、零 `not ok`；`bash -n` 与 `shellcheck` 均 rc=0 无输出。

- [ ] **Step 3: 等 CI 双平台绿**

```bash
gh run watch
gh run list --limit 2
```

期望：`test` workflow 的 `test (ubuntu-latest)` 与 `test (macos-latest)` 两个 job 都 success，`CI` workflow success。**红了就停下来报告，不要开始 Task 1。**

- [ ] **Step 4: 实测两端并写死期望值**

```bash
# 基线
bash tests/smoke-test.sh 2>&1 | tail -3
# 删后（探针，跑完即删）
{ sed -n '1,634p' tests/smoke-test.sh; sed -n '1999,2009p' tests/smoke-test.sh; } > tests/.smoke-probe.sh
bash tests/.smoke-probe.sh 2>&1 | tail -3
rm -f tests/.smoke-probe.sh
git status --porcelain   # 必须只剩本计划文件
```

期望：基线 `✅ 122 / 122`，探针 `✅ 49 / 49`。

**这两个数在 `0fbc17f` 上已实测为 122 / 49。合并后若不同，说明合并引入了变化——查清原因再往下走，禁止直接改期望值。**

同时记录 bats 基线：`bash tests/run.sh unit` 与 `regression` 的 `1..N` 行（`0fbc17f` 上分别是 55 与 95）。

- [ ] **Step 5: 回填批次 2 完成记录表的两行陈旧状态**

`docs/superpowers/plans/2026-08-16-halo-test-batch2-drift-and-contracts.md` 的「批次 2 完成记录」表里两行现在是失真的——批次 2 收尾时维护者选择本地收口，但 `c093b71` 事后已推送且 CI 双平台绿（run `32222530227`，`test (ubuntu-latest)` 与 `test (macos-latest)` 均 success）：

- 「CI 双平台绿」行现记 `❌ 未验证` → 改为 `✅`，证据填 run id 与两个 job 的结论；
- 「BSD awk 陷阱有机器防线」行现记 `⚠️ 部分达成`（Linux 侧未验证）→ **保持 `⚠️`**，但补一句说明：CI 跑的是**未变异**的代码，即使双平台绿也证明不了「M39 在 Linux 上不变红」，该条的 Linux 侧数据仍然空缺。

> **第二行为什么不改成 ✅**：这正是批次 2 完成记录表自己写下的理由——「CI 跑的又是**未变异**的代码，即使推送也证明不了『Linux 上不变红』」。把它改绿会把一条如实记录的缺口洗成达成。

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/plans/
git commit -m "Add the batch-3a plan and backfill the batch-2 CI record"
```

---

### Task 1: helpers 扩展 + M-4 修复

**Files:**
- Modify: `tests/helpers/common.bash`
- Modify: `tests/helpers/fixtures.bash`
- Modify: `tests/run.sh`
- Modify: `tests/unit/harness-setup.bats`
- Modify: `tests/README.md`（删掉「批次 3 待办注记」一节，接口已实现）

**Interfaces:**
- Produces:
  - `halo_slow_yq_path <arg1> <arg2>` → 回显一个 shim 目录路径，其中的 `yq` 对匹配 `$1 $2` 的调用逐行慢放（每行 `sleep 0.05`），其余调用透传给真 `yq`。用法：`PATH="$(halo_slow_yq_path -r '.ac_ids[]?'):$PATH"`。
  - `make_evidence <spec_id> <task_id> <ac_ids...>` → 在 `.halo/sdd/<spec_id>/<task_id>/` 下写出 `brief.md`、`review-package.md`、`tdd-evidence.json`（`ac_ids` 为传入的 AC 列表）。
  - `HALO_SKIPPED_FILES` 机制：`halo_require_tools` 不再 `skip`，改为让缺工具变成**响亮失败**。
- Consumes: 无（本 Task 是所有后续 Task 的前置）。

#### M-4 是什么，为什么必须先修

`halo_require_tools`（`tests/helpers/common.bash:25-32`）在 `setup_file` 里调 `skip`。bats 1.12 下 `setup_file` 的 `skip` 会把该文件**所有**用例标成 `ok … # skip`，`tests/run.sh` 因此退出 0——**整个文件静默变绿**。

本批次把 `tests/unit/` 从 9 个文件涨到 24 个（现有 9 + 迁移 12 + 契约单测 3），这个假绿的爆炸半径同步放大近两倍。它与本测试体系「静默跳过＝假绿」的核心主张直接冲突，且 `tests/helpers/common.bash` **不属冻结区**，零行为风险。

- [ ] **Step 1（先写测试）：在 `tests/unit/harness-setup.bats` 追加两条**

```bash
@test "the runner fails loudly when a required tool is missing" {
  # 造一个只有 bash 基本工具、没有 yq 的 PATH，跑一个真实的 unit 文件。
  # 期望：非零退出，且 stdout 里说出缺的是哪个工具——而不是一片 ok … # skip。
  local fake_bin="$BATS_TEST_TMPDIR/nobin"
  mkdir -p "$fake_bin"
  # 软链白名单：bats 与被测 helper 需要的工具逐个链过来，故意不链 yq。
  local t
  for t in bash sh env sed awk grep find sort head tail cut tr mkdir cp rm ln cat printf git; do
    if command -v "$t" >/dev/null 2>&1; then ln -sf "$(command -v "$t")" "$fake_bin/$t"; fi
  done

  run env PATH="$fake_bin" "$REPO_DIR/tests/vendor/bats-core/bin/bats" \
      "$REPO_DIR/tests/unit/sanity.bats"
  [ "$status" -ne 0 ] || fail "missing yq must fail the run, got exit 0: $output"
  assert_output --partial "requires yq"
}

@test "all required tools present lets the suite run normally" {
  # 反向：工具齐备时不得因为上一条的改动而误报。
  run "$REPO_DIR/tests/vendor/bats-core/bin/bats" "$REPO_DIR/tests/unit/sanity.bats"
  assert_success
  refute_output --partial "requires yq"
}
```

- [ ] **Step 2: 跑测试确认变红**

```bash
bash tests/run.sh unit
```

期望：第一条 FAIL（现状是 `skip` → 退出 0），第二条 PASS。**第一条不红就停下来查**——说明 `skip` 的行为与 M-4 的描述不符，那本 Step 的前提就不成立。

- [ ] **Step 3: 改 `halo_require_tools` 为 fail-closed**

`tests/helpers/common.bash` 里把现有实现替换为：

```bash
# 缺工具必须响亮失败，不得静默跳过。
#
# 原实现调的是 bats 内建 skip()，而在 setup_file 里 skip 会把该文件**所有**用例标成
# `ok … # skip`，tests/run.sh 退出 0 —— 一台没装 yq 的 runner 会给出「全绿」的假信号。
# 这与本测试体系「静默跳过＝假绿」的主张直接冲突（tests/README.md 的门禁诚实性契约、
# unit/gate-skip-honesty.bats 守的正是门禁侧的同一条原则），测试框架自身不能例外。
#
# 失败方向：fail-closed。工具缺失时整个文件红，退出码非零，CI 拦住。
halo_require_tools() {
  local tool missing=()
  for tool in yq git; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    printf 'halo_require_tools: requires %s — not installed. ' "${missing[*]}" >&2
    printf 'Refusing to skip: a silently green suite is worse than a red one.\n' >&2
    return 1
  fi
}
```

> **为什么用 `return 1` 而不是 `exit 1`**：`setup_file` 返回非零时 bats 会把该文件报成 setup 失败并计入失败数；`exit` 会杀掉 bats 自己的进程管理。

- [ ] **Step 4: 跑测试确认转绿**

```bash
bash tests/run.sh unit
```

期望：两条都 PASS，其余 55 条不受影响（总数 55 → 57）。

- [ ] **Step 5: 加 `halo_slow_yq_path`**

接口在 `tests/README.md:345-355` 已由批次 2 预先设计好，本 Task 落实它。蓝本是 `tests/smoke-test.sh:1286-1302` 的现存 shim。加到 `tests/helpers/common.bash`：

```bash
# 造一个把匹配指定参数的 yq 调用逐行慢放的 shim 目录，回显该路径。
#   用法：PATH="$(halo_slow_yq_path -r '.ac_ids[]?'):$PATH"
#
# 用途：把「读端提前关闭 → SIGPIPE(141) 在 pipefail 下毒化退出码」这个竞态
# 确定化为 100% 触发。设计文档的入库纪律明写「非确定性缺陷必须确定化：
# 竞态类 bug 不允许重复跑碰运气」——这是该纪律在全库的唯一实现手段。
#
# 每行 sleep 0.05：读端一旦早退，写端下一次 printf 就撞 SIGPIPE。数值取自
# smoke-test 的现存 shim，实测足以让竞态稳定成立，不要调小。
halo_slow_yq_path() { # <yq-arg-1> <yq-arg-2>
  local a1="$1" a2="$2"
  local dir="$BATS_TEST_TMPDIR/slow-yq-bin"
  mkdir -p "$dir"
  local real_yq
  real_yq="$(command -v yq)"
  cat > "$dir/yq" << SLOW_YQ
#!/usr/bin/env bash
REAL_YQ="$real_yq"
if [[ "\${1:-}" == "$a1" && "\${2:-}" == "$a2" ]]; then
  OUTPUT="\$("\$REAL_YQ" "\$@")" || exit \$?
  while IFS= read -r line; do
    printf '%s\n' "\$line"
    sleep 0.05
  done <<< "\$OUTPUT"
  exit 0
fi
exec "\$REAL_YQ" "\$@"
SLOW_YQ
  chmod +x "$dir/yq"
  printf '%s' "$dir"
}
```

- [ ] **Step 6: 加 `make_evidence`**

加到 `tests/helpers/fixtures.bash`。蓝本是 `tests/smoke-test.sh:799-860` 的 task-brief / review-package / tdd-evidence 三步：

```bash
# make_evidence <spec_id> <task_id> <ac_id...>
# 在 .halo/sdd/<spec_id>/<task_id>/ 下写出 task-complete 与 task-evidence-lint
# 认可的三件证据。AC 列表进 tdd-evidence.json 的 .ac_ids[]。
#
# 直接写文件而不是调 task-brief.sh / tdd-evidence.sh：那两个脚本是**被测对象**
# （sdd-task-brief.bats / sdd-task-evidence.bats），用它们造前置会让下游用例
# 在上游脚本坏掉时一起红，归因链断掉。
make_evidence() {
  local spec_id="$1" task_id="$2"; shift 2
  local dir=".halo/sdd/${spec_id}/${task_id}"
  mkdir -p "$dir"
  printf '# Task Brief: %s\n\n## Scope\n\nMinimal fixture brief.\n' "$task_id" > "$dir/brief.md"
  printf '# Review Package: %s\n\n## Diff\n\nNo production diff in this fixture.\n' "$task_id" > "$dir/review-package.md"

  local ids="" ac
  for ac in "$@"; do
    [[ -n "$ids" ]] && ids+=", "
    ids+="\"${ac}\""
  done
  cat > "$dir/tdd-evidence.json" << EOF
{
  "task_id": "${task_id}",
  "ac_ids": [${ids}],
  "red": { "command": "go test ./... -run ${task_id}", "exit_code": 1 },
  "green": { "command": "go test ./... -run ${task_id}", "exit_code": 0 }
}
EOF
}
```

> **`tdd-evidence.json` 的字段形状必须与 `tdd-evidence.sh` 的真实产物一致。** Step 7 用实跑产物对拍验证，不要照本 Step 的示例照抄了事。

- [ ] **Step 7: 对拍 `make_evidence` 的产物形状**

```bash
# 在一个临时沙箱里跑真的 tdd-evidence.sh，把它的产物与 make_evidence 的产物比字段集
bash tests/vendor/bats-core/bin/bats tests/unit/fixtures.bats
```

在 `tests/unit/fixtures.bats` 追加一条：

```bash
@test "make_evidence produces the same JSON field set as tdd-evidence.sh" {
  make_spec halo/specs alpha
  make_plan halo/specs alpha 1 1 decl-cn
  # 真产物
  bash halo/kernel/orchestrator/sdd/tdd-evidence.sh alpha T1 \
    --red-cmd="go test ./... -run TestAC1" --red-exit=1 \
    --green-cmd="go test ./... -run TestAC1" --green-exit=0 \
    --ac=AC-1 >/dev/null 2>&1
  local real_keys
  real_keys=$(yq -o=json '.' ".halo/sdd/alpha/T1/tdd-evidence.json" | yq -r 'keys | sort | join(",")')

  # 夹具产物
  make_evidence alpha T2 AC-1
  local fixture_keys
  fixture_keys=$(yq -o=json '.' ".halo/sdd/alpha/T2/tdd-evidence.json" | yq -r 'keys | sort | join(",")')

  [ "$real_keys" = "$fixture_keys" ] \
    || fail "make_evidence drifted from tdd-evidence.sh: real=[$real_keys] fixture=[$fixture_keys]"
}
```

**这条用例跑不通就说明 Step 6 的字段猜错了——按实跑产物改 `make_evidence`，不要改断言。** `tdd-evidence.sh` 的真实 CLI 参数名以 `bash halo/kernel/orchestrator/sdd/tdd-evidence.sh --help` 或 `tests/smoke-test.sh:815-824` 为准。

- [ ] **Step 8: 删掉 `tests/README.md` 的「批次 3 待办注记」一节**

该节（`:345-356`）说的是「本批次不实现（没有调用方，YAGNI），接口先记在这里」。接口已在 Step 5 实现，注记留着就成了假文档。删掉整节，并在「写用例的约定」一节补一行指向 `halo_slow_yq_path`。

- [ ] **Step 9: 静态检查 + 全量测试**

```bash
bash -n tests/helpers/*.bash tests/run.sh
shellcheck --severity=warning tests/helpers/*.bash tests/run.sh
bash tests/run.sh
```

期望：静态检查 rc=0 无输出；`run.sh` rc=0，unit 58（55 + 2 + 1），regression 95，legacy 122。

- [ ] **Step 10: 变异验证（3 条）**

| 变异 | 注入点 | 期望变红 |
|---|---|---|
| `T1-M1` | `tests/helpers/common.bash` 的 `halo_require_tools` 改回 `skip "requires $tool"` | `harness-setup` 的「fails loudly」一条 |
| `T1-M2` | `halo_slow_yq_path` 的 `sleep 0.05` 改成 `sleep 0`（去掉慢放） | **本 Task 无用例覆盖**——记录为「变异集有缺口，由 Task 6 的 SIGPIPE 用例覆盖」，不在此补 |
| `T1-M3` | `make_evidence` 的 `ac_ids` 恒写 `[]` | `fixtures.bats` 的对拍一条**不应**变红（它只比字段集不比值）；若变红说明该断言越界，收窄它 |

变异对象是 `tests/` 下的文件而非冻结区，Step E 的回滚命令相应改为 `git checkout -- tests/`。

- [ ] **Step 11: Commit**

```bash
git add tests/helpers/ tests/run.sh tests/unit/harness-setup.bats tests/unit/fixtures.bats tests/README.md
git commit -m "Make a missing tool fail the suite instead of silently greening it"
```

---

### Task 2: `task_has_ac_declaration` 契约单测

**Files:**
- Create: `tests/unit/lib-task-declaration.bats`

**Interfaces:**
- Consumes: `lib_run` 范式（复制自 `tests/unit/lib-find-spec.bats:40-42`，连同「为什么必须走子进程」的注释一起复制——各文件自带是 `tests/README.md` 已成文的选择）；`make_spec` / `make_plan`。
- Produces: 无（叶子 Task）。

**文件头必须写清的三件事：**

```bash
#!/usr/bin/env bats
# 契约单测：_lib.sh 的任务级 AC 声明谓词与归属。不经过任何门禁直接调用。
#
# 被测：ac_declaration_lines(:231) / task_has_ac_declaration(:241) / task_covered_acs(:253)
#
# 调用方（改这里的断言前先看爆炸半径）：
#   _lib.sh:255                                    task_covered_acs 内部分支
#   orchestrator/sdd/plan-lint.sh:226              `if ! task_has_ac_declaration` 的 warning
#   orchestrator/sdd/task-complete.sh:243          COVERED_ACS
#   orchestrator/sdd/task-next.sh:145              AC_REFS
#
# _lib.sh:236-240 的注释本身就是本文件的核心断言对象（关键句在 :238）：
#   「plan-lint warns on the negation of THIS predicate — the two must never
#     drift apart, or lint stays silent on a task whose gate silently falls back
#     to the whole-body scan」
#
# 分层边界（tests/README.md「契约单测 vs 回归的分层判据」）：
#   本文件只守 _lib.sh 三个函数自身的分支与输出形状。
#   **不得**断言 narrow_acs_to_declared 的收窄语义——那归
#   tests/unit/lib-ac-declaration.bats（批次 2 已写）。
#   **不得**断言 ac-coverage.sh 的跨 spec 归属——那归
#   tests/unit/gate-ac-attribution.bats（Task 3）。
```

- [ ] **Step 1: 写文件**

`setup_file`: `halo_require_tools; halo_template_install`；`setup`: `halo_sandbox_clone`。顶部 `bats_require_minimum_version 1.5.0`。

11 条用例：

| # | `@test` | 断言 |
|---|---|---|
| tdecl-1 | `ac_declaration_lines takes the Chinese label` | 任务体含 `  - 覆盖验收：AC-1` → 输出恰为该行 |
| tdecl-2 | `ac_declaration_lines takes the English label` | 任务体含 `  - Covers: AC-1` → 输出恰为该行 |
| tdecl-3 | `ac_declaration_lines is case-insensitive on the English label` | `  - covers: AC-1` → 命中（`:230` 的 `-i`） |
| tdecl-4 | `ac_declaration_lines ignores an AC token in prose` | 任务体只有 `  - Scope: 本任务不覆盖 AC-9。` → 输出为空、rc=0 |
| tdecl-5 | `ac_declaration_lines requires leading whitespace before the dash` | 行首顶格的 `- Covers: AC-1`（无缩进）→ 不命中（`:230` 的 `^[[:space:]]+`） |
| tdecl-6 | `task_has_ac_declaration is true only when a declaration line carries an AC token` | 三种输入各跑一次：有标签有 token → rc=0；有标签无 token（`- Covers: 见下文`）→ rc≠0；无标签有 token → rc≠0 |
| tdecl-7 | `task_covered_acs reads only the declaration lines when one exists` | 声明行 `- 覆盖验收：AC-1`，正文另提 `AC-2` → 输出恰为 `AC-1` |
| tdecl-8 | `task_covered_acs falls back to the whole body when no declaration line exists` | 无声明行，正文含 `AC-1` 与 `AC-2` → 输出为两者 |
| tdecl-9 | `task_covered_acs unions across multiple declaration lines` | 两行声明各带一个 AC → 输出为两者 |
| tdecl-10 | `task_covered_acs narrows to what the spec declares` | 声明行含 `AC-1 AC-14`，spec 只声明 AC-1/AC-2 → 输出恰为 `AC-1` |
| tdecl-11 | `plan-lint warns exactly when task_has_ac_declaration is false` | **齐平断言**：对 tdecl-6 的三种任务体各造一份 plan，跑 `plan-lint.sh`，断言「`task_has_ac_declaration` 为假」⟺「输出含 fallback warning」。这是 `:238` 那句注释的机器化 |

> **tdecl-11 为什么必须写成齐平而不是两条独立用例**：`_lib.sh:238` 明写这两者「must never drift apart」。写成两条独立用例，两边各自漂移一半时两条都还是绿的——那正是这条注释要防的情形。

- [ ] **Step 2: 跑测试**

```bash
bash tests/run.sh unit
```

期望：unit 58 → 69，0 failures。

- [ ] **Step 3: 变异验证（7 条）**

| 变异 | 注入点 | 期望变红 |
|---|---|---|
| `T2-M1` | `_lib.sh:230` 的 `覆盖验收` 从标签 alternation 里删掉 | tdecl-1、tdecl-7（用中文标签的那些） |
| `T2-M2` | `_lib.sh:230` 的 `Covers` 删掉 | tdecl-2、tdecl-3 |
| `T2-M3` | `_lib.sh:230` 的 `grep -iE` 改成 `grep -E`（去掉大小写不敏感） | **只** tdecl-3 |
| `T2-M4` | `_lib.sh:230` 的 `^[[:space:]]+` 改成 `^[[:space:]]*` | **只** tdecl-5 |
| `T2-M5` | `_lib.sh:244` 的 `grep -qE 'AC-[0-9]+' <<< "$decl"` 改成恒真 `true` | tdecl-6、tdecl-11 |
| `T2-M6` | `_lib.sh:255-258` 的 `if/else` 两个分支对调 | tdecl-7、tdecl-8 |
| `T2-M7` | `plan-lint.sh:226` 的 `if ! task_has_ac_declaration` 去掉 `!` | **只** tdecl-11 |

`T2-M7` 是本文件与 `plan-lint` 之间那条齐平契约的**专属证明**：它只坏 `plan-lint` 一侧，`_lib.sh` 完好，所以只有齐平用例能抓住它。**若 `T2-M7` 点亮了 tdecl-1..10 中任何一条，说明那些用例越界断了 plan-lint 的行为，回去收窄。**

按决定一的六步协议逐条执行，回滚后 `git status --porcelain` 必须为空。

- [ ] **Step 4: Commit**

```bash
git add tests/unit/lib-task-declaration.bats
git commit -m "Add task-level AC declaration contract tests with the plan-lint parity assertion"
```

---

### Task 3: AC 归属契约单测

**Files:**
- Create: `tests/unit/gate-ac-attribution.bats`

**Interfaces:**
- Consumes: `make_spec`（注意它对每个 spec 都写死 `status: drafted` 与 `updated_at: 2026-01-01T00:00:00Z`，同沙箱两个 `make_spec` 会精确并列 → `find_spec` rc=2；本文件所有用例都显式传 spec 路径，不走自动发现）。
- Produces: 无。

**文件头必须写清 O-1 边界：**

```bash
#!/usr/bin/env bats
# 契约单测：ac-coverage 的跨 spec AC 归属隔离。
#
# 被测：ac-coverage.sh:137 build_foreign_owned / :146 FOREIGN_OWNED / Tier1-Tier2 归属链
# 缺陷本体：上报 #8（跨 spec test_acN 碰撞被误归属），
#           回归见 tests/regression/2026-07-25-ac-coverage-cross-spec-attribution.bats
#
# ══ 覆盖边界：本文件只测 go 与 python 两个语言分支 ══
#
# node / javascript / typescript 在 :127 被设 DECL_TOKEN_REGEX=''，:138 的
# `[[ -n "$DECL_TOKEN_REGEX" && -d "$SPECS_ABS" ]] || return 0` 让 FOREIGN_OWNED
# 恒空 —— node 项目**完全没有**跨 spec 归属保护。
#
# 这是**真实功能缺口（O-1），不是测试缺口**。修它需要设计：:122-123 的注释说明了
# 为什么留空（node 测试标题是自由字符串、不是稳定标识符），简单填一个正则解决不了。
# 归批次 3c 走完整 SOP。
#
# **明令禁止**在本文件写出「node 项目确实没有保护」这类 refute 形态的用例 ——
# 那是把缺陷固化成期望值。批次 2 对 O-14 的裁定原文：「明令不许反向断言 detail 为空」。
#
# 分层边界：本文件断的是**归属算法**（谁的测试算谁的）。
# **不得**断言 _lib.sh 的 AC 声明谓词——那归 tests/unit/lib-task-declaration.bats。
```

- [ ] **Step 1: 写文件**

9 条用例：

| # | `@test` | 断言 |
|---|---|---|
| attr-1 | `a sibling spec's declared test does not satisfy this spec's AC` | go 项目，两个 spec 各声明 `TestAC1`，本 spec 无实现 → 本 spec 的 AC-1 判 uncovered |
| attr-2 | `a test this spec declares in its own AC table satisfies it` | 正向对照：本 spec 声明 `TestAC1` 且代码里有该测试 → covered |
| attr-3 | `build_foreign_owned excludes the spec under test by inode not by path string` | 用符号链接把同一个 spec 文件以第二个路径暴露；`-ef` 比 inode 故仍算自己 → 不进 FOREIGN_OWNED |
| attr-4 | `python declaration tokens use the test_ prefix regex` | `halo_set_language python`，声明 `test_ac1` → 归属成立 |
| attr-5 | `an unknown language falls back to the Go token regex` | `halo_set_language rust` → `:128` 的 `*)` 分支，`TestAC1` 仍被抽取 |
| attr-6 | `a Tier2 candidate is taken only when it is unique` | 两个候选测试都能匹配同一 AC → 判 ambiguous，不取 |
| attr-7 | `a unique Tier2 candidate is taken` | 正向对照：唯一候选 → 取 |
| attr-8 | `an empty specs directory yields an empty foreign-owned set without failing` | 边界：`halo/specs` 为空 → `:138` 的 `-d` 守卫 → rc=0、门禁不崩 |
| attr-9 | `the gate exits non-zero and writes gate JSON when an AC is uncovered` | 出口契约：`exit 1` 且 `write_gate_json` 落盘（守 `:188` 那类硬崩不再发生） |

- [ ] **Step 2: 跑测试**

期望：unit 69 → 78，0 failures。

- [ ] **Step 3: 变异验证（6 条）**

| 变异 | 注入点 | 期望变红 |
|---|---|---|
| `T3-M1` | `ac-coverage.sh:138` 的守卫改成 `|| true`（不再提前返回） | 无（该改动让函数继续跑，行为等价）——若有用例红，记录并交控制者裁定 |
| `T3-M2` | `ac-coverage.sh:142` 的 `[[ "$f" -ef "$SPEC" ]] && continue` 删掉 | attr-2（自己的测试被算成 foreign）、attr-3 |
| `T3-M3` | `ac-coverage.sh:142` 的 `-ef` 改成 `==`（比路径串而非 inode） | **只** attr-3 |
| `T3-M4` | `ac-coverage.sh:126` 的 python 正则 `test_[a-z0-9_]+` 改成 `Test[A-Za-z0-9_]+` | **只** attr-4 |
| `T3-M5` | `ac-coverage.sh:128` 的 `*)` 分支改成 `DECL_TOKEN_REGEX=''` | **只** attr-5 |
| `T3-M6` | Tier2 的 `ccount == 1` 判定改成 `ccount >= 1`（ambiguous 也取） | **只** attr-6 |

`T3-M2` 是批次 2 的 M26 打过的同一行，那次**只**点亮 `gate-ac-coverage.bats` 的 `acg-3`。本 Task 之后它应额外点亮 attr-2/attr-3。**若它点亮了 attr 以外、acg-3 以外的用例，记录为宽半径连带，不算失败。**

- [ ] **Step 4: Commit**

```bash
git add tests/unit/gate-ac-attribution.bats
git commit -m "Add cross-spec AC attribution contract tests for the go and python branches"
```

---

### Task 4: 模式解析链契约单测（齐平遍历）

**Files:**
- Create: `tests/unit/sdd-execution-mode.bats`

**Interfaces:**
- Consumes: `make_spec` / `make_plan`。
- Produces: 无。

**文件头必须写清两处已知分歧：**

```bash
#!/usr/bin/env bats
# 契约单测：SDD 脚本的执行模式解析链。
#
# 被测是**四份互相独立的 execution_mode 定义**，没有一份在 _lib.sh 里：
#   orchestrator/sdd/plan-lint.sh:111           行首 grep，无 -f "$spec" 守卫
#   orchestrator/sdd/task-next.sh:90            行首 grep，有守卫
#   orchestrator/sdd/task-complete.sh:80        frontmatter_value（只认 --- 块内）
#   orchestrator/sdd/task-evidence-lint.sh:69   同上，与 task-complete 逐字相同
# 外加两份 task_mode：task-complete.sh:70 / task-evidence-lint.sh:59
#
# 因为没有单一被测对象，本文件不是常规契约单测，而是**齐平遍历形态的漂移防线**
# （根因 H）：一条用例循环四份实现，断它们在同一输入上给出相同结果。
# 任何一份将来被单独改动，齐平断言立刻红。
# 写法蓝本：tests/unit/gate-skip-honesty.bats 的四门禁遍历。
#
# ══ 覆盖边界：只断四份行为一致的输入域 ══
#
# 四份**现在就已经漂移**，实测两处分歧（本文件落笔时对拍确认）：
#
#   形态②  execution_mode: 写在 front-matter 块外
#            plan-lint/task-next → tdd ；task-complete/task-evidence-lint → unknown
#            （噪声清单规则 4 已登记）
#   形态③  块内 execution_mode: tddx（前缀污染）
#            plan-lint/task-next → tddx ；task-complete/task-evidence-lint → unknown
#            成因：阵营 A 的正则 (plan|tdd) 匹配 tddx 的 tdd 前缀，sed 剥掉标签后
#            把整个 tddx 当值返回；阵营 B 的 frontmatter_value 拿到 tddx 后被
#            `== "plan" || == "tdd"` 拒绝，继续回退。
#            （本批次实测新发现，噪声清单未登记，Task 18 补登）
#
# **这两种形态不写用例、也不写反向断言。** 反向断言等于把缺陷固化成期望值
# （批次 2 对 O-14 的裁定：「明令不许反向断言 detail 为空」）。
# 收敛属批次 3c —— 那是行为变更，选哪个阵营都会改变一半脚本的真实行为。
#
# 形态③ 另牵出 O-18：plan-lint.sh:262 的 `if [[ "$MODE" == "tdd" ]]` 只有 else 兜底，
# :273 打 pass_msg "Mode: $MODE" —— tddx 的 spec 得到 `✅ Mode: tddx` 并跳过两条
# TDD 结构检查。**主动报绿**，比静默跳过更糟。归 3c，本文件不为它写断言。
```

- [ ] **Step 1: 写文件**

8 条用例：

| # | `@test` | 断言 |
|---|---|---|
| mode-1 | `all four execution_mode copies agree on a front-matter declared mode` | **齐平**：形态 ①，四份都得 `tdd`。失败信息必须带脚本名 |
| mode-2 | `all four execution_mode copies agree when nothing declares a mode` | **齐平**：形态 ④，四份都得 `unknown` |
| mode-3 | `all four execution_mode copies agree on a plan-declared English mode` | **齐平**：spec 无 `execution_mode`，plan 含 `- Execution mode: plan` → 四份都得 `plan` |
| mode-4 | `all four execution_mode copies agree on a plan-declared Chinese mode` | **齐平**：plan 含 `- 执行模式：plan` → 四份都得 `plan` |
| mode-5 | `the spec front matter outranks the plan declaration` | 回退链顺序：spec 声明 `tdd`、plan 声明 `plan` → 结果 `tdd`（四份齐平，因为 spec 侧走的是形态 ①） |
| mode-6 | `the English plan label outranks the Chinese one` | plan 同时含两种标签且值不同 → 取英文（回退链 `:85` 在 `:86` 之前） |
| mode-7 | `both task_mode copies agree on an in-body Mode line` | **齐平**：任务体含 `  - Mode: plan` → 两份 `task_mode` 都得 `plan` |
| mode-8 | `both task_mode copies fall through to the spec mode when the body declares none` | **齐平**：任务体无 `Mode:` → 两份都回退到 spec 的模式 |

齐平用例的写法（照 `gate-skip-honesty.bats:41-65`）：

```bash
# 四份 execution_mode 各自定义在自己的脚本里，无法直接调用。做法是把函数定义
# 连同它依赖的 frontmatter_value 一起抽出来跑 —— 抽取而非 source 整个脚本，
# 因为那些脚本顶层会解析 argv 并直接执行主流程。
run_execution_mode() { # <script-basename> <spec> <plan>
  local script="halo/kernel/orchestrator/sdd/$1.sh" spec="$2" plan="$3"
  {
    echo 'set -uo pipefail'
    sed -n '/^frontmatter_value()/,/^}/p' "$script"
    sed -n '/^execution_mode()/,/^}/p' "$script"
    echo 'execution_mode "$1" "$2"'
  } > "$BATS_TEST_TMPDIR/em.sh"
  bash "$BATS_TEST_TMPDIR/em.sh" "$spec" "$plan"
}

@test "all four execution_mode copies agree on a front-matter declared mode" {
  make_spec halo/specs alpha 1 1 tdd
  make_plan halo/specs alpha 1 1 decl-cn

  local scripts=(plan-lint task-next task-complete task-evidence-lint)
  local s got first=""
  for s in "${scripts[@]}"; do
    got="$(run_execution_mode "$s" halo/specs/alpha/spec.md halo/specs/alpha/plan.md)"
    [ "$got" = "tdd" ] || fail "script=$s: expected tdd, got '$got'"
    if [[ -z "$first" ]]; then first="$got"; fi
    [ "$got" = "$first" ] || fail "script=$s drifted: got '$got', first copy gave '$first'"
  done
}
```

> **`plan-lint.sh` 没有 `frontmatter_value`**（它用行首 grep）。`sed -n '/^frontmatter_value()/,/^}/p'` 对它输出为空，不报错——这是有意的，不要为它加特判。

- [ ] **Step 2: 跑测试**

期望：unit 78 → 86，0 failures。

- [ ] **Step 3: 变异验证（8 条）**

| 变异 | 注入点 | 期望变红 |
|---|---|---|
| `T4-M1` | `plan-lint.sh:113` 的 `^execution_mode:` 改成永不匹配 | mode-1、mode-5（`plan-lint` 一侧漂移） |
| `T4-M2` | `task-next.sh:93` 同上 | mode-1、mode-5 |
| `T4-M3` | `task-complete.sh:83` 的 `frontmatter_value` 调用改成恒返回空 | mode-1、mode-5 |
| `T4-M4` | `task-evidence-lint.sh:72` 同上 | mode-1、mode-5 |
| `T4-M5` | `task-complete.sh:85` 的 `Execution mode:` 改成永不匹配 | mode-3、mode-6 |
| `T4-M6` | `plan-lint.sh:115` 的 `执行模式` 改成永不匹配 | **只** mode-4 |
| `T4-M7` | `task-complete.sh:70` 的 `task_mode` 里读 `Mode:` 的那步改成永不匹配 | mode-7 |
| `T4-M8` | `task-complete.sh:85` 与 `:86` 两行对调（英文/中文回退次序反转） | **只** mode-6 |

**`T4-M1`–`T4-M4` 各只坏一份实现，齐平用例必须四条都能抓住。任何一条抓不住，说明该用例没真的遍历到那份实现——回去查 `run_execution_mode` 的抽取是否对该脚本失效了。**

- [ ] **Step 4: Commit**

```bash
git add tests/unit/sdd-execution-mode.bats
git commit -m "Add a parity guard across the four execution_mode definitions"
```

---

### Task 5: #10 SDD 门禁缺陷回归（目录形态，4 条）

**Files:**
- Create: `tests/regression/2026-07-31-sdd-gate-defects/per-task-mode.bats`
- Create: `tests/regression/2026-07-31-sdd-gate-defects/red-task-ac-quantifier.bats`
- Create: `tests/regression/2026-07-31-sdd-gate-defects/evidence-mode-chain.bats`

**Interfaces:**
- Consumes: `make_spec` / `make_plan` / `make_evidence`（Task 1）。**注意子目录里 `load` 是两级路径：`load "../../helpers/common"`。**
- Produces: 无。

**每个文件必须带固定三行文件头**（`tests/README.md` 的入库纪律）：

```bash
# Bug 报告: docs/bug_report/2026-07-31-sdd-gate-defects.md（上报 #10）
# 根因类别: G（量词/边界）+ C（失败方向）
# Fixed by: 04300a7
```

`Fixed by` 的 `04300a7` 取自 `docs/bug_report/INDEX.md:51`。**实施者必须自行考据确认它是当前 HEAD 的祖先**：

```bash
git merge-base --is-ancestor 04300a7 HEAD && echo ancestor || echo "NOT an ancestor — 停下来报告"
```

- [ ] **Step 1: 建目录并写 `per-task-mode.bats`（3 条）**

源：`tests/smoke-test.sh:1024`、`:1033`、`:1106`。对应上报 #10 的「缺陷 1：逐任务模式被证据门禁丢弃」。

| # | `@test` | 断言 |
|---|---|---|
| ptm-1 | `task-complete honors a plan-mode task inside a tdd spec` | spec 声明 `tdd`，某任务体写 `- Mode: plan` → `task-complete` 接受它而**不要求** TDD cycle 证据 |
| ptm-2 | `task-evidence-lint honors a plan-mode task inside a tdd spec` | 同上形态 → `task-evidence-lint` 判 pass |
| ptm-3 | `task-complete honors a tdd-mode task inside a plan spec` | 反向：spec 声明 `plan`，某任务体写 `- Mode: tdd` → `task-complete` **要求** cycle 证据，缺证据时拒绝 |

> **ptm-3 是双向断言的「真缺陷仍被抓住」那一半。** 只有 ptm-1/ptm-2 的话，把 `task_mode` 改成恒返回 `plan` 也全绿——那正是缺陷的另一个方向。

- [ ] **Step 2: 写 `red-task-ac-quantifier.bats`（1 条）**

源：`tests/smoke-test.sh:1112-1203`（`red-multi-ac` 沙箱）。对应上报 #10 的「备注项：RED 任务的 AC 覆盖被放宽」。

| # | `@test` | 断言 |
|---|---|---|
| raq-1 | `a red task needs cycle evidence for every AC it covers, not just one` | 一个 RED 任务声明覆盖 AC-1 与 AC-2，证据只含 AC-1 → `task-complete` 非零退出，输出含 `RED-1 missing matching TDD cycle evidence` |

**这是「量词」缺陷：`some` 与 `every` 的区别。** 断言必须构造「部分满足」的场景——全不满足与全满足都区分不出量词。

- [ ] **Step 3: 写 `evidence-mode-chain.bats`（≥2 条）**

对应上报 #10 的「顺带统一：证据门禁的模式解析链」。**这一条在 smoke-test 里没有对应断言**（当年只改了实现，没配回归），本 Task 新增。

| # | `@test` | 断言 |
|---|---|---|
| emc-1 | `task-complete and task-evidence-lint resolve the same mode for the same task` | 齐平：同一份 spec+plan+任务体，两个门禁解析出的**有效模式**一致（通过各自输出里的模式字样断言） |
| emc-2 | `an unknown effective mode is refused, not silently passed` | 四处都不声明模式 → `task-evidence-lint` 非零退出且输出含 `NOT verified`（2026-09-07 修复的 fail-closed 出口） |

> **emc-2 与 `tests/regression/2026-09-07-task-evidence-lint-unknown-mode-silent-skip.bats` 有交叠。** 按 `tests/README.md`「容许的交叠：必须逐条写明正当性」，在文件头写明：那份守的是 2026-09-07 那次修复的**缺陷本体**（`if/elif` 无 `else`），本条守的是 #10 建立的**模式解析链契约**在同一出口上仍然成立。两份文件头互指。若变异证明两者恒同红同绿，删掉 emc-2 并在报告中说明。

- [ ] **Step 4: 跑测试**

```bash
bash tests/run.sh regression
```

期望：regression 95 → 101，0 failures。

- [ ] **Step 5: 变异验证（5 条）**

变异目标按行为指定，实施者定位后回填 `文件:行`：

| 变异 | 注入行为 | 期望变红 |
|---|---|---|
| `T5-M1` | `task-complete.sh` 的 `task_mode` 改成恒返回 spec 级模式（无视任务体的 `Mode:`） | ptm-1、ptm-3 |
| `T5-M2` | `task-evidence-lint.sh` 的 `task_mode` 同上 | **只** ptm-2 |
| `T5-M3` | RED 任务 AC 证据匹配的量词从「每个 AC 都要有」放松成「有任一即可」 | **只** raq-1 |
| `T5-M4` | `task-evidence-lint.sh` 的 `unknown` fail-closed `else` 分支删掉 | emc-2 **与** `2026-09-07-…-silent-skip.bats` 的对应用例 |
| `T5-M5` | 让 `task-complete` 与 `task-evidence-lint` 的模式解析链**只在一侧**多一级回退 | **只** emc-1 |

`T5-M4` 若同时点亮两个文件，那是**预期的交叠**，按 Step 3 的正当性说明记录即可。`T5-M5` 若点不亮 emc-1，说明 emc-1 没有真的齐平——回去查。

- [ ] **Step 6: 更新 `docs/bug_report/INDEX.md:51`**

把「回归测试」列的 `批次 3 待迁` 改为：

```
`2026-07-31-sdd-gate-defects/`（目录）：<br>`per-task-mode.bats`（缺陷 1）<br>`red-task-ac-quantifier.bats`（备注项）<br>`evidence-mode-chain.bats`（顺带统一）<br>**聚合上报，按缺陷拆分**
```

- [ ] **Step 7: Commit**

```bash
git add tests/regression/2026-07-31-sdd-gate-defects/ docs/bug_report/INDEX.md
git commit -m "Migrate the SDD gate defect regressions from smoke-test"
```

---

### Task 6: #11 SIGPIPE 回归（1 条）

**Files:**
- Create: `tests/regression/2026-08-02-tdd-cycle-evidence-sigpipe.bats`

**Interfaces:**
- Consumes: `halo_slow_yq_path`（Task 1）、`make_spec` / `make_plan` / `make_evidence`。**平铺文件，`load` 一级路径：`load "../helpers/common"`。**

**文件头：**

```bash
# Bug 报告: docs/bug_report/2026-08-02-tdd-cycle-evidence-sigpipe.md（上报 #11）
# 根因类别: B（pipefail/SIGPIPE）+ D（非确定性）
# Fixed by: c75d0c4
```

- [ ] **Step 1: 写文件（1 条正向 + 1 条反向）**

源：`tests/smoke-test.sh:1205-1310`（`red-many-ac` 沙箱 + 慢 yq shim）。

| # | `@test` | 断言 |
|---|---|---|
| sig-1 | `a red task whose ACs all live in one evidence file is accepted under a slow yq` | 一个 RED 任务覆盖多个 AC，全部证据在同一个 `tdd-evidence.json` 里；`PATH="$(halo_slow_yq_path -r '.ac_ids[]?'):$PATH"` 下跑 `task-complete` → **退出 0** 且 plan 里该任务被勾选为 `- [x] RED-1:` |
| sig-2 | `the same task is still refused when an AC genuinely has no evidence` | 反向：同样的慢 yq 环境，但证据里少一个 AC → **非零退出**。缺这条，把整段匹配逻辑改成恒真也能让 sig-1 绿 |

> **为什么必须用慢 yq 而不是重复跑**：SIGPIPE 竞态在正常 `yq` 下是概率事件。设计文档的入库纪律明写「非确定性缺陷必须确定化：竞态类 bug 不允许重复跑碰运气，须如 #11 注入慢 yq 般放大为 100% 触发」。**不要把这条改成 `for i in {1..20}` 重复跑。**

- [ ] **Step 2: 确认确定性**

```bash
for i in 1 2 3 4 5; do
  tests/vendor/bats-core/bin/bats tests/regression/2026-08-02-tdd-cycle-evidence-sigpipe.bats || echo "RUN $i FAILED"
done
```

期望：5 次全绿。**任何一次红都说明 shim 没让竞态确定化，回去查 `halo_slow_yq_path` 的参数匹配是否命中了真实调用点**（真实调用点的 yq 参数以实现脚本为准，不一定是 `-r '.ac_ids[]?'`）。

再跑全量：`bash tests/run.sh regression`，期望 regression 101 → 103。

- [ ] **Step 3: 变异验证（3 条）**

| 变异 | 注入行为 | 期望变红 |
|---|---|---|
| `T6-M1` | 把修复引入的「先收进变量再匹配」改回 `yq … \| grep -q` 的管道形态（即复现 #11 原缺陷） | **只** sig-1 |
| `T6-M2` | 把 AC 证据匹配逻辑改成恒真 | **只** sig-2 |
| `T6-M3` | `halo_slow_yq_path` 的 `sleep 0.05` 改成 `sleep 0`（这是 `T1-M2` 的缺口补做） | **只** sig-1 **不**变红——它证明 shim 的慢放是 sig-1 判别力的必要条件。若 sig-1 在 `sleep 0` 下仍红，说明 sig-1 红的原因不是 SIGPIPE，回去查 |

`T6-M3` 的变异对象在 `tests/` 下，回滚命令是 `git checkout -- tests/helpers/`。

- [ ] **Step 4: 更新 `docs/bug_report/INDEX.md:52`**

「回归测试」列的 `批次 3 待迁` → `2026-08-02-tdd-cycle-evidence-sigpipe.bats`。

- [ ] **Step 5: Commit**

```bash
git add tests/regression/2026-08-02-tdd-cycle-evidence-sigpipe.bats docs/bug_report/INDEX.md
git commit -m "Migrate the TDD cycle evidence SIGPIPE regression with a deterministic slow-yq shim"
```

---

### Task 7: `sdd-spec-status.bats`（10 条）

**Files:**
- Create: `tests/unit/sdd-spec-status.bats`

**Interfaces:**
- Consumes: `make_spec` / `make_plan` / `make_evidence`。
- Produces: 无。

**文件头：**

```bash
#!/usr/bin/env bats
# spec-status 的状态机与审计事件契约。
#
# 被测：halo/kernel/orchestrator/sdd/spec-status.sh
# 迁自 tests/smoke-test.sh 的 §6c（:739/:753/:763/:785/:792/:899/:913）
# 与 §6d（:1042/:1413/:1482）。
#
# 分层归属：本文件断的是**脚本自身的出口契约**——状态推进是否被允许、
# 事件是否落盘、拒绝时是否不留痕。不断任何 _lib.sh 函数的分支
# （那归 unit/lib-*.bats），也不挂任何 bug 报告（无对应上报）。
```

- [ ] **Step 1: 写文件**

| # | `@test` | 源 | 断言 |
|---|---|---|---|
| sst-1 | `spec-status advances a drafted spec to planned` | `:739` | 退出 0，manifest / spec 的 status 变为 `planned` |
| sst-2 | `advancing to planned records a transition event` | `:753` | `halo/state/` 下落盘事件 JSON，`.from == "drafted"`、`.to == "planned"` |
| sst-3 | `spec-status blocks the implemented state while tasks remain incomplete` | `:763` | 非零退出，输出说明未完成任务 |
| sst-4 | `spec-status blocks completed tasks that carry no evidence` | `:785` | 非零退出 |
| sst-5 | `a blocked transition records no event` | `:792` | **反向**：sst-3 或 sst-4 的场景下，事件目录里没有新增条目。这是「拒绝不留痕」契约 |
| sst-6 | `spec-status advances a completed plan to implemented` | `:899` | 退出 0 |
| sst-7 | `advancing to implemented records a transition event` | `:913` | 事件 `.to == "implemented"` |
| sst-8 | `spec-status advances a tdd spec that contains a plan-mode task` | `:1042` | 逐任务模式不阻断状态推进 |
| sst-9 | `spec-status advances an implemented spec to verified` | `:1413` | 退出 0 |
| sst-10 | `the full transition chain leaves a complete audit trail` | `:1482` | drafted→planned→implemented→verified 四段事件齐备且**有序** |

> **sst-5 是本文件最有价值的一条。** 「拒绝时不留痕」是个只能反向验证的契约：正向断言「拒绝了」对「拒绝但仍写了事件」毫无判别力。

- [ ] **Step 2: 跑测试**，期望 unit 86 → 96。

- [ ] **Step 3: 变异验证（6 条，目标按行为指定，实施者回填行号）**

| 变异 | 注入行为 | 期望变红 |
|---|---|---|
| `T7-M1` | 删掉写 transition 事件的那一步 | sst-2、sst-7、sst-10 |
| `T7-M2` | 「未完成任务阻断 implemented」的判定改成恒假 | **只** sst-3 |
| `T7-M3` | 「完成任务需有证据」的判定改成恒假 | **只** sst-4 |
| `T7-M4` | 把写事件的调用移到状态检查**之前**（拒绝也写事件） | **只** sst-5 |
| `T7-M5` | `implemented → verified` 的合法转移表项删掉 | **只** sst-9 |
| `T7-M6` | 逐任务模式在 spec-status 侧被忽略（只看 spec 级模式） | **只** sst-8 |

- [ ] **Step 4: Commit** — `Migrate the spec-status state machine and audit trail assertions`

---

### Task 8: `sdd-task-complete.bats` + `sdd-task-evidence.bats`（5 条）

**Files:**
- Create: `tests/unit/sdd-task-complete.bats`
- Create: `tests/unit/sdd-task-evidence.bats`

**Interfaces:** Consumes `make_spec` / `make_plan` / `make_evidence`。

**分层声明（两个文件头都要写，并互指）：**

`sdd-task-complete.bats` 守 `task-complete.sh` 的**写路径**出口契约（勾选 / 拒绝）；`sdd-task-evidence.bats` 守 `tdd-evidence.sh` 的**产物形状**与 `task-evidence-lint.sh` 的**只读判定**。逐任务模式的行为归 `regression/2026-07-31-sdd-gate-defects/per-task-mode.bats`（Task 5），本两文件不重复。

- [ ] **Step 1: 写 `sdd-task-complete.bats`（2 条）**

| # | `@test` | 源 | 断言 |
|---|---|---|---|
| stc-1 | `task-complete refuses a task with no evidence` | `:772` | 非零退出，plan 里该任务**仍是** `- [ ]`（未被勾选）。**必须断 plan 未被改写**——只断退出码的话，「拒绝了但还是勾了」也能绿 |
| stc-2 | `task-complete marks a task complete when evidence is present` | `:872` | 退出 0，plan 里该任务变为 `- [x]` |

- [ ] **Step 2: 写 `sdd-task-evidence.bats`（3 条）**

| # | `@test` | 源 | 断言 |
|---|---|---|---|
| ste-1 | `tdd-evidence writes structured red and green results` | `:825` | 产物 JSON 含 `.red.exit_code` 与 `.green.exit_code`，且 red 非 0、green 为 0 |
| ste-2 | `tdd-evidence records the AC ids it was given` | `:859` | `.ac_ids \| join(",")` 等于传入值（**用 join 不用数组字面量比较**——mikefarah v4 的数组字面量比较静默求值为 false） |
| ste-3 | `task-evidence-lint passes a completed task that has evidence` | `:882` | 退出 0，输出含 pass 字样 |

- [ ] **Step 3: 跑测试**，期望 unit 96 → 101。

- [ ] **Step 4: 变异验证（5 条）**

| 变异 | 注入行为 | 期望变红 |
|---|---|---|
| `T8-M1` | `task-complete.sh` 的「无证据则拒绝」判定改成恒假 | stc-1 |
| `T8-M2` | `task-complete.sh` 在拒绝分支里**也**执行勾选（勾选调用上移到检查之前） | **只** stc-1（它的「plan 未被改写」那半） |
| `T8-M3` | `tdd-evidence.sh` 的 `green.exit_code` 恒写 1 | **只** ste-1 |
| `T8-M4` | `tdd-evidence.sh` 的 `ac_ids` 恒写 `[]` | **只** ste-2 |
| `T8-M5` | `task-evidence-lint.sh` 的完成任务遍历改成空集 | ste-3 |

`T8-M2` 是 stc-1 双重断言的专属证明：`T8-M1` 只坏判定（退出码和勾选一起变），`T8-M2` 只坏顺序（退出码仍非零，但 plan 被改写了）。**若 `T8-M2` 点不亮 stc-1，说明 stc-1 没真的断 plan 内容，回去补。**

- [ ] **Step 5: Commit** — `Migrate the task-complete and TDD evidence assertions`

---

### Task 9: `sdd-plan-lint.bats` + `sdd-task-next.bats` + `prismspec-lint.bats`（7 条）

**Files:**
- Create: `tests/unit/sdd-plan-lint.bats`
- Create: `tests/unit/sdd-task-next.bats`
- Create: `tests/unit/prismspec-lint.bats`

**Interfaces:** Consumes `make_spec` / `make_plan`。

**`sdd-plan-lint.bats` 的分层声明：** 本文件守 `plan-lint.sh` 的**结构判定**出口（AC 溯源、任务 schema）。**不得**断言占位符判据——那归 `regression/2026-08-03-halo-gate-findings/plan-lint-placeholder.bats`（批次 2 已写）；**不得**断言 `task_has_ac_declaration` 的谓词齐平——那归 `unit/lib-task-declaration.bats`（Task 2）。三个文件头互指。

- [ ] **Step 1: 写 `sdd-plan-lint.bats`（3 条）**

| # | `@test` | 源 | 断言 |
|---|---|---|---|
| spl-1 | `plan-lint passes a plan whose tasks trace to declared ACs` | `:727` | 退出 0 |
| spl-2 | `plan-lint rejects a plan whose tasks trace to nothing` | `:1341` | 非零退出，输出指出不可溯源 |
| spl-3 | `plan-lint rejects a task missing required schema fields` | `:1387` | 非零退出，输出指出缺失字段 |

- [ ] **Step 2: 写 `sdd-task-next.bats`（2 条）**

| # | `@test` | 源 | 断言 |
|---|---|---|---|
| stn-1 | `task-next resolves the first red-test task` | `:709` | 输出指向 `RED-1`，而不是 `T1` |
| stn-2 | `task-next reports a plan whose tasks are all complete` | `:890` | 输出说明计划已完成，退出 0 |

- [ ] **Step 3: 写 `prismspec-lint.bats`（2 条）**

| # | `@test` | 源 | 断言 |
|---|---|---|---|
| psl-1 | `prismspec lint accepts the plan artifact contract` | `:718` | 退出 0 |
| psl-2 | `prismspec lint accepts the full artifact contract` | `:1404` | spec+plan+证据齐备时退出 0 |

> **`prismspec/bin/lint.sh` 是 standalone 脚本**（`spec-select.sh:6-8` 那一族的设计契约：必须能在没有 `_lib.sh`、没有 yq 的宿主里跑）。**跑它的仓库源文件还是沙箱副本，实施者按 `tests/unit/…/spec-discovery.bats:22-37` 的两档范例判定并在文件头写明理由。**

- [ ] **Step 4: 跑测试**，期望 unit 101 → 108。

- [ ] **Step 5: 变异验证（6 条）**

| 变异 | 注入行为 | 期望变红 |
|---|---|---|
| `T9-M1` | `plan-lint.sh` 的 AC 溯源判定改成恒真 | **只** spl-2 |
| `T9-M2` | `plan-lint.sh` 的任务 schema 必填字段检查改成恒真 | **只** spl-3 |
| `T9-M3` | `task-next.sh` 的任务排序改成先 `T` 后 `RED` | **只** stn-1 |
| `T9-M4` | `task-next.sh` 的「全部完成」判定改成恒假 | **只** stn-2 |
| `T9-M5` | `prismspec/bin/lint.sh` 的某条必检项改成恒真 | psl-1 或 psl-2（实施者记录实际点亮者） |
| `T9-M6` | `plan-lint.sh:262` 的 `== "tdd"` 改成永不匹配 | **本 Task 无用例覆盖**——这是 O-18 所在的分支，按范围边界不为它写断言。记录为「已知不覆盖」，理由指向 O-18 |

- [ ] **Step 6: Commit** — `Migrate the plan-lint, task-next and prismspec lint assertions`

---

### Task 10: `sdd-task-brief.bats` + `sdd-review-package.bats`（4 条）

**Files:**
- Create: `tests/unit/sdd-task-brief.bats`
- Create: `tests/unit/sdd-review-package.bats`

**Interfaces:** Consumes `make_spec` / `make_plan`。

**`sdd-review-package.bats` 的分层声明（必须写进文件头并与对方互指）：**

> 本文件守 `review-package.sh` 的**生成契约**——包被生成、是只读的、含必需章节。
> **不得**断言 diff 范围与未跟踪文件上限——那归
> `tests/regression/2026-08-03-halo-gate-findings/review-package-scope.bats`（批次 2，守 #12 §5 的范围缺陷）。
> 判据：改「包里有什么章节」会红的归本文件；改「基线怎么解析、未跟踪文件怎么截断」会红的归那份回归。

- [ ] **Step 1: 写 `sdd-task-brief.bats`（2 条）**

| # | `@test` | 源 | 断言 |
|---|---|---|---|
| stb-1 | `task-brief generates evidence for a task` | `:799` | `.halo/sdd/<id>/T1/brief.md` 存在且非空 |
| stb-2 | `task-brief generates evidence for a second task independently` | `:833` | 对 T2 生成时不覆盖 T1 的产物 |

> **stb-2 的价值在「independently」。** 只有 stb-1 的话，一个把所有任务写到同一路径的实现也能绿。断言必须同时检查 T1 的产物仍在。

- [ ] **Step 2: 写 `sdd-review-package.bats`（2 条）**

| # | `@test` | 源 | 断言 |
|---|---|---|---|
| srp-1 | `review-package generates a read-only package` | `:807` | 产物存在，且只读语义成立 |
| srp-2 | `review-package generates a second package independently` | `:841` | 对 T2 生成时不覆盖 T1 的产物：断言 T1 的产物路径仍存在且内容未变（先记 `md5`，生成 T2 后重取比对） |

> **srp-1 的「只读」先查清是哪种语义再写断言。** 三种可能：① 文件权限位（`test ! -w "$pkg"`）；② 产物正文里的声明（`grep -q "read-only"`）；③ 脚本拒绝在包已存在时覆写。**执行 Step 2 前先跑一次实测确认**：
>
> ```bash
> bash halo/kernel/orchestrator/sdd/review-package.sh <spec-id> <task-id>
> ls -l .halo/sdd/<spec-id>/<task-id>/review-package.md   # 看权限位
> head -20 .halo/sdd/<spec-id>/<task-id>/review-package.md # 看正文声明
> ```
>
> **按实测到的那种语义写断言，并在用例注释里写明是哪一种。** `tests/smoke-test.sh:807` 的原断言条件就是现成答案，搬运时照它的判据走——不要自己发明一个更强的判据，那会让这条从「迁移」变成「新增」，等价性验证就不成立了。

- [ ] **Step 3: 跑测试**，期望 unit 108 → 112。

- [ ] **Step 4: 变异验证（4 条）**

| 变异 | 注入行为 | 期望变红 |
|---|---|---|
| `T10-M1` | `task-brief.sh` 的输出路径去掉 task_id 一级（所有任务写同一处） | **只** stb-2 |
| `T10-M2` | `task-brief.sh` 的产物内容写成空文件 | **只** stb-1 |
| `T10-M3` | `review-package.sh` 的只读处置去掉 | **只** srp-1 |
| `T10-M4` | `review-package.sh` 的输出路径去掉 task_id 一级 | **只** srp-2 |

- [ ] **Step 5: Commit** — `Migrate the task-brief and review-package generation assertions`

---

### Task 11: `sdd-summary-and-history.bats`（6 条）

**Files:**
- Create: `tests/unit/sdd-summary-and-history.bats`

**Interfaces:** Consumes `make_spec` / `make_plan` / `make_evidence`。

- [ ] **Step 1: 写文件**

| # | `@test` | 源 | 断言 |
|---|---|---|---|
| ssh-1 | `summary-draft generates a completion summary` | `:1425` | 产物存在且含必需章节 |
| ssh-2 | `summary-learn-draft refuses an empty knowledge candidate set` | `:1435` | **反向**：无候选时非零退出或明确拒绝，**不产出空草稿** |
| ssh-3 | `summary-learn-draft creates a reviewable knowledge draft` | `:1453` | 正向：有候选时产出草稿，且草稿标记为待评审 |
| ssh-4 | `spec-history aggregates transition events` | `:1494` | 输出含全部四段转移 |
| ssh-5 | `review-summary writes a structured verdict JSON` | `:1509` | JSON 含 verdict 字段，值在合法枚举内 |
| ssh-6 | `review-summary writes a canonical review markdown` | `:1518` | `review.md` 存在且含必需章节 |

> **ssh-2 与 ssh-3 是一对双向断言，必须同时存在。** 只有 ssh-3 的话，一个「无论有没有候选都产出草稿」的实现也能绿——而那正是「空草稿污染知识库」这类缺陷的形状。

- [ ] **Step 2: 跑测试**，期望 unit 112 → 118。

- [ ] **Step 3: 变异验证（6 条）**

| 变异 | 注入行为 | 期望变红 |
|---|---|---|
| `T11-M1` | `summary-draft.sh` 的某个必需章节不再写入 | **只** ssh-1 |
| `T11-M2` | `summary-learn-draft` 的「候选为空则拒绝」判定改成恒假 | **只** ssh-2 |
| `T11-M3` | `summary-learn-draft` 的「待评审」标记不再写入 | **只** ssh-3 |
| `T11-M4` | `spec-history.sh` 的事件收集只取最后一条 | **只** ssh-4 |
| `T11-M5` | `review-summary` 的 verdict 字段恒写空串 | **只** ssh-5 |
| `T11-M6` | `review-summary` 的 `review.md` 输出路径改名 | **只** ssh-6 |

- [ ] **Step 4: Commit** — `Migrate the summary-draft, spec-history and review-summary assertions`

---

### Task 12: §9c learn-draft 形态回归（3 条）

**Files:**
- Create: `tests/regression/2026-08-03-halo-gate-findings_2/learn-draft-promote-shape.bats`

**Interfaces:** Consumes `make_spec`。**子目录，`load` 两级路径。**

**文件头（含与同目录 `spec-discovery.bats` 的分工声明）：**

```bash
# Bug 报告: docs/bug_report/2026-08-03-halo-gate-findings_2.md（analysis §3 = 上报 §3.3）
# 根因类别: F（形态/格式）
# Fixed by: <实施者考据后填入；见下方 Step 1>
#
# 同目录的 spec-discovery.bats 守的是 analysis §1（上报 §8.1，spec 自动发现），
# 与本文件互不相干 —— 这份报告是**聚合上报**，按缺陷拆分成两个文件，
# 批次 2 迁了前者、本批次（3a）补齐后者。目录名与报告 basename 逐字相同。
```

- [ ] **Step 1: 考据 `Fixed by`**

```bash
git log --oneline -- harness-template/halo/kernel/context/learn-draft.sh | cat
```

找出引入「按目标文件形态选择 promote 方式」的那个提交。**若有多个候选，选最早引入该行为的那个，并在报告中列出考据过程与被排除的候选。** 用 `git merge-base --is-ancestor <sha> HEAD` 确认是祖先。

- [ ] **Step 2: 写文件**

源：`tests/smoke-test.sh:1926-1998`。

| # | `@test` | 源 | 断言 |
|---|---|---|---|
| lps-1 | `promoting into a table-shaped target appends rows` | `:1969` | 目标是表格形态 → 产物是**表格行**，不是章节 |
| lps-2 | `a table promotion leaves knowledge-lint clean` | `:1976` | promote 后跑 `knowledge-lint --strict` 退出 0。**这是「形态正确」的独立证据**——只断「是行」的话，一个产出格式错误表格行的实现也能绿 |
| lps-3 | `promoting into a section-shaped target appends a section` | `:1992` | 反向：目标是章节形态 → 产物是章节，不是表格行 |

> **lps-1 与 lps-3 构成双向。** 缺任一条，「无论目标什么形态都产出同一种」的实现都能过一半。

- [ ] **Step 3: 跑测试**，期望 regression 103 → 106。

- [ ] **Step 4: 变异验证（4 条）**

| 变异 | 注入行为 | 期望变红 |
|---|---|---|
| `T12-M1` | `learn-draft.sh` 的形态判定改成恒返回 `section` | **只** lps-1（与 lps-2） |
| `T12-M2` | 形态判定改成恒返回 `table` | **只** lps-3 |
| `T12-M3` | 表格行的列数写错（少一列） | **只** lps-2 |
| `T12-M4` | 形态判定完全删掉，永远追加纯文本 | lps-1、lps-2、lps-3 全红 |

`T12-M3` 是 lps-2 的专属证明。**若 `T12-M3` 也点亮 lps-1，说明 lps-1 越界断了列结构，收窄它——lps-1 只该断「是表格行」。**

- [ ] **Step 5: 更新 `docs/bug_report/INDEX.md:54`**

把「§3.3 learn-draft 形态：**批次 3 待迁**」改为指向本文件。

- [ ] **Step 6: Commit** — `Migrate the learn-draft promotion shape regression`

---

### Task 13: `context-learn-draft.bats`（4 条）

**Files:**
- Create: `tests/unit/context-learn-draft.bats`

**分层声明：** 本文件守 `learn-draft.sh` / `knowledge-review.sh` 的**审批与审计出口契约**。**不得**断言 promote 的产物形态——那归 Task 12 的回归文件。两个文件头互指。

- [ ] **Step 1: 写文件**

| # | `@test` | 源 | 断言 |
|---|---|---|---|
| cld-1 | `require-review blocks an unreviewed promotion` | `:1585` | 非零退出，**且目标文件未被改写**（只断退出码不够——「拒绝了但还是写了」是这类门禁的典型缺陷形状） |
| cld-2 | `knowledge-review records approval evidence` | `:1595` | 审批事件 JSON 落盘，`.kind == "knowledge-review"`、`.action == "approve"`、`.conflicts_checked == true` |
| cld-3 | `an approved draft promotes and records an audit event` | `:1615` | 退出 0，目标被改写，审计事件落盘 |
| cld-4 | `discarding a draft records an audit event` | `:1652` | 草稿被移除，审计事件落盘 |

- [ ] **Step 2: 跑测试**，期望 unit 118 → 122。

- [ ] **Step 3: 变异验证（5 条）**

| 变异 | 注入行为 | 期望变红 |
|---|---|---|
| `T13-M1` | `--require-review` 的审批检查改成恒真 | **只** cld-1 |
| `T13-M2` | 拒绝分支里仍执行写目标（写调用上移到检查之前） | **只** cld-1 的「未被改写」那半 |
| `T13-M3` | `knowledge-review.sh` 的 `conflicts_checked` 恒写 false | **只** cld-2 |
| `T13-M4` | promote 的审计事件不再写 | **只** cld-3 |
| `T13-M5` | discard 的审计事件不再写 | **只** cld-4 |

- [ ] **Step 4: Commit** — `Migrate the learn-draft review and audit assertions`

---

### Task 14: `context-knowledge.bats`（8 条）

**Files:**
- Create: `tests/unit/context-knowledge.bats`

- [ ] **Step 1: 写文件**

| # | `@test` | 源 | 断言 |
|---|---|---|---|
| ckn-1 | `knowledge-lint accepts the default knowledge templates` | `:1659` | 退出 0。**注意 O-15**：模板自带 4 个 knowledge 文件，这是既定事实，本用例断的是它们能过 lint |
| ckn-2 | `knowledge-lint rejects stale or conflicting metadata` | `:1687` | 非零退出 |
| ckn-3 | `the knowledge backend lists entries` | `:1844` | `--list` 输出含默认四个文件 |
| ckn-4 | `knowledge search matches a single keyword` | `:1854` | 命中 |
| ckn-5 | `knowledge search splits a quoted multi-word argument` | `:1866` | `"a b"` 作为一个参数时按词拆分（AND 语义） |
| ckn-6 | `knowledge search keeps OR semantics across separate arguments` | `:1873` | 两个独立参数是 OR |
| ckn-7 | `knowledge search matches inside a file larger than the pipe buffer` | `:1889` | 造一个 >64KB、关键词在**顶部**的文件 → 仍然命中。**这是 SIGPIPE 防线** |
| ckn-8 | `knowledge search treats keywords as literal text` | `:1898` | 传入 `.*` 之类的正则元字符 → 按字面匹配，不当正则 |

> **ckn-7 的断言不能穿管道。** `tests/smoke-test.sh:1850-1851` 的原注释说明了为什么：「the large-file case deliberately produces output past the pipe buffer, which is exactly the SIGPIPE condition being tested — asserting through a pipe would reintroduce it here」。搬运时把这条注释一起搬过来。
>
> **ckn-5 与 ckn-6 是一对。** 只有一条的话，一个「所有参数都按 OR」或「所有参数都按 AND」的实现都能过一半。

- [ ] **Step 2: 跑测试**，期望 unit 122 → 130。

- [ ] **Step 3: 变异验证（7 条）**

| 变异 | 注入行为 | 期望变红 |
|---|---|---|
| `T14-M1` | `knowledge-lint.sh` 的过期元数据检查改成恒真 | **只** ckn-2 |
| `T14-M2` | 后端 `--list` 只输出第一条 | **只** ckn-3 |
| `T14-M3` | 搜索的多词拆分去掉（整串当一个词） | **只** ckn-5 |
| `T14-M4` | 多参数语义从 OR 改成 AND | **只** ckn-6 |
| `T14-M5` | 大文件搜索路径改回 `… \| grep -q` 的早退管道形态 | **只** ckn-7 |
| `T14-M6` | 关键词匹配从 `grep -F` 改成 `grep -E` | **只** ckn-8 |
| `T14-M7` | `knowledge-lint.sh` 对默认模板的某条检查改严（默认模板不再通过） | **只** ckn-1 |

`T14-M5` 若点不亮 ckn-7，说明 ckn-7 的文件没真的超过 64KB 或关键词不在顶部——回去查构造。

- [ ] **Step 4: Commit** — `Migrate the knowledge lint and backend search assertions`

---

### Task 15: `delivery-eval-evidence.bats`（18 条）

**Files:**
- Create: `tests/unit/delivery-eval-evidence.bats`（**允许拆分，见 Step 1**）

- [ ] **Step 1: 先判定拆不拆**

本 Task 的 18 条覆盖四组被测对象：pipeline 的 eval JSON 落盘（4）· failure-category（3）· outcome-\*（2）· eval-\* 报告链（7）· spec-lock（2）。

**判定规则**：跑一遍看这四组的 `setup` 前置是否共用。若 `eval-*` 那 7 条需要一个「已有多次 eval run 的中央 sink」而其余组不需要，就拆成 `delivery-eval-evidence.bats` 与 `delivery-eval-reporting.bats` 两个文件。

**依据**：`tests/README.md` 已成文的「只服务单个文件的前置构造函数留在该文件里」优先于通用的「消除重复」。**拆或不拆都要在报告中写明实测依据**（各组 setup 的实际差异），不接受「感觉太大了所以拆」。

- [ ] **Step 2: 写文件**

| # | `@test` | 源 | 断言 |
|---|---|---|---|
| dee-1 | `pipeline embeds structured gate JSON in the eval run` | `:1533` | eval JSON 里含各门禁的结构化结果 |
| dee-2 | `summary-draft embeds eval JSON metrics` | `:1545` | summary 产物含 eval 指标 |
| dee-3 | `pipeline writes loop state JSON` | `:1555` | loop state 落盘 |
| dee-4 | `pipeline writes an escalation learn draft on repeated failure` | `:1575` | `SH_RETRY_COUNT=3 SH_RETRY_MAX=3` 下产出升级草稿 |
| dee-5 | `failure-category-lint accepts the default config` | `:1692` | 退出 0 |
| dee-6 | `failure-category-lint rejects an invalid config` | `:1712` | 非零退出 |
| dee-7 | `pipeline reads a configurable failure category` | `:1732` | 自定义分类生效，分类结果出现在 eval JSON |
| dee-8 | `outcome-link records post-run outcome evidence` | `:1742` | 事件 `.kind == "outcome-link"`，`.eval_run.run_id` 非空，`.context_refs \| length == 1` |
| dee-9 | `outcome-report renders attribution signals` | `:1751` | 报告含归因信号 |
| dee-10 | `eval-summary renders the pipeline JSON as Markdown` | `:1760` | 产物是 Markdown 且含关键指标 |
| dee-11 | `pr-comment renders a stable dry-run body` | `:1769` | **稳定性**：连跑两次产物逐字节相同（守「不含时间戳等非确定内容」） |
| dee-12 | `eval-history aggregates eval run JSON` | `:1780` | 聚合多次 run |
| dee-13 | `eval-sink publishes project evidence to the central sink` | `:1795` | sink 目录下出现条目 |
| dee-14 | `eval-dashboard renders the central sink as HTML` | `:1808` | 产物是 HTML 且含条目 |
| dee-15 | `eval-query summarizes the central sink` | `:1818` | 汇总输出 |
| dee-16 | `eval-query emits filtered JSON` | `:1830` | `--status=` 之类过滤生效，输出条目**严格少于**无过滤时。**必须断「少于」而不是「非空」**——恒返回全集也能让「非空」绿 |
| dee-17 | `spec-lock acquire takes the lock` | `:1908` | 退出 0，锁文件存在 |
| dee-18 | `spec-lock release frees the lock` | `:1915` | 退出 0，锁文件消失 |

> **dee-11 的「稳定性」断言值得单独说。** 原 smoke-test 断言名里的 "stable" 指的就是 dry-run 产物可重复。搬运时必须真的跑两次比对，而不是只断「产物非空」。

- [ ] **Step 3: 跑测试**，期望 unit 130 → 148。

- [ ] **Step 4: 变异验证（10 条）**

| 变异 | 注入行为 | 期望变红 |
|---|---|---|
| `T15-M1` | pipeline 的 gate JSON 嵌入去掉 | dee-1、dee-2 |
| `T15-M2` | loop state 不再写 | **只** dee-3 |
| `T15-M3` | 升级阈值判定改成恒假 | **只** dee-4 |
| `T15-M4` | `failure-category-lint` 的 schema 校验改成恒真 | **只** dee-6 |
| `T15-M5` | pipeline 忽略自定义分类配置（只用内置） | **只** dee-7 |
| `T15-M6` | `outcome-link` 的 `context_refs` 恒写空数组 | **只** dee-8 |
| `T15-M7` | `pr-comment` 的产物里插入当前时间戳 | **只** dee-11 |
| `T15-M8` | `eval-query` 的过滤条件被忽略（恒返回全集） | **只** dee-16 |
| `T15-M9` | `spec-lock` 的 release 不删锁文件 | **只** dee-18 |
| `T15-M10` | `eval-sink` 的发布路径改名 | dee-13、dee-14、dee-15（下游都读 sink） |

`T15-M7` 是 dee-11 的专属证明，`T15-M8` 是 dee-16 的。**这两条抓不住就说明对应断言退化成了「非空」检查，回去补。**

- [ ] **Step 5: Commit** — `Migrate the pipeline eval evidence and reporting assertions`

---

### Task 16: 交叉核验

**Files:**
- Modify: `docs/superpowers/plans/2026-09-09-halo-test-batch3a-sdd-migration.md`（追加「变异台账」一节）

**Interfaces:**
- Consumes: Task 1-15 各自报告里的变异记录。
- Produces: 全局变异台账；严格判据扫描结论。

本 Task **不写新断言**，只做三件单 Task 内做不到的事。

- [ ] **Step 1: 汇总全局变异台账**

把 Task 1-15 报告里的变异逐条汇进一张表：`编号 / 目标文件:行（实施者回填的实际值） / 期望变红 / 实际变红 / PASS·MISS`。

**核对两件事**：① 编号无重复、无跳号；② 每条「按行为指定」的变异都回填了实际 `文件:行`。缺失的回到对应 Task 的报告里找，找不到就重跑那条变异。

- [ ] **Step 2: 严格判据全量扫描**

对本批次新增的**每一条** `@test`，检查是否存在至少一条以它为「期望变红」的变异。

```bash
# 新增 @test 全集
git diff <Task 0 基线>..HEAD -- 'tests/**/*.bats' | grep '^+@test' | sed 's/^+@test "//; s/" {$//' | sort > /tmp/new-tests.txt
wc -l /tmp/new-tests.txt
```

**判据是「专属」不是「顺带」**：某条变异把它点亮了，但它不在该变异的期望列里，**不算**。批次 2 正是用这条严格判据（而非抽样）扫出了 `disc-10` 与 `find-5` 两个缺口，靠新增 M72/M73 才闭合。

发现缺口时按 `tests/README.md:143-145` 的两分表处置，并**在本 Task 内补做变异**（补做的编号用 `T16-Mn`）。

- [ ] **Step 3: 跨文件分层核验（四条）**

| # | 核验 | 判据 |
|---|---|---|
| ① | 打 `_lib.sh` 的变异（`T2-M1`..`T2-M6`）**不**点亮任何 `regression/` 用例 | 库层变异只该点亮 `unit/` |
| ② | 打 `plan-lint.sh` 的变异（`T2-M7`、`T9-M1`、`T9-M2`）**不**点亮 `lib-task-declaration.bats` 的 tdecl-1..10 | 只有齐平用例 tdecl-11 该被 `T2-M7` 点亮 |
| ③ | 打 `review-package.sh` 生成逻辑的变异（`T10-M3`、`T10-M4`）**不**点亮 `regression/2026-08-03-halo-gate-findings/review-package-scope.bats` | 生成契约与范围缺陷分层 |
| ④ | 打 `learn-draft.sh` 形态判定的变异（`T12-M1`、`T12-M2`）**不**点亮 `context-learn-draft.bats` | 形态归回归、审批归契约 |

**任一条不成立 → 对应文件越界，回去收窄断言，不接受现状。**

- [ ] **Step 4: 记录容许的交叠**

`emc-2`（Task 5）与 `2026-09-07-task-evidence-lint-unknown-mode-silent-skip.bats` 的交叠已在 Task 5 声明。用 `T5-M4` 的实测结果填 `tests/README.md`「容许的交叠」表新增一行，格式照现有两行：交叠对 / 断言对象为什么不同 / 正当性的机器证明。

**若 `T5-M4` 显示两者恒同红同绿，则该交叠不正当**——删掉 `emc-2` 并在本 Task 报告中说明。

- [ ] **Step 5: 全量测试 + 冻结区核验**

```bash
bash tests/run.sh; echo "rc=$?"
git diff --stat <Task 0 基线>..HEAD -- harness-template/ prismspec/    # 必须为空
git status --porcelain                                                  # 必须为空
```

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/plans/2026-09-09-halo-test-batch3a-sdd-migration.md
git commit -m "Record the batch-3a mutation ledger and the cross-file layering checks"
```

---

### Task 17: 删旧段

**Files:**
- Modify: `tests/smoke-test.sh`（删除 `635-1998`）

**Interfaces:**
- Consumes: Task 0 记录的两端实测值。

**前置：Task 16 必须已 complete 且严格判据零缺口。** 变异证据是删旧段的许可证——没有它，删除就是在丢失覆盖而不是迁移覆盖。

- [ ] **Step 1: 前置核验**

```bash
git status --porcelain          # 空
bash tests/run.sh; echo "rc=$?" # 0
bash tests/smoke-test.sh 2>&1 | tail -3   # 122 / 122
```

- [ ] **Step 2: 删除单个区间**

```bash
# §6c 起于 :635，§9c 止于 :1998（:1999 是 `# ── Summary ──`）
{ sed -n '1,634p' tests/smoke-test.sh; sed -n '1999,$p' tests/smoke-test.sh; } > tests/smoke-test.sh.tmp
mv tests/smoke-test.sh.tmp tests/smoke-test.sh
chmod +x tests/smoke-test.sh
```

**先核对边界再执行**：`awk 'NR==634 || NR==635 || NR==1998 || NR==1999' tests/smoke-test.sh` 应显示 `:635` 是 `# ── 6c. SDD helper scripts ──`、`:1999` 是 `# ── Summary ──`。行号若不符（前面的 Task 动过 smoke-test，本不该发生）就停下来查。

- [ ] **Step 3: 验证「只删不加」**

```bash
git diff --numstat -- tests/smoke-test.sh
```

期望：`0	1364`（insertions **必须为 0**；deletions = 1998 − 635 + 1 = 1364）。

- [ ] **Step 4: 验证期望值**

```bash
bash tests/smoke-test.sh 2>&1 | tail -3
```

期望：`✅ 49 / 49`。

**不是 49 就停下来查，禁止改期望值。** 常见原因：删除边界错位、残留变量引用。

- [ ] **Step 5: 残余引用扫描**

```bash
# 被删块里定义、Summary 块或 §1-§6 仍在用的变量/函数
grep -nE 'SLOW_YQ_BIN|ESCALATION_LEARN_DRAFT|PIPELINE_GATE_JSON|PROMOTE_TARGET|SECTION_TARGET' tests/smoke-test.sh
# O-11 的三个死 rm -f 条目是否随块消失
grep -n 'halo-drift-json.log\|halo-compliance-json.log\|halo-ac-json.log' tests/smoke-test.sh
```

期望：两条 grep 都无输出。有输出则说明删除边界不对或有跨块引用。

- [ ] **Step 6: 验证 O-12 闭合**

```bash
grep -n '── 7\. AC-coverage' tests/smoke-test.sh
```

期望：无输出。该标题在 `:1526`，随本区间一并删除——这闭合了批次 1 的 O-6 / 批次 2 的 O-12。

- [ ] **Step 7: 静态检查 + 全量测试**

```bash
bash -n tests/smoke-test.sh
shellcheck --severity=warning tests/smoke-test.sh
bash tests/run.sh; echo "rc=$?"
```

- [ ] **Step 8: Commit**

```bash
git add tests/smoke-test.sh
git commit -m "Delete the migrated SDD, context and delivery sections from smoke-test"
```

提交正文要写进：删除区间、`numstat` 的 `0 1364`、`122 → 49` 实测、O-12 闭合。

---

### Task 18: 文档收口

**Files:**
- Modify: `tests/README.md`
- Modify: `tests/fixtures/README.md`
- Modify: `docs/bug_report/INDEX.md`
- Modify: `docs/superpowers/specs/2026-08-07-halo-test-system-design.md`
- Modify: `docs/superpowers/plans/2026-08-25-halo-legacy-noise-inventory.md`

- [ ] **Step 1: 设计文档批次表拆成 3a/3b/3c**

`docs/superpowers/specs/2026-08-07-halo-test-system-design.md:160` 那一行改成三行，并加脚注说明：① 拆分理由（A/B/C 与 D 的纪律互斥）；② §6c 此前是**未登记空档**（批次 3 行只点名 §6d/SIGPIPE/§9c，批次 2 的范围边界表也没有它），已由 3a 收编。

批次 4 行相应更正为「E2E 主干（§1–§6）迁移，删空 smoke-test.sh」。

- [ ] **Step 2: `tests/README.md`**

四处改动：

1. 目录结构一节：`unit/` 的说明补上本批次新增的三族命名（`sdd-*` = SDD 脚本出口语义、`context-*` = knowledge/learn-draft、`delivery-*` = pipeline/eval/outcome），与既有 `lib-*` / `gate-*` 并列。
2. 「容许的交叠」表：追加 Task 16 Step 4 定下的那一行（若该交叠被判为不正当而删除了 `emc-2`，则不追加，改在本节写明「批次 3a 检查过一处候选交叠并判定不正当，已删除」）。
3. 「写用例的约定」一节：补 `halo_slow_yq_path` 与 `make_evidence` 的用法各一句。
4. **用例计数**（`:21-22` 附近）：按 Task 17 后的实测值更新。**这个数在批次 2 就被写旧过两次**（噪声清单记载：unit 50→55、regression 78→95，后者在基线上就已失准），所以本 Step 必须**先跑 `tests/run.sh` 取实测值再写**，不许照本计划的预估数抄。

- [ ] **Step 3: `tests/fixtures/README.md`**

若 Task 1-15 新增了静态 fixture，矩阵表相应追加行。**批次 2 最终评审在这份文件里抓到过两条「文档声称与仓库实际不符」**（矩阵表 6 行写着「待补：drift-check.bats / compliance.bats」而那两个文件从不存在；`:58-61` 说 §7c「可直接读现存原文核对」而 §7c 已被删）。

因此本 Step 必须做一次**全表核验**：

```bash
# 表里列的每个 fixture 路径都要存在
grep -oE 'tests/fixtures/[a-z0-9/-]+' tests/fixtures/README.md | sort -u | while read -r p; do
  [[ -e "$p" ]] || echo "MISSING: $p"
done
# 表里列的每个消费者 .bats 都要存在
grep -oE 'tests/(unit|regression)/[a-zA-Z0-9/._-]+\.bats' tests/fixtures/README.md | sort -u | while read -r p; do
  [[ -e "$p" ]] || echo "MISSING CONSUMER: $p"
done
# 引用 §7c 之类已删内容的活指针
grep -n '§7c\|§6c\|§6d\|§9c\|smoke-test\.sh:[0-9]' tests/fixtures/README.md
```

第三条 grep 有输出时逐条判断：指向已删内容的表述必须改写或删除。

- [ ] **Step 4: `docs/bug_report/INDEX.md` 终检**

Task 5/6/12 各自更新了自己那行。本 Step 做全表对拍：

```bash
# 每份有 -analysis.md 的报告都要有对应的 .bats 文件或同名目录
for a in docs/bug_report/*-analysis.md; do
  b=$(basename "$a" -analysis.md)
  if [[ ! -e "tests/regression/$b.bats" && ! -d "tests/regression/$b" ]]; then
    echo "NO TEST: $b"
  fi
done
```

已知的合法例外只有 `spec-lint-ac-gap`（`INDEX.md:50` 登记的命名例外）。**其余任何输出都说明有条目没更新。**

- [ ] **Step 5: 噪声清单补登两条**

`docs/superpowers/plans/2026-08-25-halo-legacy-noise-inventory.md`：

1. **规则 4 的 `execution_mode` 一节补登形态 ③**（`execution_mode: tddx` 的前缀污染分歧）。现有正文只记了形态 ②（front-matter 块外）。补一张四份 × 四形态的实测对拍表（数据见本计划「决定二」），并注明测法：把四份函数连同各自的 `frontmatter_value` 抽出来独立运行。
2. **新增 O-18 条目**：`plan-lint.sh:262` 的 `if [[ "$MODE" == "tdd" ]]` 只有 `else` 兜底、`:273` 打 `pass_msg "Mode: $MODE"`，未知模式**主动报绿**并跳过两条 TDD 结构检查。与 `task-evidence-lint` 的 `unknown` 静默跳过（2026-09-07 已修）同型但更糟。归 3c。
3. **「待定夺清单」第 13 条给出答案**：齐平遍历形态（一条用例循环 N 份实现，而非 N 份手写副本）在本批次用于 `sdd-execution-mode.bats` 与 `lib-task-declaration.bats` 的 tdecl-11，**采纳为同类契约的默认写法**，并写明它的边界纪律（只断行为一致的输入域，已知分歧不写不反向断言）。

- [ ] **Step 6: 全量测试 + Commit**

```bash
bash tests/run.sh; echo "rc=$?"
git add tests/README.md tests/fixtures/README.md docs/
git commit -m "Close the batch-3a documentation: batch table split, naming families and the noise inventory additions"
```

---

### Task 19: CI 双平台验证与完成记录

**Files:**
- Modify: `docs/superpowers/plans/2026-09-09-halo-test-batch3a-sdd-migration.md`（追加两张表）

- [ ] **Step 1: 推送**

```bash
git push origin main
```

- [ ] **Step 2: 等 CI**

```bash
gh run watch
gh run view --json jobs -q '.jobs[] | "\(.name)\t\(.conclusion)"'
```

期望：`test (ubuntu-latest)` 与 `test (macos-latest)` 均 success，`CI` workflow success。

- [ ] **Step 3: Linux 侧重点核对**

macOS 上跑不到的分歧面，逐条看 ubuntu job 的日志：

- `halo_slow_yq_path` 的 shim：Linux 的 `sleep 0.05` 与 `command -v yq` 路径；
- `make_evidence` 与各 `.bats` 里的 `sed` / `awk` 用法（GNU vs BSD）；
- `git branch -M main` 依赖的默认分支名（`review-package` 相关用例）；
- 任何 `env PATH=` 白名单用例：Linux 上 `yq` 常驻 `/usr/bin` 而 macOS 在 `/opt/homebrew/bin`，白名单写死路径会让用例静默退化成恒绿。

- [ ] **Step 4: 写「批次 3a 完成记录」表**

照批次 1/2 的格式，逐条对照本计划「验证（端到端）」表。**未达成与部分达成的条目排在最后，不与已达成的混排，且必须如实标注。** 批次 2 的记录表把两条未达成如实记为 ❌ 与 ⚠️，这是该记录可信的原因。

- [ ] **Step 5: 写「与计划的偏离」表**

逐条编号记录执行中偏离本计划的地方：谁提出、理由、裁定人、落点提交。

**两条格式纪律来自批次 2 的教训**：① 跨节引用一律按**条目名**指认，不要用序号（批次 2 的速查表与详述版曾出现第 3/4 条次序不同）；② 规模统计行（「N 个提交、M insertions」）是**自指统计**，必须走「写 → 提交 → 重取 → 比对」的闭环——批次 2 初版写的是提交前的快照，落盘瞬间即失真。

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/plans/2026-09-09-halo-test-batch3a-sdd-migration.md
git commit -m "Record the batch-3a completion and deviations"
git push origin main
```

---

## 验证（端到端）

批次 3a 完成定义：

| 条件 | 验收证据 |
|---|---|
| 新 bats 用例全绿 | `bash tests/run.sh` 退出 0，全程零 `not ok` |
| **每条新 `@test` 有专属变异** | 严格判据：必须存在以该用例为「期望变红」的变异，**不算宽半径顺带点亮**。Task 16 Step 2 **全量扫描**而非抽样 |
| 分层可证 | Task 16 Step 3 的四条跨文件核验全部成立 |
| 旧段已删且只删不加 | `bash tests/smoke-test.sh` → `✅ 49 / 49`（基线 122 实测）；`git diff --numstat -- tests/smoke-test.sh` = `0 1364`，insertions **恒为 0** |
| O-12 闭合 | `grep -n '── 7\. AC-coverage' tests/smoke-test.sh` 无输出 |
| `harness-template/` 与 `prismspec/` 零改动 | `git diff --stat <Task 0 基线>..HEAD -- harness-template/ prismspec/` 为空。**O-1、O-13~O-18 未被顺手修掉是这条的一部分** |
| M-4 闭合 | 缺 `yq` 的 PATH 下 `tests/run.sh` 显式报警且**非零退出**（现状是静默全绿），由 `harness-setup.bats` 的两条双向用例守 |
| `INDEX.md` 两处「批次 3 待迁」闭合 | #10 → `2026-07-31-sdd-gate-defects/`（三文件）；#11 → `2026-08-02-tdd-cycle-evidence-sigpipe.bats`；另 `:54` 的 §3.3 指向 `learn-draft-promote-shape.bats`。Task 18 Step 4 的全表对拍无输出（除已登记的命名例外） |
| 设计文档批次表已更正 | 批次 3 行拆为 3a / 3b / 3c，脚注写明拆分理由与 §6c 的空档来源；批次 4 行改为「E2E 主干（§1–§6）」 |
| 噪声清单已补登 | 形态 ③（`tddx` 前缀污染）进规则 4；O-18 新增条目；待定夺 #13 给出答案 |
| 静态检查全绿 | `bash -n` + `shellcheck --severity=warning` 覆盖 `init.sh install.sh tests/run.sh tests/smoke-test.sh tests/helpers/*.bash $(find harness-template prismspec/bin -name '*.sh')`，两者 rc=0 无输出（`.bats` 两者都不进） |
| CI 双平台绿 | `gh run view --json jobs` 确认 ubuntu + macos 两个 job |

**刻意不设的一条**：不预先写死「unit 要到 N 条、regression 要到 M 条」。批次 2 能写死是因为只有 23 条断言、映射可静态穷举；本批次 70 条断言分散在 15 个文件，预设总数是伪造精度。**每个 Task 的 Step「跑测试」里的期望值是该 Task 自己的增量下限**（上表「迁移映射」的条数），总数是各 Task 之和。完成定义只卡「严格判据 100% 通过」。

完整验证命令（`AGENTS.md` Verification 段）：

```bash
bash tests/run.sh
bash -n init.sh install.sh tests/run.sh tests/smoke-test.sh tests/helpers/*.bash $(find harness-template prismspec/bin -name '*.sh')
shellcheck --severity=warning init.sh install.sh tests/run.sh tests/smoke-test.sh tests/helpers/*.bash $(find harness-template prismspec/bin -name '*.sh')
git diff --check
git status --porcelain
```

---

## 实现观察（本批次**不修**，仅记录）

沿用批次 1/2 的机制：迁移过程中撞见的实现缺陷只登记、不修，归后续批次走完整 SOP。

| # | 位置 | 内容 | 归属 |
|---|---|---|---|
| O-18 | `plan-lint.sh:262` + `:273` | `if [[ "$MODE" == "tdd" ]]` 只有 `else` 兜底，`:273` 打 `pass_msg "Mode: $MODE"`。`execution_mode: tddx` 的 spec 得到 `✅ Mode: tddx`，同时跳过「TDD plan requires RED-{n} test-first tasks」与「RED 必须排在 T 之前」两条结构检查。与 2026-09-07 修掉的 `task-evidence-lint` `unknown` 静默跳过同型，但更糟——那是沉默，这是**主动报绿**。形态 ④（`unknown`）走同一分支，后果相同。<br>**发现路径**：本计划撰写期间为设计「模式解析链」契约单测而对拍四份 `execution_mode` 时实测发现 | 3c，需独立走完整 SOP |
| — | — | **本表在执行中持续追加。** 每条须写清：位置、缺陷是什么、为什么现在不修、发现路径（自查发现还是有上报原文）、归属批次 | — |

**登记纪律**（批次 2 立下，本批次沿用）：

- 发现缺陷的 Task **不得顺手修**，即使改动只有一行。冻结区零改动是删旧段的许可证的一部分。
- **不得为已知缺陷写反向断言**（「确认它确实是坏的」）——那是把缺陷固化成期望值。批次 2 对 O-14 的裁定原文：「明令不许反向断言 detail 为空」。
- 用例名不得撒谎：一个用例若因为已知缺陷而只能覆盖一半，`@test` 名必须反映它实际守住的那一半。批次 2 的 `dec-6` 就栽在这里——用例名写着 `reports NOT verified instead of clean`，而它恰恰守不住「报成 clean」。

# Halo 测试体系批次 1：AC 系列迁移

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

## Context

`docs/superpowers/specs/2026-08-07-halo-test-system-design.md` 定的四层防线测试体系，批次 0（bats 骨架 + helpers + CI workflow + 维护手册）已实现完毕，唯一未闭合的是 CI 双平台验证——本地 8 个提交（含 `.github/workflows/test.yml`）从未推送，`test` workflow 从未在 GitHub Actions 上跑过。

本轮做两件事：**先推送闭合批次 0**，再执行**批次 1：AC 系列迁移**。

为什么是 AC 系列先迁：设计文档的根因统计里，A 类「词法上把『提及』当成『声明』」复发 **5 次**（#7 → #8 → #9 → #14 → runningtime），是全部根因中复发最多的一类，而它现有的防线全在 3023 行的单体 `tests/smoke-test.sh` 里——fixture 与断言纠缠、失败难归因、无法单跑、存在隐式时序耦合。迁到 bats 后每条断言独立进程、独立沙箱、可按名字单跑，且文件名直指 bug 报告，失败时「测试文件 → 报告 → 根因」三跳直达。

预期产出：22 条 smoke-test 断言 + 6 条 `tests/ac-coverage-test.sh` 断言（共 28 条）→ 6 个 `tests/regression/*.bats`（32 条）+ `tests/unit/gate-ac-coverage.bats`（2 条），合计 **34 条**用例，其中 **6 条为本批次新增**（4 条补齐双向断言、2 条来自把压在一起的断言拆开）；用变异测试证明等价后删除旧段，`tests/ac-coverage-test.sh` 退役。`tests/unit/` 另因 helper 扩展增加 3 条自测，由 9 条增至 14 条。

**基线提交：`1e5fbc8`**（本计划全部行号以此为准，已逐条实测核对）。

---

## Global Constraints

- 除已 vendored 的 bats（core 1.12.0 / support 0.3.0 / assert 2.1.0）外**不引入任何新依赖**。迁移后 `#8` 用例不再需要 `python3`（旧脚本用它解析 gate JSON，新用例用 `yq`），前置回到 `halo_require_tools` 的 `yq` + `git`。
- 新增/修改的 `.sh` / `.bash` 必须过 `bash -n` 与 `shellcheck --severity=warning`；`.bats` 不进 shellcheck。
- 兼容 macOS（BSD）与 Linux：禁止无后缀 `sed -i`；**禁止在 sed 替换串里用 `\n` 造多行**（BSD sed 不支持，复制行一律用 `awk '/pat/{print; print; next} {print}'`）；禁止 GNU 专属 flag。
- 不得出现设计文档根因 B/D 反模式：不用 `cmd | grep -q` 作管道读端末端判定（改 `out="$(cmd)"; grep -q … <<< "$out"`）、不消费无 `sort` 的 `find` 输出做决策、命令替换包 grep 必须 `|| true` 兜底。
- **不得修改 `harness-template/` 下的实现代码。** Task 8 的变异是临时验证动作，每条变异前后强制 `git status --porcelain` 校验，任何变异不得进入提交。发现实现缺陷只记入「实现观察」，不在本批次修。
- `tests/smoke-test.sh` 冻结纪律：**只删不加**。本批次对它的唯一改动是删除整块行区间，不改任何残留行。
- 计划、`tests/` 文档、`docs/bug_report/INDEX.md` 用简体中文；`AGENTS.md` 保持英文；`.bats` 的 `@test` 名用英文（与现有 9 条一致），注释用中文。
- 提交信息结尾带 `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`。

---

## 范围边界（明确不越界）

批次 1 只做 **AC 系列**。以下已核实属其他批次，本轮**不碰**：

| 对象 | 位置 | 归属 | 理由 |
|---|---|---|---|
| `red-multi-ac`（smoke-test:1167-1258） | §6d | 批次 3 | 根因 G（量词错误），报告是 `2026-07-31-sdd-gate-defects.md`，其余断言散在 §6d |
| `red-many-ac` + 慢 yq shim（1260-1366） | §6d | 批次 3 | #11 SIGPIPE，设计文档明列批次 3 |
| `find_spec` / `narrow_acs_to_declared` / `spec_declared_acs` 的 `_lib.sh` 函数级契约单测 | `_lib.sh` | 批次 2/3 | 设计文档批次表明列 |
| drift-check 系列（§7c）与 §7 残余 gate JSON | 2037+ | 批次 2 | — |

**边界处的一个处理**：旧断言 1685-1693（「plan-lint 对无声明行的任务 warn 但不 fail」）属本批次的 C 组，但借用了批次 3 的 `red-multi-ac` fixture。迁移时不搬 fixture，改用 `make_plan … ref`（默认 Ref: 风格、无声明行）现造等价输入，语义一致且解开跨批次依赖。删段时 `red-multi-ac` 原样保留。

---

## 决定一：历史报告的命名与 SOP 落地

四份纯 AC 报告不满足 `tests/README.md` 的 SOP（无 analysis、命名非 `YYYY-MM-DD-<slug>.md`），已逐份核对：

| 报告 | 形态 | analysis | 修复提交 |
|---|---|---|---|
| `halo-ac-coverage-bug-report.md` | 规范报告正文 | ❌ | `de6c249`（2026-07-12） |
| `spec-lint-ac-cross-reference-duplicate.md` | 目标项目 verify.md，缺陷在其中一节 | ❌ | `45d5f7f`（2026-07-19） |
| `ac-coverage-bug/`（目录） | verify.md + 2 份 eval 产物 | ❌ | `f60637d`（2026-07-25） |
| `spec-lint-ac-gap-analysis.md` | 它自己就是复核文本，无配对原文 | 命名例外 | `334bdb6`（2026-07-26） |

**三条决定：**

1. **不重命名历史报告。** 这些文件被 CHANGELOG 与历史提交信息引用，重命名换不来机器价值却打断归因链。SOP 的命名约定对**新报告**生效。
2. **不补写 analysis。** `tests/README.md` 对 analysis 的定义是「**当时**不采信报告结论、自行验证根因的独立复核」；今天补写一份 7 月的「复核」是伪造过程证据，比缺失更坏。四份报告全部早于 SOP 成文（2026-08-07），此事实记入名录。
3. **新增 `docs/bug_report/INDEX.md` 作历史资产名录**，并把 regression 命名规则写进 `tests/README.md`：
   - 报告已合规 → bats 文件名与报告 basename **逐字相同**，机器可直接对拍；
   - 历史遗留报告 → 日期取**修复提交的作者日期**（可考据、与文件头 `Fixed by` 自洽），slug 取语义 slug，映射登记到 INDEX.md。

据此本批次 6 个 regression 文件名：

| bats 文件 | 对应报告 |
|---|---|
| `2026-07-12-ac-coverage-python-lowercase.bats` | `halo-ac-coverage-bug-report.md` |
| `2026-07-19-spec-lint-ac-cross-reference-duplicate.bats` | `spec-lint-ac-cross-reference-duplicate.md` |
| `2026-07-25-ac-coverage-cross-spec-attribution.bats` | `ac-coverage-bug/` |
| `2026-07-26-spec-lint-ac-number-gap.bats` | `spec-lint-ac-gap-analysis.md` |
| `2026-08-03-user-report.bats` | `2026-08-03-user-report.md` ✅ |
| `2026-08-07-runningtime-report.bats` | `2026-08-07-runningtime-report/` ✅ |

INDEX.md 同时为批次 3 的「报告↔测试对应检查」兜底：`spec-lint-ac-gap-analysis.md` 以 `-analysis` 结尾却无配对原文，朴素的「去后缀找原文」逻辑会去找不存在的文件。

---

## 决定二：fixture 三档判定

写进 `tests/README.md`，作为批次 2-4 继续扩展的准绳：

- **进构造函数**（`helpers/fixtures.bash`）：跨用例复用的黄金形态，差异可用少量标量参数表达。
- **进 `tests/fixtures/` 静态文件**：语法/语义变体，尤其是「多个陷阱元素同时出现在一份文档不同位置」的形态——价值在于**可被逐字审阅**，参数化会把陷阱藏进生成逻辑。
- **用例内 `awk`/`sed` 派生**：单元素、一行可表达的变体（改一个单元格、改一个 AC 号、复制一行）。

`tests/ac-coverage-test.sh` 的迁移方式：**放弃它的轻量形态（`cp -R` kernel + 手写 6 行 manifest），复用 `halo_template_install` 沙箱 + `halo_set_language python`**。理由——手写 manifest 让门禁读的是一份为通过测试而裁剪的配置，而设计文档的根因 E「框架读不懂自带模板」已复发 4 处，跑真实 `install.sh + init.sh` 才能覆盖它；且统一沙箱语义让批次 2-4 的 20+ 个文件不必解释「这个用例为什么用另一种沙箱」。旧脚本之所以手写 manifest（以及 §7b 之所以要「改完改回去」），是因为它们在单个共享沙箱里串行执行——bats 每用例一个 `cp -R` 副本后这个约束消失，这正是迁移的净收益。

---

## 任务清单

### Task 0: 推送闭合批次 0 ✅ 已完成（2026-08-16）

- [x] `git push origin main`
- [x] `gh run watch` 确认 `test` workflow 的 ubuntu 与 macos 两个 job 都绿
- [x] 更新批次 0 计划文档的完成定义表

**实际结果与预期不同，值得记录**：首跑 macos 红，且不是依赖抖动，而是抓到一个真缺陷——
`init.sh` 的 Go/Rust 探测在 `set -euo pipefail` 下无 `||` 兜底，探测器不可用时 `halo init`
**静默猝死**（GitHub macos-latest arm64 镜像不预装 Go；ubuntu 预装所以一直绿）。
按 `tests/README.md` 的处置 SOP 走完全流程后闭合：

| 产出 | 位置 |
|---|---|
| 复核文档 | `docs/bug_report/2026-08-16-init-detection-probe-pipefail-analysis.md` |
| 双向回归测试（5 条，先红后绿实测） | `tests/regression/2026-08-16-init-detection-probe-pipefail.bats` |
| 修复 | `1a9773e`（`init.sh:124` 与 `:153`） |
| CI | [run 31924319231](https://github.com/Spadex/halo/actions/runs/31924319231) 双平台绿 |

**对本批次的两处影响**：
1. `tests/regression/` 套件已提前启用，Task 2 起不再是「首次创建」；
2. 后续各 Task 的 regression 计数需在原计划数字上 **+5**（Task 2 → 11，Task 3 → 15，
   Task 4 → 27，Task 5 → 34，Task 6 → 37）。

> CI 重叠（旧 `CI` workflow 与新 `test` workflow 都跑 smoke-test）按既定决定**暂不处理**，双轨期结束（批次 4 删除 smoke-test.sh）时自然收敛。

---

### Task 1: helpers 扩展 + `tests/fixtures/` 骨架

**Files:** Modify `tests/helpers/fixtures.bash`、`tests/helpers/common.bash`、`tests/unit/fixtures.bats`；Create `tests/fixtures/README.md` 与 `tests/fixtures/ac/**`

**Interfaces:**
- `make_plan <root> <id> [ac_count=2] [ac_start=1] [style=ref|decl-cn|decl-en]` —— `ref` 行为与批次 0 逐字不变；`decl-cn` 产 `- 覆盖验收：AC-N`；`decl-en` 产 `- Covers: AC-N`。未知 style 必须 `return 1` 并打印（禁止静默 fallback——那是根因 C）。
- `halo_install_fixture <fixture_rel_dir> [dest=$SANDBOX]` —— 把 `tests/fixtures/<rel>/` 整棵树叠加到沙箱（fixture 按项目布局镜像，`halo/specs/…` 与 `tests/…` 一次到位）。源目录不存在直接 `return 1`（fail-closed，不静默跳过）。
- `halo_set_language <lang>` —— `yq -i` 改沙箱 manifest 的 `project.language`，无需还原。
- 导出 `HALO_FIXTURES_DIR`。

> `style` 进构造函数而非 fixtures/：声明行不是「变体」，是 plan 任务的现行强制字段（`plan-lint.sh:226` 对缺它的任务 warn），`ref` 与 `decl-*` 是两种并列的黄金形态。「一个任务声明多条 AC / 声明外部 spec 的 AC / 声明行无 AC token」一律走静态 fixture。
> 两个新函数属「沙箱形态操作」，与 `halo_template_install` 同族放 `common.bash`；fixture **内容**构造留在 `fixtures.bash`。这条分界线是后续批次的准绳。

- [ ] **Step 1（先写测试）**：`tests/unit/fixtures.bats` 追加 3 条——`decl-cn` / `decl-en` 通过 plan-lint 且输出**不含** `no 覆盖验收/Covers line`；`ref`（默认）通过 plan-lint 且输出**含**该 warning。`bash tests/run.sh unit` → FAIL（预期）
- [ ] **Step 2**：实现 `make_plan` 的 `style` 参数，只改任务体那一行标签，其余逐字不动
- [ ] **Step 3**：`common.bash` 加 `HALO_FIXTURES_DIR` 与两个新函数
- [ ] **Step 4**：建 `tests/fixtures/ac/**`（结构见下）。三份迁移 fixture 的正文**逐字**取自 `smoke-test.sh:1372-1437`、`:1498-1566`、`:1709-1758` 与 `ac-coverage-test.sh:61-102`，只做搬运不做措辞调整——措辞里埋着陷阱，改一个字就可能改掉被测语义
- [ ] **Step 5**：写 `tests/fixtures/README.md`：每份 fixture 一行，列「路径 / 对应报告 / 刻意埋的陷阱 / 被哪个 bats 消费」
- [ ] **Step 6**：`bash -n` + `shellcheck --severity=warning` 两个 helper；`time bash tests/run.sh unit` → 12 tests 0 failures，耗时记进 commit message
- [ ] **Step 7: Commit** — `Add declaration-line plan style and static AC fixture matrix`

```
tests/fixtures/ac/
  cross-spec-mentions/          # #14：Non-Goals 散文 + AC-3 单元格 + plan Out-of-scope + RED-1 任务体，四处提 upstream AC-14
  declaration-line/             # runningtime：RED-1 声明 AC-1,AC-2 + 散文否定「不覆盖 AC-3」；RED-2 Covers: AC-3, AC-14；T1 全中文字段
                                #   另含 decl-warn-ac：声明行「覆盖验收：以下条目补充说明」无 AC token
  cross-spec-attribution/       # #8：两 spec 共享测试目录，中文五列表 + 末列反引号测试名
  cross-spec-attribution-absent-decl/   # #8 反向（新增）：声明了不存在的测试
  python-lowercase/             # #5：裸 spec.md（非目录布局）+ 小写 def test_ac；另含 gap 变体与零测试文件变体
```

三条注意：① `python-lowercase` 刻意保留「裸 spec.md 在项目根」的布局（与旧段一致），它同时覆盖「非目录 spec 仍被接受」，且把该 spec 排除在 `spec_select` 候选与 `build_foreign_owned`（`ac-coverage.sh:137-146` 只扫 `$SPECS_ABS`）之外；② 测试文件目录须避开 `ac-coverage.sh:165-176` 的 prune 列表（`tests/`、`pytests/` 安全）；③ A 组（#7/#9）**不建静态 fixture**，用 `make_spec` + 一行派生——变体各只有一个元素，静态化反而让「与黄金形态的差异」不可见。

---

### Task 2: #7 + #9 —— spec-lint AC 查重与断号（含 #7 双向补齐）

**Files:** Create `tests/regression/2026-07-19-spec-lint-ac-cross-reference-duplicate.bats`、`tests/regression/2026-07-26-spec-lint-ac-number-gap.bats`

两份文件头均带 SOP 强制的三行注释（Bug report 路径 + 历史命名说明 / Root cause class: A / Fixed by: `45d5f7f`、`334bdb6`）。

查重（3 条）：

| @test | 断言 | 来源 |
|---|---|---|
| `in-cell AC cross-reference is not a duplicate row` | exit 0；`refute_output --partial "Duplicate AC rows"` | 旧 549-564 |
| `a genuinely duplicated AC row is still reported` | `assert_failure`；`assert_output --partial "Duplicate AC rows: AC-2"` | **新增反向** |
| `a prose AC mention outside the table is not declared` | `assert_output --partial "2 ACs found"` | **新增加强** |

断号（3 条）：

| @test | 断言 | 来源 |
|---|---|---|
| `a non-1 start with contiguous ACs reports no gap` | exit 0；`refute_output --partial "AC number gaps"` | 旧 566-585（拆分） |
| `an in-cell reference to a lower AC creates no phantom gap` | exit 0；同上 | 旧 566-585（拆分） |
| `a real internal AC gap is still reported` | `assert_output --partial "AC number gaps: 13"` | 旧 587-602 |

> 拆分说明：旧断言把「非 1 起点」与「单元格内交叉引用」两个独立元素压在一条里，失败时无法分辨是哪一半坏了。拆成两条是等价超集，不改语义。

派生写法（可直接抄，注意 BSD sed 限制）：

```bash
# #7 正向：AC-2 行的 Then 单元格加交叉引用
sed 's/| Result 2 |/| Result 2 (see AC-1) |/' halo/specs/golden/spec.md > halo/specs/xref-ac/spec.md
# #7 反向：复制 AC-2 整行造真重复（BSD sed 替换串不支持 \n，必须用 awk）
awk '/^\| AC-2 \|/ { print; print; next } { print }' halo/specs/golden/spec.md > halo/specs/dup-ac/spec.md
# #9 正向 a：非 1 起点由构造函数直接产出
make_spec halo/specs global-ac 2 12          # → AC-12, AC-13
# #9 正向 b：非 1 起点 + 单元格内引用更低的 AC-3
sed 's/| Result 13 |/| Result 13 (see AC-3) |/' halo/specs/global-ac/spec.md > halo/specs/global-xref-ac/spec.md
# #9 反向：真内部断号 AC-12, AC-14
sed 's/| AC-13 |/| AC-14 |/' halo/specs/global-ac/spec.md > halo/specs/real-gap-ac/spec.md
```

- [ ] Step 1 写两个文件（`setup_file`: `halo_require_tools; halo_template_install`；`setup`: `halo_sandbox_clone`）
- [ ] Step 2 `bash tests/run.sh regression` → 6 tests 0 failures
- [ ] Step 3 `bash tests/run.sh legacy` 仍绿（本 Task 不删旧段，双轨重叠是有意的）
- [ ] Step 4 Commit — `Migrate spec-lint AC duplicate and gap regressions to bats`

---

### Task 3: #14 —— 跨 spec AC 提及（4 条）

**Files:** Create `tests/regression/2026-08-03-user-report.bats`（`Fixed by: 1f993a4`，Root cause class: A）

| @test | 断言 |
|---|---|
| `task-next ac_refs excludes an upstream spec's AC` | `yq -e '.task_id == "RED-1" and .ac_refs == ["AC-1","AC-2","AC-3"]'` |
| `plan-lint does not demand another spec's AC in plan.md` | exit 0；`refute_output --partial "AC-14"` |
| `ac-coverage counts only declared ACs, not in-cell cross-references` | `assert_output --partial "Spec AC count: 3"` |
| `task-complete ignores a cross-spec AC in a red task body` | exit 0；plan.md 中 `^- \[x\] RED-1:` |

两处改进：
- 旧段第 1 条带注释「task-next runs first: completing RED-1 below would move the pointer to T1」——这正是隐式顺序耦合。bats 下每用例独立沙箱，第 1 条与第 4 条互不影响，**该注释与它描述的约束一并消失，不要搬运**。
- 旧段用 `grep -q '"ac_refs": \["AC-1", "AC-2", "AC-3"\]'` 断言**格式化后的字面量**，脆且属于「断言中间实现细节」。改用 `yq -e` 做语义比较（yq 读 JSON）——等价加强，不是放松。

- [ ] Step 1 写文件（`halo_install_fixture ac/cross-spec-mentions`；第 4 条前置补 `tdd-evidence.sh cross-spec-ac T1 --ac=AC-1 --ac=AC-2 --ac=AC-3 …`）
- [ ] Step 2 `bash tests/run.sh regression` → 10 tests 0 failures
- [ ] Step 3 `bash tests/run.sh` 全绿
- [ ] Step 4 Commit — `Migrate cross-spec AC mention regression to bats`

---

### Task 4: runningtime —— 覆盖声明行 vs 散文提及（12 条）

**Files:** Create `tests/regression/2026-08-07-runningtime-report.bats`（`Fixed by: 3e25d7e`，Root cause class: A 复发 + H 谓词漂移）

旧段（smoke-test:1567-1770）是一条严格时间线：写 AC-1 证据 → 断言失败信息 → 断言 JSON → 补 AC-2 证据（**故意落在 T1 目录**，因为证据树是 spec 级不是任务级）→ 断言成功 → 补 AC-3 → 断言 RED-2 成功 → `--all` 断言依赖前面的完成状态。

**拆解方案：每条用例显式自建前置**，在文件内定义 4 个 builder（不进 helpers——它们是这份报告专有的，进 helpers 会成为下一个「谁在用它」的谜团）：

```bash
decl_evidence_ac1()  # tdd-evidence.sh decl-line-ac RED-1 --ac=AC-1 …
decl_evidence_ac2()  # tdd-evidence.sh decl-line-ac T1    --ac=AC-2 …   # 故意落在 T1 目录
decl_evidence_ac3()  # tdd-evidence.sh decl-line-ac RED-2 --ac=AC-3 …
decl_complete()      # run task-complete.sh decl-line-ac "$1"; assert_success
```

12 条 `@test` 与前置：

| # | @test | 前置 |
|---|---|---|
| 1 | `task-complete names the exact ACs lacking cycle evidence` | `decl_evidence_ac1` |
| 2 | `task-complete --json carries covered_acs and missing_acs` | `decl_evidence_ac1` |
| 3 | `a prose AC mention creates no obligation when a declaration line exists` | `ac1; ac2` |
| 4 | `task-next --task narrows declaration-line ACs to this spec` | `ac1; ac2; complete RED-1` |
| 5 | `task-complete accepts a declaration line carrying a cross-spec AC` | 同上 + `ac3` |
| 6 | `task-next --all lists every task with completion state` | 同上 + `complete RED-2` |
| 7 | `task-next --task reports not-found with a non-zero exit` | 无 |
| 8 | `task-next default next-task selection is unchanged by the new flags` | 同 6 |
| 9 | `plan-lint passes a declaration-line plan without a fallback warning` | 无 |
| 10 | `plan-lint warns without failing when a task has no declaration line` | `make_spec`+`make_plan … ref` |
| 11 | `task-next rejects an empty --task= value` | 无 |
| 12 | `a declaration line without AC ids warns and falls back to the whole-body scan` | 无 |

为什么不用别的方案：把 12 条塞进一个 `@test` 保持原时间线 = 把 smoke-test 的问题原样搬进 bats，失败仍不可归因；用 `setup_file` 建共享状态则不可行——bats 每用例 `BATS_TEST_TMPDIR` 独立，且断言 3/5 本身要写状态。

- [ ] Step 1 定义 4 个 builder，每条用例开头显式调用所需前置
- [ ] Step 2 第 10 条用 `make_plan … ref` 现造无声明行的 plan，**不引用 `red-multi-ac`**（解开对批次 3 fixture 的依赖）
- [ ] Step 3 第 6 条把旧断言加强为三个任务的完整状态（新前置已确定性完成 RED-2）
- [ ] Step 4 `bash tests/run.sh regression` → 22 tests 0 failures
- [ ] Step 5 抽查可归因性：`tests/vendor/bats-core/bin/bats tests/regression/2026-08-07-runningtime-report.bats -f "not-found"` 只跑 1 条且绿
- [ ] Step 6 Commit — `Migrate AC declaration-line gating regression to bats`

---

### Task 5: #8 —— ac-coverage 跨 spec 归属（7 条）

**Files:** Create `tests/regression/2026-07-25-ac-coverage-cross-spec-attribution.bats`（`Fixed by: f60637d`，Root cause class: A + F）

| @test | 对应旧脚本 |
|---|---|
| `alpha gate fails when an AC has no spec-owned test` | `ac-coverage-test.sh:122-126` |
| `alpha AC-1 resolves to alpha's own declared test` | `:127`（Tier1 精确归属） |
| `alpha AC-3 is uncovered, never borrowed from beta` | `:128`（Tier2 跨 spec 隔离，本 bug 的核心方向） |
| `beta gate passes when every AC owns its test` | `:132-136` |
| `beta AC-1 resolves to beta's own test` | `:137` |
| `beta AC-3 resolves to beta's own test` | `:138` |
| `a declared test that does not exist is uncovered, not silently satisfied` | **新增（Tier1 反向）** |

实现要点：`setup` 为 `halo_sandbox_clone; halo_set_language python; halo_install_fixture ac/cross-spec-attribution`；第 7 条额外叠加 `ac/cross-spec-attribution-absent-decl` 覆盖 beta 的 spec.md，断言 `assert_failure` + `yq -e '.findings[] | select(.ac=="AC-3") | .status == "uncovered"'` + message 含 `declared test`。JSON 字段用 `yq -r` 读，**不用 python3**。

- [ ] Step 1 写文件
- [ ] Step 2 `bash tests/run.sh regression` → 29 tests 0 failures
- [ ] Step 3 **不删** `tests/ac-coverage-test.sh`（删除统一在 Task 7），确认 legacy 中它仍 6/6 绿
- [ ] Step 4 Commit — `Migrate ac-coverage cross-spec attribution regression to bats`

---

### Task 6: #5 python 小写（3 条）+ ac-coverage 门禁契约单测（2 条）

**Files:** Create `tests/regression/2026-07-12-ac-coverage-python-lowercase.bats`（`Fixed by: de6c249`，Root cause class: B + F）、`tests/unit/gate-ac-coverage.bats`

regression（3 条）：

| @test | 断言 | 方向 |
|---|---|---|
| `lowercase def test_ac is counted as covered` | exit 0；含 `AC Coverage Matrix`；含 `1/1` | 正向（旧 2008-2035） |
| `an AC with no lowercase test is still reported uncovered` | `assert_failure 1`；矩阵中 AC-1 ✅、AC-2 ❌ | **新增反向 A** |
| `the gate reaches the coverage matrix instead of crashing` | python 项目 + 零测试文件；`assert_failure 1`（**退出码恰为 1**，不是 2/141）；含 `AC Coverage Matrix`；含 `0/1` | **新增反向 B** |

> 反向 B 的意义：#5 的报告有两半——「小写没算上」（正确性）与「`set -euo pipefail` 下硬崩、连矩阵都打不出来」（健壮性）。只断言正向等于只覆盖一半。反向 B 把健壮性变成可观测契约：**「报告未覆盖」与「崩溃」必须可区分**。

unit（2 条，非 bug 绑定的门禁出口语义；文件头按约定注明调用方：`delivery/pipeline.sh`、`release-check`、`summary-draft.sh`）：

| @test | 断言 | 来源 |
|---|---|---|
| `ac-coverage exits 1 and names uncovered ACs when no tests exist` | `assert_failure 1`（**收紧**）；含 `uncovered` | 旧 1987-1996 |
| `ac-coverage --json-out writes ac_total, ac_uncovered and per-AC findings` | `assert_failure 1`；`yq -e '.gate=="ac-coverage" and .metrics.ac_total==2 and .metrics.ac_uncovered==2 and (.findings\|length==2)'` | 旧 1998-2006 |

> **收紧的宽松兜底**：旧 1992-1996 有个 `else pass "ac-coverage ran (exit=$AC_EXIT)"` 分支——任何非 0 非 1 的退出码（包括崩溃）都会被记为 PASS，是把缺陷行为固化成期望值的典型。新用例断言 `assert_failure 1`，兜底分支不迁移。

- [ ] Step 1 写两个文件（regression 用 `halo_set_language python` + `halo_install_fixture ac/python-lowercase`；unit 用 `make_spec halo/specs uncovered-go 2`，保持 Go 语言与零测试文件）
- [ ] Step 2 `bash tests/run.sh` → unit 14 + regression 32 全绿
- [ ] Step 3 Commit — `Migrate python lowercase AC regression and ac-coverage gate contract`

---

### Task 7: 等价性验证——21 条变异（完成定义的核心）

**Files:** 无（验证 Task，零代码改动）

SOP 的「先红后绿」要求在未修复代码上确认 FAIL，但本批次的 6 个 bug 早已修复，无法回退。等价且更强的做法是**对修复点注入定向变异，确认预期用例变红**——这正是设计文档批次 1 完成定义（「旧段注入缺陷时新用例也红」）的含义。

**验收门槛：每条被迁移的断言都必须在下表中至少出现一次作为「期望变红」。** 若某条断言没有任何变异能点亮它，说明它不具判别力，必须回到对应 Task 加强（而不是放行）。

**变异协议（强制，每条严格执行）：**

```bash
git status --porcelain                          # 1. 必须无输出
#  2. 手工编辑单行（或 awk 写临时文件后 mv——禁止 sed -i）
tests/vendor/bats-core/bin/bats tests/regression/<file>.bats    # 3. 记录 RED
git checkout -- harness-template/               # 4. 回滚
git status --porcelain                          #    必须无输出
tests/vendor/bats-core/bin/bats tests/regression/<file>.bats    #    必须全绿
```

**变异对照表**（行号已逐条实测核对于 `1e5fbc8`；路径在 `harness-template/halo/kernel/` 下）：

| # | 目标 | 变异 | 期望变红 |
|---|---|---|---|
| M1 | `_lib.sh:203` | `spec_declared_acs` 的行首锚定+取首格 → 全文 token 扫描 | #7-1、#7-3、#9-2、#14-3 |
| M2 | `spec-lint.sh:172` | `uniq -d` → `TABLE_DUPES=""` | #7-2（反向） |
| M3 | `spec-lint.sh:160` | 恢复「必须从 1 起」：`[[ -n "$PREV" && … ]]` → `[[ "$num" -ne $((${PREV:-0}+1)) ]]` | #9-1、#9-2 |
| M4 | `spec-lint.sh:166` | `if [[ -z "$GAPS" ]]` → `if true` | #9-3（反向） |
| M5 | `_lib.sh:219` | `narrow_acs_to_declared` 去掉收窄，原样返回全部提及 | #14-1/2/4、rt-4、rt-5 |
| M6 | `ac-coverage.sh:152` | 调用点绕过共享谓词，自己 grep（证明确实走共享定义，防根因 H 漂移） | #14-3 |
| M7 | `task-complete.sh:239` | 失败信息删掉 `; missing: …` | rt-1 |
| M8 | `_lib.sh:233` | `(覆盖验收\|Covers)` → `(Covers)`（中文标签失效） | rt-2、rt-3、rt-9 |
| M9 | `_lib.sh:244` | `[[ -n "$decl" ]] && grep -qE 'AC-…'` → `[[ -n "$decl" ]]`（恢复谓词漂移） | rt-12 |
| M10 | `plan-lint.sh:226` | `if ! task_has_ac_declaration` → 去掉 `!`（warn 方向反转） | rt-9、rt-10 |
| M11 | `task-next.sh:32-33` | 删掉 `--task=` 空值/格式校验 | rt-11 |
| M12 | `task-next.sh:191` | not-found 分支 `exit 1` → `exit 0` | rt-7 |
| M13 | `task-next.sh:239` | `--all` 收集只列未完成任务 | rt-6 |
| M14 | `task-next.sh:260` | 默认选择返回第一个任务而非第一个未完成任务 | rt-8 |
| M15 | `_lib.sh:255` | `task_covered_acs` 删掉声明行分支，永远全文扫描 | rt-2、rt-3 |
| M16 | `ac-coverage.sh:228` | 删掉 `comm -23` 的 FOREIGN_OWNED 扣除 | #8-2、#8-3 |
| M17 | `ac-coverage.sh:220-222` | Tier1 未命中改为落回 Tier2 数字兜底 | #8-7（反向） |
| M18 | `ac-coverage.sh:185` | `grep -ioE` → `grep -oE`（去掉大小写不敏感） | #5-1、#5-2 |
| M19 | `ac-coverage.sh:240` | `if [[ -n "$func_name" ]]` → `if true` | unit-1、unit-2、#5-2、#8-3 |
| M20 | `ac-coverage.sh:84` | `write_gate_json` 的 `ac_uncovered` 硬编码 0 | unit-2 |
| M21 | `ac-coverage.sh:185` | 合成变异：token 正则换成必不匹配的 `'ZZ[0-9]+'` **且**删 `\|\| true` → pipefail 下硬崩 | #5-3（反向） |

覆盖核对：#7 三条 ← M1/M2；#9 三条 ← M1/M3/M4；#14 四条 ← M1/M5/M6；runningtime 十二条 ← M5/M7/M8/M9/M10/M11/M12/M13/M14/M15；#8 七条 ← M16/M17/M19；#5 三条 ← M18/M19/M21；unit 两条 ← M19/M20。**34/34 均有对应变异。**

- [ ] Step 1 前置：`git status --porcelain` 无输出，`bash tests/run.sh` 全绿
- [ ] Step 2 逐条执行 M1-M21，记录「变异编号 / 目标行 / 实际变红的 @test / 是否与期望一致」
- [ ] Step 3 判定：实际变红 ⊇ 期望变红 → 通过；某条期望用例未变红 → **该断言无判别力**，回到对应 Task 加强后重跑该变异；大量非预期变红不算失败（共享谓词本就有爆炸半径），但要记录，作为批次 2 契约单测的输入
- [ ] Step 4 收尾再次 `git status --porcelain`（无输出）+ `bash tests/run.sh`（全绿）
- [ ] Step 5 Commit（若 Step 3 触发断言加强则有代码改动，否则 `--allow-empty` 承载记录），正文逐条列出 21 条变异及其实际变红清单

---

### Task 8: 删旧段 + 收口 `tests/run.sh`

**Files:** Modify `tests/smoke-test.sh`（纯删除）、`tests/run.sh`；Delete `tests/ac-coverage-test.sh`

**删除区间**（边界锚文本已实测核对；**必须自下而上删**，否则先删的会移位后面的行号）：

| 顺序 | 行区间 | 起始锚 | 结束锚 |
|---|---|---|---|
| 1 | **1987-2035** | `AC_EXIT=0` | python 覆盖块的 `fi` |
| 2 | **1368-1771** | `# A spec that cross-references an UPSTREAM spec's AC-14 — in prose, inside its own` | `declaration line without AC ids` 块的 `fi` 及其后空行 |
| 3 | **549-603** | `# Regression: an AC cell that cross-references another AC (e.g. "see AC-1") must` | `rm -rf "$SANDBOX/halo/specs/real-gap-ac"` 及其后空行 |

区间 2 是一整块：B 组（1368-1490）与 C 组（1491-1771）在文件中连续，中间无残留代码。区间 1 **保留** 1985-1986 的 `# ── 7. …` 与 `echo`：后续 2037+ 仍是 drift/compliance/pipeline 的断言，标题只是略陈旧；冻结纪律下改写 echo 属于「加」，该标题在批次 2 迁 drift-check 时自然消失。

**残余顺序耦合核查**（本 Task 风险最高的部分，已逐项追查）：

1. **`modern-feature` 状态推进链** ✅ 不受影响。A 组只在它还是 `drafted` 时做**只读 sed 派生**，产物落独立目录且块内 `rm -rf`；B/C/E 组不碰它。
2. **spec 自动发现**（`smoke-test.sh:2895` 的 `pipeline.sh --only=spec-lint` 无 `--spec`）⚠️ 需显式核查，**结论安全**：`spec-select.sh:76` 把 `verified` 归 rank 1、其余 rank 0，`:95` 按 rank 升序 + `updated_at` 降序排，`:103` 在「同 rank + 同 updated_at」时返回 rc=2。被删的三个 spec 的 `updated_at` 全是硬编码 `2026-06-26T00:00:00Z`，而 rank-0 唯一胜出者 `missing-evidence` 携带 `spec-status.sh` 写入的真实时间戳，严格大于它们——删掉更老的同分候选不改变胜出者也不制造新平局。**验证方式**：删除后断言 `:2896-2903` 与 `:2917-2929` 两条仍绿。
3. **§7 依赖「沙箱内无 Go 测试文件」** ✅ 旧 §7b 唯一写入的是 `.py` 文件，删掉只会更干净；后续依赖此前提的 `:2058`（要求 `ac_total==2 and ac_uncovered==2`）仍绿即为证。
4. **变量泄漏** ✅ `AC_*` / `PY_*` / `CROSS_*` / `DECL_*` 全部只在被删区间内定义与使用。
5. **manifest 语言的临时改写**（旧 `:2023-2027`）✅ 随区间 1 消失，是全局可变状态的净减少。

- [ ] **Step 1** 按上表**自下而上**删除三个区间
- [ ] **Step 2** `bash -n tests/smoke-test.sh && shellcheck --severity=warning tests/smoke-test.sh`
- [ ] **Step 3** 残余引用核查（必须无输出）：`grep -n 'xref-ac\|global-ac\|real-gap-ac\|cross-spec-ac\|decl-line-ac\|decl-warn-ac\|AC_JSON\|AC_OUTPUT\|PY_SPEC\|PY_TEST_DIR\|CROSS_\|DECL_' tests/smoke-test.sh`；同时确认 `red-multi-ac` / `red-many-ac` **仍在**（属批次 3）
- [ ] **Step 4** `git rm tests/ac-coverage-test.sh`；删 `tests/run.sh:43-46` 的 ac-coverage-test 那条腿；`bash -n` + shellcheck
- [ ] **Step 5** PASS 计数核对：`bash tests/smoke-test.sh | tail -5`。删除的是 **22 条运行时断言**（3 + 16 + 3；区间 1 有 4 个 `pass` 分支，其中两个是同一断言的 if/else 两侧）。基线已实测：**167 / 167**（`1e5fbc8`，macOS）。**期望删除后为 `✅ 145 / 145`。若数字不是 145，先查是哪条断言意外消失/新增，禁止直接改期望值。** 中间态可分步核对：删完区间 1 应为 164，删完区间 2 应为 148
- [ ] **Step 6** `bash tests/run.sh` + `time bash tests/run.sh unit` + `time bash tests/run.sh regression`：unit 14 + regression 32 = 46 条全绿，legacy 只剩 smoke-test，退出码 0
- [ ] **Step 7: Commit** — `Delete migrated AC segments from smoke-test and retire ac-coverage-test.sh`，正文记录 PASS 计数变化、ac-coverage-test 6/6 → bats 7 条、以及核查点 2 的证据

> **耗时逃生阀**（仅在实测超标时启用，不预先做）：若 `bash tests/run.sh` 的 bats 部分总耗时超过 90 秒，另开一个 Task 把 `halo_template_install` 的产物提到 `$BATS_SUITE_TMPDIR/template`（整轮运行共享），用 marker 文件做「已装则跳过」。`tests/run.sh` 不带 `--jobs`，串行下无需加锁。

---

### Task 9: 文档收口

**Files:** Create `docs/bug_report/INDEX.md`；Modify `tests/README.md`、`docs/superpowers/plans/2026-08-07-halo-test-batch0-bats-skeleton.md`

- [ ] **Step 1** `docs/bug_report/INDEX.md`（中文）：一张表覆盖**全部**已处置报告（不只 AC 系列）——报告路径 / 规范化 slug / 上报日期 / 修复提交 / 修复日期 / 根因类别 / 对应 `tests/regression/*.bats` / analysis 状态与备注；未迁移的填「批次 N 待迁」。开头写清「决定一」的三条与批次 3 的对拍规则
- [ ] **Step 2** `tests/README.md` 增补四节：① regression 命名规则（两条分支 + INDEX.md 兜底）；② fixtures/ 与构造函数的三档分界线（点名「BSD sed 替换串不支持 `\n`，复制行用 awk」）；③ 等价性验证（变异测试）——对已修复的历史 bug，SOP 的「先红后绿」以变异测试代替，给出四步协议与「变异不得进入提交」红线；④ 批次 3 待办注记：`halo_slow_yq_path` 预告接口（把 SIGPIPE 竞态确定化，蓝本 `smoke-test.sh:1338-1356`；本批次不实现——无调用方，YAGNI）
- [ ] **Step 3** 更新 `tests/README.md` 目录表中 `regression/`、`fixtures/` 两行的批次标注为已启用，并补当前用例数
- [ ] **Step 4** 同步批次 0 计划文档：`tests/run.sh` 代码块改为去掉 ac-coverage-test 腿后的最终形态，「偏离记录」表加一行——该文档正文声称与仓库文件一致，不同步就成了假文档
- [ ] **Step 5** `bash tests/run.sh && git diff --check`
- [ ] **Step 6: Commit** — `Add bug report index; document regression naming and mutation testing`

---

## 实现观察（本批次**不修**，仅记录）

| # | 位置 | 观察 | 归属 |
|---|---|---|---|
| O-1 | `ac-coverage.sh:127` + `:138` | node/js/ts 的 `DECL_TOKEN_REGEX` 为空串 → `build_foreign_owned` 直接 `return 0` → **node 项目完全没有 #8 的跨 spec 归属保护**，同号 `test_acN` 会重新静默借用。#8 的修复对 node 不生效——真实功能缺口 | 独立 bug 报告 + 批次 3（需走完整 SOP） |
| O-2 | `ac-coverage.sh:185` 的 `\|\| true` | 该守卫在现行三种 `FUNC_REGEX` 下**不可达**（三者都必然在匹配行含 AC+数字）。是防御性冗余，只有放宽 FUNC_REGEX 才会用到。故 #5-3 只能断言可观测契约（退出码恰为 1 + 打印矩阵） | 批次 3 meta-lint 的 pipefail 规则可列为「正确但当前不可达」正样本 |
| O-3 | `task_body()` 四份逐字副本（`task-evidence-lint.sh:49`、`task-complete.sh:60`、`task-next.sh:63`、`plan-lint.sh:87`） | 根因 H。本批次 rt-9/rt-10 通过两个调用方间接对齐了 `task_has_ac_declaration`，但 `task_body` 本身仍可各自漂移 | 批次 3 meta-lint 重复定义检测 |
| O-4 | `spec-select.sh:103` | smoke-test 沙箱能通过自动发现断言，靠的是 `missing-evidence` 恰好携带真实时间戳而唯一胜出——一个**未被任何断言保护的隐性前提**。未来增删 `halo/specs` fixture 都可能把它推成 rc=2 | 批次 2 的 `find_spec` 契约单测应固化「同 rank 同 updated_at → rc=2」与「时间戳唯一 → rc=0」 |
| O-5 | `smoke-test.sh:2699` | `.gitignore` heredoc 仍列 `py-ac-coverage/`，Task 8 后成为死条目；冻结纪律下不改 | 批次 4 删除 smoke-test 时消失 |
| O-6 | `smoke-test.sh:1985-1986` | `── 7. AC-coverage gate ──` 标题在 Task 8 后已无对应内容；冻结纪律下不改写 | 批次 2 迁 drift-check 时消失 |

---

## 验证（端到端）

批次 1 完成定义：

| 条件 | 验收证据 |
|---|---|
| 新 bats 用例全绿：regression 32 条，unit 由 9 增至 14 条 | `bash tests/run.sh` 退出码 0，suite 计数与本计划一致（46 条） |
| 每条被迁移断言都有对应变异且验证过 | Task 7 的 commit message 中 21 条变异记录，「期望变红 ⊆ 实际变红」逐条成立 |
| 旧段已删且未破坏残余用例 | `bash tests/smoke-test.sh` → `✅ 145 / 145`（基线 167 实测，−22）；`tests/run.sh` 的 ac-coverage-test 腿已移除；Task 8 Step 3 的残余引用 grep 无输出 |
| `harness-template/` 零改动 | `git diff --stat 1e5fbc8..HEAD -- harness-template/` 为空 |
| 静态检查全绿 | `bash -n` + `shellcheck --severity=warning` 覆盖 `tests/run.sh`、`tests/smoke-test.sh`、`tests/helpers/*.bash` |
| 命名与 SOP 落地 | `docs/bug_report/INDEX.md` 存在；6 个 regression 文件均带固定三行文件头；`tests/README.md` 已写入命名规则、fixtures 分界线、变异测试协议 |
| CI 双平台绿 | Task 0 已首次闭合；批次 1 推送后再次 `gh run watch` 确认双平台绿。macOS 侧重点看 BSD 行为：`ac-coverage.sh:228` 的 `comm -23 <(…) <(…)` 与 `:206/:210/:218` 的 awk 是最可能出问题的点 |

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

## 明确不做（后续批次）

- `red-multi-ac`（#10 量词）、`red-many-ac` + 慢 yq shim（#11 SIGPIPE）→ 批次 3
- `_lib.sh` 函数级契约单测（`find_spec` / `narrow_acs_to_declared` / `spec_declared_acs` / `task_has_ac_declaration`）→ 批次 2/3
- drift-check 系列（§7c）与 §7 残余 gate JSON → 批次 2
- meta-lint 五条规则、报告↔测试对应检查、`release-check.sh` 扩展 → 批次 3
- O-1（node 无跨 spec 归属保护）的修复 → 需先走完整 SOP（报告 + analysis + 回归 + 修复同批提交）
- CI 两个 workflow 的 smoke-test 重叠合并 → 批次 4 双轨期结束时

---

## 批次 1 完成记录（2026-08-16）

| 条件 | 状态 | 证据 |
|------|------|------|
| 新 bats 用例全绿 | ✅ | `bash tests/run.sh` 退出码 0：unit 18 条（9 → 18）、regression 37 条、smoke-test 145/145，总耗时 64 秒 |
| 每条被迁移断言都有对应变异且验证过 | ✅ | 22 条变异，**34/34** 用例被点亮，记录见 `8c3b118` |
| 旧段已删且未破坏残余用例 | ✅ | smoke-test `167 → 145`（−22，与预测一致）；三处顺序耦合逐项核查通过；残余引用 grep 无输出 |
| `harness-template/` 零改动 | ⚠️ 一处，有充分理由 | `1a9773e` 修了 CI 抓到的 `init.sh` 缺陷（不在 `harness-template/` 下，是根目录安装器）。除此之外 kernel 零改动，变异全部回滚 |
| 静态检查全绿 | ✅ | `bash -n` + `shellcheck --severity=warning` 覆盖 run.sh / smoke-test.sh / helpers |
| 命名与 SOP 落地 | ✅ | `docs/bug_report/INDEX.md`；7 个 regression 文件均带三行文件头；`tests/README.md` 已写入命名规则、三档分界线、变异测试协议、批次 3 待办 |
| CI 双平台绿 | 待推送后确认 | 批次 0 的修复已验证过双平台（run 31924319231） |

### 与计划的偏离

| 项 | 计划 | 实际 | 原因 |
|---|---|---|---|
| Task 0 | 推送即闭合 | 首跑 macos 红，先修 `init.sh` 缺陷才闭合 | CI 抓到真缺陷，见批次 0 计划 Task 4 Step 3 |
| `tests/regression/` 启用时机 | 批次 1 Task 2 | 提前到 Task 0 | 上面那个缺陷的回归用例要落地 |
| 用例总数 | 34 | 34 + 5（init 缺陷）+ 5（helper 自测）= unit 18 + regression 37 | 计划外产出，均有对应报告或自测职责 |
| JSON 数组断言写法 | `yq -e '.ac_refs == [...]'` | `join(",")` 比较 | 本仓 yq 是 mikefarah v4，表达式语言不是 jq，数组字面量比较静默求值为 false。已写进 `tests/README.md` |
| 变异条数 | 21 | 22 | 前 21 条只点亮 30/34。缺的 4 条全是「正向归属」方向，原因是变异集**只有放松方向没有收紧方向**，不是断言没判别力。补 M22（Tier 1 存在性检查恒不命中）后精确点亮那 4 条 |
| 慢 yq shim | 预告接口 | 同左，未实现 | 无调用方（#11 属批次 3） |

### 实测发现的覆盖空洞（不在本批次修）

删掉 `ac-coverage.sh:142` 的 `[[ "$f" -ef "$SPEC" ]] && continue`（自跳过），
让一个 spec 自己声明的测试被算成「兄弟 spec 拥有」——**一条测试都不红**。
旧的 smoke-test 与 ac-coverage-test 同样没守它，不是本次迁移引入的。
要触发需要「一条 AC 声明了测试、另一条 AC 依赖数字兜底且候选恰是自己声明的 token」
的 fixture，属契约单测范畴 → **批次 2**（与 `find_spec` / `narrow_acs_to_declared` 同批）。

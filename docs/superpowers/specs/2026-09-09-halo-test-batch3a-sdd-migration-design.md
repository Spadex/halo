# 批次 3a 设计：SDD / context / delivery 三簇迁移 + 契约单测其余三项

日期：2026-09-09
状态：设计已定，待写实施计划
基线：**待 Task 0 确定**（当前 `main` = `c093b71`，另有 5 个未合并提交在 `fix/2026-08-25-ac-coverage-pipefail-and-compliance-fail-open`）

> 本文档全部数字与行号均为实测（`grep` / `awk` / `sed` 直接跑在工作树上）。
> 凡属静态阅读推断而未实测的结论，就地标注「**推断**」。

---

## 为什么要拆出 3a

设计文档 `docs/superpowers/specs/2026-08-07-halo-test-system-design.md:160` 把批次 3 定义为：

> SDD 门禁系列（§6d、SIGPIPE、learn-draft §9c）+ 契约单测其余三项（`task_has_ac_declaration`、AC 归属、模式解析链）+ meta-lint 五条规则上线

但批次 2 收官后，挂在「批次 3」名下的实际存量远不止这些。逐项清点后是四类**性质完全不同**的工作：

| 类 | 内容 | 体量 |
|---|---|---|
| A 测试迁移 | smoke-test §6c–§9c 全部残余，加两份待迁旧报告 #10 / #11 | 70 条断言 |
| B 契约单测其余三项 | `task_has_ac_declaration`、AC 归属、模式解析链 | 3 个新文件 |
| C meta-lint 子系统 | 五条规则 + `allowlist.txt` + `meta-test.bats` 双向自测 + 报告↔测试对应检查 + `release-check.sh` 扩展 | 全新目录 `tests/meta/` |
| D 生产缺陷（各走完整 SOP） | O-1、O-7、O-13、O-14、O-15、O-16、O-17、O-18 八条，加噪声清单余下 5 处 / 4 组 | 12+ 条 |

作为标尺：**批次 2 只做了 A 的一小部分 + B 的两项，用掉 12 个 Task、19 个提交、74 条变异。**

### 拆分的决定性理由：A/B/C 与 D 的纪律互斥

A/B/C 的硬纪律是「`harness-template/` 与 `prismspec/` 零改动」，而 **D 的本质就是改这两个目录**。

这不是洁癖。迁移批次的完成定义核心是**变异等价性验证**——往实现里注入缺陷，看新断言是否变红。如果同一批次里既有人改实现修缺陷、又有人跑变异验证，「测试变红」这个信号就同时有两个可能来源，整批变异的证据链一起贬值。批次 2 专门把 O-1 从「顺手修掉」拦下，理由写在它的完成记录表里：

> **O-1 未被顺手修掉是「冻结区零改动」这条的一部分。**

**决定：批次 3 拆为 3a（A + B，本文档）、3b（C，meta-lint 上线）、3c（D，生产缺陷 SOP 批）。**
设计文档批次表相应更正（Task 18 负责）。批次 2 已就 §9b 归属改过一次该表，有先例。

### 顺带修正一处未登记的空档

**smoke-test §6c「SDD helper scripts」（20 条断言）此前不属于任何批次。** 设计文档批次 3 行只点名 §6d / SIGPIPE / §9c；批次 2 计划的「范围边界」表 12 行也没有它。它既不在批次 3 也不在批次 4。本批次把它收进 3a 并在 Task 18 补登该表。

---

## 一、范围与终态

### 迁移对象（实测边界）

| 分节 | 行区间 | 断言数 | 内容 |
|---|---|---|---|
| §6c | `635-918` | 20 | SDD helper scripts（task-next / plan-lint / spec-status / task-complete / task-brief / review-package / tdd-evidence / task-evidence-lint / prismspec lint） |
| §6d | `919-1525` | 17 | Per-task execution mode，含 `red-multi-ac`（#10 量词，`:1112-1203`）与 `red-many-ac` + 慢 yq shim（#11 SIGPIPE，`:1205-1310`） |
| §7 残余 | `1526-1837` | 22 | pipeline gate JSON / loop state / escalation（6）· learn-draft + knowledge（5）· failure-category（4）· outcome-\* / eval-\*（7） |
| §8 | `1838-1903` | 6 | Context knowledge backend，含 `:1878-1889` 的 64KB 管道缓冲区断言 |
| §9 | `1904-1920` | 2 | Spec-lock acquire / release |
| §9c | `1921-1998` | 3 | Learn draft promotion shape |
| **合计** | **`635-1998` 连续** | **70** | |

**这六节在文件里是连续的**（实测：`§6c` 起于 `:635`，`§9c` 止于 `# ── Summary ──` 之前的 `:1998`）。因此删旧段是**一个区间**，不是批次 2 那样的三段。`:1999` 起的 Summary 块原样保留。

### 终态与期望值

- smoke-test 运行时断言 **122 → 49**。**两端都是实测，不是推算。**

  | 端 | 命令 | 结果 |
  |---|---|---|
  | 基线 | `bash tests/smoke-test.sh` | `✅ 122 / 122` |
  | 删后 | 构造 `sed -n '1,634p'` + `sed -n '1999,2009p'` 拼成的版本，置于 `tests/` 下运行 | `✅ 49 / 49` |

  探针文件跑完即删，`git status --porcelain` 复核为空（除本设计文档本身）。

  > **静态推算在这里对不上，所以不采用。** `grep -c 'pass "'` 得静态站点 113（§1–§6 占 43、本批次迁走 70），加上两个循环的运行时增量——`:236`（§3，8 个 slash command，+7）与 `:865`（§6c，4 个 task_id，+3）——应得 123 而非 122，差 1。差值来源未查（**推断**：某个 `pass` 站点在当前沙箱形态下不可达）。**实测值 49 不依赖这条推算**，此处记录只为让后人别再从静态数推一遍还以为自己算错了。

- **删完不符就查，禁止改期望值**（批次 2 Task 10 纪律）。Task 0 需在最终基线（合并 fix 分支后的 `main`）上重跑一次两端，确认仍是 122 / 49——那 5 个提交改过 `compliance.sh:42` 的退出方向，虽然 `tests/smoke-test.sh` 全文 `grep -c "compliance.sh"` = 0（噪声清单实测）故不应受影响，但基线换了就得重测。
- 收官后 smoke-test 只剩 §1–§6（语法检查 / install / init / install --init / 空 pipeline / spec-lint 现代布局），恰好等于设计文档给批次 4 的定义「E2E 主干迁移」。
- **O-12 随之闭合**：`── 7. AC-coverage gate ──` 标题在 `:1526`，随本区间一并删除。批次 1 的 O-6 预测它在批次 2 消失、批次 2 更正为 O-12 顺延至此。

### 迁移映射

判据：**有 bug 报告可挂的进 `regression/`，其余按被测脚本进 `unit/`。**

#### 进 `tests/regression/`（3 个条目）

| 目标 | 条数 | 来源 | 报告 |
|---|---|---|---|
| `2026-07-31-sdd-gate-defects/`（**目录形态**：`per-task-mode.bats`、`red-task-ac-quantifier.bats`、`evidence-mode-chain.bats`） | 4 | §6d 的逐任务模式三条（`task-complete` / `task-evidence-lint` 认 plan 模式、`task-complete` 认 tdd 模式）+ `red-multi-ac` 量词一条（`:1112-1203`） | #10。其 analysis 含「缺陷 1 逐任务模式被证据门禁丢弃」「备注项：RED 任务的 AC 覆盖被放宽」「顺带统一：证据门禁的模式解析链」三条互不相干的已修缺陷 → 按批次 2「决定一」用目录形态承载 |
| `2026-08-02-tdd-cycle-evidence-sigpipe.bats`（平铺） | 1 | §6d 的 `red-many-ac` + 慢 yq shim（`:1205-1310`） | #11，单缺陷 |
| `2026-08-03-halo-gate-findings_2/learn-draft-promote-shape.bats` | 3 | §9c 全节 | #15 §3.3。**批次 2「决定一」预留的位置，目录已存在**，本批次补齐 |
| **小计** | **8** | | |

**慢 yq shim 必须原样搬运。** 它是设计文档「非确定性缺陷必须确定化：竞态类 bug 不允许重复跑碰运气」这条入库纪律在全库的**唯一现存实例**——一个逐行 `sleep 0.05` 输出 `.ac_ids[]?` 的 `yq` 替身，让早退管道消费者的 SIGPIPE 从概率事件变成 100% 触发。搬运时只改沙箱路径，不改逻辑。

这两个条目同时闭合 `docs/bug_report/INDEX.md:51`（#10）与 `:52`（#11）的「批次 3 待迁」。

#### 进 `tests/unit/`（新增三族命名，12 个文件）

沿用批次 2 已建立的两族（`lib-*` = `_lib.sh` 函数契约、`gate-*` = 门禁出口语义），新增 `sdd-*` = SDD 脚本出口语义、`context-*` = knowledge / learn-draft、`delivery-*` = pipeline / eval / outcome。

| 文件 | 条数 | 来源 |
|---|---|---|
| `sdd-spec-status.bats` | 10 | §6c 状态机推进 / 事件记录 / 阻断条件（7）+ §6d 审计链（3） |
| `sdd-task-complete.bats` | 2 | §6c 无证据拒绝 + 标记完成 |
| `sdd-task-evidence.bats` | 3 | §6c tdd-evidence 结构 ×2 + task-evidence-lint |
| `sdd-plan-lint.bats` | 3 | §6c AC 溯源通过 + §6d 拒绝不可溯源 / 拒绝不完整任务 schema |
| `sdd-task-brief.bats` | 2 | §6c task-brief ×2 |
| `sdd-review-package.bats` | 2 | §6c review-package ×2 |
| `sdd-task-next.bats` | 2 | §6c 解析首个 red 任务 / 报告计划完成 |
| `sdd-summary-and-history.bats` | 6 | §6d summary-draft / summary-learn-draft ×2 / spec-history / review-summary ×2 |
| `prismspec-lint.bats` | 2 | §6c plan 契约 + §6d 完整制品契约 |
| `context-learn-draft.bats` | 4 | §7 的 require-review / knowledge-review / promote / discard |
| `context-knowledge.bats` | 8 | §7 的 knowledge-lint ×2 + §8 全 6 条 |
| `delivery-eval-evidence.bats` | 18 | §7 的 pipeline gate JSON / loop state / escalation / summary-draft eval / failure-category ×3 / outcome-\* ×2 / eval-\* ×7 + §9 spec-lock ×2 |
| **小计** | **62** | §6c 20 + §6d 12 + §7 残余 22 + §8 6 + §9 2 |

**加总核验**：`unit` 62 + `regression` 8 = **70** = 迁移对象表的合计。三张表任一改动都必须重新对上这个数——批次 2 的复核记录里，噪声清单初版正是栽在「两个近似值掩盖了对不上账」。

**逐文件条数是设计期的静态映射，实施计划按 `setup` 形态复核后可微调**，但三张表的加总恒等关系不可破。

`sdd-review-package.bats` 与批次 2 的 `regression/2026-08-03-halo-gate-findings/review-package-scope.bats` **分层**：后者守 #12 §5 的范围缺陷，前者守生成契约。两个文件头互指。

`delivery-eval-evidence.bats` 的 17 条偏大。**是否拆分由该 Task 的实施者按 `setup` 形态是否共用判定，并在报告中说明理由**——不预先切死。依据是 `tests/README.md` 已成文的「只服务单个文件的前置构造函数留在该文件里」优先于通用的「消除重复」。

---

## 二、契约单测其余三项

### 障碍：「模式解析链」没有单一被测对象

批次 2 的两项契约单测（`find_spec`、`narrow_acs_to_declared`）都能用 `lib_run` 直接打 `_lib.sh` 的单一实现。第三项打不了：**`execution_mode` 的四份定义没有一份在 `_lib.sh` 里**——

| 位置 | 读 spec 的方式 | 回退条件 |
|---|---|---|
| `plan-lint.sh:111-117` | `grep -Eim1 '^execution_mode:[[:space:]]*(plan\|tdd)'`，**无 `-f "$spec"` 守卫** | `[[ -n "$value" ]]` |
| `task-next.sh:90-98` | 同上，**有**守卫 | `[[ -n "$value" ]]` |
| `task-complete.sh:80-88` | `frontmatter_value`（awk 解析 `---` 块，只认块内） | `[[ "$value" == "plan" \|\| "$value" == "tdd" ]]` |
| `task-evidence-lint.sh:69-77` | 同上，与 `task-complete` 逐字相同 | 同上 |

**实测对拍**（四份函数各自抽出独立可调用，喂同一组 spec）：

| # | spec 形态 | plan-lint | task-next | task-complete | task-evidence-lint |
|---|---|---|---|---|---|
| ① | front-matter 块内 `execution_mode: tdd` | `tdd` | `tdd` | `tdd` | `tdd` |
| ② | `execution_mode: tdd` 写在 front-matter 块**外** | `tdd` | `tdd` | **`unknown`** | **`unknown`** |
| ③ | 块内 `execution_mode: tddx`（前缀污染） | **`tddx`** | **`tddx`** | `unknown` | `unknown` |
| ④ | 四处全落空 | `unknown` | `unknown` | `unknown` | `unknown` |

形态 ② 是噪声清单规则 4 已登记的漂移。**形态 ③ 是本次实测新发现、清单未登记的第三处分歧**：阵营 A 的正则 `(plan|tdd)` 匹配 `tddx` 的 `tdd` 前缀，`sed` 剥掉标签后把整个 `tddx` 当值返回；阵营 B 的 `frontmatter_value` 拿到 `tddx` 后被 `== "plan" || == "tdd"` 拒绝，继续回退直至 `unknown`。

### 处置：改写成「齐平遍历」形态的漂移防线

一条用例循环四份实现，断言它们在同一输入上给出**相同结果**——沿用批次 2 末尾建立的 `unit/gate-skip-honesty.bats` 写法（一条用例遍历四个门禁，而不是四份手写副本）。这样它直接成为**根因 H 的机器防线**：任何一份将来被单独改动，齐平断言立刻红。

噪声清单「待定夺清单」第 13 条问的正是这种形态要不要成为同类契约的默认写法。**本批次用它，并把结论写回清单。**

边界必须写死，因为四份**现在就已经漂移**：

1. **只在四份行为一致的输入域上断言齐平**——形态 ① 与 ④。
2. **形态 ② 与 ③ 是已知分歧，不写用例、不反向断言。** 反向断言等于把缺陷固化成期望值；批次 2 对 O-14 的裁定原文是「明令不许反向断言 detail 为空」，同一条纪律适用。
3. 两处分歧逐条写进文件头并指向 3c。分歧的收敛属 3c——那是行为变更，选哪个阵营都会改变一半脚本的真实行为，噪声清单「待定夺 #6」正悬着这个问题。

### 三项的分层判据与边界

| 文件 | 被测 | 守什么 | 明令不碰 |
|---|---|---|---|
| `unit/lib-task-declaration.bats` | `_lib.sh:231` `ac_declaration_lines` · `:241` `task_has_ac_declaration` · `:253` `task_covered_acs` | 声明行的两种合法标签（`覆盖验收` / `Covers`）；有声明行时**只读声明行**、无声明行时回退全身扫描；`:241` 与 `plan-lint.sh:226` 的谓词**同真同假** | 不断言 `narrow_acs_to_declared` 的收窄语义——批次 2 的 `lib-ac-declaration.bats` 已守 |
| `unit/gate-ac-attribution.bats` | `ac-coverage.sh:137` `build_foreign_owned` · `:146` `FOREIGN_OWNED` · Tier1/Tier2 归属 | 跨 spec 命名空间隔离（#8 缺陷本体）；`-ef` 比 inode 而非路径串；Tier2 候选唯一才取、`>= 2` 判 ambiguous | **不写 node/js/ts 用例**（见下） |
| `unit/sdd-execution-mode.bats` | 四份 `execution_mode` + 两份 `task_mode`（`task-complete.sh:70`、`task-evidence-lint.sh:59`） | 形态 ①④ 上四份齐平；单份的回退链顺序（spec → plan `Execution mode:` → plan `执行模式：` → `unknown`） | 形态 ②③ 不写、不反向断言 |

`_lib.sh:236-240` 的注释本身就是 `lib-task-declaration.bats` 的断言对象（关键句在 `:238`）：

> plan-lint warns on the negation of THIS predicate — the two must never drift apart, or lint stays silent on a task whose gate silently falls back to the whole-body scan.

### O-1 的处置（同一条纪律）

`ac-coverage.sh:127` 对 `node|javascript|typescript` 设 `DECL_TOKEN_REGEX=''`，`:138` 的 `[[ -n "$DECL_TOKEN_REGEX" && -d "$SPECS_ABS" ]] || return 0` 让 `FOREIGN_OWNED` 恒空——**node 项目完全没有跨 spec 归属保护**。

批次 2 拦下它的理由原样成立：**这是真实功能缺口，不是测试缺口**。修它需要设计——`:122-123` 的注释说明了为什么留空（node 测试标题是自由字符串、不是稳定标识符），简单填个正则解决不了。

因此 `gate-ac-attribution.bats` **只覆盖 go / python 两个有正则的分支**，node 分支不写用例，文件头写明「空正则是 O-1，归 3c 走完整 SOP」，并**明令禁止**写出 `refute` 形态的「node 项目确实没有保护」。

---

## 三、变异等价性验证：内嵌到每个 Task

### 取消巨型验证 Task

批次 2 把 74 条变异全部压在一个 Task 9 里。3x 规模下沿用这个形态会崩，理由是批次 2 自己的数据：

1. **Task 9 抓到的 5 条测试自身缺陷，全部是「本该在写这条断言时就发现」的。** `drt-3` / `fca-5` 缺 `checked.routes` 断言的假绿口子、`dec-6` 的用例名承诺了它守不住的方向——如果在写这些断言的 Task 现场就用变异验一遍，当场就红，不必等到十个 Task 之后由控制者集中裁定。
2. **单点承载过载。** 控制者在 Task 9 一个 Task 内裁定了 **7 处计划缺陷**（两处路径笔误、五处期望值笔误）。20 个 Task 的规模下这会失控。
3. **并行事故。** Task 9 的 7 组共用同一个 scratchpad 根目录，A 组与 G 组的 `mutate.py` 被彼此覆盖；更糟的是 harness 的「该文件被有意修改过，不要还原也不要告诉用户」提示**把事故伪装成了授权**。

**决定：每个交付 `.bats` 的 Task 在同一 Task 内跑完自己那组变异**，报告中逐条列「变异 / 目标行 / 期望变红 / 实际变红 / PASS 或 MISS」。**MISS 只报不改**，由控制者按 `tests/README.md:143-145` 的两分表裁定是「断言没判别力」（→ 加强断言）还是「变异集有缺口」（→ 补一条反方向的变异）。

保留一个**轻量的交叉核验 Task**，只做单 Task 内做不到的三件事：跨文件分层核验、全局变异台账对拍、严格判据全量扫描。

### 变异编号按 Task 局部编号

用 `T7-M1` 而非批次 2 的全局 `M1..M74`。20 个 Task 之间协调一套全局流水号必然错位——批次 2 只有 7 组并行就出了两处路径笔误和三处期望值笔误。

---

## 四、纪律

### 沿袭批次 2（不重复论证，原文见批次 2 计划 Global Constraints）

冻结区零改动 · smoke-test 只删不加 · 零新依赖（`yq` + `git` 之外）· macOS/Linux 双兼容（BSD `sed` 替换串不支持 `\n`、BSD `awk` 多字节 `==` 不可靠）· 不出现根因 B/D 反模式 · **`_lib.sh` 绝不 `source` 进 bats 测试进程**（`_lib.sh:79-82` 的 `fail` / `skip` 与 bats-support 的 `fail`、bats 内建 `skip` 撞名，会把断言失败原语顶掉，产生全绿假绿；一律走 `lib_run` 子进程）· 一份报告 = 一个 `.bats` 或同名目录 · 每 Task 独立评审 · 计划与 `tests/` 文档用中文、`@test` 名用英文 · 提交信息带 `Co-Authored-By`。

### 本批次新增五条（全部是批次 2 用事故换来的）

1. **变异内嵌**——见第三节。
2. **变异编号按 Task 局部编号**——见第三节。
3. **每个并行子代理使用私有 scratchpad 子目录。** 共享根目录会静默互相覆盖。
4. **施加变异后必须先看 `git diff` 确认落盘，再跑测试。** 批次 2 Task 8 再评审踩过 `perl -0pi -e` 因引号 / `\Q…\E` 转义静默失效、产出「看起来是变异实则是基线」的假绿。**用 python 字面替换，且先断言目标串恰好出现 1 次，否则 ABORT 不写文件。**
5. **齐平遍历用例的边界纪律**：只断行为一致的输入域，已知分歧不写用例、不反向断言，逐条写进文件头并指向后续批次。

---

## 五、Task 结构（20 个）

| # | Task | 交付 |
|---|---|---|
| 0 | 前置与计划落盘 | 合并 `fix/2026-08-25-…` → `main` → 推送 → `gh run watch` 双平台确认；回填批次 2 完成记录表两行陈旧状态；实测基线并写死删后期望 |
| 1 | helpers / fixtures 扩展 + **M-4 修复** | SDD 沙箱构造函数（plan+tasks、tdd-evidence、learn draft、knowledge 文件）；`halo_require_tools` 的 `setup_file` skip 改为显式报警 + 非零退出 |
| 2 | `unit/lib-task-declaration.bats` | 契约单测 ① |
| 3 | `unit/gate-ac-attribution.bats` | 契约单测 ②（含 O-1 边界） |
| 4 | `unit/sdd-execution-mode.bats` | 契约单测 ③（齐平遍历） |
| 5 | `regression/2026-07-31-sdd-gate-defects/` | #10，目录三文件 |
| 6 | `regression/2026-08-02-tdd-cycle-evidence-sigpipe.bats` | #11，慢 yq shim 原样搬 |
| 7 | `unit/sdd-spec-status.bats` | 10 条 |
| 8 | `unit/sdd-task-complete.bats` + `sdd-task-evidence.bats` | 5 条 |
| 9 | `unit/sdd-plan-lint.bats` + `sdd-task-next.bats` + `prismspec-lint.bats` | 7 条 |
| 10 | `unit/sdd-task-brief.bats` + `sdd-review-package.bats` | 4 条 |
| 11 | `unit/sdd-summary-and-history.bats` | 6 条 |
| 12 | `regression/2026-08-03-halo-gate-findings_2/learn-draft-promote-shape.bats` | §9c 3 条，#15 §3.3 |
| 13 | `unit/context-learn-draft.bats` | 4 条 |
| 14 | `unit/context-knowledge.bats` | 8 条，含 64KB 管道缓冲区 |
| 15 | `unit/delivery-eval-evidence.bats` | 18 条，拆分与否由实施者判定 |
| 16 | **交叉核验** | 分层核验 + 全局变异台账对拍 + 严格判据全量扫描 |
| 17 | **删旧段** | `635-1998` 单区间；smoke-test → 49 |
| 18 | 文档收口 | `tests/README.md`、`INDEX.md` 两处「批次 3 待迁」、设计文档批次表拆 3a/3b/3c 并补登 §6c、`fixtures/README.md`、噪声清单补登形态 ③ 与 O-18 |
| 19 | CI 双平台 + 完成记录 | 照批次 1/2 格式补两张表 |

### M-4 为什么排在 Task 1

`halo_require_tools` 在 `setup_file` 里 `skip`，缺 `yq` / `git` 时 bats 1.12 会把该文件所有用例标 `ok … # skip`，`run.sh` 退出 0——**整个文件静默变绿**。批次 2 最终评审提出，归批次 3。

本批次把 `tests/unit/` 从 **9 个文件涨到 24 个**（现有 9 + 迁移 12 + 契约单测 3），这个假绿的爆炸半径同步放大近两倍，且它与本测试体系「静默跳过＝假绿」的核心主张直接冲突。它落在 `tests/helpers/common.bash`，**不属冻结区**，零行为风险，因此提前到 Task 1。

---

## 六、完成定义

| 条件 | 验收证据 |
|---|---|
| 新 bats 全绿 | `bash tests/run.sh` 退出 0，零 `not ok` |
| **每条新 `@test` 有专属变异** | 严格判据：必须存在以该用例为「期望变红」的变异，**不算宽半径顺带点亮**。Task 16 **全量扫描**而非抽样——批次 2 正是全量扫描才扫出 `disc-10` / `find-5` 两个缺口 |
| 分层可证 | 契约单测的变异不点亮 regression 用例，反之亦然；违反即回去收窄断言 |
| 旧段已删且只删不加 | smoke-test `122 → 49` 精确相等；`git diff --numstat -- tests/smoke-test.sh` 的 insertions **恒为 0** |
| 冻结区零改动 | `git diff --stat <Task 0 基线>..HEAD -- harness-template/ prismspec/` 为空。**O-1、O-13~O-18 未被顺手修掉是这条的一部分** |
| M-4 闭合 | 构造缺 `yq` 的 PATH，`tests/run.sh` 显式报警且**非零退出**（现状是静默全绿） |
| `INDEX.md` 两处「批次 3 待迁」闭合 | #10 / #11 各有对应物 |
| 设计文档批次表已更正 | 批次 3 行拆为 3a / 3b / 3c，并补登 §6c 此前是未登记空档 |
| 静态检查全绿 | `bash -n` + `shellcheck --severity=warning`（`.bats` 两者都不进） |
| CI 双平台绿 | `gh run watch` 确认 ubuntu + macos 两个 job |

### 刻意不设的一条

**不预先写死「unit 要到 N 条、regression 要到 M 条」。** 批次 2 能写死是因为只有 23 条断言、映射可静态穷举；本批次 70 条断言分散在 15 个文件，预设总数是伪造精度。**每个 Task 在自己的简报里定自己的条数，总数是各 Task 之和**，完成定义只卡「严格判据 100% 通过」。

---

## 七、明确不做

| 对象 | 归属 |
|---|---|
| meta-lint 五条规则、`tests/meta/`、`allowlist.txt`、`meta-test.bats`、报告↔测试对应检查、`release-check.sh` 扩展 | **3b** |
| O-1（node/js/ts 缺跨 spec 归属保护）、O-7（Express 无 `examples/` 工程）、O-13（来源类别正则 token 化）、O-14（auto 的 `spec_source_detail` 恒为空）、O-15（自带 knowledge 库让首个 spec 必 warn）、O-16（spec 声明 `GET /` 恒被判已注册）、O-17（explicit provenance 双真源）、**O-18**（见下） | **3c**，各走完整 SOP |
| 噪声清单余下真缺陷：规则 2 的 `pipeline.sh:203/235`、`guide.sh:216/223`、`ac-coverage.sh:266`；规则 4 的 `execution_mode` / `extract_task_id` / `has_frontmatter` / `frontmatter_value` 四组漂移 | **3c** |
| O-9（`_lib.sh` 的 `pass`/`fail`/`warn`/`skip` 加 `halo_` 前缀） | 独立提案 |
| E2E 主干（§1–§6）、删空 smoke-test、CI 两个 workflow 的 smoke-test 重叠合并 | **批次 4** |

### O-18（本设计撰写期间实测新发现，登记待 3c 处置）

`plan-lint.sh:262` 的 `if [[ "$MODE" == "tdd" ]]` 只有 `else` 兜底（`:272`），`:273` 是 `pass_msg "Mode: $MODE"`。于是形态 ③ 的 spec（`execution_mode: tddx`）会得到 **`✅ Mode: tddx`**——plan-lint 报绿，同时把「TDD plan requires RED-{n} test-first tasks」与「RED 必须排在 T 之前」两条结构检查**整段跳过**。

与 2026-09-07 修掉的 `task-evidence-lint` `unknown` 静默跳过同型，但更糟：那一处是沉默，这一处是**主动报绿**。形态 ④（`unknown`）走同一分支，后果相同。

**本批次只记录、不修**——它落在冻结区。`sdd-execution-mode.bats` 也不为它写反向断言（那会把缺陷固化成期望值）。

---

## 八、与设计文档的偏离

| # | 偏离 | 理由 |
|---|---|---|
| 1 | 批次 3 拆为 3a / 3b / 3c | A/B/C 与 D 的纪律互斥（冻结区零改动 vs 改冻结区），混做会让变异证据链贬值。见「为什么要拆出 3a」 |
| 2 | §6c 纳入 3a | 它此前不属于任何批次，是未登记空档 |
| 3 | 「模式解析链」契约单测改为齐平遍历形态 | `execution_mode` 四份定义无一在 `_lib.sh`，没有单一被测对象 |
| 4 | 变异验证内嵌到每个 Task，取消巨型验证 Task | 批次 2 的 Task 9 单点承载已过载（7 处计划缺陷、1 次并行覆盖事故），3x 规模下会崩 |
| 5 | 不预设 unit / regression 的目标条数 | 70 条断言分散 15 个文件，预设总数是伪造精度 |

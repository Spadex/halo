# Halo 存量代码噪声与缺陷清单

日期：2026-08-25
基线提交：`c093b71`
状态：**已复核并修正，已完成两批处置**。2026-08-25 修两处高危缺陷，2026-09-07 修
`unknown` 静默跳过与规则 5 的五处 skip 文案（见「处置记录（2026-09-07）」）。其余登记待批次 3。
用途：批次 3 `tests/meta/` 上线前置。五条 meta-lint 规则在当前代码库的全部命中面，逐条给出判定与两种处置方案。

> 本文档全部数字均为实测（`grep`/`awk`/`md5` 直接跑在工作树上，基线 `c093b71`）。

## 复核记录（2026-08-25）

初版由一次独立复核逐条重跑（三个核查代理分头复算 + 人工实测所有会改变处置建议的结论）。
**硬事实**——原文引用、pipefail 继承链、`gate_skip` 机制、md5、对设计文档的转述——几乎全部
经得起复核；出问题的集中在**分类判读**与**计数**。修正后的真缺陷账：

| 规则 | 初版 | 复核后 |
|---|---|---|
| 1 失败方向注释 | 0 缺陷 / 9 缺注释 | 0 / **8** |
| 2 pipefail | 5 | **6**（新增 `ac-coverage.sh:188`） |
| 3 非确定性 | 6 | **0** |
| 4 重复定义 | 4 组 | 4 组（成立）+ `unknown` 静默跳过 |
| 5 诚实 skip | 5 | **6** |

三处错误会改变行动方向，均已在下文就地订正并标注 `【复核订正】`：

1. **规则 3 的 6 处「真缺陷」全部不成立**——而它正是初版「若只能动一处」的头号建议。
2. **`ac-coverage.sh:188` 被判为「不会致命」，实测是硬崩**——本次复核发现的最严重缺陷，
   已修复（`docs/bug_report/2026-08-25-ac-coverage-func-name-pipefail-analysis.md`）。
3. **规则 5 的实施障碍（「改文案会打红测试」）不存在**，命中面也少数了一处。

已随本批修复的两处：`ac-coverage.sh:188`、`compliance.sh:42`。

## 处置记录（2026-09-07）

第二批处置，对象是本文档登记的 P0 与规则 5 剩余项。两项都走了先红后绿。

| 项目 | 处置 | 测试 |
|---|---|---|
| `task-evidence-lint.sh:136-144` 的 `unknown` 静默跳过 | 补 `else` 分支，fail-closed，输出含 `NOT verified` | `tests/regression/2026-09-07-task-evidence-lint-unknown-mode-silent-skip.bats`（7 条，双向） |
| **`task-complete.sh:231-233` 的同型缺陷**（独立评审发现，清单原先未登记） | 补对称的 `elif != plan` → `fail_complete` | 同上文件的用例 5、6 |
| 规则 5 剩余五处 skip 出口文案 | 五处各补 `— … NOT verified` | `tests/unit/gate-skip-honesty.bats`（5 条，含反向） |

### 独立评审揪出的三处，已就地修正

本批的实现与文档经过一次独立评审（只读，独立上下文）。三处实质问题，均已修：

1. **`task-complete.sh:231-233` 是同一缺陷的兄弟站点，而且在写路径上。** 同一个
   `execution_mode()` + `task_mode()` 回退链、同一个 `if [[ tdd ]] … fi`，连 `plan`
   分支都没有。lint 只读，它会**勾选任务**。正常路径上 `:217` 的 plan-lint 调用会先拦住，
   但那道护栏是 `if [[ -x … ]]`——**本身就是 fail-open**，执行位一丢就静默跳过
   （`doctor.sh:135` 专门检查这一位，说明该失效模式被建模过）。实测复现：
   `chmod -x plan-lint.sh` 后，无模式无证据的任务被写成 `- [x] T1:`，退出码 0。
2. **齐平用例对 `drift-check` 恒真。** 初版断的是宽泛子串 `NOT verified`，
   而 `drift-check` 走**正常**路径时本来就打印这个词（`:576-577` 逐个列出未比较的维度）。
   四个门禁里有一个完全不设防。已改为逐门禁断**各自那句完整出口文案**；
   `drift-check` 不加反向用例（会立刻红且无意义），理由写进了测试文件。
3. **回归用例 3 的说明与它实际守的东西不符。** 初版称它守「无声 `exit 1`」，
   实测该变异下它仍绿（裸 `exit` 在循环里直接终止，收尾不执行），真正守住的是用例 2。
   断言本身有判别力（`warn_msg` 变异能点亮），错的是描述。另收紧了断言串：
   `"0 fail(s)"` 是 `"10 fail(s)"` 的子串，已改为 `"0 fail(s), 0 warning(s)"`。

另修两处事实错误：本文档三处把 `No AC numbers found in spec` 的行号写作 `:158`
（基线实为 `:156`，`git show c093b71:… | grep -n` 可验），`tests/README.md:21-22`
的用例计数被本批改旧（unit 50→55、regression 78→95，后者在基线上就已失准）。

复核报告：`docs/bug_report/2026-09-07-task-evidence-lint-unknown-mode-silent-skip-analysis.md`。

### 反向断言的判别力验证（四条变异）

正向断言由先红后绿证伪过（修复前实测变红）。**反向断言在修复前后都是绿的**，
按 `tests/README.md`「一条断言的『绿』，只有在它被独立证伪过之后，才构成证据」，
它们必须各自被至少一条变异点亮。四条变异走完六步协议，逐条记录：

| 变异 | 注入点 | 预期点亮 | 实测 |
|---|---|---|---|
| M-A | `spec-lint.sh:22` 的标题行追加 `NOT verified`（无条件声称未验证） | `gate-skip-honesty` #3 | ✅ 只点亮 #3 |
| M-B | `task-evidence-lint.sh:142` 的 `== "plan"` 改成永不匹配的值 | `silent-skip` #7 | ✅ 只点亮 #7 |
| M-C | `task-evidence-lint.sh:136` 的 `== "tdd"` 改成永不匹配的值 | `silent-skip` #4 | ✅ 只点亮 #4 |
| M-D | `ac-coverage.sh:161` 的 AC 计数行追加 `NOT verified` | `gate-skip-honesty` #4 | ✅ 只点亮 #4 |
| **M-E2** | `drift-check.sh:36` 的 skip 文案退化成只剩 `NOT verified` 三个字 | `gate-skip-honesty` #1 | ✅ 只点亮 #1 |
| **M-F** | `compliance.sh` 顶部无条件 `echo "MUTANT compliance NOT verified"` | `gate-skip-honesty` #5 | ✅ 只点亮 #5 |
| **M-G** | `task-complete.sh:231` 的 `== "tdd"` 改成永不匹配的值 | `silent-skip` #6 | ✅ 只点亮 #6 |

每条变异「只点亮预期的那一条」这件事本身也是产出：它证明反向断言没有越界去
约束别的行为。M-A/M-D/M-F 一并证明了「无条件把 `NOT verified` 打进输出」这条捷径
过不了关——这正是补文案时最容易走偏的方向。

**M-E2 与 M-F 是评审后补的，各自对应一处此前的判别力缺口**：

- **M-E2** 专门挑了一条**旧断言会放过、新断言抓得住**的变异。旧版断宽泛子串
  `NOT verified`，文案退化成只剩这三个字时照样绿；改断完整出口文案后变红。
  （相对地，「改坏文案让它完全不含 `NOT verified`」这类变异新旧断言都能抓，
  证明不了新断言更强，故不作为证据。）
- **M-F** 是评审实测过**旧版零变红**的那条。新增的 compliance 反向用例把它抓住了。

**诚实记录一处抓不住的方向**：同样的「无条件打印 `NOT verified`」若注入 `drift-check`，
**没有任何用例会红**，而且这是**结构性的、补不上的**——`drift-check` 走正常路径时
本来就打印 `NOT verified`（`:576-577` 逐个列出未比较的维度），任何
`refute_output --partial "NOT verified"` 对它都会立刻误红。该门禁那一侧的诚实性
由 `gate_skip` 三件套的既有断言守（`checked.*`、`checks_run`），不归本文件。
测试文件里就这一点写了理由，不留无声的空洞。

协议执行：每条变异前 `git status --porcelain` 为空，用 python 字面替换并断言目标串
恰好出现 1 次，`git diff` 确认落盘后才跑测试，跑完 `git checkout -- harness-template/ prismspec/`
回滚。四条全部回滚后 status 再次为空，`tests/run.sh` 退出码 0、零 `not ok`、
smoke-test 122/122。**无变异进入提交。**

### 本次实测产生的三条订正

1. **`unknown` 的触发门槛比本文档写的低得多。** 本文档把它描述为根因 H（`execution_mode`
   多份定义漂移）的下游后果，说要「把 `execution_mode:` 写在 front-matter 块外」才造得出。
   实测不需要任何漂移：`execution_mode()` 末行是 `printf '%s' "${value:-unknown}"`，
   spec front-matter 无 `execution_mode:`、plan 无 `Execution mode:` / `执行模式：`、
   任务体无 `Mode:`，四处全部落空即返回 `unknown`。**这是纯粹的漏写。**
   影响：本文档据此把它排在「`execution_mode` 收敛」之后，理由是「根因在上游」——
   实测表明两者可解耦，fail-closed 出口独立成立，不必等收敛。已按此顺序处置。
2. **规则 2 的优先级排序需要反转。** 详见下方「【2026-09-07 实测】规则 2 五处的触发门槛对比」。
3. **`docs/bug_report/INDEX.md` 记的 `7976672` 是悬空 hash**（amend 前的提交，
   `git merge-base --is-ancestor 7976672 HEAD` 为假），已改为 `c2fbfc8` 并加注记说明核验方式。

### 行号漂移对照（读本文档前先看这个）

**正文所有行号都是基线 `c093b71` 的值**，这是本文档声明的取数口径，不改。但两处修复各自加了几行注释，
**这两个文件在修复后的行号已经漂移**。批次 3 的实现者在当前工作树上找位置时按下表换算：

| 文件 | 漂移量 | 基线 → 现值（举例） |
|---|---|---|
| `delivery/gates/ac-coverage.sh` | `:187` 之后 **+6** | `:188`→`:194`（func_name 抽取）、`:226`→`:232`（Tier2 候选 `sort -u`）、`:231`→`:237`、`:266`→`:272`（`grep -A 5`）、`:302`→`:308`、`:306`→`:312` |
| `delivery/gates/compliance.sh` | `:41` 之后 **+4** | `:42`→`:46`（存在性守卫）。`:38` 及之前不变 |
| `orchestrator/sdd/task-evidence-lint.sh` | `:143` 之后 **+8** | `:144`→`:152`（模式分支的 `fi`）。**2026-09-07 新增**，`:143` 及之前不变 |

其余 48 个文件的行号未变。2026-09-07 补的五处 skip 文案只改字符串内容、不增删行，
`ac-coverage.sh` / `drift-check.sh` / `spec-lint.sh` / `compliance.sh` 的行号不受它影响。

> 写这张表是因为本文档自己在规则 2 里记了一笔：设计文档 `:13` 的 `guide.sh:180,187` 落笔当天就已失准，
> 无人察觉。同一个坑不该由这份文档再踩一次。

## 为什么需要这份文档

设计文档 `docs/superpowers/specs/2026-08-07-halo-test-system-design.md:114-131` 定义了五条 meta-lint 规则，并在 `:126` 要求配套「防 meta-lint 自身成为噪声源」的设计。但设计文档没有统计过这五条规则在现有代码上的命中面。

实测结果是：**按设计原文口径直接实现，五条规则合计命中 160+ 处**。若全部登记豁免，`allowlist.txt` 会超过 200 行，meta-lint 从第一天起就是噪声；若强行修改存量使其合规，批次 3 会从测试批次膨胀成修复批次，且违反 `tests/README.md:45` 的「先红后绿」纪律。

这份文档把 160+ 处拆开，标出哪些是规则口径过宽造成的误报、哪些是代码缺注释、哪些是真缺陷。

## 判据

对每一处命中，问三个问题：

1. **规则想防的那类风险，在这一处存在吗？** 不存在 → **噪声**（规则口径问题）
2. **代码行为正确，但看不出为什么正确吗？** → **缺注释**
3. **代码行为本身有问题吗？** → **真缺陷**

三类的处置方向不同：噪声应收窄规则口径或登记 `EXEMPT`；缺注释应补注释；真缺陷应登记 `KNOWN-DEFECT` 并走完整 SOP 修复（不在批次 3 内）。

**扫描范围**：`init.sh`、`install.sh`、`harness-template/**/*.sh`（**40** 个）、`prismspec/bin/*.sh`（5 个）、`tests/run.sh`、`tests/release-check.sh`、`tests/helpers/*.bash`（2 个），共 51 个文件。

> 【复核订正】初版把 harness-template 一栏写成 45，总数 51 反而是对的——是先算对总数再回填分项时写错的。实测 `find harness-template -name '*.sh' -type f | wc -l` = 40。

**`tests/smoke-test.sh` 排除在扫描范围外**。理由：它已冻结（`tests/README.md:29` 只删不加），批次 4 整体删除。把它纳入扫描会产生 18 条 `| grep -q` 豁免，而这些条目在批次 4 会随文件一起消失。建议在 meta-lint 脚本里硬编码排除并注明原因，而不是写进 allowlist。

---

## 规则 1：失败方向注释强制

> 设计原文（`:120`）：code 侧提取循环中的 `continue`/过滤，两行内必须有注明失败方向的注释。

### 命中面

宽口径（所有含 `continue` 的非注释行）命中 **95 处**。构成：

| 形态 | 数量 |
|---|---|
| 独立成行 `continue` | 18 |
| 一行式 `… && continue` | 32 |
| 一行式 `… \|\| continue` | 44 |
| 误配（heredoc 里的 JSON 字符串值） | 1 |

误配两处，但只有一处计入 95：`capabilities.sh:139` 的 JSON 串 `"id": "continue"`（在 `:136` 起的 `cat <<'JSON'` heredoc 内），以及 `spec-lint.sh:151` 注释里的英文单词 "continue"。

> 【复核订正】初版这一栏写 2，导致 18+32+44+2 = 96 与声明的总数 95 对不上。`spec-lint.sh:151` 是注释行，按本文档自己的口径（「所有含 `continue` 的**非注释行**」）本就已被排除，不该再计入分项。

### 判读结果

按「这个 `continue` 跳过的是数据还是空值」分类：

| 类别 | 数量 | 判定 |
|---|---|---|
| 空值守卫及其他（跳过的是空行/空值，不是记录；含 1 处 heredoc 误配） | **55** | **噪声** |
| CLI 过滤器（用户通过 `--project=` / `--status=` / `--type=` / `--severity=` / `--limit=` 显式要求跳过） | 22 | **噪声** |
| 配置项不完整跳过（`bootstrap.sh`，多数跳过前已有 `warn` 输出） | 8 | **噪声** |
| 真·数据过滤（跳过的是有效记录，失败方向真的重要） | **8** | **缺注释** |
| 已有失败方向注释 | 2 | 合规 |

> 【复核订正】初版这张表写 `~62 + 22 + ~8 + 9 + 1`，加总 **102 ≠ 95**。两个近似值（`~62`、`~8`）掩盖了对不上账这件事。复核后按实测重算：`bootstrap.sh` 精确是 8，其余噪声倒推为 55，全表加总 55+22+8+8+2 = **95** ✓。

**噪声占比 89%（85/95）。** 最典型的是 `delivery/eval-query.sh` 的 22 处——全部是 CLI 过滤器，跳过记录是用户显式要求的行为，与「漏验证」无关。构成是 `matches_project`（`--project=`，`:126-129` 定义）9 处、`STATUS_FILTER` 3、`TYPE_FILTER` 3、`SEVERITY_FILTER` 3、`LIMIT` 4：

> 【复核订正】初版说这 22 处「全部是 `--status` / `--type` / `--severity` / `--limit`」，实测这四个 flag 只覆盖 13 处，另 9 处是 `--project`。分类判定（噪声）不变，措辞不准。

```bash
eval-query.sh:178:  [[ -n "$STATUS_FILTER" && "$status" != "$STATUS_FILTER" ]] && continue
eval-query.sh:263:  [[ "$emitted" -ge "$LIMIT" ]] && continue
```

### 真正需要注释的 8 处

> 【复核订正】初版列了 9 处，其中 `drift-check.sh:341` **已有失败方向注释**（在 `:337-338`：「a trailing-segment match still counts as registered, so an unmodelled prefix causes a missed detection rather than a false failure」——这就是 fail-open 的完整表述）。注释在 3 行外，机械的「两行内」规则确实会命中它，但判定应是「注释位置需上移」而非「缺注释」。它也是初版 9 条里唯一一条「失败方向」栏没填方向的。下表已剔除，编号顺延。

| # | 位置 | 原文 | 跳过了什么 | 失败方向 |
|---|---|---|---|---|
| 1 | `orchestrator/sdd/task-complete.sh:123` | `valid_tdd_evidence "$evidence" \|\| continue` | 无效的 TDD 证据文件 | fail-closed（找不到有效证据 → `matched=false` → 报缺失）。**这是 TDD 门禁的核心过滤，方向搞反直接产生假绿** |
| 2 | `delivery/gates/ac-coverage.sh:186` | `[[ -z "$ac_num" ]] && continue` | 提不出编号的测试函数 | fail-closed（该测试不计入覆盖 → AC 更可能判未覆盖）。**这是 #7 的修复点**——`:185` 补 `\|\| true` 之后本行才可达 |
| 3 | `delivery/gates/ac-coverage.sh:262` | `[[ -z "$func_name" ]] && continue` | `--deep` 模式下提不出函数名的行 | 同上 |
| 4 | `delivery/gates/ac-coverage.sh:142` | `[[ "$f" -ef "$SPEC" ]] && continue` | 自身 spec（跨 spec 归属隔离） | 排除自己，正确。用 `-ef` 比 inode 而非比路径字符串 |
| 5 | `delivery/gates/spec-lint.sh:158` | `[[ -z "$num" ]] && continue` | 提不出编号的 AC 行 | 与 #2 同型 |
| 6 | `delivery/gates/drift-check.sh:484-485` | `UNVERIFIED_NUMERIC=true` 换行 `continue` | 无数值常量可比对时的错误码 | **已自带诚实标记**——跳过时显式置 `UNVERIFIED_NUMERIC=true`。这一处是全库最好的样板 |
| 7 | `orchestrator/sdd/review-package.sh:66` | `git_ok rev-parse --verify "$candidate^{commit}" \|\| continue` | 不存在的基线分支候选 | fallback 链（依次试 `origin/HEAD` → `origin/main` → `main` …），正确 |
| 8 | `spec-select.sh:122` | `[[ "$other" == "$top" ]] && continue` | 选出赢家后打印诊断列表时的自身候选 | 排除自己，正确 |

> 【复核订正】三处引用不准：#6 初版写作 `UNVERIFIED_NUMERIC=true; continue` 的一行式，实际是 `:484`+`:485` 两行（`:485` 单独一行只有 `continue`，这也是它被计入「独立成行 18」的原因）；#8 初版写「平局比较时的自身候选」，实际平局在 `:103-110` 已 `return 2` 提前退出，`:120-122` 是**选出赢家之后**打印「not selected」诊断列表的循环——结论「排除自己，正确」不变，场景描述错了。

已有失败方向注释的是**两处**：`delivery/gates/drift-check.sh:325`（注释在 `:319-324`，关键词 "fail open" 落在 `:323`）与 `drift-check.sh:341`（注释在 `:337-338`）。

> 【复核订正】初版称「唯一已有注释」，且注释区间写作 `:322-324`，实测是 `:319-324`。

### 处置方案

**方案 A · 纠正**（改代码使其不再命中）

不适用。这 8 处的代码行为都是正确的，没有可「纠正」的对象。规则 1 的产出物本来就是注释，不是代码改动。

**方案 B · 注释**

给 8 处补失败方向注释，统一成机器可识别的固定标记。当前全库有 **5 种不同措辞**，没有任何统一标记：

| 位置 | 现有措辞 |
|---|---|
| `tests/run.sh:23` | `（fail direction: …）` |
| `tests/helpers/common.bash:67` | `# 失败方向：…（fail-closed）` |
| `harness-template/halo/kernel/_lib.sh:228` | `# Failure direction: fail-open. …` |
| `init.sh:124` `init.sh:157` | `# Fail open: …` |
| `delivery/gates/drift-check.sh:323` | `# to fail open. Genuine non-paths …`（句中散文，无标签无冒号） |

> 【复核订正】初版说 4 种，漏掉的第 5 种恰恰是它自己在上一节认定为「唯一已有注释」的那处。这也说明为什么统一标记是必要的——散文形态连人工清点都会漏。

建议统一为 `_lib.sh:228` 的英文形态 `# Failure direction: fail-open|fail-closed. <理由>`，因为它已在 kernel 代码里，且是唯一带冒号分隔的可解析形态。

**同时必须收窄规则口径**，否则补完 8 处仍有 92 处命中。建议口径：只扫「循环数据源是外部命令（`grep`/`find`/`awk`/`yq`/`git`）」且「过滤条件不是纯空值判断」的 `continue`。这不是放水——设计原文写的就是「**提取循环**中的 continue」，纯空值守卫本来就不在其中。

**倾向**：方案 B，8 处全补，外加把 `drift-check.sh:337-338` 的注释上移到紧贴 `:341`。补注释零行为风险，且 allowlist 里出现「豁免理由 = 还没写注释」是荒谬的。

---

## 规则 2：pipefail 反模式扫描

> 设计原文（`:121`）：`yq … | grep -q`、`find … | xargs ls -t | head`、命令替换包 grep 无 `|| true` 兜底。

### 2a. 管道进 `grep -q`

正则命中 **11 处**，扣掉下表自认的误报 `plan-lint.sh:236`（here-string 不是管道），真正「管道进 `grep -q`」的生产代码是 **10 处**（`tests/smoke-test.sh` 另有 18 处，已排除）。

> 【复核订正】初版把自认的误报计进了 11，汇总表也跟着算。分母不干净会让「收窄口径」显得比实际更必要。smoke-test 的 18 是**按行**计；按出现次数是 20（`:339`、`:346` 各含 2 处）。

判据：`grep -q` 在首次匹配即退出，若左侧仍在写入则收到 SIGPIPE(141)；在 `set -o pipefail` 下这会把「命中」变成「失败」。**只有左侧输出量可能超过管道缓冲区（64KB）时才会触发。**

| 位置 | 原文 | pipefail 生效？ | 判定 |
|---|---|---|---|
| `prismspec/bin/guide.sh:216` | `find "$RUN_DIR" -type f \( -name 'verify.md' -o -name 'evidence.json' \) \| grep -q .` | ✅ `guide.sh:4` | **真缺陷** |
| `prismspec/bin/guide.sh:223` | `find "$RUN_DIR" -type f -name 'review.md' \| grep -q .` | ✅ | **真缺陷** |
| `delivery/gates/ac-coverage.sh:266` | `grep -A 5 "$func_name" "$test_file" \| grep -qiE 't\.Skip\|pytest\.skip\|…'` | ✅ 继承 `_lib.sh:12` | **真缺陷** |
| `delivery/pipeline.sh:203` | `printf '%s\n' "$output" \| grep -qiE "$output_regex"` | ✅ 继承 `_lib.sh:12` | **真缺陷** |
| `delivery/pipeline.sh:235` | `printf '%s\n' "$output" \| grep -qiE 'command not found\|…'` | ✅ 继承 | **真缺陷** |
| `prismspec/bin/doctor.sh:95,96,97` | `echo "$GUIDE_OUTPUT" \| grep -q '"host"'` 等 3 处 | ✅ | 噪声（JSON 输出，量受限） |
| `prismspec/bin/lint.sh:77` | `head -1 "$skill_file" \| grep -qxF -- '---'` | ✅ | 噪声（`head -1` 只出一行） |
| `delivery/gates/spec-lint.sh:192` | `echo "$line" \| grep -qE '^\s*//'` | ✅ | 噪声（单行） |
| `orchestrator/sdd/plan-lint.sh:236` | `grep -Eq '…' <<< "$body"` | ✅ | **误报**（here-string 不是管道，无 SIGPIPE 可能） |

**`guide.sh:216` / `:223` 是设计文档 `:13` 点名的「已知未修」**（原文记的行号 `180,187`，代码原样未动）。它们的返回值在 `guide.sh:239,241,263,265` 直接决定 guide 输出哪个阶段——SIGPIPE 会让「有证据」误报成「无证据」，把用户导向错误的阶段。与 #11（`docs/bug_report/2026-08-02-tdd-cycle-evidence-sigpipe.md`）完全同型。

> 【复核订正】两处措辞失真：
>
> 1. **行号漂移发生在设计文档写作之前，不是之后。** `grep -q .` 从 `25b95a9`(2026-07-10) 的 180/187 变成 216/223 是在 `7a50adf`(2026-08-03)，而设计文档是 2026-08-07 写的——它落笔时行号**已经**是错的，属首日失准。
> 2. **不是「已知未修超过三周」的遗忘，是有据的搁置。** `2026-08-02-tdd-cycle-evidence-sigpipe-analysis.md:88-97` 明确记载这两处当年**实测过**（同规模下 15/15 返回 0），结论是「均已实测在现实规模下不触发，故本次不作投机性改动」。
>
> 另外，设计文档 `:13` 点名的「已知未修」是**两处**：`_lib.sh:158` 与 `guide.sh:180,187`。初版只处理了后者。`_lib.sh:158` 的原始形态是 `find … | xargs -0 ls -t | head -1`（见同一份 analysis `:91-94`），已随 `7a50adf` 迁到 **`spec-select.sh:85`**——正是本文档 2b 判为「设计选择」的那处。今天 `_lib.sh` 的 `| grep` / `| head` 零命中，这条线索已闭合。

`pipeline.sh:203/235` 的左侧 `$output` 是被测命令的完整输出，**可以任意大**——这两处的风险不比 guide.sh 小，但从未被登记过。调用链已复核：`pipeline.sh:390` `output=$(run_cmd "$run" 2>&1)` → `:407` `classify_failure_category "$name" "$output"` → `:227` → `:229` → `:192` → `:203`，全程无截断（`record_step` 的 `tail -20/-40` 是另一条路径）。

### 【2026-09-07 实测】规则 2 五处的触发门槛对比

本文档「若只能动一处」的榜单把 `guide.sh:216/223` 列为第 5 项（「登记最久」），
而 `pipeline.sh:203/235` **根本没进榜**。实测表明这个排序反了。

管道缓冲区阈值实测（macOS，`printf` 喂 `grep -qiE`，首行即命中）：

```
   800 行 /   45622 字节 -> OK
  1000 行 /   57022 字节 -> OK
  1200 行 /   68422 字节 -> MISCLASSIFIED
  3000 行 /  171022 字节 -> MISCLASSIFIED
```

64KB 一过就把「命中」变成「未命中」。据此对比两处的实际触发概率：

| 位置 | 管道左侧是什么 | 到 64KB 的现实距离 |
|---|---|---|
| `pipeline.sh:203/235` | 被测命令的**完整输出**（测试套件、构建日志） | **常态**。一个中等规模的测试套件输出轻易过 64KB |
| `guide.sh:216/223` | `RUN_DIR` 下的**文件路径列表** | 需 1000+ 个文件。`2026-08-02-…-analysis.md:88-97` 实测同规模下 15/15 返回 0 |

后果方向也不同：

- `pipeline.sh:235` —— 环境类失败（`command not found` 等）漏判，落回按 `step_name` 的
  兜底分类，`default_action` 走错；
- `pipeline.sh:203` —— 用户在 `failure-categories` 里配的 `output_regex` 规则
  **匹配成功却被 `continue` 静默跳过**，配置静默失效；
- `guide.sh:216/223` —— 「有证据」误判为「无证据」，方向是**假红**（把用户导回更早的阶段），
  保守但不产生错误的绿。

**结论：规则 2 若只动一处，应该是 `pipeline.sh:203/235`，不是 `guide.sh`。**
两处同根因，一份回归测试可覆盖；`task-complete.sh:113-115` 有现成的修复注释样板。

另需订正本文档「处置方案 · 方案 A」的标题「（5 处真缺陷）」——那 5 处里
`ac-coverage.sh:266` 的下游是 `--deep` 的 `DEEP_WARNINGS`，而 `ac-coverage.sh:295` 明写
`warnings (non-blocking, for review reference)`，不进门禁判定；且 `grep -A 5` 的左侧是
单文件的匹配上下文，很难到 64KB。它是五处里优先级最低的一处，不该与另外四处并列。

### 2b. `find … | xargs ls -t | head`

命中 **1 处**：`spec-select.sh:85`

```bash
latest="$(printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 ls -t 2>/dev/null | head -1)"
```

判定：**设计选择**。`spec-select.sh:10-16` 有 7 行注释专门解释为什么 mtime 不可靠，`:80-83` 说明这是「无任何语义信号可排序时」的最后回落，且 `:89-90` 会向 stderr 打印警告（`:88` 是赋值，不是警告）。

> 【复核订正·论据】初版用「执行分支 `:134` 是 `set -uo pipefail`（无 `-e`），SIGPIPE 不会中止脚本」作为免疫依据——**这个论据在主要调用路径上不成立**。`:134` 在 `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]` 守卫内，只在**直接执行**时生效；而两个真实调用方 `_lib.sh:136` 与 `prismspec/bin/guide.sh:131` 都是 **source**，此时继承调用方的 `set -e`。
>
> 结论「设计选择」仍然成立，但真正的理由是**数据量**：`ls -t` 左侧是 spec 文件名列表，远小于 64KB 管道缓冲区，且 `:86` 有 `[[ -n "$latest" ]] || return 1` 兜底。这也与 `2026-08-02-…-analysis.md:91-94` 的实测一致（200 个目录 20/20 正常，1600 个目录才失败）。

### 2c. 命令替换含 grep 无 `|| true`

正则命中 8 处（`spec-select.sh:103`、`ac-coverage.sh:188`、`drift-check.sh:230/233/393/394`、`task-next.sh:131`、`plan-lint.sh:185`），扣掉 `drift-check.sh:393/394` 后**真实是 6 处**。

> 【复核订正】`drift-check.sh:393/394` 命中的是**函数名 `grep_folded`**，行上没有真正的 grep 调用。该函数定义在 `:302-309`，内部 `:307` 已有 `|| true`、`:304` 对空输入 `return 0`。这是纯正则假阳性，初版把它和真正的裸 grep 并列在同一个「8 处」里未加区分。

### 【复核订正·真缺陷】`ac-coverage.sh:188` 是 fail-hard，不是无害

初版判定：「因为 `head` 在管道末段吞掉了 grep 的退出码，实际不会致命」。**两处都错**：

1. **`head -1` 不在末段。** 完整管道是 `grep -oE … | head -1 | sed … | sed … | sed …`，末段是第三个 `sed`。初版引用原文时把三个 `sed` 缩写成一个，恰好模糊掉了这一点。
2. **在 `pipefail` 下，末段是谁根本无关。** `pipefail` 返回管道中**最右侧非零**的退出码。`head`/`sed` 都返回 0，`grep` 未命中返回 1 → 整条管道返回 1。

`ac-coverage.sh:3` source `_lib.sh`（`:12` = `set -euo pipefail`），裸赋值拿到非零 → **errexit 直接终止门禁**。实测复现：

```bash
bash -c 'set -euo pipefail
line="it.each([[1], [2]])(\"AC-1 …\", (n) => {"
fn=$(echo "$line" | grep -oE "…|(describe|it|test)\(" | head -1 | sed "s/($//")
echo "NOT REACHED"'
# 不打印 NOT REACHED，退出码 1
```

触发条件真实存在：node 分支的**选行**正则 `(describe|it|test).*AC[_-]?([0-9]+)`（`:108`）只要求行内任意位置有 it/test/describe 和 AC 号，而 `:188` 的**抽名**正则要求 `(describe|it|test)\(` 紧跟左括号。jest 的 `it.each(` / `test.concurrent(` / `describe.skip(` 全部命中前者、漏掉后者。后果是门禁在循环中途硬崩，`write_gate_json`（`:302`/`:306`）执行不到，gate JSON 不落盘。

**初版内部自相矛盾**：它在规则 1 的 #2 明写「`:185` 补 `|| true` 之后本行才可达」，却对同一循环体内同一形态的 `:188` 得出相反结论，且倒向了错误的一边。

**已修复**，见 `docs/bug_report/2026-08-25-ac-coverage-func-name-pipefail-analysis.md` 与 `tests/regression/2026-08-25-ac-coverage-func-name-pipefail.bats`。

判定：其余 5 处需逐处判断 grep 是否可能未命中。**这一子条规则误报率高（8 命中里 2 处是函数名假阳性），但绝不能因此不上线**——它本该抓住 `ac-coverage.sh:188`。上线时只扫「命令替换整体作为 `if` 条件之外的裸赋值」这一更窄形态，且判定标准必须写明「`pipefail` 取最右侧非零码，末段是谁与危险性无关」，否则同一个误判会在 allowlist 登记时重演一次。

### 处置方案

**方案 A · 纠正**（5 处真缺陷）

```bash
# guide.sh:216 现状
[[ -n "$RUN_DIR" && -d "$RUN_DIR" ]] && find "$RUN_DIR" -type f \( -name 'verify.md' -o -name 'evidence.json' \) | grep -q .

# 纠正后（去掉管道）
[[ -n "$RUN_DIR" && -d "$RUN_DIR" ]] || return 1
local found
found="$(find "$RUN_DIR" -type f \( -name 'verify.md' -o -name 'evidence.json' \) -print -quit 2>/dev/null || true)"
[[ -n "$found" ]]
```

`-print -quit` 让 find 自己在首个匹配后停止，既消除 SIGPIPE 又避免遍历整棵树。`ac-coverage.sh:266` 与 `pipeline.sh:203/235` 同理，改成先收进变量再用 here-string 匹配（`task-complete.sh:113-115` 已有这个修复的注释样板可照抄）。

**代价**：每处都是行为敏感的改动，按 SOP 需要各自的回归测试（先红后绿）。`guide.sh` 的两处可以合并成一份回归（同一函数族、同一根因）。总计约 3 份回归测试。

**方案 B · 注释**

在 5 处各加一行 `# Known SIGPIPE risk under pipefail — see docs/bug_report/2026-08-02-…`，并在 `allowlist.txt` 登记为 `KNOWN-DEFECT`。meta-lint 打印告警但不失败，条目只减不增。

**倾向**：`ac-coverage.sh:188` 已按方案 A 修复（它是 fail-hard，不能等）。其余 5 处按设计文档 `:160` 归批次 3——该行明文把「SIGPIPE」列进批次 3 的迁移内容，不必推到批次 4。

`guide.sh:216/223` 在这 5 处里优先级最高：`has_verification_evidence` 的误判会直接改变 guide 给用户的指令。但要记住 `2026-08-02-…-analysis.md:88-97` 的实测结论——它在现实规模下不触发，当年是**刻意搁置**。纠正它是把潜伏风险清掉，不是在补一个正在流血的口子。

---

## 规则 3：非确定性依赖扫描

> 设计原文（`:122`）：决策路径上的 `ls -t`、`stat %m`、无 `sort` 的 `find` 直接消费。

### 命中面

| 子模式 | 命中 | 说明 |
|---|---|---|
| `ls -t` | 1 | `spec-select.sh:85`（同 2b，设计选择） |
| `stat %m` / `stat -c %Y` / `--sort=time` | **0** | **全库零命中**。这一子条规则在当前代码库上没有靶子 |
| `find` 无 `sort` | **29** | 6 处 `done < <(find …)` + 19 处命令替换 + 4 处裸管道 |

> 【复核订正】初版写 26（6 + 20）。实测 29，漏掉的 3 处是 `eval-sink.sh:93`、`guide.sh:216`、`guide.sh:223`（第 4 处裸管道 `drift-check.sh:106` 初版按命令替换归类，可接受）。另有 `tests/release-check.sh:18` 在初版里未被任何一行表格分类。**这些遗漏全部是噪声，不引入新缺陷。**

### `find` 无 sort 的判读

判据：find 的输出顺序是否进入决策。

**全部 29 处都是噪声。** 复核逐处追下游确认：

| 判定 | 数量 | 位置 |
|---|---|---|
| 拷贝循环，顺序无关 | 3 | `init.sh:222`、`context/sync.sh:77,101` |
| 只做计数（`wc -l` / `count++`） | **10** | `tests/run.sh:26`、`sync.sh:121,122,127`、`summary-draft.sh:119-122`、`lint.sh:207`、`eval-sink.sh:93`、**`eval-dashboard.sh:94`** |
| 只判存在性 | 4 | `pipeline.sh:323,325`、`guide.sh:216,223` |
| 下游有 `sort -u` / `sort \| uniq` 吸收 | **8** | `ac-coverage.sh:144`（`:146`）、**`ac-coverage.sh:165/168/171/174`**（`:226`）、`drift-check.sh:218`、**`drift-check.sh:213`**（`:233`）、`drift-check.sh:106` |
| 集合语义，顺序不影响结果 | 3 | `drift-check.sh:355`、`compliance.sh:120`、`release-check.sh:18` |
| **真缺陷** | **0** | —— |

> 【复核订正·推翻】初版列了 6 处「真缺陷」，**无一成立**。三路证据（人工实测 + 独立核查代理）独立吻合：
>
> | 位置 | 初版判定 | 实测 |
> |---|---|---|
> | `ac-coverage.sh:165/168/171/174` | 「`TEST_FILES` 顺序决定 Tier2 归属，`:188` 的 `head -1` 对顺序敏感」 | **读错了 `:188`**——那个 `head -1` 作用在**单条 `match_line` 内部**取行内第一个函数名 token，与文件顺序无关。真正的 Tier2 归属在 `:226`，候选集经 `sort -u` 排过序，且 `:231` 要求 `ccount == 1` 才取、`>= 2` 直接判 ambiguous，双重保险。Tier1（`:218`）是 awk 存在性判断。矩阵行序由 `SPEC_ACS` 驱动（`:203`，而 `:151` 已排序） |
> | `eval-dashboard.sh:94` | 「同文件三处同型 find，唯独这处漏了 sort」 | **三处不同型**。`:88-96` 是**计数循环**（`count=$((count+1))`，最后 `printf '%s' "$count"`）；`:103` 收进 `MANIFESTS[]` 按数组序输出；`:162` 收进数组后**倒序取最近 N 条**。后两处需要 sort 是因为顺序进了输出，`:94` 不需要是因为它只数数——它属于本表自己的「只做计数」档 |
> | `drift-check.sh:213` | 「结果进入模型比对」 | `MODEL_FILES` 的实质消费点是 `:229-233`，末尾 `sort \| uniq` 吸收顺序，`comm -23`/`comm -13` 比的是已排序集合。**更强的反证**：`:218` 写进**同一个变量、走同一段下游**，却被初版判为噪声——同一条数据流两种判决 |
>
> 共同的病根：初版在 `ac-coverage.sh:144` 上用了「下游有 `sort -u` 吸收 → 噪声」这条判据，却没在这 6 处沿用。**两套标准。**

### 处置方案

**方案 A · 纠正**：无对象。这 29 处加 `| sort` 都是无害的，但也都是零收益的。

**方案 B · 注释**：可以诚实地给关键几处加 `# Order-independent: <理由>`。初版说「这 6 处的顺序确实重要，写这种注释等于说谎」——结论正好反了，它们恰恰都可以诚实地这么写。

**倾向**：**规则 3 在当前代码库零真缺陷**。`ls -t` 1 处是有注释的设计选择，`stat %m` 子条零靶子，29 处无 sort 的 `find` 全部顺序无关。

规则仍应上线，但要认清它的定位是**防回退**而非清存量：

- `stat %m` 子规则零命中，说明设计文档写这条时依据的是 `#15` 修复**之前**的代码。保留它防回退，但在文档里注明当前是纯预防性的。
- `find` 无 sort 子条误报率 100%（29/29）。若照原文口径上线，需要 29 条豁免。**建议收窄为「find 输出直接进入数组/输出且下游无 sort」**，或干脆只在 review 中人工判读。

---

## 规则 4：重复定义检测

> 设计原文（`:123`）：同一函数名在多个文件重复定义。点名 `task_body` 现存 4 份副本。

### 命中面

跨文件重复的函数名 **33 个**，涉及定义 **129 份**（已排除 `tests/`）。

前十：

| 份数 | 函数名 |
|---|---|
| 15 | `json_escape` |
| 13 | `rel_path` |
| 7 | `md_escape` · `json_get` · `frontmatter_value` |
| 5 | `usage` · `json_num` |
| 4 | `task_body` · `resolve_plan_file` · `execution_mode` |

### 关键发现：md5 不同 ≠ 漂移

对 19 个重复函数逐份算 md5，12 个显示「多种实现」。但抽查后发现**必须区分两类**：

**表层差异（不是漂移）** —— `resolve_plan_file` 四份：

```bash
# plan-lint.sh
[[ -n "$input" ]] || { echo "Usage: plan-lint.sh <spec-id|path/to/plan.md>"; exit 1; }
# task-evidence-lint.sh
[[ -n "$input" ]] || { echo "Usage: task-evidence-lint.sh <spec-id|path/to/plan.md>"; exit 1; }
```

路径解析的五行（`:27-33` 的 `*.md`/`*/*` 判断、绝对/相对拼接、`halo/specs/$input/plan.md` 兜底、`-f` 存在检查、`printf`）四份逐字节相同。核心逻辑没有漂移。

> 【复核订正·论据】初版说「四份的**唯一**差异是 usage 提示里的脚本名」——实测四份是 4 个不同 md5，除脚本名外还有两处差异：
>
> 1. **`task-complete.sh:26` 多了 `&& -n "$TASK_ID"` 守卫**——这是**行为差异**（缺 TASK_ID 时提前 usage 退出），不是文案差异；
> 2. 两份用字面量 usage 串（`plan-lint`、`task-evidence-lint`），两份用变量 `"Usage: $usage_line"`（`task-next`、`task-complete`）。
>
> 上面引的两份恰好是真的只差脚本名的那两份——**抽样抽到了最有利的证据**。归入「表层差异→噪声」的方向仍可接受（路径解析确实一致），但 `task-complete` 的额外守卫应单独登记。

**实质漂移（真缺陷）** —— `extract_task_id` 三份：

```bash
# plan-lint.sh:97 与 task-next.sh:73（相同）
sed -E 's/^- \[[ xX]\] ((T[0-9]+|RED-[0-9]+)):.*/\1/' <<< "$line"
# task-evidence-lint.sh:84
sed -E 's/^- \[[xX]\] (T[0-9]+):.*/\1/' <<< "$line"
```

`task-evidence-lint` 的版本**不认 RED 任务，也不认未勾选的 `[ ]`**。这是真实的行为差异。

`has_frontmatter` 三份同理：

```bash
# knowledge-lint.sh:90 —— 要求 --- 开始且有 --- 结束（完整块）
[[ "$(sed -n '1p' "$file")" == "---" ]] && awk 'NR > 1 && $0 == "---" { found = 1; exit } END { exit(found ? 0 : 1) }' "$file"
# spec-state-lint.sh:49 与 spec-status.sh:62 —— 只看第一行
[[ "$(head -1 "$file" 2>/dev/null)" == "---" ]]
```

一个只有开始 `---`、没有结束 `---` 的文件，`knowledge-lint` 判 false，另两个判 true。

**`frontmatter_value` 七份分两种实现**（A = `knowledge-lint`/`learn-draft`；B = 五个 `sdd/*`）。初版只下了「实质漂移」的判定没给证据，复核实测出四条可复现的行为分叉：

| # | 输入 | A（`-F': *'` + `$1 == key`） | B（`index($0, key ":") == 1`） |
|---|---|---|---|
| 1 | `execution_mode: 'tdd'` | 只剥 `"`，返回 `'tdd'`（带引号） | 剥 `"`/`'`/`` ` ``，返回 `tdd` |
| 2 | `status: draft␣␣` | 不去尾，返回 `draft␣␣` | `gsub` 去尾，返回 `draft` |
| 3 | `status:\tdraft` | `-F': *'` 不吃 Tab，返回 `\tdraft` | 返回 `draft` |
| 4 | front-matter 里一行只写裸 `status` | `$1 == key` **命中**，把 **key 名当 value 返回** | 不命中，无输出 |

第 1 条直接影响 `execution_mode`：`task-complete.sh:83` / `task-evidence-lint.sh:72` 拿到的是 B 的结果，`[[ "$value" == "tdd" ]]` 通过；哪天改用 A 的实现就会 fail。

### 分类结果

| 类别 | 代表 | 判定 |
|---|---|---|
| **刻意的独立副本** | `json_escape`×15、`rel_path`×13、`md_escape`×7、`json_get`×7、`json_num`×5、`usage`×5 | **噪声**。这些脚本刻意不 source `_lib.sh`（`spec-select.sh:6-8` 写明理由：`_lib.sh` 在缺 yq 或 manifest 时会退出，standalone 宿主必须能独立跑）。合并它们会引入依赖，方向是错的 |
| **纯冗余，尚未漂移** | `task_body`×4（四份 md5 **完全相同** `384d89f…`）、`safe_slug`×3、`valid_tdd_evidence`×2、`task_mode`×2、`spec_file_for_plan`×2 | **缺注释**或低优先级合并。风险是「将来漂移」不是「已经漂移」 |
| **表层差异（usage 文案）** | `resolve_plan_file`×4 | **噪声** |
| **实质漂移** | `execution_mode`（3 种）、`extract_task_id`（2 种）、`has_frontmatter`（2 种）、`frontmatter_value`（2 种） | **真缺陷** |

**设计文档点名的 `task_body` 恰恰是没漂移的那个**（四份逐字节相同），而真正已经漂移的 `execution_mode` / `extract_task_id` / `has_frontmatter` / `frontmatter_value` 从未被登记过。

> 【复核订正】初版把 `rel_path`×13 同时列进「刻意的独立副本」和「纯冗余，尚未漂移」两档，重复计数 13 份。上表已从后者移除——它属前者（`rel_path` 是 standalone 脚本各自持有的路径工具）。这也是汇总表里规则 4 那行 `~100 + ~20 ≠ 129` 的来源之一：**该行的噪声/缺注释数是未穷尽的估算，只有「真缺陷 4 组」是精确的。**

### `execution_mode` 的漂移细节（最严重的一处）

四份分三种实现（md5 `dbe1e20` / `e06c920`×2 / `4422cb8`），但只有**两个行为阵营**：

| 位置 | md5 | 读 spec 的方式 | 后果 |
|---|---|---|---|
| `plan-lint.sh:111` | `dbe1e20` | `grep -Eim1 '^execution_mode:…'`，**无 `-f "$spec"` 守卫** | front-matter 块**外**的 `execution_mode:` 也能读到 |
| `task-next.sh:90` | `4422cb8` | 同上，**有**守卫 | 同上 |
| `task-complete.sh:80` · `task-evidence-lint.sh:69` | `e06c920`×2 | `frontmatter_value`（awk 解析 `---` 块） | 只认块内，块外读不到 → 得到 `unknown` |

> 【复核补充】第三个 md5 的**全部来源**是 `plan-lint.sh` 少了另外三份都有的 `if [[ -n "$spec" && -f "$spec" ]]; then … fi` 包裹（因此少 2 行），不是读取口径不同。`$spec` 为空或不存在时 grep 失败被 `2>/dev/null || true` 吞掉，行为上等价于返回空——所以它不是缺陷，但会让「三种实现」与下面的两行分组表看起来矛盾。两者只是口径不同（md5 计数 vs 行为分组），不冲突。

即：一份把 `execution_mode:` 写在 front-matter 块外的 spec，`plan-lint` 认为它是 tdd 模式、`task-complete` 认为它是 unknown。而 `task-evidence-lint.sh:136-144` 对 `unknown` 的处理是**既不 pass 也不 fail，一行输出都没有**——该任务的模式维度完全静默。这与批次 2 立的「静默跳过＝假绿」红线（`tests/README.md:317-343`）直接冲突。

### 处置方案

**方案 A · 纠正**

分两档：

- **收敛真漂移的 4 组**（`execution_mode`、`extract_task_id`、`has_frontmatter`、`frontmatter_value`）到 `_lib.sh` 单一实现。
  **代价：这不是重构，是行为变更。** 合并 `execution_mode` 时必须在两种口径里选一种，选哪种都会改变一半脚本的真实行为。需要各自的回归测试。
- **合并纯冗余的 `task_body`×4** 到 `_lib.sh`。零行为风险（四份逐字节相同），但 `task_body` 的四个调用方分属四个 SDD 脚本，需确认它们都已 source `_lib.sh`。

**方案 B · 注释**

给「刻意的独立副本」加统一的头注释，说明为什么不合并：

```bash
# Deliberate standalone copy: this script must run in a host without _lib.sh
# (see spec-select.sh:6-8). Do not merge into _lib.sh.
json_escape() { … }
```

meta-lint 规则 4 改为「只对带此标记的副本放行」，其余报警。这样 allowlist 不需要列 15 行 `json_escape`，标记直接写在代码里、review 中可见。

**倾向**：

- 规则 4 **不能全自动判定**。md5 相同/不同都不足以判断，必须人工区分「表层差异」与「实质漂移」。建议规则实现为「报告全部重复项 + 标出 md5 是否一致」，由人判读，而不是直接给红绿。
- 方案 B 用于噪声档（在代码里加标记，比 allowlist 更持久）。
- 真漂移的 4 组登记 `KNOWN-DEFECT`，其中 `execution_mode` 优先级最高——它同时是根因 H（多份定义漂移）和「静默跳过」两条红线的交点。

---

## 规则 5：诚实 skip 检查

> 设计原文（`:124`）：门禁 `exit 0` 前无「NOT verified / skipped」输出即报警。

### 命中面

`harness-template/halo/kernel/delivery/gates/` 下共 **14 个 `exit 0`**，分三类：

| 类别 | 数量 | 判定 |
|---|---|---|
| 正常 PASS 出口 | 4 | 噪声（`ac-coverage.sh:307`、`drift-check.sh:584`、`compliance.sh:173,185`） |
| CLI 动作出口（`spec-lock.sh` 的 acquire/release/status/clean） | 4 | 噪声（非门禁语义） |
| **跳过型出口** | **6** | 见下表 |

| # | 位置 | 前置输出 | 含 `skipping` | 含 `NOT verified` |
|---|---|---|---|---|
| 1 | `gates/ac-coverage.sh:38` | `⚠️  No spec file found, skipping` | ✅ | ❌ |
| 2 | `gates/drift-check.sh:36` | `⚠️  No spec file found, skipping` | ✅ | ❌ |
| 3 | `gates/spec-lint.sh:17` | `⚠️  No spec file found, skipping` | ✅ | ❌ |
| 4 | `gates/compliance.sh:38` | `⚠️  No spec file found, skipping compliance check` | ✅ | ❌ |
| 5 | `gates/compliance.sh:42` | `⚠️  Spec not found: $SPEC`（修复前） | ❌ | ❌ |
| 6 | `gates/ac-coverage.sh:156` | `⚠️  No AC numbers found in spec` + `write_gate_json "skip"` | ❌（仅 JSON 里有 `"status":"skip"`） | ❌ |

> 【复核订正】初版漏掉 **`spec-lint.sh:17`**，导致 4+4+5 = 13 ≠ 14。它与 `ac-coverage.sh:38`、`drift-check.sh:36` 是**逐字相同的第三份副本**（同一 `find_spec` 失败分支），而且 `spec-lint.sh` 全文只有这一个 `exit 0`（正常 PASS 走 `_lib.sh:282 print_summary` 的 `return 0`），不可能被归进「正常 PASS 出口」。

**六处全部缺 `NOT verified`**（本表为基线 `c093b71` 的状态；六处已于 2026-08-25 与
2026-09-07 分两批全部处置——`compliance.sh:42` 改方向，其余五处补文案）。

`compliance.sh:42` 是其中最恶劣的一处（**已修复**）：

```bash
[[ -f "$SPEC" ]] || { echo "⚠️  Spec not found: $SPEC"; exit 0; }   # 修复前
```

同种情况（spec 路径明确给了但文件不存在）在另外三个门禁都是 `exit 1`：

```bash
ac-coverage.sh:43:  [[ -f "$SPEC" ]] || { echo "Spec file not found: $SPEC"; exit 1; }
drift-check.sh:41:  （同型 exit 1）
spec-lint.sh:20:    [[ -f "$SPEC" ]] || { echo "File not found: $SPEC"; exit 1; }
```

即 compliance 门禁在「spec 文件不存在」时报绿。这不是 skip 语义不完整的问题，是**方向搞反**（根因 C）。

> 【复核补充】把范围从四个门禁扩大到整个 kernel，「spec 文件不存在」时的处理还有五处，**全部是 `exit 1`**：`task-brief.sh:19`、`review-package.sh:35`、`spec-status.sh:34`、`summary-draft.sh:33`、`spec-state-lint.sh:21`。`compliance.sh:42` 是**全 kernel 唯一**报绿的一处——比初版举证的更孤立。
>
> **已随本批修复**，见 `docs/bug_report/2026-08-25-compliance-missing-spec-fail-open-analysis.md`。

### 对照：`gate_skip` 是正确的样板

`drift-check.sh:144-149` 的 `gate_skip()` 同时做四件事：输出含 `NOT verified` 的消息、写 `findings[].status = "skip"`、递增 `SKIPPED`、记入 `SKIPPED_DIMENSIONS[]`。17 处调用里 16 处消息含 `NOT verified`，唯一例外是 `:236` 的 `gate_skip "Table '$table': not found in model"`。

`drift-check.sh:575-578` 的收尾输出是全库最好的诚实 skip 样板：

```bash
echo "📊 Drift Check: no drift in $RUN_COUNT verified dimension(s) · $SKIPPED NOT verified"
printf "   NOT verified: %s\n" "$(…)"
echo "   A skipped dimension was not compared. Do not read this as contract alignment."
```

**但 `ac-coverage.sh` 与 `compliance.sh` 没有 `gate_skip`，也没有 `mark_checked`/`checks_run` 机制。** 它们的「跳过」只体现在 JSON 的 `status` 字段，stdout 上看不出来。

> 【2026-09-07 登记·口径外残留】`compliance.sh:143` 的
> `echo "  ⏭️  Context knowledge is empty, skipping"` 与本规则修的五处同型，
> 但**本规则扫不到它**——规则 5 的口径是「门禁 `exit 0` 前」，而这一处不在 `exit 0` 站点上。
> 严重度也更低：它同时 `record_finding "knowledge_reference" "skip"`，**JSON 侧是诚实的**，
> 缺的只有 stdout 那半句。
>
> 登记在此而不是顺手改掉，是因为它和 ②`checked.*` / ③`checks_run` 属同一件待办：
> 等 `gate_skip` 三件套提到 `_lib.sh` 时一并处理。**同时它也是规则 5 口径的一个已知盲区**
> ——上线后别把「规则 5 零命中」读成「stdout 诚实性已全覆盖」。

### 处置方案

**方案 A · 纠正**

1. `compliance.sh:42` 改 `exit 0` → `exit 1`，与另外三个门禁对齐。**这是行为变更**：现在报绿的场景会开始报红。**已完成**（复核确认该分支此前无任何测试覆盖，改动不打红任何现有用例）。
2. 其余五处的输出补 `NOT verified` 字样。**代价：零。已完成（2026-09-07）**，五处现文案：

   | 位置 | 现文案 |
   |---|---|
   | `ac-coverage.sh:38` | `⚠️  No spec file found, skipping — AC coverage NOT verified` |
   | `ac-coverage.sh:156` | `⚠️  No AC numbers found in spec — AC coverage NOT verified` |
   | `drift-check.sh:36` | `⚠️  No spec file found, skipping — drift NOT verified` |
   | `spec-lint.sh:17` | `⚠️  No spec file found, skipping — spec lint NOT verified` |
   | `compliance.sh:38` | `⚠️  No spec file found, skipping compliance check — compliance NOT verified` |

   `skipping` 字样一并保留，二选一口径与收紧口径同时满足。
   契约单测：`tests/unit/gate-skip-honesty.bats`（齐平遍历四个门禁 + 反向断言
   「真比较过的门禁不得声称 NOT verified」）。实测「改文案零成本」的结论成立：
   `tests/run.sh` 与两份 `examples/*/try-it.sh` 全绿。

> 【复核订正】初版称第 2 项的代价是「`tests/smoke-test.sh` 与部分 bats 用例有 grep 门禁输出文案的断言，改文案会打红它们」，据此把它推迟到批次 4。**实测这个障碍不存在**：`tests/`（排 `vendor/`）对 `No spec file found` / `Spec not found` / `Spec file not found` / `No AC numbers found` 的断言**为零**；`tests/smoke-test.sh` 全文 `grep -c "compliance.sh"` = 0，根本不调这个门禁。
>
> 唯一沾边的 `tests/unit/lib-find-spec.bats:245` 是**否定**断言（`output != *"skipping"*`），且跑的是 ambiguous 路径（两份 spec → `SPEC_RC=2` → `exit 1`），与 skip 分支无关。
>
> 所以「等 smoke-test 删掉后同步成本下降」的理由不成立——补文案现在就是零成本。

更彻底的做法是把 `gate_skip` / `mark_checked` / `checks_run` 三件套从 `drift-check.sh` 提到 `_lib.sh`，让三个门禁共用。`ac-coverage.sh:3` 与 `compliance.sh:5` 确实都 source 了 `_lib.sh`（且 `_lib.sh` 里这三个函数目前都不存在，`grep` 零命中），所以这与规则 4 的「刻意独立副本」原则不冲突，可行。

**方案 B · 注释**

不成立。这六处的问题不是「缺注释说明为什么正确」，是行为本身不满足 `AGENTS.md:86-87` 明写的「没比较过的维度必须报未验证」。加注释等于把缺陷写进文档。

### 【复核订正·口径】规则 5 的判定关键词已定为「二选一」

设计原文 `:124` 写的是「门禁 `exit 0` 前无「NOT verified / **skipped**」输出即报警」——**二选一**。初版实际采用的是「必须有 `NOT verified`」的收紧口径，却称「照原文口径上线，不收窄」。这个分歧初版没点破。

**已定：照设计原文字面，二选一。** 命中面随之从 6 降为 **2**：

| 命中 | 放行（含 `skipping` 字样） |
|---|---|
| `compliance.sh:42`（无任何 skip 字样） | `ac-coverage.sh:38` |
| `ac-coverage.sh:156`（`skip` 只在 JSON 里） | `drift-check.sh:36` |
| | `spec-lint.sh:17` |
| | `compliance.sh:38` |

**曾经必须记录的落差（2026-09-07 已部分闭合）**：被放行的这四处此前**不满足**
`AGENTS.md:86-87` 与 `tests/README.md:323` 的三条硬契约（① 输出含 `NOT verified`；
② 对应的 `checked.*` 为 false；③ 不计入 `checks_run`）。规则 5 按字面口径管不到它们，
所以这在当时不是「缺陷消失」而是「规则覆盖不到」。

现状：

- **① 已闭合**——六处出口现在全部含 `NOT verified`（含被放行的四处），
  按收紧口径也已达标。契约由 `tests/unit/gate-skip-honesty.bats` 守住，
  不再依赖规则 5 是否收窄。
- **②③ 仍未闭合，但需要重新表述**。实测 `mark_checked` / `checks_run` / `checked.*`
  **只存在于 `drift-check.sh`**（`:58`、`:67`、`:165`），`ac-coverage.sh` 的
  `write_gate_json`（`:69-99`）根本没有 `checked.*` 字段，`compliance.sh` / `spec-lint.sh`
  也没有这套机制——这与本文档「对照：`gate_skip` 是正确的样板」一节的观察一致。
  更关键的是：这四处出口都在**写任何 gate JSON 之前**就 `exit 0`，所以对它们而言
  ②③ 不是「没满足」，是**没有可满足的对象**。

  因此 ②③ 的真实待办不是「补两个字段」，而是本节处置方案里那条「更彻底的做法」——
  把 `gate_skip` / `mark_checked` / `checks_run` 三件套提到 `_lib.sh` 让三个门禁共用。
  **该项仍未做。** 在做之前，别把「规则 5 绿」读成「诚实 skip 已达标」：
  达标的只有输出文案这一层。

**倾向**：

- 第 1 项（`compliance.sh:42`）已完成。它是全 kernel 唯一一处「同种情况其他都报错、唯独这里报绿」的 fail-open 不一致。
- 第 2 项（补 `NOT verified` 文案）成本为零，**已于 2026-09-07 完成**，未等批次 3。
  实测印证了「零成本」：`tests/run.sh` 全绿、两份 `examples/*/try-it.sh` 全绿，无一处需要迁就。
- 规则 5 是五条规则里信噪比最好的一条：14 个 `exit 0` 里 8 处噪声、6 处真缺陷，且按二选一口径命中的 2 处全是真缺陷、零误报。

---

## 附：报告↔测试对应检查

> 设计原文（`:149`）：`docs/bug_report/` 下每份已处置报告（存在 `-analysis.md`）须有同名 `tests/regression/*.bats`。

`docs/bug_report/` 下 12 个逻辑条目，9 份有 `-analysis.md`。对拍 `tests/regression/` 下 **10 个对拍条目**（8 个 `.bats` 文件 + 2 个目录），共 **14** 个 `.bats` 文件：

> 【复核订正】初版写「12 个 `.bats`（含 2 个子目录）」——既不等于文件数 14，也不等于条目数 10。

| 条目 | 缺口 |
|---|---|
| `2026-07-31-sdd-gate-defects`（上报 #10） | **真缺测试**，`INDEX.md:51` 标注「批次 3 待迁」 |
| `2026-08-02-tdd-cycle-evidence-sigpipe`（上报 #11） | **真缺测试**，`INDEX.md:52` 标注「批次 3 待迁」 |
| `spec-lint-ac-gap-analysis.md` | **误报**。已在 `INDEX.md:50` 登记为命名例外（`:40-41` 只是解释这个坑的说明段），实际测试是 `2026-07-26-spec-lint-ac-number-gap.bats` |
| `2026-08-03-halo-gate-findings_2` | 目录存在但内容不全，`INDEX.md:54` 标注 §3.3 的 learn-draft 形态归批次 3 |

两份真缺口正是批次 3 明文承接的迁移项，不需要额外处置。**规则实现时必须支持「`.bats` 文件或同名目录」二选一**（`INDEX.md:25-38` 已写死此规则），且要读 `INDEX.md` 的豁免登记，否则 `spec-lint-ac-gap` 会持续误报。

---

## 汇总

**下表为复核后的数字**（初版数字见文首「复核记录」）：

| 规则 | 命中 | 噪声 | 缺注释 | 真缺陷 | 建议口径 |
|---|---|---|---|---|---|
| 1 失败方向注释 | 95 | 85 (89%) | 8 | 0 | **必须收窄**：只扫外部命令喂数据的循环 + 非纯空值过滤 |
| 2 pipefail 反模式 | 17（10 + 1 + 6） | 11 | 0 | **6** | **必须上线 2c**，但判定标准要写明 pipefail 取最右侧非零码 |
| 3 非确定性依赖 | 30 | 30 | 0 | **0** | 纯防回退。`find` 无 sort 子条误报率 100%，需收窄或改人工判读 |
| 4 重复定义 | 129 | ~估算 | ~估算 | **4 组** | **不能全自动**：报告 + 标 md5，人工判读。噪声/缺注释未穷尽分类，只有真缺陷数是精确的 |
| 5 诚实 skip | 14 | 8 | 0 | **6** | 二选一口径（命中 2 处，零误报）；余下 4 处的落差另行登记 |

**真缺陷合计 12 处 / 4 组**（初版称 20 处 / 4 组）。登记在案的原有 2 处（`guide.sh:216/223`），其余为复核新发现。

**处置进度（截至 2026-09-07）：已修 7 处，余 5 处 / 4 组。**

| 批次 | 已修 | 测试 |
|---|---|---|
| 2026-08-25 | `ac-coverage.sh:188`（pipefail 硬崩）、`compliance.sh:42`（fail-open 报绿） | `regression/2026-08-25-*.bats` ×2 |
| 2026-09-07 | 规则 5 剩余五处 skip 文案 | `unit/gate-skip-honesty.bats` |
| 2026-09-07 | `task-evidence-lint.sh` 的 `unknown` 静默跳过（本文档「复核补充」登记的额外项，不在五条规则的命中面统计内） | `regression/2026-09-07-task-evidence-lint-unknown-mode-silent-skip.bats` |
| 2026-09-07 | `task-complete.sh` 的同型缺陷（独立评审发现，清单原先完全未登记） | 同上文件 |

余下的 5 处 = 规则 2 的 `guide.sh:216/223`、`ac-coverage.sh:266`、`pipeline.sh:203/235`；
4 组 = 规则 4 的 `execution_mode` / `extract_task_id` / `has_frontmatter` / `frontmatter_value`。

### 若只能动一处

按「纠正成本 ÷ 风险收益」排序（**第 2–5 项已动，第 6–7 项待办**）：

1. ~~**规则 3 的 6 处加 `| sort`**~~ —— **已作废**，对象不存在（见规则 3 的复核订正）。
2. **`ac-coverage.sh:188` 补 `|| true`** ✅ 已修复（2026-08-25）—— 唯一一处会让门禁**硬崩**的缺陷，且 node 项目用 jest 参数化写法即触发。
3. **`compliance.sh:42` 的 `exit 0` → `exit 1`** ✅ 已修复（2026-08-25）—— 一行改动，闭合全 kernel 唯一一处「同种情况其他都报错、唯独这里报绿」的 fail-open 不一致。
4. **`task-evidence-lint.sh:136-144` 的 `unknown` 静默跳过** ✅ 已修复（2026-09-07）—— 补 `else` 分支，fail-closed。触发门槛比本文档原先认定的低得多，不依赖根因 H，见「处置记录（2026-09-07）」的订正 1。
5. **规则 5 的五处 skip 文案** ✅ 已修复（2026-09-07）—— 零行为风险，实测零成本。
6. **`pipeline.sh:203/235`** —— **未修，现列为规则 2 的队首**。实测 64KB 一过即误判，而管道左侧是被测命令的完整输出，超阈值是常态。详见「【2026-09-07 实测】规则 2 五处的触发门槛对比」。
7. **`guide.sh:216/223`** —— 未修。登记最久，但实测触发需 1000+ 文件，且方向是假红。**排在 `pipeline.sh` 之后**，这是 2026-09-07 对本榜单原顺序的反转。

### 【复核补充】`unknown` 模式静默跳过 ✅ 已修复（2026-09-07）

`task-evidence-lint.sh:136-144`（基线行号）是 `if / elif / fi`，**没有 `else`**：

```bash
136  if [[ "$effective_mode" == "tdd" ]]; then …
142  elif [[ "$effective_mode" == "plan" ]]; then
143    pass_msg "$task_id plan mode (TDD evidence not required)"
144  fi
```

`effective_mode` 为 `unknown`（或任何第三值）时这段完全不执行：`FAILS`、`WARNS` 都不增加，`pass_msg`/`warn_msg`/`fail_msg` 一行都不输出。该任务的模式维度**静默消失**，而 `:150` 仍打印 `$TASK_COUNT completed task(s) checked`、`:157` 照常 `✅ PASS`。

这与 `tests/README.md:317-343` 的「静默跳过＝假绿」红线直接冲突。**本清单里唯一一处会产生假绿的缺陷。**

实测输出（修复前）：

```
── Completed task evidence ──
  ✅ T1 brief.md
  ✅ T1 review-package.md
  ✅ 1 completed task(s) checked

📊 Task Evidence Lint: 0 fail(s), 0 warning(s)
✅ PASS
```

> 【2026-09-07 实测订正】本节原先把它归为根因 H（`execution_mode` 多份定义漂移）的下游后果，
> 说「一份把 `execution_mode:` 写在 front-matter 块外的 spec 就能造出 `unknown`」。
> **实测不需要任何漂移**：`execution_mode()` 末行是 `printf '%s' "${value:-unknown}"`，
> spec front-matter 无 `execution_mode:`、plan 无 `Execution mode:`、plan 无 `执行模式：`、
> 任务体无 `Mode:`——四处全落空即得 `unknown`。**这是纯粹的漏写，不是漂移。**
>
> 这条订正改变了处置顺序：原先它被排在「`execution_mode` 四份定义收敛」之后
> （理由是「根因在上游」），实测表明两者可解耦，fail-closed 出口独立成立。已按此处置。
> 根因 H 的收敛仍应做——它消除的是**另一条**通往 `unknown` 的路径——但不再是本处的前置。

**修复**：补 `else` 分支，fail-closed，输出含 `NOT verified`，退出码变 1。
选 `fail_msg` 而非 `warn_msg` 的理由：收尾的 `✅ PASS` 只看 `FAILS`（`:156`），
报 warning 仍然是报绿，缺陷核心原样保留。
详见 `docs/bug_report/2026-09-07-task-evidence-lint-unknown-mode-silent-skip-analysis.md`。

### 待定夺清单

1. 规则 1 的口径是否收窄到「提取循环」？若不收窄，是否接受 93 条豁免？
2. 8 处失败方向注释是否在批次 3 补？统一标记用哪种措辞？（另需把 `drift-check.sh:337-338` 上移到紧贴 `:341`）
3. 规则 2 的 2c 子条真实分母是 6 不是 8。它**必须上线**（本该抓住 `ac-coverage.sh:188`），待定的是收窄到哪种形态。
4. ~~规则 3 的 6 处 `| sort`~~ —— **已作废**。改为：`find` 无 sort 子条 29/29 全误报，是收窄口径、还是改为「只报告不判红」？
5. 规则 4 是否接受「不能全自动判定」，改为报告 + 人工判读？
6. `execution_mode` 三种口径若要收敛，选 front-matter 严格解析还是行首 grep？**注意这是行为变更，选哪种都会改变一半脚本的真实行为，需独立 SOP。**
7. ~~`compliance.sh:42` 是否在批次 3 纠正？~~ —— **已修复**。
8. `allowlist.txt` 是否采用 `EXEMPT` / `KNOWN-DEFECT` 两类条目？后者「打印告警但不失败、只减不增」的语义是否接受？
9. `tests/smoke-test.sh` 排除出扫描范围（硬编码而非 allowlist）是否可接受？
10. ~~规则 5 按二选一口径放行的四处仍不满足 `AGENTS.md:86-87`，是补文案还是登记落差？~~ —— **已定并已做（2026-09-07）：补文案。** 连同 `ac-coverage.sh:156` 共五处，实测零成本。**但落差只闭合了「① 输出含 `NOT verified`」这一层**，②`checked.*` 与 ③`checks_run` 仍未闭合——见规则 5 的口径一节，它们的真实待办是把 `gate_skip` 三件套提到 `_lib.sh`。
11. ~~`task-evidence-lint.sh:136-144` 的 `unknown` 静默跳过是否排进批次 3 队首？~~ —— **已修复（2026-09-07）**，并订正了它对根因 H 的依赖关系。
12. **【新增】** 规则 2 的处置顺序按 2026-09-07 的阈值实测反转为 `pipeline.sh:203/235` 优先、`guide.sh:216/223` 次之、`ac-coverage.sh:266` 最后。这个顺序是否接受？三处是否合并成一批（同根因、同修法，`task-complete.sh:113-115` 有样板）？
13. **【新增】** `tests/unit/gate-skip-honesty.bats` 是本仓第一个「齐平遍历多个门禁」的契约单测。这种形态（一条用例循环四个门禁，而不是四份手写副本）是否作为同类契约的默认写法？

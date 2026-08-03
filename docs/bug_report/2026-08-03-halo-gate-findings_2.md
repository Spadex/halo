# Halo 门禁与工具链问题上报（monorepo 项目侧）

| 项 | 内容 |
|---|---|
| 上报方 | layrax `monorepo` 项目组 |
| 上报日期 | 2026-08-03 |
| kernel_version | `1.0.0` |
| 主要触发场景 | `model-set` spec 的 `/implement` → `/review` → `/verify` 全流程（2026-08-01 ~ 08-03） |
| 项目形态 | Python 3.12 + uv workspace + FastAPI + SQLAlchemy/Alembic；spec 与 plan 全中文书写 |
| 项目侧纪律 | 遵守「halo 框架问题只上报、不改框架代码」——`halo/kernel/**` 本期零改动，全部问题以规避手法绕过并留痕 |

本文所列每一条都在 2026-08-03 于 kernel `1.0.0` 上**现场复核过源码与实际输出**，
不是凭历史记录转述。文末第 4 节列出两条**此前上报、现已确认修复**的问题，供贵方核对回归覆盖。

---

## 1. 高优先级：`drift-check` 对非 Go / 非数值码项目结构性失效

### 1.1 错误码漂移检测：数值码 + Go 文件双重硬编码

**位置**：`halo/kernel/delivery/gates/drift-check.sh:214-238`

**现象**：本期 spec 第 5.3 节明确定义了新增业务错误码 `REFERENCE_IN_USE`（HTTP 409），
门禁输出却是 `⏭️ No business error codes in spec`，该错误码从未被校验。

**根因**（两处独立的硬编码，任一处都足以让检测失效）：

```bash
# :214-216 —— 只从「首列为纯数字」的表格行提取错误码
SPEC_CODES=$({ grep -E '^\| *[0-9]+ *\|' "$SPEC" || true; } | \
  awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); if ($2 ~ /^[0-9]+$/) print $2}' | ...

# :223-225 —— 只扫 *.go 文件
CODE_CONSTS=$(find "$PROJECT" -name '*.go' -not -path '*/vendor/*' \
  -exec grep -ohE "${CONST_PAT:-'(Code|Err)[A-Za-z]+ *= *[0-9]+'}" {} + 2>/dev/null | ...
```

1. **spec 侧**假定错误码是**数值**（如 `40001`）。本项目错误码是字符串枚举
   （`REFERENCE_NOT_FOUND` / `DUPLICATE_KEY` / `REFERENCE_IN_USE`），首列永远不是纯数字 → 提取结果恒为空。
2. **代码侧**即使 spec 提取成功，`find -name '*.go'` 也决定了**任何非 Go 项目必然走
   `No error code constants found` 分支**——尽管 `manifest.yaml` 里 `project.language: python`。
   `manifest.drift.error_codes.const_pattern` 可配置，但它只是喂给 grep 的模式，
   **文件类型 `*.go` 不可配置**，所以配置项在这里是无效的旋钮。

**复现**：

```bash
bash halo/kernel/delivery/gates/drift-check.sh halo/specs/model-set/spec.md .
# 观察 "── Error code drift detection ──" 段输出：
#   ⏭️  No business error codes in spec
```

**影响**：`drift_count: 0` + `✅ PASS` 会被读成「契约无漂移」，实际语义是「**一条都没比对**」。
这是一个**静默失效**：门禁绿灯，但对本期核心契约零鉴别力。本项目已连续两期（model-upload
2026-08-01、model-set 2026-08-03）在 `verify.md` 中登记同一现象。

**修复建议**（按投入排序）：

- 最小改动：把 `find -name '*.go'` 改为按 `manifest.project.language` 分派后缀，或增加
  `manifest.drift.error_codes.file_glob` 配置项。
- spec 侧提取放宽为「表格首列匹配大写蛇形常量 `^[A-Z][A-Z0-9_]+$`」，与数值码并存，两者取并集。
- 若短期不打算支持非 Go：**把 skip 文案改为可辨识的口径**，例如
  `⏭️ Error code drift: unsupported for language=python (skipped, NOT verified)`，
  并在 eval JSON 里区分 `drift_count: 0` 与 `drift_checked: false`。目前二者不可区分是最大的问题。

### 1.2 路由漂移检测：表格列位置硬编码 + FastAPI 分支未实现

**位置**：`halo/kernel/delivery/gates/drift-check.sh:163-203`

**现象**：本期 spec 5.1 定义了 `/model-sets` 六个端点，门禁输出 `⏭️ No routes in spec API table`。

**根因**：

```bash
# :163-170 —— 方法必须在第 3 个 awk 字段、路径在第 4 个（即 markdown 表格的第 2、3 个单元格）
SPEC_ROUTES=$({ grep -E '^\|.*\| *(GET|POST|PUT|DELETE|PATCH) *\|' "$SPEC" || true; } | \
  awk -F'|' '{ method=$3; path=$4; ... }' | sort)
```

只要 spec 的 API 表把方法放在第 1 列（本项目写法：`| 端点 | 方法 | 说明 | ... |` 之外的任何列序），
提取即为空。表格**列序**成了隐式契约，而任何文档都没有声明它。

即便提取成功，后续 `case "${FRAMEWORK:-none}"` 中：

- `gin|echo|chi` → 实现了检测（仍是 `find -name '*.go'`）
- `express|fastapi` → `gate_skip "... not yet implemented (contributions welcome)"`
- `none|*` → 跳过

本项目 `manifest.drift.routes.framework: "uv workspace"` 落入 `*` 分支。**结论：Python/FastAPI
项目的路由漂移检测目前完全不可用**，无论 spec 怎么写。

**复现**：同 1.1 的命令，观察 `── Route drift detection ──` 段。

**修复建议**：

- 表格解析改为**按表头名定位列**（找到含 `Method`/`方法` 的列索引），而非固定 `$3`/`$4`。
- FastAPI 分支可用极简实现覆盖大部分场景：`grep -rhoE '@router\.(get|post|put|patch|delete)\("([^"]*)"'`
  再与 `APIRouter(prefix=...)` 拼接。本项目 `apps/layrax-model/src/layrax_model/routers/*.py` 是标准写法。
- 同 1.1：未实现的分支应在 eval JSON 中体现为「未检查」而非「无漂移」。

---

## 2. 中优先级：工具链缺陷

### 2.1 `review-package.sh` 只 diff 工作树，实施已提交时产出空评审包

**位置**：`halo/kernel/orchestrator/sdd/review-package.sh:58` 与 `:64`

```bash
git_cmd diff --stat
...
git_cmd diff -- .
```

**现象**：`git diff` 不带 `--cached`、不带 commit 范围、不含 untracked 文件。因此：

- 实施者按纪律**逐任务提交**后（本项目的标准做法，本期 11 个 commit），工作树为空 →
  评审包 diff 段全空，评审者拿到一份**零信息**的评审包。
- 绿地开发的新文件（untracked）同样不入包——本期 `model_set.py`(193 行)、
  `routers/model_sets.py`(115 行)、`test_model_sets.py`(1467 行) 若未提交则全部缺席。

**影响**：`/review` 技能的输入依赖该包。本期评审者只能**按 commit 范围自建**
`.halo/sdd/model-set/branch/review-package.md`（`git diff ff84ad1..926db20`），
框架产出的包被弃用。这削弱了评审链路的可复现性——不同评审者自建的包范围可能不一致。

**复现**：

```bash
# 在一个所有改动均已提交、工作树干净的 spec 分支上
bash halo/kernel/orchestrator/sdd/review-package.sh <spec-id> branch
# 生成的 review-package.md 的 diff 段为空
```

**修复建议**：接受可选的 base ref 参数（`--base=<ref>`，缺省用 `git merge-base HEAD main`），
diff 命令改为 `git diff <base>...HEAD`，并追加 `git diff` 与 `git status --porcelain`
覆盖未提交与未跟踪部分。三段合并即可同时覆盖「已提交」「已暂存」「未跟踪」三种形态。

### 2.2 `task-complete.sh` 的 SIGPIPE 竞态（**仍存在**）

**位置**：`halo/kernel/orchestrator/sdd/task-complete.sh:115` + `halo/kernel/_lib.sh:12`

```bash
# _lib.sh:12
set -euo pipefail

# task-complete.sh:115
if valid_tdd_evidence "$evidence" && yq -r '.ac_ids[]?' "$evidence" 2>/dev/null | grep -qxF "$ac"; then
```

**根因**：`grep -q` 命中后立即退出，上游 `yq`（Go 实现，无缓冲逐条 write）收到 SIGPIPE 以非零码退出；
`pipefail` 下整条管道判失败 → 明明匹配上的 AC 被判为「无证据」。

**触发条件**：`ac_ids` 元素较多、且目标 AC **不在末位**时几乎必然失败（此前期次实测：6 元素文件中，
末行 AC 恒过、中前段 AC 恒败）。本期 `model-set` 的 RED 任务 `ac_ids` 多为单元素或目标 AC 恰在末位，
**未触发**，故本期无新增实测数据；但源码模式与 `pipefail` 设置均未变，缺陷仍在。

**补充实测（`layout-furnish-api`，2026-08-03 同日）——首次拿到 `PIPESTATUS` 级证据**：
同一份 5 元素 `ac_ids`（`AC-4`…`AC-8`）的 `tdd-evidence.json`，对首元素与末元素各连测 5 次：

| 目标 AC | 位置 | 连测 5 次的 `PIPESTATUS` | 结果 |
|---|---|---|---|
| `AC-4` | 首元素 | `141 0` ×5（141 = 128+13，`yq` 被 SIGPIPE 杀） | 恒败 |
| `AC-8` | 末元素 | `0 0` ×5 | 恒过 |

这坐实了根因判断，并把结论从「几乎必然失败」收紧为：**只有 `ac_ids` 的最后一个元素能被可靠匹配，
覆盖 N>1 个 AC 的 RED 任务用单份证据在结构上不可能通过**——不是竞态偶发，是确定性失败。

⚠️ 复现时注意：用 `bash -x` 跟踪运行会因 trace 输出开销让 `yq` 抢先写完而**偶然通过**，
不要把这种侥幸当成「缺陷不存在」的证据。请按上表直接读 `PIPESTATUS`。

**项目侧规避**（沿用至今）：在 `RED-N/` 目录下按 AC 落**单元素分片** `cycle-AC-N/tdd-evidence.json`
（数据取自同一红绿循环，非伪证），唯一行即末行，恒安全。

**修复建议**：`yq -r '.ac_ids[]?' "$evidence" 2>/dev/null | grep -qxF "$ac"` 改为先落变量再匹配：

```bash
ids="$(yq -r '.ac_ids[]?' "$evidence" 2>/dev/null || true)"
if valid_tdd_evidence "$evidence" && grep -qxF "$ac" <<< "$ids"; then
```

或在该管道前后临时 `set +o pipefail`。

### 2.3 `plan-lint` 占位符正则误伤路径参数与不等号

**位置**：`halo/kernel/orchestrator/sdd/plan-lint.sh:214`

```bash
if grep -Eiq '\b(TODO|TBD|FIXME)\b|<[^>]+>|\{[A-Za-z_][A-Za-z0-9_-]*\}' <<< "$body"; then
  fail_msg "$task_id contains unresolved placeholder text"
```

**现象**：三类合法内容被判为「未解决的占位符」：

1. REST 路径参数 `{set_id}` / `{model_id}` —— 写 plan 时无法自然地描述端点。
2. 同一行内先后出现 `<` 与 `>`（例如「成员数 < 100 时…… > 1000 时降级」）会被拼成假的尖括号对。
3. 正文里出现字面 "TBD" 的自检句（例如「本节不得留 TBD」）同样命中。

**项目侧规避**：plan 中路由一律写冒号风格 `:set_id`，数学区间改写为 `≤` / `≥` 措辞，不写字面 TBD。

**修复建议**：把占位符判据收窄为「整行仅由占位符构成」或要求特定标记（如 `<<TODO>>`、`${...}`），
并把 `{[A-Za-z_]...}` 排除在外——它与 REST 路径参数、f-string、mermaid 语法冲突面太大。

---

## 3. 低优先级：中文 spec 场景下的识别口径与可用性

### 3.1 `compliance` 的 source-trace 只认英文 token

**位置**：`halo/kernel/delivery/gates/compliance.sh:136`

```bash
if grep -qiE '\| *(user|code|test|schema|contract|knowledge|external) *\|' "${SEARCH_FILES[@]}"; then
```

**现象**：本项目 spec 第 3 节「上下文依据」实际已按七类分栏记录来源
（用户输入 / 用户决策 / 代码事实 / 项目知识 / 历史 spec / 外部依赖 / 待确认），
但因为单元格是中文，门禁恒报 `⚠️ Context basis does not clearly record source categories`。

**影响**：软门禁不阻塞，但**每期都产生一条永不消失的噪声告警**，久而久之会训练出「告警可以忽略」的习惯，
削弱软门禁本身的信号价值。本项目已连续 10+ 个 spec 携带此告警。

**修复建议**：正则补充中文同义词（`用户|代码|测试|契约|知识|外部`），或改为可在
`manifest.yaml` 中配置的 token 列表（与 `specs.required_sections` 已支持中文的做法保持一致）。

### 3.2 `compliance` 的 knowledge-reference 按路径字符串匹配

**位置**：`halo/kernel/delivery/gates/compliance.sh` 的 Knowledge source check 段

```bash
if [[ "$TOTAL_KB" -gt 0 ]] && grep -qiE 'halo/context/knowledge|knowledge/' "${SEARCH_FILES[@]}"; then
```

判据是 spec 正文里出现**字面路径**。spec 若以自然语言引用同一条项目知识（本期即如此：
第 3 节引用了「进 git 的 dev DB 必须处于 alembic head」这条 `rules.md` 中的常设规则，
但没写出路径字符串），仍报告警。

**修复建议**：这条更接近「书写约定」而非缺陷，建议在告警文案中直接给出满足条件的写法
（「在 spec 中写出 `halo/context/knowledge/<file>.md` 路径即可消除本告警」），
让告警自带修复指引，避免每个项目各自摸索。

### 3.3 `summary-learn-draft.sh` 只认英文精确标题

**位置**：`halo/kernel/context/summary-learn-draft.sh:47`

```awk
/^## Knowledge Candidates[[:space:]]*$/ { capture = 1; next }
```

中文 verify.md 写「## 11. 知识候选」一律提取不到，报 `No durable knowledge candidates found`；
双语标题也不行（要求整行精确匹配，不允许编号前缀）。

**更好的项目侧规避（`layout-furnish-api` 2026-08-03 实测）**：把 verify.md 该节的标题**直接写成
英文 `## Knowledge Candidates`**（中文说明移到节内正文首行），helper 即可正常产出 draft，
不必放弃自动化。两点代价：① awk 会把标题下的**所有非空行**都当候选（含说明段落），
draft 里需人工剔除；② 该节在中文文档里成为唯一的英文标题，须就地注明缘由否则后人会「修正」回中文。

**同时发现：`learn-draft.sh promote --to=<表格式知识文件>` 不可用**（`halo/kernel/context/learn-draft.sh`）。
本仓 `halo/context/knowledge/*.md` 均为**表格**结构，而该脚本把 draft 的 Lesson Candidate 段
**追加成 `## Promoted Learn Draft` 小节**到文件末尾（表格之外、`## Do Not Repeat` 之后），
写入的是**裁断过程而非知识本身**，污染文件结构，须手工删除。

建议的正确流程（本期已按此执行）：`summary-learn-draft.sh` 产 draft → 在 draft 内做裁断与实证记录
→ **手工**往表格加行 → `knowledge-review.sh approve` 留评审事件 → `knowledge-lint.sh` 复检；
**跳过 `learn-draft.sh promote`**。

**修复建议（追加）**：`learn-draft.sh promote` 应识别目标文件是表格式还是小节式，
或至少在 `--to` 指向表格文件时给出警告而非静默追加。

**修复建议**：放宽为 `^#{1,3}[[:space:]]+.*([Kk]nowledge [Cc]andidates|知识候选)`，与 `prismspec/bin/lint.sh`
的 `contains_heading` 已有的宽松匹配方式保持一致（同一套工具链内两种严格度容易踩坑）。

### 3.4 `knowledge-lint.sh` 的未来日期判定按 UTC

**位置**：`halo/kernel/context/knowledge-lint.sh:97` 与 `:115`

```bash
today="$(date -u +%Y-%m-%d)"
...
elif [[ "$verified_at" > "$today" ]]; then   # 报 future-verified_at
```

本项目在 UTC+8 时区，本地 00:00–08:00 之间写入「今天」的日期会被判为未来日期并告警。
**项目侧规避**：`verified_at` 一律填 UTC 日期。

**修复建议**：允许一天的容差（比较 `today + 1`），或在告警文案中注明判定基准是 UTC。

### 3.5 `prismspec/bin/lint.sh` 的 check 名与产物名不一致（可用性）

产物文件是 `verify.md`，而对应的 check 名是 `evidence`；`bash prismspec/bin/lint.sh <dir> verify`
会直接报 `Invalid check: verify` 并退出 1。这是一个每次都要查一遍 usage 的小摩擦。

**修复建议**：把 `verify` 加为 `evidence` 的别名（`all|spec|plan|evidence|verify|skillpack`），零风险。

---

## 4. 流程设计反馈（非缺陷，但值得纳入文档）

### 4.1 「RED 全部前置」的 plan 形态与 `red_task_has_cycle_evidence` 存在结构性张力

**涉及**：`plan-lint.sh`（要求全部 RED 任务列在 T 任务之前）
+ `task-complete.sh:107-123`（`red_task_has_cycle_evidence` 要求该 RED 覆盖的**每条 AC**
都存在一份 `red.exit_code != 0` 且 `green.exit_code == 0` 的 `tdd-evidence.json`）。

而 `green` 段数据**只有对应 T 任务转绿后才写得出**。两条规则合起来意味着：
**RED-N 永远无法早于其转绿责任任务 T-N 被标记完成**，实际执行单位是「RED-N + T-N」红绿对，
而不是 plan 结构所暗示的「先跑完所有 RED，再跑所有 T」。

当一条 AC 跨任务转绿时还要顺延（本期 AC-13 由 T3 满足前两段、T4 满足第三段，
故 RED-4 直到 T4 完成才能 complete）。

**这不是 bug**——两条规则各自都合理。但对首次按 tdd 模板写 plan 的人来说，
`task-next.sh` 卡在某个 RED 上会被误读为工具故障。**建议**：在 tdd plan 模板或
`prismspec-planning` 技能文档中显式写明「RED 与 T 成对执行」，
或让 `task-complete.sh` 在该分支下输出更具指向性的提示
（当前失败信息不指出「证据要等 T 任务转绿后才存在」）。

### 4.2 回归护栏类 AC「首跑即绿」在 tdd 模式下缺少表达方式

本期 AC-19 断言「既有契约未被本期破坏」（迁移文件计数、`model` 表列集合、
`CREATE_REQUIRED_FIELDS` 元组不变）。这类护栏在**正确实现下本就该绿**——
它没有「被测行为缺失」的阶段，`RED-7` 首跑退出码即为 0。

项目侧的处理是：不弱化断言、不倒退实现制造伪红，改用**变异法**取红证据
（往新 revision 的 `upgrade()` 里加一句 `op.add_column('model', ...)`，AC-19 当场失败于
`test_model_sets.py:1325`——该条记录于 `.halo/sdd/model-set/T6/report.md` 第 3 节，
非本次复核现场重跑），并在 `tdd-evidence.json` 的 `red` 段记录变异下的命令与退出码、
在 summary 注明缘由。

**建议**：`tdd-evidence.json` 的 schema 增加一个可选字段（如 `red.method: "mutation"`
与 `red.mutation_description`），让这类合法情形有**结构化表达**，而不是只能写进自由文本 summary。
否则日后审计 21 份证据时，无法从机器侧区分「变异法取红」与「伪造红绿数据」。

---

## 5. 本次复核确认**已修复**的历史上报项

以下两条曾由本项目在此前期次上报，**2026-08-03 复核源码确认已修复**，列出供贵方核对回归覆盖：

| 原问题 | 复核结论 | 证据 |
|---|---|---|
| `spec-lint` 假定每个 spec 的 AC 编号从 1 连续，对前端增量 spec 的全局编号（AC-12..22）误报 `AC number gaps`（layout-canvas 2026-07-25 上报） | ✅ **已修复** | `spec-lint.sh:140-144` 注释明确「起点可以非 1，前端增量 spec 延续全局编号」，仅报真实内部缺号（如 12,14 缺 13） |
| `task-complete.sh` 不识别任务级执行模式，tdd spec 里标注「模式: plan」的工具/收口任务照样被索取 `tdd-evidence.json`（layout-solve-trace 期上报） | ✅ **已修复** | `task-complete.sh:200-202`：`EFFECTIVE_MODE="$(task_mode "$BODY")"`，任务级优先、spec 级仅作 fallback |

另有两条更早的修复（`ac-coverage` 跨 spec 别名盲区 2026-07-25、`spec-lint` AC 单元格交叉引用误报
2026-07-19）在本期持续受益：本期 20 条 AC 全部经 AC 表末列声明的桥接函数名走 Tier 1 精确归属，
`20/20 (100%)`，未出现任何跨 spec 撞号问题（本仓 `test_ac1..test_ac17` 被多个 spec 重复占用）。

---

## 6. 附：本期用于复现的环境

```
kernel_version : 1.0.0
project        : monorepo (python 3.12.13)
工具            : yq v4.53.3 / uv 0.11.6 / node v25.9.0
spec           : halo/specs/model-set/spec.md (611 行, 20 AC, 61 decision items)
pipeline       : ✅ 9  ❌ 0  ⏭️ 1 / 10，ALL PASS
eval JSON      : halo/state/eval-runs/20260803T031536Z-41768.json
verify 证据     : halo/specs/model-set/verify.md（第 7 节登记 drift-check 与 compliance 两项）
review 证据     : halo/specs/model-set/review.md（R-3 / R-4 登记 drift-check 与 review-package）
```

复现全部门禁：

```bash
bash halo/kernel/delivery/pipeline.sh --json-out
```

---

## 7. 补充上报：`style-i18n-seed` 期新发现（2026-08-03，同日）

### 7.1 高优先级：`ac-coverage` 的 AC 编号提取按整行盲扫且允许空编号

**位置**：`halo/kernel/delivery/gates/ac-coverage.sh:137`

**现象**：`style-i18n-seed` 的 13 条 AC 在门禁自己的覆盖矩阵中**逐条 ✅**（全部经 Tier 1
精确归属命中），门禁却判 `13/15 (86%) ❌ FAIL — uncovered: AC- AC-99`。多出来的两条 AC
在 spec 中并不存在——它们是提取环节凭空造出来的。

**根因**：

```bash
SPEC_ACS=$({ grep -E '^\| *AC-[0-9]+ *\|' "$SPEC" || true; } | \
           { grep -o 'AC-[0-9]*' || true; } | sort -t- -k2 -n | uniq)
```

第一段 `grep -E` 正确地按**行首单元格**筛出 AC 行，第二段 `grep -o` 却对**整行**扫描，于是：

1. `AC-[0-9]*` 的 `*` 允许**零位数字**——行内任何 `AC-<非数字>` 都会被截成伪 AC `AC-`。
   本期 spec 的 AC-12 / AC-13 行含前端命名空间标签 `AC-STYLE-12`（该标签形式正是为规避
   本仓 `ac-tag-substring-collision` 而采用的），于是产出 `AC-`。
2. 行内**引用**的其它编号被当成本期待覆盖的 AC。本期 AC-13 的 Given 里 `AC-99` 是
   「库中不存在的标签」这一负例的字面量，却被当成第 15 条验收标准。

**最小复现**（不依赖本项目）：

```bash
$ echo '| AC-13 | tag `AC-STYLE-12` 与 `AC-99` |' | grep -o 'AC-[0-9]*'
AC-13
AC-        ← 伪 AC：`[0-9]*` 允许零位数字
AC-99      ← 行内引用的负例编号被当成本期 AC
```

**影响**：任何在 AC 行正文里出现命名空间标签（`AC-<域>-<n>`）、或引用他期/负例编号的
spec，都会凭空多出**永不可覆盖**的 AC 而 FAIL；由于 pipeline 在此 fail-fast，其后的
`integration-test` / `drift-check` / `compliance` 三步全部跑不到。本期只能以
`pipeline.sh --only=<step>` 逐步补跑，并在 `verify.md` 记为「已知缺陷豁免」。

**建议修复**：AC 编号只从行首第一个单元格取，且要求至少一位数字：

```bash
SPEC_ACS=$(sed -nE 's/^\| *(AC-[0-9]+) *\|.*/\1/p' "$SPEC" | sort -t- -k2 -n | uniq)
```

注意这与 §2.3 / 下述 7.2 的 `plan-lint` 是同一类「跨语境归属」缺陷：门禁把 spec 正文里
**被提及**的编号等同于**本期认领**的编号。

### 7.2 中优先级：`plan-lint` 的 `AC-\d+` 全文盲扫（与 7.1 同源）

**位置**：`halo/kernel/orchestrator/sdd/plan-lint.sh`

**现象**：spec 正文中引用**其它 spec 的编号**（本期为 model-upload 的 `AC-15`，因本期按
该 spec 的 D-12 修正了它的迁移数断言口径）也被索取 plan 侧覆盖说明，否则 fail。

**规避（本仓既有手法）**：在 `plan.md` 的「非本期验收项」清单中枚举该编号即转绿。本期
已如此处理 `AC-15` / `AC-22` / `AC-23` / `AC-99`，`plan-lint` 因此 0 fail / 0 warning。

**建议**：与 7.1 一并按「AC 表首列 = 本期认领」的口径收敛。

### 7.3 澄清：`tdd-evidence.sh` 的畸形路径不是框架缺陷

本期评审曾把一处畸形证据路径（`.halo/sdd/<spec>/RED-4 .halo/sdd/.../tdd-evidence.json/`，
`task_id` 被污染为整串路径）记为「调用侧参数未加引号被切分」的框架问题。verify 期复核
`tdd-evidence.sh:36-66` 后确认**框架行为正确**：位置参数与 `--out=` 的解析均已正确加引号，
真实成因是调用方把 `--out=` 的值与 task-id 一起塞进了第二个位置参数。特此更正，避免贵方
误查。**可加固点（建议，非缺陷）**：对 `TASK_ID` 做形状校验（禁空格与斜杠），把这类静默
畸形变成显式报错。

### 7.4 本节复现环境

```
kernel_version : 1.0.0
spec           : halo/specs/style-i18n-seed/spec.md (417 行, 13 AC, 35 decision items)
pipeline       : ✅ 6  ❌ 1（停在 ac-coverage）/ 7，其余 3 步以 --only 补跑全 PASS
eval JSON      : halo/state/eval-runs/20260803T051558Z-23171.json
verify 证据     : halo/specs/style-i18n-seed/verify.md（第 5 节登记本节三项）
```

---

## 8. 补充上报：`layout-furnish-api` 期新发现（2026-08-03，同日）

### 8.1 高优先级：「当前 spec」的判定锚在文件 mtime 上，git 操作后会静默验错 spec

**位置**（两处**重复实现**，非共用函数）：

```bash
# halo/kernel/_lib.sh:155  —— find_spec() 的兜底分支
latest=$(find "$PROJECT_ROOT/$spec_dir" -name 'spec.md' -type f -not -path '*/.locks/*' -print0 \
         | xargs -0 ls -t 2>/dev/null | head -1)

# prismspec/bin/guide.sh:106 —— 同一逻辑的另一份拷贝
latest=$(find "$SPEC_ROOT" -name spec.md -type f -not -path '*/.locks/*' -print0 \
         | xargs -0 ls -t 2>/dev/null | head -1 || true)
```

**根因**：`manifest.specs.active` 为空时（本仓一直为空），两处均以 **`ls -t`（文件 mtime）最新**
作为「当前 spec」。mtime 是文件系统的偶发属性，**任何 git 操作都会重写它**——`merge`、`checkout`、
`rebase`、`stash pop` 检出文件时一律刷成当前时刻，与「哪个 spec 是本次工作对象」毫无语义关联。

**本期实测**：`layout-furnish-api` 收口后合并 `main`（带入 `style-i18n-seed` 等 10 个提交），

| spec.md | mtime | 来源 |
|---|---|---|
| `layout-furnish-api/spec.md` | `Aug 3 13:52:14` | `spec-status.sh` 推进 verified 时写入 |
| `style-i18n-seed/spec.md` | `Aug 3 14:44:25` | **`git merge` 检出时刷新** |

于是 `bash halo/kernel/delivery/pipeline.sh --json-out`（不带 `--spec=`）验的是
`style-i18n-seed`，而非刚收口的 `layout-furnish-api`。`guide.sh --json` 同样从
`spec_id: layout-furnish-api` 翻转为 `spec_id: style-i18n-seed`——**整条工具链一起错**。

**为什么此前一直没暴露（掩盖机制）**：`spec-status.sh` 推进状态时会改写 `spec.md` 的
`updated_at`，顺带把 mtime 刷成最新。所以在「单分支、刚推进完状态就 verify」的常规流程里，
当前 spec 恰好总是 mtime 最新的那个，缺陷被完美掩盖。**只有 git 操作介入时才翻车**，
而这正是合并前收口验证的标准动作。

**危害等级**：本期是「错选的 spec 恰好 FAIL」，异常刺眼故被发现。真正危险的是**反面**——
若错选的 spec 恰好 PASS，则：

- 终端打印 `✅ ALL PASS`，无任何提示说验的是别的 spec；
- `eval-runs/*.json` 里 `spec_file` / `spec_hash` 指向**无关 spec**（本期失败那轮实录：
  `"spec_file": "halo/specs/style-i18n-seed/spec.md"`），而 `verify.md` 会照抄这份「通过」证据；
- `ac-coverage` 校验的是那个 spec 的 AC，本期 spec 的 AC **一条都没验**。

即一份**结构完整、内容无关**的假绿证据。这比 `drift-check` 空转更隐蔽——后者至少在输出里
逐项打印 `⏭️ No X in spec`，此项则全程无声。

**项目侧规避**：`/verify` 一律显式传 `--spec=halo/specs/<本期>/spec.md`；
或在 `manifest.yaml` 设 `specs.active`（但需每期手工改，易忘）。
读 `eval-runs/*.json` 时**先核对 `spec_file` 字段是否为本期 spec** 再采信结论。

**修复建议**（按优先级）：

1. **改用文档内的语义时间戳而非文件 mtime**：`spec.md` frontmatter 已有 `status` 与
   `updated_at`（ISO-8601），二者均随 git 内容走、不受检出影响。选「`status` 非 `verified`
   中 `updated_at` 最新者」比 `ls -t` 语义正确得多。
2. 或以 `halo/state/spec-transitions/*.json` 的最新事件为准（本仓已有该目录，文件名自带
   UTC 时间戳与 spec-id，天然是权威流水）。
3. **兜底至少要能被察觉**：候选多于一个时，把选中的 spec 与理由**打印到 stdout**
   （现在完全静默），或在存在多个 `status != verified` 的 spec 时直接要求显式 `--spec=`。
4. `_lib.sh:155` 与 `guide.sh:106` 两份拷贝应收敛为同一函数，避免将来只修一处。

### 8.2 本节复现环境

```
kernel_version : 1.0.0
本期 spec       : halo/specs/layout-furnish-api/spec.md（8 AC, 17 decision items）
误选 spec       : halo/specs/style-i18n-seed/spec.md
误选轮 eval    : halo/state/eval-runs/20260803T064611Z-94488.json
                 （spec_file 指向 style-i18n-seed，status=fail）
正确轮 eval    : halo/state/eval-runs/20260803T064754Z-19546.json
                 （--spec= 显式指定，9 pass / 0 fail / 1 skip）
verify 证据     : halo/specs/layout-furnish-api/verify.md §1.1
```

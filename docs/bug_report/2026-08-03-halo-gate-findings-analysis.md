# 分析：2026-08-03 门禁与工具链上报

上报原文：[`2026-08-03-halo-gate-findings.md`](2026-08-03-halo-gate-findings.md)
（来自 layrax `monorepo` 项目组，spec `model-set` 的 `/implement` → `/review` → `/verify` 全流程，
kernel 1.0.0，Python 3.12 + uv workspace + FastAPI + SQLAlchemy，spec 与 plan 全中文）。
上报者按纪律只上报不改框架代码，本文是 halo 侧的独立复核。

## 结论

10 条上报中 **8 条成立并已修复**，1 条已在此前提交中修复（上报者跑的是旧版本），
1 条本期不修（P2，见 §5）。

复核结论与上报定性有**四处不一致**，其中三处是**上报低估了严重度**。

| 条目 | 上报定性 | 复核结论 |
|---|---|---|
| 1.1 错误码漂移 | 非 Go / 非数值码项目失效 | **更严重**：与语言无关，见 §1 |
| 3.1 source-trace | 中文 spec 的识别口径，低优先级 | **更严重**：框架与自带模板打架，见 §3 |
| 2.2 SIGPIPE | 仍存在 | **已修复**，见 §6 |
| 2.3 plan-lint 占位符 | 误伤路径参数 | **判据方向错了**，见 §4 |

另有一条上报方未提、但与「中文 spec」直接相关的缺陷，见 §7。

---

## 1. 错误码漂移：失效范围比上报的更广（已修复）

`drift-check.sh:214`（修复前）只从「表格首列为纯数字」的行提取错误码。

上报把这归因为「本项目错误码是字符串枚举」。但框架**自带的默认 spec 模板**
`harness-template/halo/kernel/orchestrator/templates/spec-template.md:89-91` 写的是：

```markdown
| 错误码 | 触发条件 | 副作用 | 是否可重试 |
|---|---|---|---|
| {ERROR_CODE} | {条件} | {有 / 无} | yes / no |
```

`{ERROR_CODE}` 是字符串枚举占位。也就是说，**任何按框架自己模板写 spec 的项目，
错误码漂移检测都恒为 skip**，无论它是 Go 还是 Python。这不是「非 Go 项目失效」，
是框架的门禁读不懂框架自己的模板。

第二处硬编码 `find -name '*.go'`（`:223`）与上报描述一致。
`manifest.drift.error_codes.const_pattern` 确实是无效旋钮——文件类型不可配。

### 修复

- spec 侧改为**按表头定位错误码表**（`错误码` / `Error Code` 等），取首列，
  接受纯数字与大写蛇形常量两种形态。找不到错误码表时回退到原有的全文数值扫描，
  保证既有数值码 spec 不回归。模板占位 `{ERROR_CODE}` 带花括号，两条判据都不命中，
  不会被误提取为错误码。
- 代码侧按 `project.language` 分派源文件后缀，新增 `drift.error_codes.file_glob` 可覆盖。
  语言无映射时明确报 `no source file mapping for language 'X' (NOT verified)`。
- 匹配方式分两路：数值码沿用 `const_pattern`；字符串码用**字面量 `grep -wF`**。
  字符串枚举的定义语法跨语言差异太大（Python `class ErrorCode(str, Enum)`、
  TS `const enum`、Go `const X = "..."`），维护单一 `const_pattern` 不现实，
  而「spec 声明的码在源码中根本不出现」已足够鉴别漂移。

## 2. 路由漂移：列序 + 未实现分支（已修复）

`drift-check.sh:163-170`（修复前）把方法固定读 awk 第 3 字段、路径读第 4 字段。
上报描述准确：表格**列序**成了任何文档都没声明的隐式契约。

补充一条上报方未展开的事实：`init.sh:147-150` 会主动探测 `fastapi` / `sqlalchemy`
并写进 manifest，而门禁对它们是 `not yet implemented` 的 skip。框架**宣称支持、静默不检**。

### 修复

- 表格解析改为**按表头名定位** `Method|方法` 与 `Path|路径|端点|URL|Endpoint` 两列，
  找不到表头时回退到原有的 `$3`/`$4`（`examples/go-gin-gorm` 的
  `| API | Method | Path | Description | Auth |` 表恰好落在回退路径上，已验证无回归）。
- 数据行额外要求路径以 `/` 开头。这条护栏正是本次测试暴露出来的：中文列序表
  `| 端点 | 方法 | 说明 |` 在旧实现下**不是提取失败，而是把「说明」列当成了路径**，
  `spec_routes` 计数正常，比对结果却全错。
- 实装 FastAPI 与 Express 路由检测：抓装饰器/注册调用，与 `APIRouter(prefix=)`
  / `app.use('/x')` 的前缀做笛卡尔拼接得到候选集，路径参数（`{id}` / `:id` / `<id>`）
  归一化后比对。先做完整路径精确匹配，失败再回退到与 Go 分支同样宽松的尾段匹配——
  **前缀建模不准只会漏报，不会误报**，门禁不会因为解析不完美而假红。

## 3. compliance source-trace：同样是框架与自带模板打架（已修复）

`compliance.sh:136` 只认英文 token。上报把它归为「中文 spec 场景下的识别口径」，
列在低优先级。

但默认模板 `spec-template.md:45-50` 的上下文依据表是：

```markdown
| 来源 | 已采用事实或约束 | 对方案的影响 |
| 用户输入 | {事实} | {影响} |
| 代码 / 测试 | {事实} | {影响} |
```

**按框架自己的中文模板写 spec，这条软门禁必然告警**。上报方说「已连续 10+ 个 spec
携带此告警」，成因不是项目的书写习惯，是框架自己造的永久噪声。这与 §1 是同一类问题。

修复：正则补齐中文来源类别。不引入 manifest 配置项——这是软门禁，
可配置列表的复杂度不抵收益。

## 4. plan-lint 占位符：上报说对了现象，但判据的问题更根本（已修复）

原判据 `\b(TODO|TBD|FIXME)\b|<[^>]+>|\{[A-Za-z_][A-Za-z0-9_-]*\}`。

上报指出 `{set_id}` 与跨 `<`/`>` 的误伤，属实。但更关键的是：
`\{[A-Za-z_][A-Za-z0-9_-]*\}` **只匹配 ASCII 标识符**，而框架模板里真正的残留占位
大量是中文 `{条件}`、`{事实}`、`{影响}` ——**旧判据一个都抓不到**。
这条分支实际上只在误伤 REST 路径参数与 f-string，对它要防的东西没有鉴别力。

修复后的判据：

| 输入 | 旧 | 新 |
|---|---|---|
| `POST /model-sets/{set_id}/members` | 误报 | 通过 |
| `成员数 < 100 时，> 1000 时降级` | 误报 | 通过 |
| `f"{name}"` | 误报 | 通过 |
| `{ERROR_CODE} 未定义` | 报 | 报 |
| `{条件} 待补` | **漏** | 报 |
| `见 <spec-id> 文档` | 报 | 报 |

`\b(TODO|TBD|FIXME)\b` 保持原样。上报提到「本节不得留 TBD」这类自指句被命中，
属罕见写法，收窄它会削弱这条判据的主要价值。

## 5. review-package 空评审包（已修复）

`review-package.sh:58,64`（修复前）只跑 `git diff --stat` 与 `git diff -- .`：
不带 `--cached`、不带 commit 范围、不含 untracked。

上报的定性准确，且这是**框架自我矛盾**：逐任务提交是 SDD 纪律本身要求的做法，
按纪律执行的项目必然拿到零信息评审包。

修复：

- 新增 `--base=<ref>`；缺省按 `origin/HEAD` → `origin/main` → `origin/master` → `main` → `master`
  依次尝试，取 `git merge-base HEAD <default>`。全部失败时退化为仅工作树 diff（不报错）。
- 输出拆为 `Committed Diff (<base>...HEAD)`、`Uncommitted Diff (staged + worktree)`、
  `Untracked Files` 三段，空段写 `(none)` 而不是留空 code fence。
- untracked **文件内容**在文件数 ≤ 50 时以 `git diff --no-index` 内联；
  超限时只列清单并提示补 `.gitignore`。绿地开发的新文件是上报方的核心诉求
  （`model_set.py` 193 行、`test_model_sets.py` 1467 行此前全部缺席），
  只列文件名不解决问题；但不设上限会让一个缺 `.gitignore` 的仓库把构建产物灌进评审包。
- 包头 `## Sources` 记录实际使用的 base ref，让评审范围可复现。

## 6. SIGPIPE：已在上报之前修复

上报 2.2 标注「**仍存在**」。复核结论：`c75d0c4`（2026-08-02）已修复，
`task-complete.sh:107-127` 现在先把 `ac_ids` 落进变量再用 here-string 匹配，
并附带了 `red-many-ac` 确定性回归场景（注入逐行输出的 yq 包装器把竞态放大为必现）。

上报方跑的是已发布的 kernel `1.0.0`，源码已领先于发布。
**升级到 `main` 后，`RED-N/cycle-AC-N/` 的单元素分片规避手法可以撤掉。**

## 7. 附带发现：项目语言覆盖了 locale 环境变量（已修复）

上报方未提。`drift-check.sh:33`、`ac-coverage.sh:37`、`pipeline.sh:299` 都写了：

```bash
LANG=$(get_language)
```

`LANG` 是 locale 环境变量。把它赋成 `python` / `go` 会让所有子进程
（awk、grep、sed、sort）落进无效 locale。这对中文 spec 的处理有实际影响，
与本次上报的主题（中文 spec 场景下的门禁行为）直接相关。三处已统一改为 `PROJECT_LANG`。

同一轮验证中还发现：**macOS 的 BSD awk 对多字节字符串的 `==` 比较不可靠**——
任意两个非空 CJK 字符串都会被判为相等。表头定位因此不能用 `c == "方法"`，
必须用正则 `c ~ /^(方法|Method)$/`。相关代码已加注释说明，避免日后被「简化」回去。

## 8. 本期不修

| 条目 | 理由 |
|---|---|
| 3.2 knowledge-reference 按路径字符串匹配 | 上报方自己也定性为书写约定。语义匹配不可靠，仅改文案的收益有限，留待与 3.3/3.4/3.5 一并处理 |
| 3.3 `summary-learn-draft.sh` 只认英文精确标题 | 框架自产的 `verify.md`（`summary-draft.sh:215`）写的就是英文 `## Knowledge Candidates`，命中正常；仅手写中文标题时失配。P2 |
| 3.4 `knowledge-lint.sh` UTC 未来日期 | warn 级，规避成本极低。P2 |
| 3.5 `prismspec/bin/lint.sh` 的 `verify` 别名 | 零风险可用性改进。P2 |
| 4.1 「RED 全部前置」与 `red_task_has_cycle_evidence` 的张力 | 上报方自述非缺陷。属流程文档问题，另行评估 |
| 4.2 `tdd-evidence.json` 增加 `red.method: mutation` | 属 schema 新特性，不是缺陷修复。变异法取红的诉求成立，值得单独设计 |

## 9. 回归覆盖

`tests/smoke-test.sh` 新增第 7c 节，10 条断言，修复前全部失败（`{ERROR_CODE}` 占位护栏一条除外）：

| 场景 | 断言 |
|---|---|
| skip 可辨识 | `checks_skipped >= 3`、`checked.error_codes == false`、stdout 含 `NOT verified` |
| 模板占位不被误提取 | `spec_error_codes == 0`（spec 中只有 `{ERROR_CODE}` 行） |
| 字符串错误码漂移 | Python 源缺 `REFERENCE_IN_USE` → exit 1、`drift_count == 1`；补齐后 → exit 0 |
| FastAPI 路由漂移 | `@router` + `APIRouter(prefix)` 下缺 DELETE → exit 1；补齐后 → exit 0 |
| 路由表列序 | `| 端点 | 方法 | 说明 |` 与代码一致 → exit 0、`drift_count == 0` |
| compliance 中文来源表 | `source_trace` finding 的 status 为 `pass` |
| plan-lint 路径参数 | `{set_id}` 与 `< / >` 不报；`{SCOPE_TBD}` / `<spec-id>` 仍报 |
| review-package | 工作树干净时包内含已提交内容与未跟踪文件内容 |

收口：`bash -n` / `shellcheck --severity=warning` / `tests/smoke-test.sh`（132/132）
/ `examples/go-gin-gorm/try-it.sh` / `git diff --check` 全通过。

go-gin-gorm 示例是 Go 路径的回归护栏，本次改动动了它所在的代码块，
其输出确认 DDL 与 route 两维度仍被真实比对（`no drift in 2 verified dimension(s) · 2 NOT verified`）。

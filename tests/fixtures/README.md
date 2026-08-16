# 静态 fixture 变体矩阵

这里放**语法/语义变体**的 fixture 文件。判定标准见 `tests/README.md`：

- 跨用例复用、差异能用少量标量参数表达的**黄金形态** → `helpers/fixtures.bash` 的构造函数；
- **单元素变体**（改一个单元格、改一个 AC 号、复制一行）→ 用例内 `awk`/`sed` 从黄金形态派生；
- **多个陷阱元素同时出现在一份文档不同位置**的形态 → 放这里。

第三类之所以必须是静态文件：它的价值在于**可被逐字审阅**。参数化会把陷阱藏进生成逻辑，
读用例的人再也看不出「这份 spec 到底埋了什么」。

## 目录约定

每份 fixture 是一棵**按目标项目布局镜像**的目录树（`halo/specs/...`、`tests/...`），
用 `halo_install_fixture <rel>` 整棵叠加进沙箱。叠加会覆盖同名文件，
这正是造反向场景的手段（先装基线，再叠一份只改一个文件的变体）。

## 矩阵

| 路径 | 对应报告 | 刻意埋的陷阱 | 消费者 |
|------|----------|--------------|--------|
| `ac/cross-spec-mentions/` | `docs/bug_report/2026-08-03-user-report.md`（#14） | 同一份 spec/plan 在**四个位置**提到外部 spec 的 `AC-14`：spec 的 Non-Goals 散文、AC-3 行的单元格内、plan 的 Out-of-scope、RED-1 任务体的 Discriminating power 行。自身只声明 AC-1..AC-3 | `regression/2026-08-03-user-report.bats` |
| `ac/declaration-line/` | `docs/bug_report/2026-08-07-runningtime-report/` | `decl-line-ac`：RED-1 声明 `覆盖验收：AC-1, AC-2` 且散文里写**否定句**「本任务不覆盖 AC-3」；RED-2 的声明行上挂着**外部** spec 的 `AC-14`；T1 字段名全中文。`decl-warn-ac`：声明行 `覆盖验收：以下条目补充说明` **不含任何 AC token** | `regression/2026-08-07-runningtime-report.bats` |
| `ac/cross-spec-attribution/` | `docs/bug_report/ac-coverage-bug/`（#8） | 两个 spec **共用一个测试目录**，测试函数同号（`test_acN_*`）。中文五列 AC 表、末列反引号测试名。alpha 的 AC-3 末列写的是 `drift-check gate` 而非测试名（走 Tier 2 数字回退），且 alpha 没有自己的 `test_ac3` | `regression/2026-07-25-ac-coverage-cross-spec-attribution.bats` |
| `ac/cross-spec-attribution-absent-decl/` | 同上（反向，本批次新增） | 只覆盖 beta 的 `spec.md`：AC-3 声明的 `test_ac3_beta_absent` **在测试文件里不存在**。Tier 1 找不到声明的函数时必须判未覆盖，不许悄悄落回数字兜底 | 同上 |
| `ac/python-lowercase/` | `docs/bug_report/halo-ac-coverage-bug-report.md`（#5） | **裸 `spec.md` 放在项目根**（非 `halo/specs/<id>/` 目录布局）、两列 AC 表、小写 `def test_ac1`。`py-ac-gap-spec.md` 多一条无对应测试的 AC-2（反向）；`pytests-empty/` 是存在但零测试文件的目录（反向） | `regression/2026-07-12-ac-coverage-python-lowercase.bats` |
| `drift/spec-template-placeholder/` | 本批次新增（§7c drift-check 迁移） | 唯一错误码行是模板占位符 `{ERROR_CODE}`：`spec_error_codes` 必须是 0 且四个 drift 维度全部落在「未验证」而非「无 drift」。表格逐字取自框架自带 `spec-template.md` 的 5.1 错误码表 | 待补：drift-check.bats |
| `drift/fastapi-prefixed-router/` | 同上 | `APIRouter(prefix="/api")` + 单行 `get`/`post("/model-sets")`，刻意缺 `DELETE`。两份 spec 变体：`spec-method-first.md`（方法列在前）与 `spec-path-first.md`（端点列在前，列序倒置 + 中文表头），验证路由抽取靠表头定位而非列位置 | 待补：drift-check.bats |
| `drift/fastapi-collection-root/` | 同上 | `prefix="/model-sets"` + `get("")`/`post("")`/`get("/{set_id}")`，刻意不写 `get("/")`：验证空路径装饰器（prefix 独自扛整条路由）被算作已注册，而不是被「结尾斜杠宽容匹配」的逻辑误伤 | 待补：drift-check.bats |
| `drift/fastapi-slash-root/` | 同上（反向，本批次新增） | 与 `collection-root` 同形，但用 `@router.get("/")` 而非 `get("")`：验证纯斜杠根路由同样被正确识别为已注册。独立目录，不与 `collection-root` 混放 | 待补：drift-check.bats |
| `drift/fastapi-multiline/` | 同上（含本批次新增陷阱） | 装饰器跨多行的 `post(...)`/`delete(...)` 与跨多行的 `APIRouter(\n  prefix=…,\n)` 声明，保留一条单行 `get("/reports")` 兜底：路由抽取必须整份文件读而非逐行 grep，且不能因为 `CODE_ROUTES` 判空而假通过。新增 `@router.get("")` 仅依赖 prefix 展开成 `GET /api`——它是多行 prefix 读取失败时唯一无法被「结尾段宽容匹配」掩盖的信号（其余装饰器自带完整路径段，即使 prefix 读取失败仍会靠该宽容匹配假通过） | 待补：drift-check.bats |
| `compliance/context-basis-zh/` | 同上（compliance.sh source_trace） | 中文来源类别（用户输入 / 代码 / 测试 / 项目知识 / 待确认），逐字取自框架自带 `spec-template.md` 的「3. 上下文依据」表，是根因「框架读不懂自带模板」的直接证据 | 待补：compliance.bats |
| `compliance/context-basis-en/` | 同上（反向，本批次新增） | 英文来源类别（`User` / `Code` / `Knowledge` / `External`，均为与 `source_trace` 正则单元格精确匹配的单词）：防止只认中文类别的回归 | 待补：compliance.bats |
| `compliance/context-basis-unrecognised/` | 同上（反向，本批次新增） | 表格结构齐全，但来源列全是自造词（`甲方`/`乙方评审`/`丙方存档`/`丁项闲聊`），不命中 `source_trace` 正则任何一个分支，`source_trace` 必须落 `warning` 而不是假 `pass` | 待补：compliance.bats |

### 五条容易踩的约束

1. **测试文件目录必须避开 `ac-coverage.sh` 的 prune 列表**（`*/halo/*`、`*/.halo/*`、
   `*/prismspec/*`、`*/vendor/*`、`*/.venv/*`、`*/node_modules/*`）。`tests/`、`pytests/` 是安全的。
2. **`python-lowercase` 的裸 spec 位置是刻意的**：放在项目根既复刻了原缺陷现场，
   也把它排除在 `spec_select` 候选与 `build_foreign_owned` 的扫描范围（只扫 `specs.dir`）之外，
   让那几条用例只测一件事。
3. **空路径 fixture 与 `"/"` fixture 必须分置两个目录**：`fastapi-collection-root`（`get("")`）
   与 `fastapi-slash-root`（`get("/")`）是两种不同的装饰器写法，各自单独验证；混进同一份
   `routers.py` 会让「空路径未被算作已注册」与「斜杠根未被算作已注册」这两个回归互相掩护。
4. **多行 fixture 必须保留一条单行路由**：`fastapi-multiline` 的 `@router.get("/reports")`
   不是随手写的兜底——如果路由抽取整体退化到「一条都读不出」，`CODE_ROUTES` 会变空，
   drift-check 的路由维度整体转入 `gate_skip`（exit 0），回归会被静默吞掉而不是让断言失败。
5. **`drift-check.sh` 的第二个位置参数（`PROJECT`）必须指向 fixture 自己的子目录**
   （如 `drift/slash-root`），**不能指向整个 `$SANDBOX`**。指向 `$SANDBOX` 时，`install.sh`
   vendor 进 `.halo/framework/` 的整棵框架源码树会被一起当作项目代码扫描，兄弟 fixture 的
   路由也会被一并读进 `CODE_ROUTES`，互相污染。失败表现是**假绿**：比如
   `fastapi-slash-root` 刻意缺的 `DELETE` 本该被判为 drift，一旦 `PROJECT` 传成
   `$SANDBOX`，`drift_count` 会从预期的 1 变成 0，看着像是通过了，其实是污染掩盖了缺口。

## 改这里的文件之前

这些正文是**逐字**从内嵌 heredoc 搬过来的：`ac/` 一族取自 `tests/ac-coverage-test.sh`
（已随批次 1 删除，要对照原文去 git history 找 `be50a1f` 之前的版本）；`drift/`、`compliance/`
一族取自 `tests/smoke-test.sh` 的 §7c 段（`:1866` 起，该文件在本批次 Task 10 之前仍留在仓库里，
可直接读现存原文核对，不必翻 git history）。
措辞里埋着被测语义（比如那句否定式的「本任务不覆盖 AC-3」），**改一个字就可能改掉断言的含义**。
要调整就先问：我改的是陷阱本身，还是只是觉得读着不顺？

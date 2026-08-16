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

### 两条容易踩的约束

1. **测试文件目录必须避开 `ac-coverage.sh` 的 prune 列表**（`*/halo/*`、`*/.halo/*`、
   `*/prismspec/*`、`*/vendor/*`、`*/.venv/*`、`*/node_modules/*`）。`tests/`、`pytests/` 是安全的。
2. **`python-lowercase` 的裸 spec 位置是刻意的**：放在项目根既复刻了原缺陷现场，
   也把它排除在 `spec_select` 候选与 `build_foreign_owned` 的扫描范围（只扫 `specs.dir`）之外，
   让那几条用例只测一件事。

## 改这里的文件之前

这些正文是**逐字**从 `tests/smoke-test.sh` 与 `tests/ac-coverage-test.sh` 的内嵌 heredoc 搬过来的
（两处来源都已随批次 1 删除，要对照原文去 git history 找 `be50a1f` 之前的版本）。
措辞里埋着被测语义（比如那句否定式的「本任务不覆盖 AC-3」），**改一个字就可能改掉断言的含义**。
要调整就先问：我改的是陷阱本身，还是只是觉得读着不顺？

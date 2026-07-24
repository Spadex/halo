# Verify: data-sync

- Spec: `halo/specs/data-sync/spec.md`
- Execution mode: `tdd`
- Verified at: 2026-07-18T15:37Z
- Run id: `20260718T153722Z-61776`（eval JSON: `halo/state/eval-runs/20260718T153722Z-61776.json`）
- Pipeline: `bash halo/kernel/delivery/pipeline.sh --json-out` → **exit 0，ALL PASS（9 ✅ / 0 ❌ / 1 ⏭️ / 共 10 步）**

## 结论

**PASS。** 15/15 AC 全部由测试覆盖并通过，全量单测 103 通过，构建/lint/ac-coverage/drift/compliance 全绿，TDD 红→绿证据完整。

## 门禁 / 命令证据

| # | 步骤 | 命令 | 退出码 | 结果摘要 |
|---|------|------|--------|----------|
| 1 | bootstrap | `halo/kernel/delivery/bootstrap.sh check` | 0 | 必需工具 python/yq/uv 均在；docker/kubectl 可选未装（⏭️） |
| 2 | spec-lint | `halo/kernel/delivery/gates/spec-lint.sh …/data-sync/spec.md` | 0 | ✅ 18 / ❌ 0 / ⚠️ 1（无 CREATE TABLE，非本 spec 场景）。**首跑曾 FAIL，见下「门禁缺陷上报」** |
| 3 | prismspec-lint | `prismspec/bin/lint.sh …/data-sync spec` | 0 | PASS spec contract |
| 4 | build | `uv sync --locked` | 0 | Resolved 34 / Checked 31 packages（含新增 `psycopg[binary]`，lock 一致） |
| 5 | lint | `uv run ruff check .` | 0 | All checks passed! |
| 6 | unit-test | `uv run pytest -x` | 0 | **103 passed in 0.85s**（全量，覆盖 §5 回归边界） |
| 7 | ac-coverage | `halo/kernel/delivery/gates/ac-coverage.sh …/data-sync/spec.md .` | 0 | **AC Coverage: 15/15 (100%)** |
| 8 | integration-test | （manifest 未配置） | — | ⏭️ SKIP（no_integration，符合 §13：本期不做集成/PG 真库测试） |
| 9 | drift-check | `halo/kernel/delivery/gates/drift-check.sh …/data-sync/spec.md .` | 0 | no drift（spec 无 DDL / route / error-code / seed.sql，均 N/A） |
| 10 | compliance | `halo/kernel/delivery/gates/compliance.sh …/data-sync/spec.md` | 0 | PASS（soft gate）；1 warning，见下「残留 / soft warning」 |

### 聚焦测试（spec §13 验证计划）

```
uv run pytest apps/layrax-layout/tests/test_sync.py apps/layrax-model/tests/test_sync.py -v
→ 19 passed in 0.12s（exit 0）
```

- layout 侧 15 项：`test_ac1..ac9`、`test_ac7_write_phase_rollback`、`test_ac11..ac15`
- model 侧 4 项：`test_ac10_round_trip_model_three_tables`、`test_ac6_model_import_idempotent`、`test_ac7_model_import_rolls_back_on_invalid`、`test_ac7_model_write_phase_rollback`

## AC 完成情况（15/15）

ac-coverage 门禁逐条映射到 `def test_acN_*` 并通过：

AC-1 逐文件导出 · AC-2 字段取舍（含 status、排除 id/时间戳）· AC-3 稳定序列化 · AC-4 清残留（源库非空）· AC-5 layout round-trip · AC-6 幂等（第二遍 0 变更）· AC-7 非法记录整批回滚 · AC-8 `--prune` 物理删除且默认关 · AC-9 `--dry-run` 只报不写 · AC-10 model 三表 round-trip · AC-11 无静默 SQLite 回退 · AC-12 坏 JSON 报文件路径 · AC-13 空库保护中止不动目录 · AC-14 status 0/1 双向保真 · AC-15 prune 删除前先打印待删清单。

## TDD 红→绿证据（execution_mode: tdd）

- 红灯（实现前）：
  - `.halo/sdd/data-sync/RED-1/red-output.txt` → `ImportError: cannot import name 'sync' from 'layrax_layout'`（1 error during collection）
  - `.halo/sdd/data-sync/RED-2/red-output.txt` → `ImportError: cannot import name 'sync' from 'layrax_model'`（1 error during collection）
- 绿灯：上表 #6（103 passed）与聚焦 19 passed。
- TDD 证据元数据：`.halo/sdd/data-sync/T{1..5}/tdd-evidence.json`（tdd_total=5, tdd_complete=5, tdd_invalid=0）。

## 门禁缺陷上报（halo 框架，按纪律只上报不改框架）

- **现象**：`spec-lint` 首跑 FAIL，报 `Duplicate AC rows: AC-13`，阻断后续全部步骤；但 spec 的 AC 表中 AC-13 只定义一次，无真实重复行。
- **根因**：`halo/kernel/delivery/gates/spec-lint.sh:151` 的查重逻辑
  `grep -E '^\| *AC-[0-9]+ *\|' | grep -oE 'AC-[0-9]+' | sort | uniq -d`
  抓取「以 `| AC-N |` 开头的表格行」后，从**整行**提取所有 `AC-数字` 记号。当某 AC 行的单元格里**引用了另一个 AC 号**时，该行会吐出多个记号，与被引用 AC 自身那行撞车，被误判为重复。本例 AC-4 行的 Then 单元格含「见 AC-13」，于是 `AC-13` 出现两次。
- **复现**：`grep -E '^\| *AC-[0-9]+ *\|' spec.md | grep -oE 'AC-[0-9]+' | sort | uniq -d` → `AC-13`。
- **修复建议（交 halo 团队）**：查重只应取每行的**首个** AC 记号（该行的行号），例如 `grep -oE 'AC-[0-9]+' | head -1` 或 `sed -E 's/^\| *(AC-[0-9]+).*/\1/'`，避免把单元格内的交叉引用计入。
- **本项目侧规避**：`spec.md` 为项目自有文件，已将 AC-4 单元格的交叉引用从「源库为空时的行为见 AC-13」改为「…由空库保护接管（§6 INV-8）」——INV-8 正是空库保护的规范不变量、AC-13 是其验收测试，语义等价且不再触发朴素正则误判。规避后 spec-lint 复跑 PASS（上表 #2）。此缺陷已录于项目知识 `halo-gate-quirks` 第 3 条（"AC 行内交叉引用被计为重复行"），本次规避与其记录手法一致。

## 跳过 / 未做项（均有据）

- **integration-test**：manifest `services.test: []`、未配置集成命令 → SKIP，符合设计。
- **PostgreSQL 真库 round-trip**：本期不做（spec D-13 / §13）。无 PG 容器、项目无 pytest skip 先例；PG 侧由首次真实导入前的 `--dry-run` + 人工核对兜底（README §4.5 约定 3）。
- **compliance soft warning**：`Spec does not reference project knowledge paths`（`halo/context/knowledge` 下有 4 条）。本 spec 在 Context Basis 中以名称引用了项目知识（`halo-gate-quirks`、`model-registry-app-stack`），但未按路径引用；属 soft rule，不阻断，记录备查。

## 残留风险

- **通道未在真实数据上跑过**：本期只交付通道、不交付数据（spec §1），两个本地开发库尚不存在，所有 AC 在内存 SQLite 上验证。真实空开发库上执行 export 会按 INV-8 报错中止（预期行为）。首次真实同步由后续数据写入任务触发，届时先 `--dry-run`。
- **PG 与 SQLite 差异**：仅靠 schema 层 Pydantic 校验兜底（不依赖 DB 约束），本期无 PG 真库自动化验证。

## 后续动作（Next Actions）

1. 推进 spec 状态 `implemented → verified`（本次验证通过后执行）。✅ 已完成（transition: `20260718T153935Z-data-sync-verified`）。
2. 后续独立任务：向 `layout` / `category` / `style` / `model` 写入初始数据，并首次真实 export/import（先 `--dry-run`）。

## 知识候选（Knowledge Candidates）

- 无新增。本次触发的 spec-lint「AC 行内交叉引用被计为重复行」已属 `halo-gate-quirks` 第 3 条既有条目。

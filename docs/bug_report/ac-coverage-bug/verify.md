# 验证证据：layout-migration（家具迁移算法精细化）

- 验证时间：2026-07-24（本地 22:40–22:45，UTC 14:40–14:45）
- 验证人：Claude（/verify，prismspec-verification skill）
- git SHA：f3ccc20（worktree `worktree-layout-migrate-function`，含未提交实现变更）
- 执行模式：tdd（model-selected）

## 1. 流水线（Halo-hosted）

命令：

```bash
bash halo/kernel/delivery/pipeline.sh --json-out
```

结果：**✅ ALL PASS**（exit 0），9 PASS / 0 FAIL / 1 SKIP。
Eval JSON：`halo/state/eval-runs/20260724T144053Z-47811.json`；Loop state：`halo/state/loops/20260724T144053Z-47811.json`。

| # | 步骤 | 命令 | 退出码 | 结果 | 摘要 |
|---|---|---|---|---|---|
| 1 | bootstrap | `halo/kernel/delivery/bootstrap.sh check` | 0 | ✅ | python 3.12.13 / yq v4.53.3 / uv 0.11.6 就绪 |
| 2 | spec-lint | `gates/spec-lint.sh …/layout-migration/spec.md` | 0 | ✅ | 17 通过、1 警告（无 CREATE TABLE，本 spec 无 DDL，属预期）；78 条决策全部 confirmed |
| 3 | prismspec-lint | `prismspec/bin/lint.sh … spec` | 0 | ✅ | 通过 |
| 4 | build | `uv sync --locked` | 0 | ✅ | 锁定同步通过 |
| 5 | lint | `uv run ruff check .` | 0 | ✅ | 无告警 |
| 6 | unit-test | `uv run pytest -x` | 0 | ✅ | **128 passed in 0.82s**（含 layout-plan / layout-solve-trace 重写后全量回归） |
| 7 | ac-coverage | `gates/ac-coverage.sh …/spec.md .` | 0 | ✅ | **19/19 AC 100% 覆盖**（归属展示有已知框架瑕疵，见第 4 节） |
| 8 | integration-test | `${commands.integration_test}` | — | ⏭️ SKIP | 原因 `no_integration`（manifest 未配置集成测试，属预期） |
| 9 | drift-check | `gates/drift-check.sh` | 0 | ✅ | 无 DDL / 路由 / 错误码 / seed 漂移项，no drift |
| 10 | compliance | `gates/compliance.sh` | 0 | ✅ | 软门禁通过，3 条警告（见第 4 节） |

TDD 证据（eval JSON metrics）：`tdd_total=8, tdd_complete=8, tdd_invalid=0` —— 与 execution_mode `tdd` 匹配。

## 2. AC 完成情况

ac-coverage 门禁判定 **AC-1..AC-19 全部覆盖（19/19，100%）**，unit-test 全绿即 AC 测试全绿。实际测试归属（人工核对，修正门禁展示名）：

- AC-1..AC-6（提取阶段）：`apps/layrax-layout/tests/test_migration_extract.py`
- AC-7..AC-11（尺寸策略/错误码）：`apps/layrax-layout/tests/test_migration_sizing.py`
- AC-12..AC-18（位置求解）：`apps/layrax-layout/tests/test_migration_position.py`
- AC-19（trace 契约）：`apps/layrax-layout/tests/test_solve_trace.py` 等收口测试

## 3. 人工验证 T-1 / T-2（留痕）

### T-1：e2e 报告 CLI 跑通 + 新字段渲染 + sizing 章节移除

口径修正（沿 plan.md 第 1 节注记）：spec T-1 所列 `--db` 调用形态在现 CLI（`tests/e2e_report/__main__.py`）中不存在——数据源固定为 committed 样板库 `library.db`，实际按 `--case` / `--all` 两种调用执行，不属实现缺陷。

命令（于 `apps/layrax-layout/`）：

```bash
uv run python tests/e2e_report --case bedroom-square-small   # exit 0
uv run python tests/e2e_report --all                          # exit 0，5 case 全部 solved=True
```

归档产物（trace.json + report.html，均已生成）：

- `tests/e2e_report/artifacts/<case>/20260724-224233-f3ccc20/`，case ∈ {bedroom-landscape, bedroom-master-large, bedroom-narrow-tall, bedroom-portrait, bedroom-square-small}
- 单 case 调用另产 `bedroom-square-small/20260724-224224-f3ccc20/`

内容核验：

- 迁移明细表按新 `MigrationStep` 字段渲染：category / 策略 / 墙(源→目标) / 贴墙 / 用户尺寸 / 尺寸前后 / 空间区间源→目标 / 源相对区间 / 约束明细(dev mm，>1mm 高亮)（`report.py:_migration_table`）。
- sizing 章节已移除：`grep -i sizing` 在 `report.py` 与生成的 `report.html` 中均 0 命中。

### T-2：种子库全量 case 报告抽查

对 5 个 case 的 trace.json 逐一机检 + 报告抽看（脚本遍历 `trace.candidates`）：

| case | 选中方案 | 迁移步骤 | 约束条数 | 偏差>1mm | 校验违规 |
|---|---|---|---|---|---|
| bedroom-landscape | bedroom_29fe00308d55 | 4 | 18 | 无 | 无 |
| bedroom-master-large | bedroom_4 | 4 | 16 | 无 | 无 |
| bedroom-narrow-tall | bedroom_5 | 3 | 13 | 无 | 无 |
| bedroom-portrait | bedroom_3 | 4 | 18 | 无 | 无 |
| bedroom-square-small | bedroom_7 | 4 | 16 | 无 | 无 |

观察：仅胜出候选进入迁移阶段（其余在 gate 前淘汰，符合流程）；约束满足情况与偏差在明细表逐条可读、无明显错位；校验清单零违规。

## 4. 警告、跳过项与残余风险

1. **ac-coverage 归属展示瑕疵（框架问题，只上报不修）**：门禁将 AC-4..AC-9 展示为 data-sync 特性的同名测试（如 `test_ac4_export_clears_stale_files`）——跨 spec 的 `test_ac{n}` 命名归属盲区，与记忆/既往记录的「ac-coverage 归属盲区」一致。实质覆盖已人工核对为真（第 2 节），门禁 PASS 结论不受影响；瑕疵留待 halo 团队修复。
2. **compliance 3 条软警告**：未引用 `halo/context/knowledge` 路径、来源类别未显式分类、无歧义记录。本 spec 决策留痕充分（78 条 confirmed、第 14/15 节呈报复核），判定可接受。
3. **integration-test SKIP**（`no_integration`）：manifest 未配置集成测试，项目现状预期内。
4. **spec-lint 1 警告**：无 CREATE TABLE——本特性纯算法无 DDL，预期。

## 5. 结论与下一步

- **结论：PASS**。流水线全绿、AC 19/19、全量回归 128 passed、T-1/T-2 留痕完成。
- 已执行：`spec-status.sh layout-migration verified --from=implemented`（状态推进记录见 `halo/state/spec-transitions/`）。
- 下一步建议：① 提交本切片变更;② 向 halo 团队上报第 4.1 条 ac-coverage 归属瑕疵;③ 如需沉淀经验可走 `/capture`。

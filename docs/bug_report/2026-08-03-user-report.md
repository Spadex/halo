# 实施报告：T2 TDD 证据收口与全量门禁验证

- Spec: `layout-furnish-api`
- Task: `T2`（plan 模式，无新增行为，仅收口）
- Status: **DONE_WITH_CONCERNS**（全部验证与门禁通过；两条 halo 内核缺陷已上报并按已知缺陷豁免推进，见下）

## 1. TDD 证据落盘

| 文件 | `ac_ids` | red | green |
|---|---|---|---|
| `.halo/sdd/layout-furnish-api/RED-1/tdd-evidence.json` | AC-1, AC-2, AC-3 | exit 1，`3 failed in 0.20s`（三条均 `assert 404 == 200`） | exit 0，`8 passed in 0.25s` |
| `.halo/sdd/layout-furnish-api/RED-2/tdd-evidence.json` | AC-4..AC-8 | exit 1，`8 failed in 0.23s`（AC-4/5 `ModuleNotFoundError`，AC-6/7/8 404） | exit 0，`8 passed in 0.25s` |
| `.halo/sdd/layout-furnish-api/T1/tdd-evidence.json` | AC-1..AC-8 | 同上（实现前复跑确认仍全红） | exit 0；同版本包内全量 135 passed |

三份均由内核 `tdd-evidence.sh` 生成，`status=pass`；红/绿摘要逐字取自落盘的 `red-output.txt` / `green-output.txt`，无回填臆造。T1 那份是内核对「tdd 模式 T 任务」的硬性要求（`task-complete.sh:204`），plan §3 未预见，属计划遗漏而非偏离。

## 2. AC 归属核对（ac-coverage Tier 1）

`grep -rn "def test_ac" apps/layrax-layout/tests/` → 全仓 127 处，其中本 spec 8 处，全部落 `tests/test_floorplan_furnish_api.py`（输出存 `ac-attribution.txt`）。八个函数名 `test_ac{1..8}_furnish_api_*` 经 `sort | uniq -c` 核验**各出现 1 次**，与其他 spec 的 `test_acN` 无撞号（[[halo-gate-quirks]] 跨 spec 撞号规避生效）。门禁实测 **AC Coverage 8/8 (100%)**。

## 3. 回归边界核对

| 项 | 结果 |
|---|---|
| `git status --porcelain` | 仅 2 改（`app.py`、`errors.py`）+ 3 新增（`routers/floorplan.py`、`tests/fixtures/data4_single_bedroom.json`、`tests/test_floorplan_furnish_api.py`）+ spec/plan 与状态流水 |
| `git diff --stat` | `app.py` +2/-1、`errors.py` +22/-1（唯一删除行为 `install_error_handlers` 的单行 docstring 被扩写） |
| `floorplan/`、`solver/`、`similarity/`、`tests/fixtures/data4.json`、`conftest.py` | 零变更 |
| `pyproject.toml` / `uv.lock` | 零变更（`git status --porcelain` 空） |
| `data/local/layrax_layout.db`（绝版真源） | 零变更（`git status --porcelain` 空） |

## 4. 全量验证

| 命令 | 结果 |
|---|---|
| `uv sync --locked` | Resolved 56 packages / Checked 53 packages，锁文件无变更 |
| `uv run ruff check .` | All checks passed |
| `uv run pytest -q`（仓库全量） | **216 passed** |
| `uv run pytest apps/layrax-layout -q` | **135 passed**（基线 127 + 新增 8，零 failed） |
| `uv run pytest .../test_floorplan_furnish_api.py -q` | **8 passed** |
| `bash halo/kernel/delivery/pipeline.sh` | **✅ ALL PASS — 9 pass / 0 fail / 1 skip（共 10 步）** |

pipeline 逐步：bootstrap / spec-lint / prismspec-lint / build / lint / unit-test / ac-coverage(8/8) / drift-check(no drift) / compliance(soft warn) 全 PASS；integration-test 按 `no_integration` SKIP（已知内核行为）。compliance 的软警告为「spec 未引用 `halo/context/knowledge` 路径」——本 spec 以 `[[wiki-link]]` 形式引用了四条项目知识（Context Basis 末四行），门禁只识别路径形式，属已知软规则局限，不阻塞。

## 5. halo 内核缺陷上报（只上报不改框架）

### 缺陷 A：`red_task_has_cycle_evidence` 的 AC 提取无 spec 归属限定

- **现象**：RED 任务正文中对**其他 spec** 的 AC 引用被当作本任务必须提供红→绿证据的 AC。本期 RED-1 正文原有「见 layout-furnish AC-14」，导致 `task-next --json` 的 `ac_refs` 为 `["AC-1","AC-14","AC-2","AC-3"]`，`task-complete RED-1` 因缺 AC-14 证据而拒绝。
- **根因**：`task-complete.sh` 以 `grep -oE 'AC-[0-9]+' <<< "$body"` 扫描整段任务正文，不区分「覆盖验收」行与说明性文字，也不排除伴随其他 spec id 的 token。
- **修复建议**：只从「覆盖验收 / Covers」行提取，或忽略同行内出现其他 spec id 的 AC token。
- **本期规避**：改述 plan 中那句跨 spec 引用（语义等价，判别力说明完整保留），已在 RED-1 报告留痕。

### 缺陷 B：`task-complete.sh` 的 `yq | grep -q` 管道在 `pipefail` 下被 SIGPIPE 击穿（**阻塞级**）

- **现象**：`task-complete.sh RED-2` 恒失败并报 `RED-2 missing matching TDD cycle evidence`，尽管 `.halo/sdd/layout-furnish-api/RED-2/tdd-evidence.json` 合法且含全部五个 AC。连续 8 次重试全败。
- **根因**：`red_task_has_cycle_evidence` 内的判定为

  ```bash
  yq -r '.ac_ids[]?' "$evidence" 2>/dev/null | grep -qxF "$ac"
  ```

  脚本头部 `set -euo pipefail`（`halo/kernel/_lib.sh:12`）。`grep -q` 命中后立即退出并关闭管道读端，yq 若仍有后续行要写就吃到 SIGPIPE 而以 **141** 退出，`pipefail` 遂把整个管道判为失败 → 该 AC 被误判为「无证据」。
- **实证**（`PIPESTATUS` 直读，同一份 RED-2 证据文件）：

  ```
  AC-4（ac_ids 首行）：5/5 次 NOT matched，PIPESTATUS=141 0
  AC-8（ac_ids 末行）：5/5 次 matched，  PIPESTATUS=0 0
  ```

  即**只有排在 `ac_ids` 最后一个的 AC 能被可靠匹配**；一个覆盖 N>1 个 AC 的 RED 任务，用单份证据文件在结构上就不可能通过该检查。RED-1 之所以侥幸通过，是因为当时以 `bash -x` 跟踪运行、trace 开销拖慢了 grep 的退出时机，让 yq 抢先写完退出——纯属竞态，与证据内容无关（[[halo-gate-quirks]] 第 1 条记的「SIGPIPE 竞态」即此，本期首次拿到 `PIPESTATUS` 级实证与「只有末行可靠」的结论）。
- **修复建议**（任一即可）：
  1. `mapfile -t ids < <(yq -r '.ac_ids[]?' "$evidence" 2>/dev/null)` 后用纯 bash 比对，彻底去掉管道；
  2. 或 `grep -qxF "$ac" <<< "$(yq -r '.ac_ids[]?' "$evidence" 2>/dev/null)"`（先落变量再匹配）；
  3. 或在该判定前后临时 `set +o pipefail`。
- **本期规避**：按 [[halo-report-not-fix-policy]] 不改框架代码，改用 [[halo-gate-quirks]] 第 1 条已沉淀的**按 AC 分片**手法——在 `RED-2/` 下为五个 AC 各落一份单元素证据 `cycle-AC-{4..8}/tdd-evidence.json`（`find` 递归扫描任意深度；单元素即末元素，恒无 SIGPIPE）。分片与主证据 `RED-2/tdd-evidence.json` 出自**同一次红→绿循环**，红/绿命令与退出码完全一致，逐条 `red_summary` 另记该 AC 自己的红因，非伪证。分片落盘后 `task-complete.sh RED-2` 一次通过，**未手工编辑 plan 勾选**；RED-1 与 T1 亦由内核脚本正常标记完成。四个任务勾选全部出自 `task-complete.sh`。

## 6. Concerns

- 上述缺陷 B 使 `task-complete.sh` 对**任何**多 AC 的 RED 任务不可用，影响面超出本 spec，建议 halo 侧优先修复。
- plan 输出 ②「`floorplan` 侧不反向导入 `errors`，无循环」的判断在实施期被证伪（真实环经 `solver.recall → crud → errors` 闭合），已在 T1 报告与评审记录中作为 plan drift 留痕；实现改为函数体内延迟导入，依赖方向未变。
- plan §3 未给 T1 安排 `tdd-evidence.json`，但内核对 tdd 模式的 T 任务强制要求；本期已补齐，后续 spec 的 plan 应直接把 T 任务的 TDD 证据列进产出物。

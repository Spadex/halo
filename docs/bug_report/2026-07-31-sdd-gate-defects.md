# Halo SDD 门禁缺陷上报（2 项）

| 项 | 内容 |
|---|---|
| 上报日期 | 2026-07-31 |
| Halo 版本 | `halo/kernel/VERSION` = `1.0.0`；`manifest.yaml` `schema_version: halo.manifest.v1` |
| 发现场景 | 交付 spec `model-upload`（`execution_mode: tdd`，11 个任务：RED-1..RED-5 + T1..T6） |
| 涉及脚本 | `halo/kernel/orchestrator/sdd/task-complete.sh`、`task-evidence-lint.sh`、`plan-lint.sh`、`task-next.sh`、`spec-status.sh` |
| 影响 | 缺陷 1 会**互锁**，使 spec 无法从 `planned` 推进到 `implemented`；缺陷 2 使工具链自荐的执行顺序不可执行 |
| 复现 | 两项均可在本仓 `halo/specs/model-upload/` 上直接复现，下附命令 |

---

## 缺陷 1（阻塞级）：逐任务声明的 `模式：` 被证据门禁完全忽略，导致 tdd spec 中的 plan 任务永远关不掉

### 现象

spec `model-upload` 的 frontmatter 是 `execution_mode: tdd`。plan.md 的最后一个任务 T6 按
`plan-lint` 要求声明了自己的模式为 `plan`：

```markdown
- [ ] T6: 既有契约零变更回归护栏与全量门禁
  - 覆盖验收：AC-15
  - 模式：plan
```

T6 的证据（`brief.md` / `report.md` / `review-package.md`）全部齐备，但关不掉：

```console
$ bash halo/kernel/orchestrator/sdd/task-complete.sh model-upload T6
T6 missing or invalid tdd-evidence.json
```

### 根因

`plan-lint.sh` 与两个证据门禁对「任务模式」的理解不一致：

**`plan-lint.sh:205` —— 逐任务的 `模式：` 是必填字段，缺了就 fail：**

```bash
require_task_pattern "$task_id" "$body" '(Mode|模式)[[:space:]]*[:：][[:space:]]*(plan|tdd|`plan`|`tdd`)' "missing Mode"
```

**`task-complete.sh:150-163` —— 只读 spec frontmatter，从不读逐任务的那个字段：**

```bash
MODE="unknown"
...
if [[ -f "$SPEC_FILE" ]]; then
  MODE="$(frontmatter_value "execution_mode" "$SPEC_FILE")"        # ← 只有 spec 级
fi
if [[ -z "$MODE" || "$MODE" == "unknown" ]]; then
  MODE="$(grep -Eim1 'Execution mode:[[:space:]]*(plan|tdd)' "$PLAN_FILE" ...)"   # ← plan 级
fi
MODE="${MODE:-unknown}"
```

**`task-complete.sh:176-182` —— 用这个 spec 级 MODE 去卡每一个 `T<n>`：**

```bash
if [[ "$TASK_ID" == T* ]]; then
  TASK_DIR="$EVIDENCE_ROOT/$TASK_ID"
  [[ -f "$TASK_DIR/brief.md" ]] || fail_complete "$TASK_ID missing brief.md"
  [[ -f "$TASK_DIR/review-package.md" ]] || fail_complete "$TASK_ID missing review-package.md"
  if [[ "$MODE" == "tdd" ]]; then
    valid_tdd_evidence "$TASK_DIR/tdd-evidence.json" || fail_complete "$TASK_ID missing or invalid tdd-evidence.json"
  fi
```

`task-evidence-lint.sh:71-79 / 110-115` 是同一套逻辑的复制，同样只读 spec 级。

于是：**只要 spec 是 tdd，plan.md 里逐任务声明的 `模式：plan` 就没有任何效力**——那个被
`plan-lint` 强制要求填写的字段，在证据门禁处被完全丢弃。

### 为什么不能「补一份 tdd-evidence 了事」

`valid_tdd_evidence`（`task-complete.sh:80-84`）要求 `red.exit_code != 0`：

```bash
yq -e '.kind == "tdd-evidence" and .status == "pass" and (.red.exit_code | tonumber) != 0 and (.green.exit_code | tonumber) == 0 and ((.ac_ids // []) | length > 0)' "$file"
```

T6 覆盖的 AC-15 是**回归护栏**：它断言「既有 6 个 model 端点契约未变、alembic 迁移文件仍是 4 个」。
这类断言**不存在合法的红**——要让它红，就得先蓄意破坏既有端点或删掉迁移文件。
`tdd-evidence.sh` 也会拒绝 red 为 0 的输入（`Invalid TDD evidence: red must fail and green must pass`）。
填一个假的 red 退出码只是在骗门禁，不是证据。

这正是 plan 阶段把 T6 声明为 `模式：plan` 的原因——而这个声明恰恰是被忽略的那个字段。

### 连带互锁：spec 状态推不动

`spec-status.sh` 有两道闸，`--force` 只跳过第一道之外的「状态跃迁合法性」检查，**都拦不住**：

```bash
# spec-status.sh:217-224
case "$TARGET_STATUS" in
  implemented|verified)
    if plan_has_incomplete_tasks "$SPEC_DIR/plan.md"; then          # ← 闸一：要求 plan.md 无未勾任务
      echo "plan.md has incomplete tasks; complete or split them before status=$TARGET_STATUS"
      exit 1
    fi ;;
esac
# spec-status.sh:233-238
if [[ "$TARGET_STATUS" == "implemented" || "$TARGET_STATUS" == "verified" ]]; then
  bash "$KERNEL_DIR/orchestrator/sdd/task-evidence-lint.sh" "$SPEC_DIR/plan.md"   # ← 闸二
fi
```

- 不勾 T6 → 闸一失败。
- 手工勾上 T6 → 闸二失败（`task-evidence-lint` 对已勾的 T6 要 `tdd-evidence.json`）。

实测（本仓当前状态，T6 已手工勾选）：

```console
$ bash halo/kernel/orchestrator/sdd/spec-status.sh model-upload implemented --from=planned
  ✅ T6 brief.md
  ✅ T6 review-package.md
  ❌ T6 missing or invalid tdd-evidence.json
  ✅ 6 completed task(s) checked
📊 Task Evidence Lint: 1 fail(s), 0 warning(s)
❌ FAIL
```

结论：**一个 tdd spec 只要包含哪怕一个合理的 plan 模式任务，就永远到不了 `implemented`**，
后续 `/verify`、`verified` 全线受阻。

### 复现步骤

在本仓 worktree 内（spec `model-upload`，`execution_mode: tdd`，T6 声明 `模式：plan`）。

**闸二可直接复现**（T6 当前已手工勾选，故 `task-evidence-lint` 会把它算进已完成任务）：

```bash
bash halo/kernel/orchestrator/sdd/task-evidence-lint.sh model-upload
#   → ✅ T6 brief.md / ✅ T6 review-package.md / ❌ T6 missing or invalid tdd-evidence.json
#   → 📊 Task Evidence Lint: 1 fail(s) → ❌ FAIL

bash halo/kernel/orchestrator/sdd/spec-status.sh model-upload implemented --from=planned
#   → 同上 FAIL，状态停在 planned
```

**闸一与 `task-complete` 需先还原 T6 的勾选**（当前直接跑会返回 `Task already complete`）：

```bash
# 把 plan.md 第 374 行的 "- [x] T6:" 改回 "- [ ] T6:"，然后：
bash halo/kernel/orchestrator/sdd/task-complete.sh model-upload T6
#   → T6 missing or invalid tdd-evidence.json
bash halo/kernel/orchestrator/sdd/spec-status.sh model-upload implemented --from=planned
#   → plan.md has incomplete tasks; complete or split them before status=implemented
```

最小化复现：任取一个 `execution_mode: tdd` 的 spec，在 plan.md 里加一个 `模式：plan` 的
`T<n>` 任务，备齐 `brief.md` 与 `review-package.md`，然后 `task-complete.sh`。

### 修复建议

让两个证据门禁的模式判定优先采用**该任务自己声明的**模式，spec frontmatter 仅作缺省回退——
与 `plan-lint.sh:205` 已经强制要求的逐任务语义对齐。

`task-complete.sh` 建议改法（`task-evidence-lint.sh` 同理，其循环内已有 `$body`）：

```bash
task_mode() {                                   # 新增：从任务体解析逐任务模式
  local body="$1"
  grep -Eoim1 '(Mode|模式)[[:space:]]*[:：][[:space:]]*`?(plan|tdd)`?' <<< "$body" \
    | sed -E 's/.*[:：][[:space:]]*//; s/`//g' | tr '[:upper:]' '[:lower:]'
}

# 176 行附近：
if [[ "$TASK_ID" == T* ]]; then
  TASK_DIR="$EVIDENCE_ROOT/$TASK_ID"
  [[ -f "$TASK_DIR/brief.md" ]] || fail_complete "$TASK_ID missing brief.md"
  [[ -f "$TASK_DIR/review-package.md" ]] || fail_complete "$TASK_ID missing review-package.md"
  EFFECTIVE_MODE="$(task_mode "$BODY")"          # ← 逐任务优先
  EFFECTIVE_MODE="${EFFECTIVE_MODE:-$MODE}"      # ← 缺省回退到 spec 级
  if [[ "$EFFECTIVE_MODE" == "tdd" ]]; then
    valid_tdd_evidence "$TASK_DIR/tdd-evidence.json" || fail_complete "..."
  fi
```

若担心被滥用（把任务随手标成 `plan` 来绕开 TDD），可加一条护栏：tdd spec 中声明为 `plan` 的
任务，要求其任务体写明 no-test / no-red 的理由（`plan-lint` 侧校验），而不是在证据门禁处一刀切。

### 本项目当前的规避

按项目纪律（`CLAUDE.md`：halo 框架问题只上报、不改框架代码），已在 plan.md 手工勾选 T6 并在
`plan.md`、`.halo/sdd/model-upload/T6/report.md`、`.halo/sdd/model-upload/progress.md` 三处留痕；
spec 状态保持 `planned`。全量门禁 `bash halo/kernel/delivery/pipeline.sh` 为 ✅ 9 / ❌ 0 / ⏭️ 1（ALL PASS）。

---

## 缺陷 2（顺序契约不一致）：`plan-lint` 强制的 RED 前置布局，在 `task-next` + `task-complete` 下不可执行

### 现象

三个工具对「RED 任务与 T 任务的先后」给出互相矛盾的约束：

1. **`plan-lint.sh:247-249` 强制 RED 任务必须列在 T 任务之前**：

   ```bash
   if [[ "$FIRST_T_LINE" -gt 0 && "$FIRST_RED_LINE" -gt 0 && "$FIRST_T_LINE" -lt "$FIRST_RED_LINE" ]]; then
     fail_msg "TDD plan must list RED-{n} tasks before implementation T{n} tasks"
   fi
   ```

2. **`task-next.sh` 按 plan.md 的书面顺序返回第一个未勾任务** → 返回 `RED-1`。

3. **但 `RED-1` 关不掉**：`task-complete.sh:184` 对 RED 任务走
   `red_task_has_cycle_evidence`（`:86-96`），要求其覆盖的 AC 已存在一份 red≠0 **且 green=0** 的
   `tdd-evidence.json`：

   ```bash
   red_task_has_cycle_evidence() {
     ...
     if valid_tdd_evidence "$evidence" && yq -r '.ac_ids[]?' "$evidence" | grep -qxF "$ac"; then
       return 0
   ```

   而 green 证据只有在配对的 T 任务转绿后才存在。

于是：**`task-next.sh` 交给你一个你此刻无法关闭的任务**。操作者必须偏离工具自荐的顺序，
先跑 T 任务，再回头关 RED 任务。

### 附带后果：红阶段的失败原因失真

因为 plan 被 `plan-lint` 逼成「全部 RED 前置」的布局，plan 作者在写 RED-4 / RED-5 的
「预期失败」时，描述的却是**配对执行**下的失败（「502 缺失」「返回 409」）。若真按书面顺序跑，
此时端点根本还不存在，实际失败是 `create_app() got an unexpected keyword argument 'store'`
的 `TypeError`——红阶段就无法按 plan 声明的理由如实验证。

本次交付实际采用了配对拓扑序（RED-1→T1→RED-2→T2→…→RED-5→T5→T6），它满足 plan 第 4 节声明的
全部依赖关系，且让每个 RED 的失败原因与 plan 的预期逐条对上。

### 复现步骤

```bash
# 一个 execution_mode: tdd 的 spec，plan.md 形如 RED-1..RED-n 在前、T1..Tn 在后，全部未勾
bash halo/kernel/orchestrator/sdd/task-next.sh <spec-id> --json     # → task_id: RED-1
# 按它执行 RED-1，写好 brief / report，然后：
bash halo/kernel/orchestrator/sdd/task-complete.sh <spec-id> RED-1
#   → RED-1 missing matching TDD cycle evidence
```

### 修复建议（三选一，按侵入性从低到高）

1. **文档化**：在 `task-next.sh` 的输出或 SKILL 文档里说明「RED 任务须在配对 T 任务转绿后才能关闭，
   执行顺序应为配对序而非书面序」。改动最小，但把认知负担留给操作者。
2. **`task-next.sh` 感知这条依赖**：若返回的是 RED 任务且其 AC 尚无 green 证据，
   顺带在 JSON 里提示配对的 T 任务 id（例如加一个 `blocked_until` 字段）。
3. **放宽 `red_task_has_cycle_evidence`**：RED 任务关闭时只要求存在 red≠0 的证据（证明红已立起），
   把「green 必须存在」的校验挪到配对 T 任务的关闭时机。这样书面序与执行序就一致了。

### 备注（非缺陷，供参考）

`red_task_has_cycle_evidence` 在**任一** AC 命中即 `return 0`（`:92-94`）。若一个 RED 任务覆盖
5 条 AC，只要其中 1 条有红绿证据就算通过。不确定这是有意的宽松还是笔误，一并提一下。

---

## 附：本次交付的其它门禁观察（均非缺陷，不需修复）

- **`drift-check`**：对本 spec 报「No routes in spec API table」「No business error codes in spec」
  两条 skip。本期确有新增路由 `POST /models/upload` 与三个新错误码，但 spec 第 5 / 5.1 节用的
  表结构与该门禁期望的形态不同，故未被识别。本期本就是零 DDL、零错误码常量表变更，结论无误，
  仅提示该门禁的识别方式对 spec 表格形态较敏感。
- **`compliance`**：2 条 soft 警告（未引用 `halo/context/knowledge/` 路径、来源类别记录不够清晰）。
  本 spec 第 3 节确已引用 `halo/context/README.md` 与 `halo/manifest.yaml`，只是未命中门禁期望的
  `halo/context/knowledge/` 路径形态。soft gate 判 PASS，仅记录。

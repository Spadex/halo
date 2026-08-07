# Halo 门禁与工具链问题上报：`model-set-search` implement 期发现

| 项 | 内容 |
|---|---|
| 上报方 | layrax `monorepo` 项目组 |
| 上报日期 | 2026-08-07 |
| 发现场景 | spec `model-set-search` 的 `/implement` 会话（2026-08-06），及其后的执行时长复盘与独立审核 |
| 佐证材料 | `docs/retrospectives/2026-08-07-model-set-search-implement-runtime.md`（复盘）与 `…-audit.md`（独立审核，含全部数字的实测口径） |
| 环境 | 本 worktree 当前内核（`halo/kernel/`），行号以 2026-08-07 快照为准 |

---

## 1. 高优先级：`narrow_acs_to_declared` 对任务正文全文粗抓 AC 编号，散文提及即成硬性覆盖义务

### 现象

RED-1 收口时 `task-complete.sh` 反复失败，报「missing matching TDD cycle evidence」。主代理为定位
根因花费约 16 次往返（跨 13:11–14:39，中间插着其他任务），最终发现：plan.md 中 RED-1 的**散文
正文**（预期失败说明等叙述性文字）提到了某个 AC 编号，被门禁抓取为「该任务声明覆盖、必须提供
红绿证据的 AC」。

### 根因

`halo/kernel/_lib.sh:213-220`：

```bash
narrow_acs_to_declared() {
  local text="$1" spec="${2:-}" declared mentioned
  mentioned="$({ grep -oE 'AC-[0-9]+' <<< "$text" || true; } | sort -u)"   # :215 全文无差别抓取
  ...
}
```

`text` 是由 awk 从任务复选框行取到下一任务/二级标题的**整段正文**（`task-complete.sh:60-68` 的 `task_body`），
包含「预期失败」「执行步骤」「完成条件」等全部散文。唯一的窄化是「是否为本 spec 声明的 AC」
（`spec_declared_acs`），**不区分结构化声明与散文提及**。抓取结果在 `task-complete.sh:215-218`
成为 RED 任务的硬门：

```bash
COVERED_ACS="$(narrow_acs_to_declared "$BODY" "$SPEC_FILE")"
red_task_has_cycle_evidence "$COVERED_ACS" || fail_complete "$TASK_ID missing matching TDD cycle evidence"
```

同一函数被 `task-next.sh:145`、`plan-lint.sh` 复用，即「散文提及 = 覆盖声明”的语义贯穿整条链路。

### 复现

在任意 tdd 模式 plan 的 RED 任务散文里写一句「注意：本任务不覆盖 AC-9」（AC-9 为 spec 已声明的
AC），则 `task-complete.sh` 会要求为 AC-9 提供 `tdd-evidence.json` 红绿循环证据，否则收口失败。
——「不覆盖 X」的否定句式同样被抓取，这是纯词法抓取无法避免的。

### 影响

- plan 作者被迫遵守一条**无处成文的隐性纪律**：任务正文散文不得出现 `AC-N` 字面。本项目已把它
  记入项目侧规避清单，并且本仓库 plan.md 里已出现「刻意不写 AC 编号字面」的绕行注释——纪律靠
  口口相传，新项目必然重踩。
- 失败信息（missing TDD cycle evidence）与真实根因（散文被抓取）之间距离很远，定位成本高
  （本次约 16 次往返）。

### 建议

任选其一（按侵入性从低到高）：

1. **失败信息增强**（最小改动）：`fail_complete` 时列出 `COVERED_ACS` 及每个 AC 在正文中的
   命中行，让「散文误吸」一眼可见；
2. **结构化声明语法**：任务段支持显式声明行（如 `覆盖 AC: AC-3, AC-5` / `Covers: AC-3 AC-5`），
   存在声明行时**只认声明行**，散文提及不再产生义务；无声明行时保留现行为以兼容存量 plan；
3. 至少将「散文提及 = 覆盖义务」写进 plan 撰写文档，把隐性纪律显性化。

---

## 2. 中优先级：`task-next.sh` 无逐任务查询入口，AC 抓取结果无法在 plan 定稿时左移预检

### 现象

复盘改进项 A2 提出「plan 定稿后、进 implementation 前，对每个任务预跑一次 AC 抓取并与预期比对，
不一致当场改 plan」——左移成本 1 次往返，可拦掉问题 1 那种收口期搏斗。独立审核核实：**现有工具
做不到**。

### 根因

- `task-next.sh:115` 只取**第一条未勾选任务**：
  ```bash
  NEXT_LINE="$(grep -E '^- \[ \] (T[0-9]+|RED-[0-9]+):' "$PLAN_FILE" 2>/dev/null | head -1 || true)"
  ```
  无 `--task=<id>`、无 `--all`。plan 定稿时全部任务未勾选，反复调用只会返回队首。
- `--json` 输出确有 `ac_refs`（`task-next.sh:145,161`），能力本身存在，只是没有逐任务入口。
- `plan-lint.sh` 是全 plan 聚合比对（spec 声明的 AC 是否在 plan 全文出现），无法暴露
  「某任务散文误吸某 AC」这种任务级错配。
- `narrow_acs_to_declared` / `task_body` 均为脚本内部函数，无 CLI 暴露，项目侧无法在不复制
  内核逻辑的前提下自建预检（复制则有漂移风险）。

### 建议

为 `task-next.sh` 增加 `--task=<id>`（或新增 `task-inspect.sh <spec> [--all]`），输出与现行
`--json` 同构的 `ac_refs` 视图。这样 plan 定稿后一条命令即可核对每个任务将被门禁认定的 AC 集合，
把问题 1 的定位成本从收口期（本次约 16 次往返）左移到 plan 期（1 次往返）。

---

## 3. 流程设计反馈（非缺陷）：评审串行阻塞是 implement 阶段第一大时间项，建议明文化批量评审与派发形态

### 数据

`model-set-search` 实施主 turn（约 4 小时）经逐时间戳实测：评审子代理串行阻塞 **93.5 min（约
38–42%）**，是最大单项，高于主代理 LLM 生成（约 80 min）。6 个评审点每次 13–30 min，其中约 22%
是可模板化的固定上下文重建（找 reviewer 契约、找制品路径）。

### 现状文档的两个引导性问题

1. `prismspec/skills/prismspec-implementation/SKILL.md:95` "Use a single task-scoped reviewer"
   的措辞引导逐任务派发；实际上本会话已出现三次合并评审（RED-2/3、T3/T4、RED-4/T5）且未被任何
   门禁拦截——**批量评审事实上被允许，但没有成文**，执行者只能各自摸索。
2. 评审派发形态（同步等待 vs background）无任何成文规定；约束只有因果性的
   「Critical/Important 修完才能 task-complete」（SKILL.md:60-63,100）。形态留白导致实践中
   默认退化为最保守的全程同步等待。

3. `prismspec/agents/task-reviewer.md:11-17` 的 Inputs 段只把 `brief.md` 写成全路径，
   `report.md`/`review-package.md` 只给文件名、TDD 证据连文件名都没写——评审者每次开局花 5–6 轮
   现场找路径，即上文 22% 固定开销的直接来源。

### 建议

1. SKILL.md 明文允许**批量评审点**（一个评审者、一次覆盖多个耦合任务），并给出批边界判据
   （如：同批任务改动面重叠 / 后置任务建立在前置任务代码上时必须同批评审）；
2. 明文允许对低耦合批（如只增测试文件的 RED 批）**background 派发**，并写清前提
   （评审结论回来前不得对被评审代码执行 task-complete）；
3. `task-reviewer.md` 的 Inputs 段补全四件套全路径模式
   `.halo/sdd/<spec-id>/<task-id>/{brief.md, report.md, review-package.md, tdd-evidence.json}`，
   消除每次评审的找路径开销。

4. SKILL.md 增补任务实施的**子 agent 执行形态**指引。项目方的原则诉求是「应分尽分」：切分
   **无伤害**（不产生共享文件写冲突、关键现场知识可经制品传递）且**有明显时间收益**（任务留在
   主会话执行会为后续任务垫高上下文）时，就应下放子 agent 执行，主会话退为编排者。实测依据：
   主会话延迟随上下文的斜率约 70 s/百万 token，后期单轮 25–32 s，而小上下文子 agent 约
   10–14 s/轮。RED/T 任务具体如何切分、判据如何成文，请 halo 团队定夺；需要一并写清的约束：
   ① `plan.md` 复选框与 `.halo/sdd/` 是共享写目标，`task-complete.sh` 收口应收回主代理串行
   执行；② 前序任务的现场发现经 `report.md` 传递给后续子 agent，不依赖会话记忆。

5. plan 模板增加「**执行拓扑**」段：定稿时写明任务批次划分、每批评审点位置、可并行/可子 agent
   化的任务集合。任务依赖与改动面重叠度在 plan 阶段看得最清楚，执行拓扑左移后，implement 期
   的评审批量化与子 agent 切分都照图执行、零临场决策。

### 预期收益

按本期实测折算：批量化至 2–3 个评审点约省 30–50 min，路径补全约省 15–18 min，合计可将该阶段
评审阻塞压缩约一半，且不削减任何验证深度（独立验证环节占评审时长约 42%，不属于本条建议的
削减对象）。

---

## 4. 附：与既有上报的关系

- 本文问题 1 与 `2026-08-03-halo-gate-findings.md` §0 提到的 `narrow_acs_to_declared` 新增逻辑
  同源：该函数当时是作为「ac-coverage 整行盲扫」的修复引入的，修复了「伪 AC」问题，但
  「散文提及 = 覆盖义务」的词法语义保留至今，本文是对同一机制的后续反馈，不是回归。
- `task-complete.sh` 经管道取退出码失真的问题已在 2026-08-03 文档 §2.2 上报并修复；本期 14:37
  踩到的是项目侧旧习惯（经管道调用），非内核回归，不另立条目。

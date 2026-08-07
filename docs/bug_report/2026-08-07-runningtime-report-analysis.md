# 分析:2026-08-07 执行效率上报(runningtime-report)

| 项 | 内容 |
|---|---|
| 上报材料 | `2026-08-07-runningtime-report/` 三份:`…-implement-findings.md`(问题上报)、`…-implement-speedup-top5.md`(提速方案)、`prismspec-session-time-optimization.md`(会话耗时优化清单) |
| 处置日期 | 2026-08-07 |
| 处置方式 | 独立核实全部代码声明后逐条采纳/不修;内核修复 + 流程文档明文化 |

## 结论

上报的内核侧声明**全部属实**(行号精确);流程文档侧大体属实,两处需更正(见 §7)。本期落地两项内核修复与一批流程文档明文化,预期消除上报实测的三类最大浪费:门禁误抓散文 AC(单次事故约 16 次往返)、评审串行阻塞(93.5 min/42%)、评审 fail 对 spec 层分歧的重复重派(96 min)。

## 1. 散文提及 AC 即成覆盖义务(已修复,findings §1)

**核实**:`_lib.sh` 的 `narrow_acs_to_declared` 对任务正文全文 `grep -oE 'AC-[0-9]+'`,仅按「是否本 spec 声明」收窄——跨 spec 提及已被 #14(`1f993a4`)挡住,残留问题精确地是**本 spec 内的散文/否定提及**(「本任务不覆盖 AC-9」照样成为红绿证据义务)。

**修复**(采纳上报建议 2「结构化声明语法」+ 建议 1「失败信息增强」,且不需要发明新语法——plan 任务格式本就有「覆盖验收：」字段):

- `_lib.sh` 新增 `ac_declaration_lines()` + `task_covered_acs()`:任务正文存在含 AC token 的 `覆盖验收：`/`Covers:` 声明行时只认声明行(多行取并集),散文提及不再产生义务;无声明行回退全文扫描(存量 plan 行为逐字节不变,fail-open)。
- `task-complete.sh`、`task-next.sh` 改用 `task_covered_acs`;`plan-lint.sh` 的聚合校验不改(散文提及在该处只帮忙不添乱),新增 **warn 不 fail**:无声明行任务提示回退语义。
- 失败信息从静态字符串增强为 `RED-1 missing matching TDD cycle evidence (covered: …; missing: …)`(前缀保持,存量断言不破);`--json` 增 `covered_acs`/`missing_acs` 数组(schema v1 内增量,不 bump)。
- 唯一变严路径:声明行 AC **全部**为外部 spec AC 时 COVERED_ACS 为空,走既有 `references no AC declared` 失败——刻意保留,显式声明写错应当大声失败。

## 2. task-next.sh 无逐任务查询入口(已修复,findings §2)

采纳。`task-next.sh` 新增 `--task=<id>`(忽略勾选状态查询指定任务,`status: selected` + `complete` 字段;不存在时 `not-found` + exit 1)与 `--all`(`kind: task-list` 输出全部任务及各自 `ac_refs`)。plan 定稿后一条命令即可预检每个任务将被门禁认定的 AC 集合,把 §1 类事故的定位成本从收口期左移到 plan 期。默认调用的文本与 JSON 输出逐字节不变。

## 3. 评审串行阻塞与派发形态留白(已修复——文档明文化,findings §3 / top5 方案 1、3、4)

- **批量评审点**成文:`prismspec-implementation/SKILL.md` Task Review 段允许一个评审点覆盖多个耦合任务,批边界判据成文(改动面重叠、或后置任务建立在前置代码上的必须同批);`prismspec-review/SKILL.md` 的 "per task or run" 措辞同步明确;rules.md Review 段同向。
- **background 派发**成文:只增测试文件的批可后台派发评审,硬前提写死——评审结论返回前不得对被评审任务执行 task-complete;生产代码批默认同步等待。
- **评审派发路径模板**:`task-reviewer.md` Inputs 段补全四件套全路径(brief/report/review-package/tdd-evidence.json),消除每次评审约 22% 的找路径固定开销;派发提示模板同时写进 implementation SKILL.md。
- review SKILL.md 原 Red Flag「Multiple review items are batched…」加限定语,明确它约束的是**修复项不逐项验证**,与批量评审点不冲突。

## 4. 子代理下放与收口往返(已修复——文档明文化,top5 方案 2、5)

- 上报称「SKILL.md 无子 agent 下放规定」**不成立**(见 §7),但缺口真实存在于两处:判据未成文、常驻指令面(rules.md)零承载且逐块串行命令排版构成反向引导——这是目标项目开了 subagent 开关但实施仍留在主会话的直接原因(评审被派发恰因 rules.md 明确写了 reviewer)。
- 修复:`prismspec-implementation/SKILL.md` 的 Subagent Execution Loop 改为**默认下放**(留在主会话需记一行理由),删除 "tasks are independent" 这个给串行留合法出口的措辞——依赖链决定的是能否并行,不决定是否下放;rules.md Implementation 段开头补同向承载。
- **用户裁定:本期仅串行逐个派发,不引入并行派发**(实现有顺序,防止并行引入新问题;现有文档本无并行安排,维持)。已写入 SKILL.md 措辞(serially, not in parallel)。
- **收口合并 + 工具调用并行**:rules.md 新增执行约定——收口固定序列 `&&` 串成单条命令(各步幂等,失败整条重跑),互不依赖的读取/检查一轮并行发。此处「并行」指工具调用,与任务实施派发形态无关。

## 5. 评审 fail 分诊(已修复——文档新规则,session-optimization 优化 1)

`prismspec-implementation/SKILL.md` 新增 Review Fail Triage:fail 项先分「实现缺陷」(修复后重派)与「spec 层分歧」(修复需改 spec.md AC/不变量正文,或两轮指向同一条目——立即停下请用户裁定,禁止再派一轮试试);rules.md Review 段同向。对应上报实测:T3 三轮评审 96 min,第 2、3 轮(40 min)撞的是第 1 轮已暴露的同一堵 spec 层墙。

## 6. spec/plan 阶段改动(「三个刀口」,top5 天花板部分)

- **刀口一(任务上限判据)——轻量采纳**:`prismspec-planning/SKILL.md` Task Right-Sizing 补上限判据(任务可大到「一次评审仍能独立验证」为止,不按步骤/文件切)与固定仪式成本提示。既有反过切判据(:68-69)本就存在,本期过切主要是执行未遵守。
- **刀口二(执行拓扑)——完整采纳**:planning SKILL.md 新增 Execution Topology 推荐段(批次、每批评审点、可下放子代理的任务集合;串行执行),含 plan-lint 雷区规避说明(批次成员不用 checkbox、不留占位符/TBD);Self-Review 增声明行预检与拓扑自查两项。
- **刀口三(spec/plan 执行层/背景层分层)——本期不修**:spec.md/plan.md 是全链路唯一事实源(spec-lint、门禁、evidence、context 供给锚定),分层需重定义门禁对「正文按需引用」的语义,改动面最大而收益最小(上报自估 10–20 min),且有评审/实施引用链断裂风险。列入 roadmap 单独立项。

## 7. 上报更正(两处)

1. findings §3.4 与 top5 方案 2 称「SKILL.md 无任务实施下放子 agent 的规定」——**不成立**。`prismspec-implementation/SKILL.md` 自带完整 Subagent Execution Loop(含状态机与进度账本)。真实缺口是默认方向(「满足条件才考虑下放」而非「默认下放」)与常驻面 rules.md 零承载,已按 §4 修复。
2. findings §4 称问题 1 与「`2026-08-03-halo-gate-findings.md` §0」同源——该文件无 §0,来龙去脉实际记录在 `2026-08-03-user-report-analysis.md` §3–§7(`narrow_acs_to_declared` 由 #14 引入,当时修的是跨 spec 伪 AC,本次是同一机制的残留词法语义,非回归)。

## 8. 本期不修

- **评审规格分档(标准/深度,session-optimization 优化 2)**:与仓库设计立场冲突(README「刻意只提供两个稳定执行落点」);已有按风险域加挂 reviewer 人格的机制(`review-evidence-checklist.md`);其诉求大半被批量评审点 + Inputs 路径补全吸收。
- **限流后短等重试(优化 3)**:项目侧执行习惯;SKILL.md 已有 `BLOCKED: do not retry unchanged` 原则,不为单次限流事件立框架规则。
- **上下文超 250k 收口分段(优化 4)**:项目侧操作策略;阶段工件本就支持断点续跑,已在 `docs/wiki/sdd.md` 一句话点明,不做机制。
- **并行派发多个 implementer**:用户裁定本期不引入(实现有顺序,防引入新问题);子代理下放保留且为默认,但严格串行逐个派发。
- **task_body 四份逐字副本去重**(task-complete/task-next/plan-lint/task-evidence-lint):独立 follow-up,避免高扇出 `_lib.sh` 改动与门禁语义变化混同一 diff。

## 9. 独立评审轮

实施完成后派独立只读评审(实测验证式,非仅读 diff)。评审确认:默认路径输出与旧版 `cmp` 逐字节一致、声明行 14 组边界用例在 bash 3.2/5.3 + BSD grep 下行为一致且与注释声称相符、新 JSON 全部合法。评审发现并已修复两项:

1. **Important**:plan-lint 的 warn 条件(仅「无声明行」)与门禁真实回退条件(「无声明行**或**声明行不含 AC token」)不一致——「覆盖验收：见下文」这类行会让 lint 沉默而门禁回退全文扫描,正是本次要消灭的陷阱形态。修复:回退判断抽成 `_lib.sh` 共享谓词 `task_has_ac_declaration()`,`task_covered_acs` 与 plan-lint 共用,消除条件漂移;planning SKILL.md 与 sdd.md 同步补「声明行须含至少一个 AC 编号才生效」。
2. **Minor**:`task-next.sh --task=`(空值)被静默当作未传参。修复:记录 flag 出现与否,空值进 `Invalid task id` 分支。

## 10. 回归覆盖

`tests/smoke-test.sh` 新增 `decl-line-ac` + `decl-warn-ac` fixture(12 条断言),双向覆盖:

- 误抓消除方向:声明行存在时,散文否定提及(AC-3)不产生义务,RED-1 在无 AC-3 证据时照常收口;
- 强制保留方向:声明的 AC-2 缺证据时收口失败,失败信息点名 `missing: AC-2`,`--json` 携带 `covered_acs`/`missing_acs`;
- 跨 spec 收窄:声明行里的 AC-14 被收窄,不索要证据;
- 存量兼容:red-multi-ac(`Ref:` 风格)与 cross-spec-ac 既有断言即回退路径回归,原样保留;plan-lint 对无声明行任务 warn 且 exit 0;
- 空声明行边界:「覆盖验收：以下条目补充说明」触发 warn 且门禁回退全文扫描(§9.1 的双向证明);
- 新 CLI:`--task`(含 not-found + exit 1、空值报错)、`--all`(完成状态与 ac_refs)、默认调用回归。

全量 smoke 167/167 通过;`bash -n`、`shellcheck --severity=warning`、两个 examples try-it、`git diff --check` 全绿。

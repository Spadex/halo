# 分析：2026-08-03 门禁与工具链追加上报

上报原文：[`2026-08-03-halo-gate-findings_2.md`](2026-08-03-halo-gate-findings_2.md)
（来自 layrax `monorepo` 项目组，覆盖 `model-set` / `style-i18n-seed` / `layout-furnish-api` 三期，
kernel `1.0.0`，Python 3.12 + uv workspace + FastAPI + SQLAlchemy，spec 与 plan 全中文）。
本文是 halo 侧的独立复核，逐条对**当前 `main`**（而非上报者安装的 `1.0.0`）核对源码。

## 结论

**上报者安装的 kernel `1.0.0` 已显著落后于源码。** 上报的 15 条里：

| 分类 | 条数 | 说明 |
|---|---|---|
| 已在此前提交中修复 | 8 | §1.1 §1.2 §2.1 §2.2 §2.3 §3.1 §7.1 §7.2 |
| 本次修复 | 2 | §8.1、§3.3 的 `learn-draft.sh promote` 追加项 |
| 本期不修（P2 / 非缺陷） | 5 | §3.2 §3.3(标题) §3.4 §3.5 §7.3 |
| 流程反馈，非缺陷 | 2 | §4.1 §4.2 |

复核结论与上报定性有**三处不一致**：

| 条目 | 上报定性 | 复核结论 |
|---|---|---|
| §7.1 / §7.2 AC 编号盲扫 | 高 / 中优先级，仍存在 | **已修复**，见 §2 |
| §8.1 spec 选取按 mtime | 高优先级 | **成立，且是本批最危险的一条**，见 §1 |
| §3.3 promote 追加项 | 「本仓知识文件是表格结构」，像是项目侧形态差异 | **更根本：框架自带的默认目标就是表格**，见 §3 |

---

## 1. §8.1 spec 自动发现按 mtime（成立，已修复）

上报的根因判断与实测证据完全准确。复核只补两点。

**第一，波及面比上报写的还要宽。** 上报列了 `_lib.sh:155` 与 `guide.sh:106` 两处拷贝。
但 `find_spec()` 是 `pipeline.sh:290` 与 `ac-coverage.sh` / `spec-lint.sh` / `drift-check.sh` /
`compliance.sh` **五个调用点**的共同入口，所以「验错 spec」不是某一个门禁的问题，
而是整条链路同时错到同一个错误对象上——因此内部完全自洽，没有任何一处会互相打架报警。

**第二，`manifest.specs.active` 的默认值就是空。**
`harness-template/halo/manifest.template.yaml:40` 写的是 `active: ""`。
也就是说 mtime 兜底不是边角路径，而是**所有项目的默认路径**。

上报给的三条修复建议方向都对，本次按第 1 条（frontmatter 语义时间戳）实装，
并把第 3 条（兜底必须可被察觉）作为设计的重点而非附带项。第 2 条
（`halo/state/spec-transitions/*.json`）复核后未采纳：该目录不在 `init.sh:242` 的预建清单里，
只在 `spec-status.sh` 发生状态推进时才生成，一个已起草但从未推进过状态的 spec 在那里没有任何事件，
作为**权威**流水不够完备；而 frontmatter 的 `status` / `updated_at` 由 `spec-state-lint.sh:141,185`
强制校验取值与格式，是有门禁背书的信号。

### 修复

新增 `harness-template/halo/kernel/spec-select.sh`，`_lib.sh` 与 `guide.sh` 共用。
刻意不依赖 `_lib.sh` 与 yq：`_lib.sh` 在缺 yq 或缺 manifest 时直接 `exit 1`，
而 `guide.sh` 必须能在没有 halo 的 standalone 宿主下工作。

排序两键：

1. **`status != verified` 优先**。`verified` 是终态，推进中的 spec 才是工作对象。
   所有候选都已 verified 时这一键自动退化为无操作。
2. **frontmatter `updated_at` 降序**。它随 git 内容走，不受检出影响。

边界：

- 缺 `updated_at` 的 spec 排到**最低**而非最高——元数据失修是最弱的候选资格，不是最强的。
- **全部**候选都缺 `updated_at` 时回退 `ls -t`（保证不比旧行为更差），并明确打印这是 mtime 兜底、
  git 检出可能改变它。
- 最高位**完全并列**（同 status 档 + 同 `updated_at`）时以退出码 2 拒绝猜测。
  这是本文件存在的意义所在：并列时抛硬币正是要消除的失败模式。

**可察觉性**是本次修复的重点，也是上报第 3 条建议的核心：

- `spec-select.sh` 向 stderr 打印选中项与**每个落选项**及其 status / updated_at。
- `pipeline.sh` 在头部打印 `Spec: <path> (source=auto, status=… updated_at=…)`。
- eval JSON 新增 `spec_source`（`explicit` / `manifest-active` / `auto`）与 `spec_source_detail`，
  `guide.sh --json` 新增 `spec_source`。**这条让「谁指定了这个 spec」进入证据链**——
  上报方「读 eval JSON 时先核对 `spec_file`」的规避手法，现在框架自己就提供了判据。
- 四个门禁的 `find_spec` 调用点不再把「歧义」降级成 `⚠️ No spec file found, skipping`。
  原写法是 `SPEC=$(find_spec) || { echo "skipping"; exit 0; }`——**拒绝猜测会变成静默跳过门禁**，
  比猜错更糟。现在退出码 2 单独分支，报错退出。

**两份拷贝的收敛做到什么程度**：halo 宿主下是真正的单份实现（`guide.sh` 委托给 kernel 选取器）。
standalone 宿主保留同算法的内联副本——`prismspec` 设计上要能脱离 halo 运行（`guide.sh:73-86` 的
HOST 探测），让它硬依赖 `halo/kernel/` 会破坏这条边界。
冒烟测试断言两条路径在同一棵树上选出同一个 spec，防止将来漂移。

---

## 2. §7.1 / §7.2 AC 编号盲扫（已在上报之前修复）

上报把 §7.1 标为高优先级、§7.2 标为中优先级，且都描述为现存缺陷。
复核结论：`1f993a4`（2026-08-03）已修复两条，且修法与上报建议同向但更彻底。

`_lib.sh:176` 新增了单一权威来源：

```bash
spec_declared_acs() {
  { grep -E '^\| *AC-[0-9]+ *\|' "$spec" || true; } | sed -E 's/^\| *(AC-[0-9]+).*/\1/'
}
```

只取 AC 表行首单元格，且要求至少一位数字——上报最小复现里的两个伪 AC 都不再产生：

```
| AC-13 | tag `AC-STYLE-12` 与 `AC-99` |
  旧: AC-13 / AC-  / AC-99
  新: AC-13
```

§7.2 由 `_lib.sh:189 narrow_acs_to_declared()` 覆盖（`plan-lint.sh:169` 调用），
把 plan 侧的 AC 引用**收窄到 spec 声明的集合**，跨 spec 引用不再被索取覆盖说明。
同一修复也覆盖了 `task-complete.sh` 与 `summary-draft.sh`。

上报把这归纳为「门禁把 spec 正文里**被提及**的编号等同于**本期认领**的编号」，
这个概括准确，也正是修复采用的口径。

**对上报方的影响**：升级后 `AC-STYLE-12` 这类命名空间标签、
以及在 `plan.md` 的「非本期验收项」清单里枚举 `AC-15` / `AC-99` 的规避手法，**都可以撤掉**。

---

## 3. §3.3 追加项：`learn-draft.sh promote` 污染表格式知识文件（成立，已修复）

上报把它写成「本仓 `halo/context/knowledge/*.md` 均为表格结构，而该脚本追加成小节」，
读起来像项目侧的文件形态差异。复核后定性要更重一档：

**框架自带的默认 promote 目标本身就是表格。**
`harness-template/halo/context/knowledge/pitfalls.md`：

```markdown
| Pitfall | Trigger | Guidance | Source |
|---------|---------|----------|--------|

## Do Not Repeat
```

而 `learn-draft.sh:170`（修复前）无条件 `>> "$TARGET_ABS"`，
把 `## Promoted Learn Draft` 追加到文件末尾——落在表格之外、`## Do Not Repeat` 之后。
`--to` 的默认值就是这个文件（`learn-draft.sh:13`）。
即**任何按默认配置使用 `learn-draft.sh promote` 的项目都会被污染**，与本仓形态无关。

这与上一轮的 §1（错误码门禁读不懂框架自己的 spec 模板）、§3（软门禁读不懂框架自己的中文模板）
是同一类问题：**框架与自带模板打架**。

**且 `knowledge-lint.sh` 抓不到**：`check_source()` 只要求文件里存在
`**Source**:` 行或 `| Source |` 列，表格的表头已经满足，追加的小节因此永远是静默的。

上报的第二点——「写入的是裁断过程而非知识本身」——同样成立：
`**Failure category**` / `**Default action**` / `**Promoted at**` 是裁断元数据，
它已经完整存在于 `halo/state/learn-promotions/*.json` 与归档草稿里，重复写进知识文件只有污染。

### 修复

promote 分支按目标文件形态分流：

- **表格式目标**：定位首个 markdown 表（表头行 + `|---|` 分隔行），
  在该表最后一条连续数据行之后插入。每条 Lesson Candidate 生成一行：
  第 1 列放教训正文，表头匹配 `Source|来源|出处` 的列填归档草稿路径，其余列填 `—`。
  正文中的 `|` 转义为 `\|`，否则会静默多切出一列。
  **不再**写入裁断元数据。
- **小节式目标**：保持原有追加行为不变。
- 收口消息区分形态：`(N row(s) added to knowledge table)` / `(section appended)`。

行内容通过临时文件而非 `awk -v` 传入：`awk -v` 会展开反斜杠转义，把 `\|` 还原成 `|`，
正好抵消掉上面的转义。

上报建议的「至少给出警告而非静默追加」是下限；本次直接实装了表格写入，
因为默认目标就是表格，只警告等于让框架自带的流程永远走不通。

---

## 4. 本期不修

| 条目 | 理由 |
|---|---|
| §3.2 knowledge-reference 按路径字符串匹配 | 上报方自己也定性为书写约定。语义匹配不可靠，仅改文案收益有限 |
| §3.3 `summary-learn-draft.sh` 只认英文精确标题 | 框架自产的 `verify.md`（`summary-draft.sh:218`）写的就是英文 `## Knowledge Candidates`，命中正常；仅手写中文标题时失配。上报方本期已找到更好的规避（该节标题直接写英文），成本进一步降低。P2 |
| §3.4 `knowledge-lint.sh` UTC 未来日期 | warn 级，规避成本极低。P2 |
| §3.5 `prismspec/bin/lint.sh` 的 `verify` 别名 | 零风险可用性改进。P2 |
| §7.3 `TASK_ID` 形状校验 | 上报方已自行更正——框架行为正确，成因在调用侧。加固建议成立但非缺陷，P2 |
| §4.1 RED/T 成对执行的文档说明 | 上报方自述非缺陷。属流程文档问题，另行评估 |
| §4.2 `tdd-evidence.json` 的 `red.method: mutation` | 属 schema 新特性而非缺陷修复。变异法取红的诉求成立（「审计 21 份证据时无法从机器侧区分变异取红与伪造红绿」这个论证是对的），值得单独设计 |

---

## 5. 给上报方的升级说明

上报方安装的是已发布的 kernel `1.0.0`，源码已领先。升级到 `main` 后，
以下**规避手法可以全部撤除**：

| 规避手法 | 对应上报条目 | 可撤除的原因 |
|---|---|---|
| `RED-N/cycle-AC-N/` 单元素分片证据 | §2.2 | `c75d0c4` 已消除 SIGPIPE，多元素 `ac_ids` 可靠匹配 |
| plan 中路由写冒号风格 `:set_id`、区间改写 `≤`/`≥` | §2.3 | `plan-lint.sh:226-227` 已排除小写花括号与非括号对的 `<`/`>` |
| `AC-STYLE-12` 命名空间标签 | §7.1 | AC 只从行首单元格提取，行内标签不再造出伪 AC |
| plan 的「非本期验收项」清单枚举 `AC-15`/`AC-99` | §7.2 | plan 侧 AC 引用已收窄到 spec 声明集合 |
| `/verify` 一律显式传 `--spec=` | §8.1 | 本次修复。不过**显式传参仍是更好的习惯**，且现在 eval JSON 会记 `spec_source=explicit` 留痕 |
| 手工往知识表格加行、跳过 `learn-draft.sh promote` | §3.3 | 本次修复，promote 认得表格式目标 |
| spec 第 3 节上下文依据的中文来源表告警 | §3.1 | `compliance.sh:139` 已补齐中文来源类别 |

仍需保留的：`verified_at` 填 UTC 日期（§3.4）、verify.md 的知识候选节用英文标题（§3.3）。

`harness-template/halo/kernel/VERSION` 本次未变动（与 `#10`–`#14` 一致），
版本号与发布节奏是独立决定；请以 `main` 的源码为准，或在升级后用
`bash halo/kernel/doctor.sh` 确认 `spec-select.sh` 已就位。

---

## 6. 回归覆盖

`tests/smoke-test.sh` 新增两节，共 11 条断言，**修复前全部失败**（在 HEAD 工作树上实测：141/152）：

**`── 9b. Spec auto-discovery ──`**

| 场景 | 断言 |
|---|---|
| mtime 与 `updated_at` 相反（`touch` 模拟 git 检出） | 选中 `updated_at` 最新者——上报的原始复现 |
| 选取过程 | stderr 同时出现 `selected` 与 `not selected` |
| verified spec 的 `updated_at` 更新 | 仍选中未 verified 者 |
| 同 status 档 + 同 `updated_at` | 退出码 2，消息含 `--spec=` |
| 全部候选缺 `updated_at` | 回退 mtime 且文案含 `mtime` |
| `pipeline.sh --json-out` 自动发现 | stdout 含 `source=auto`，eval JSON `spec_source == "auto"` |
| `pipeline.sh --spec=` | eval JSON `spec_source == "explicit"` |
| `guide.sh --json` | `spec_id` 与 kernel 选取器一致，`spec_source == "auto"` |

**`── 9c. Learn draft promotion shape ──`**

| 场景 | 断言 |
|---|---|
| promote 进表格式目标 | 表内行数由 1 增至 3、`## Do Not Repeat` 之前、文件不含 `Promoted Learn Draft`、消息含 `row(s) added` |
| 教训正文含 `\|` | 输出为 `Escape the \| pipe`，表格未被撑破 |
| `knowledge-lint.sh --strict` | 仍通过 |
| 小节式目标 | 仍写 `## Promoted Learn Draft`，消息含 `section appended` |

既有的 `learn-draft promotes draft with audit event` 用例同步修正：
它的目标 `pitfalls.md` 是表格文件，此前断言 `grep -q "Promoted Learn Draft"`
恰好把缺陷行为固化成了期望值。

收口：`bash -n` / `shellcheck --severity=warning` / `tests/smoke-test.sh`（152/152）
/ `examples/go-gin-gorm/try-it.sh` / `git diff --check` 全通过。

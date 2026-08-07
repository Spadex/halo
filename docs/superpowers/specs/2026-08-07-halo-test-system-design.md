# Halo 测试体系设计（四层防线 + 流程闭环）

日期：2026-08-07
状态：已与维护者逐节确认

## 背景与问题

Halo 已收到 11 组外部 bug 报告（`docs/bug_report/`）。对全部报告的根因归类显示：

| 根因类别 | 复发次数 | 代表报告 |
|---|---|---|
| A. 词法抓取「提及 ≠ 声明」不分 | 5 次 | #7 → #8 → #9 → #14 → runningtime |
| B. `set -euo pipefail` 退出码/管道语义 | 3 次（另有 2 处已知未修：`_lib.sh:158`、`guide.sh:180,187`） | #5、#11、#17 |
| C. fail-open / fail-closed 方向搞反 | 4 次（含原则作者在写下原则的同一提交里违反） | #10、#12、#15、#16 |
| D. mtime/列序/目录序等非确定性依赖 | 3 次 | #15、#12、#17 |
| E. 框架读不懂自带模板 | 4 处 | #12、#15 |
| F. 语法变体覆盖不足（硬编码单一形态） | 3 次 | #5、#12、#16 |
| G. 判定量词错误（任一 vs 全部） | 1 次 | #10 |
| H. 同一语义多份定义漂移 | 4 次（`task_body` 仍有 4 份副本） | #10、#14、#15、runningtime |

现有测试形态的问题：

- `tests/smoke-test.sh` 已达 3023 行单体，fixture 与断言纠缠，失败难归因，无法单跑用例，自身还产生过 bug（#17）。
- 测试与实现出自同一心智模型，只验证「编码对不对」，验证不了现实形态（FastAPI 用例曾只有单行装饰器一种形态；有用例把缺陷行为固化成期望值）。
- 最危险的失败形态是「一处根因、整条链路一致地错、内部自洽无报警」（`find_spec` 是 5 个门禁的共同入口），只能靠外部上报发现。
- 已在实践中形成的回归测试纪律（双向断言、先红后绿、竞态确定化）没有成文，也没有机器强制。

## 目标

1. 已修过的 bug 不复发（回归语料库）。
2. 核心原则（AGENTS.md Gate Rules）不被后续改动违反（机器强制，不只靠文档）。
3. 核心功能有出口语义级的验收（E2E）。
4. 未来的 bug 处置有明确 SOP，且约定被 CI 强制。

## 已确认的关键决策

| 决策 | 结论 |
|---|---|
| 改造范围 | 框架 + 内容都做 |
| 测试运行器 | bats-core（git submodule 引入并锁版本，不要求 brew/npm 安装） |
| 迁移节奏 | 先搭骨架，存量分批迁移，每批迁完删除对应旧段 |
| 整体架构 | 方案 A：四层防线 + 流程闭环 |

## 目录结构

```
tests/
  run.sh                    # 统一入口：跑 bats 各套件 + 存量 smoke-test（双轨期）
  vendor/                   # git submodule，锁定版本
    bats-core/
    bats-support/
    bats-assert/
  helpers/
    common.bash             # setup 公共逻辑：隔离临时目录、安装 harness
    fixtures.bash           # spec/plan 构造函数（heredoc 参数化）
  fixtures/                 # 静态 fixture 文件（语法变体矩阵按框架分目录）
  unit/        *.bats       # 第 1 层：契约单测
  regression/  *.bats       # 第 2 层：bug 回归语料
  e2e/         *.bats       # 第 3 层：完整 pipeline
  meta/                     # 第 4 层：原则守护 lint（脚本 + 它自身的测试 + allowlist.txt）
  README.md                 # 维护者手册（bug 处置 SOP）
  smoke-test.sh             # 存量，分批瘦身直至删除
  release-check.sh
```

基础设施要点：

- `tests/run.sh` 检测 submodule 未初始化时提示 `git submodule update --init`；本地与 CI 跑同一份 bats。
- 每条用例独立进程 + 独立临时目录（bats 默认行为）。安装 harness 较慢，用 `setup_file` 每文件安装一次到模板目录，每条用例从模板 `cp -R` 出隔离副本。
- fixture 从内嵌 heredoc 提炼为参数化构造函数（如 `make_spec --id x --acs 3`）；语法变体（多行装饰器、中文列序、非 1 起点 AC 等）保存为 `fixtures/` 静态文件。
- CI 新增 test workflow，matrix 跑 ubuntu + macos（macos runner 是机器化拦截 BSD awk 类平台缺陷的唯一手段，#12 目前只靠代码注释防回退）。

## 第 1 层：契约单测 `tests/unit/`

防御目标：「一处根因、多个门禁一致地错、无报警」。规则：**凡被多个调用方共享的谓词，必须有不经过任何门禁的直接测试。**

首批覆盖对象（按共享度排序）：

| 被测函数 | 所在文件 | 契约要点 |
|---|---|---|
| `find_spec` | `_lib.sh` | 排序语义确定（不依赖 mtime）；歧义时报错退出而非静默 skip；两条调用路径选同一 spec |
| `narrow_acs_to_declared` | `_lib.sh` | 声明行 vs 散文提及的判定边界；跨 spec 引用收窄；空声明行为 |
| `task_has_ac_declaration` | `_lib.sh` | plan-lint 与门禁共用同一谓词，防再漂移 |
| AC 提取/归属逻辑 | `ac-coverage.sh` | 大小写契约、Tier1/Tier2 归属、跨 spec 命名空间隔离 |
| 模式解析链（`执行模式：`等） | `task-complete.sh` 等 | 中英文别名统一口径；unknown 显式报告而非静默跳过 |

写法约定：

- 每个契约测试文件头注明「此函数有 N 个调用方：…」，让改动者一眼看到爆炸半径。
- 每个共享函数的单测必须包含边界条件族：空输入、grep 未命中、pipefail 下的管道退出码（对应根因 B）。

## 第 2 层：回归语料库 `tests/regression/`

组织规则：**一份 bug 报告 = 一个测试文件**，文件名与报告对齐：

```
tests/regression/2026-08-03-fastapi-collection-root.bats
  ↔ docs/bug_report/2026-08-03-fastapi-collection-root-route-dropped.md
```

文件头固定三行注释：bug 报告路径、根因类别、修复提交哈希。任何回归失败的归因链路为「测试文件名 → 报告 → 根因」三跳直达。

入库纪律（把 #16 / runningtime 处置中形成的事实标准成文）：

1. **双向断言**：必须同时有「误报已消除」与「真缺陷仍被抓住」两个方向。只有正向断言的回归测试等于没有。
2. **先红后绿**：先在未修复代码上确认 FAIL，再确认修复后 PASS，提交信息记录。
3. **非确定性缺陷必须确定化**：竞态类 bug 不允许重复跑碰运气，须如 #11 注入慢 yq 般放大为 100% 触发。

## 第 3 层：端到端 `tests/e2e/` + `examples/`

1. `tests/e2e/pipeline.bats`：完整走「init → spec → plan → 门禁 → 证据」黄金路径。断言出口语义（退出码、eval JSON 关键字段），不断言中间实现细节（避免 #10 式「硬编码计数被无关新增误伤」）。
2. `examples/*/try-it.sh` 真实项目矩阵：职责是打破「测试与实现同一心智模型」。规则：**drift-check 每声称支持一种框架，`examples/` 必须有该框架的可运行工程，且刻意包含其惯用语法变体**（现有 go-gin-gorm、py-fastapi；未来支持 Express 时同步新增）。

## 第 4 层：原则守护 meta-lint `tests/meta/`

把 AGENTS.md Gate Rules 从文档变成机器断言：

| 检查 | 拦截的根因 | 实现方式 |
|---|---|---|
| 失败方向注释强制：code 侧提取循环中的 `continue`/过滤，两行内必须有注明失败方向的注释 | C（方向搞反 4 次） | grep 扫描 |
| pipefail 反模式扫描：`yq … \| grep -q`、`find … \| xargs ls -t \| head`、命令替换包 grep 无 `\|\| true` 兜底 | B（3 次复发 + 2 处已知未修） | grep 模式库 |
| 非确定性依赖扫描：决策路径上的 `ls -t`、`stat %m`、无 `sort` 的 `find` 直接消费 | D（3 次） | grep 扫描 |
| 重复定义检测：同一函数名在多个文件重复定义 | H（4 次，`task_body` 现存 4 份副本） | 函数定义清点 |
| 诚实 skip 检查：门禁 `exit 0` 前无「NOT verified / skipped」输出即报警 | 静默跳过＝假绿（#10、#15） | grep 扫描 |

配套设计（防 meta-lint 自身成为噪声源）：

- **豁免清单** `tests/meta/allowlist.txt`：每条豁免必须带原因注释；误报登记豁免而非改代码迁就 lint。
- **meta-lint 自身有测试** `tests/meta/meta-test.bats`：每条规则配「坏样本必须被抓 + 好样本必须放行」双向用例。

分工边界：meta-lint 只抓词法层可判定的模式；A 类（提及 vs 声明）的机器防线是第 1 层对 `narrow_acs_to_declared` 的契约单测。

## 流程闭环

### 维护者手册 `tests/README.md`

核心是 bug 处置 SOP：

1. **收报告**：上报原文放 `docs/bug_report/YYYY-MM-DD-<slug>.md`（多文件建同名目录），原文一字不改。
2. **独立复核**：不采信报告结论，自行验证根因，写 `…-analysis.md`。
3. **写回归测试**：`tests/regression/YYYY-MM-DD-<slug>.bats`，头三行注释，双向断言，先红后绿。
4. **随修复一并提交**：报告、analysis、回归测试、修复代码同批提交，不留未跟踪文件。
5. **根因归类**：归入手册末尾根因类别表。若是已有类别复发，必答一问：「meta-lint 或契约单测为什么没拦住？」——答案通常指向要新增的 lint 规则或单测，这是第 4 层持续生长的机制。

手册另收录：跑测试的方式（全量/单文件/单用例）、fixture 构造函数用法、meta-lint 豁免登记方式、新增框架支持时 examples 的配套义务。

### 机器强制

- **报告↔测试对应检查**（`tests/meta/`）：`docs/bug_report/` 下每份已处置报告（存在 `-analysis.md`）须有同名 `tests/regression/*.bats`；纯流程/性能类报告登记豁免并注明原因。新报告未配测试则 CI 红。
- **`release-check.sh` 扩展**：发版前 `tests/run.sh` 须全绿；kernel 有改动而 `VERSION` 未动时报警（#15 发现 #10–#16 期间 VERSION 未变，发布与修复脱钩导致重复上报）。
- **AGENTS.md 修订**：Verification 段命令清单改为 `tests/run.sh`；新增一行指向 `tests/README.md` 作为 bug 处置规范入口。

### 迁移批次计划

| 批次 | 内容 | 完成定义 |
|---|---|---|
| 0 | bats 骨架 + helpers + CI workflow + `tests/README.md`；此后新测试只允许写 bats，smoke-test.sh 冻结（只删不加） | CI 双平台绿 |
| 1 | AC 系列迁移（查重/断号/跨 spec/声明行，对应 #7/#9/#14/runningtime） | 新用例与旧断言等价（旧段注入缺陷时新用例也红），删旧段 |
| 2 | drift-check 系列（§7c，#12/#16）+ 契约单测首批（`find_spec`、`narrow_acs_to_declared`） | 同上 |
| 3 | SDD 门禁系列（§6d、SIGPIPE、learn-draft §9b/9c）+ 契约单测其余三项（`task_has_ac_declaration`、AC 归属、模式解析链）+ meta-lint 五条规则上线 | 同上；meta-lint 双向自测绿 |
| 4 | E2E 主干迁移，删空 smoke-test.sh，双轨期结束 | smoke-test.sh 删除，`tests/run.sh` 为唯一入口 |

双轨期约束：`tests/run.sh` 同时跑 bats 与 smoke-test 残余，CI 全程有覆盖，无真空窗口。

## 错误处理与失败语义

- 测试失败输出必须自含归因信息（文件名 → 报告 → 根因三跳），不依赖阅读实现。
- meta-lint 误报走豁免清单，不允许为通过 lint 而改坏代码。
- `tests/run.sh` 任何套件失败即非零退出；套件间不互相吞退出码（这本身是根因 B，运行器自身要过 shellcheck 与 meta-lint）。

## 非目标

- 不引入 bash 之外的测试语言/框架。
- 不做「halo 安装 halo 自测自己」的 dogfooding gate（记为远期方向）。
- 不在本设计内解决 runningtime 报告中的性能/流程类议题（评审串行、上下文膨胀）——那是流程文档的事，不是测试体系的事。

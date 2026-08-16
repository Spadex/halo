# Halo 测试维护手册

本目录是 Halo 的测试体系。设计全貌见
`docs/superpowers/specs/2026-08-07-halo-test-system-design.md`。

## 怎么跑

```bash
bash tests/run.sh              # 全量（bats 各套件 + 存量 smoke-test）
bash tests/run.sh unit         # 只跑某个套件：unit|regression|e2e|meta|legacy
tests/vendor/bats-core/bin/bats tests/unit/fixtures.bats            # 单文件
tests/vendor/bats-core/bin/bats tests/unit/fixtures.bats -f "make_spec"  # 按名字过滤单用例
```

首次使用先初始化 submodule：`git submodule update --init`。

## 目录结构

| 目录 | 职责 |
|------|------|
| `unit/` | 契约单测与门禁行为单测（18 条） |
| `regression/` | 回归语料库：一份 bug 报告 = 一个 `.bats` 文件（37 条） |
| `e2e/` | 端到端：init → spec → plan → 门禁 → 证据 黄金路径 （批次 4 起）|
| `meta/` | 原则守护 lint：把 AGENTS.md Gate Rules 变成机器断言 （批次 3 起）|
| `helpers/` | `common.bash`（沙箱）、`fixtures.bash`（spec/plan 构造函数） |
| `fixtures/` | 静态语法变体 fixture，见 `fixtures/README.md` 的变体矩阵 |
| `vendor/` | bats-core / bats-support / bats-assert（git submodule，锁版本） |

`smoke-test.sh` 是迁移中的存量：**已冻结，只删不加**。新测试一律写 bats。

## 遇到 bug 怎么办（处置 SOP）

1. **收报告**：上报原文放 `docs/bug_report/YYYY-MM-DD-<slug>.md`（多文件建同名目录），原文一字不改。
2. **独立复核**：不采信报告的结论与建议，自行验证根因，复核结论写同名 `…-analysis.md`。
3. **写回归测试**：`tests/regression/YYYY-MM-DD-<slug>.bats`，文件名与报告对齐。文件头固定三行注释：

   ```bash
   # Bug report: docs/bug_report/YYYY-MM-DD-<slug>.md
   # Root cause class: <见下方根因类别表>
   # Fixed by: <commit hash>
   ```

   入库纪律：
   - **双向断言**——「误报已消除」和「真缺陷仍被抓住」两个方向都要有；
   - **先红后绿**——先在未修复代码上确认 FAIL，再确认修复后 PASS，提交信息里记录；
     历史 bug 已经修过、回不到修复前的，走下方「等价性验证」；
   - **竞态必须确定化**——不允许重复跑碰运气（参考 #11 注入慢 yq 的做法）。

   **命名规则**（对拍靠它，别随手起名）：
   - 报告已合规（文件名是 `YYYY-MM-DD-<slug>.md` 或同名目录）→ bats 文件名与报告
     basename **逐字相同**；
   - 历史遗留报告（命名不合规）→ 日期取**修复提交的作者日期**，slug 取语义 slug，
     映射登记到 `docs/bug_report/INDEX.md`。
   - 自查/CI 发现、没有上报原文的缺陷 → 只写 analysis，正文必须写清**发现路径**
     （哪次 CI、哪个 run），**不许**为了凑格式补造一份「上报原文」。
4. **随修复一并提交**：报告、analysis、回归测试、修复代码同一批提交，不留未跟踪文件。
5. **根因归类**：归入下表。若是已有类别的复发，必须回答：「meta-lint 或契约单测为什么没拦住？」——答案通常就是要新增的 lint 规则或单测。

## 根因类别表

| 类别 | 含义 | 机器防线 |
|------|------|----------|
| A. 词法「提及≠声明」 | 全文 grep 把散文/交叉引用当结构化声明 | `unit/` 对 `narrow_acs_to_declared` 等的契约单测 |
| B. pipefail 语义 | grep 未命中崩溃、SIGPIPE、while 退出码 | `meta/` 反模式扫描 + 单测边界条件族 |
| C. 失败方向搞反 | fail-open/fail-closed 用错边 | `meta/` 失败方向注释强制 |
| D. 非确定性依赖 | mtime 排序、find 目录序、表格列序 | `meta/` 扫描 |
| E. 框架读不懂自带模板 | 默认模板触发自家门禁误报 | `e2e/` + examples 黄金路径 |
| F. 语法变体覆盖不足 | 只认单一书写形态 | `fixtures/` 变体矩阵 + examples 真实工程 |
| G. 判定量词错误 | 任一 vs 全部 | 回归用例双向断言 |
| H. 同一语义多份定义漂移 | 重复实现各自演化 | `meta/` 重复定义检测 + 契约单测 |

## 新增框架支持的配套义务

drift-check 每声称支持一种框架，`examples/` 必须新增该框架的可运行工程，
且工程里刻意包含该框架的惯用语法变体（多行装饰器、集合根路由等）。

## meta-lint 豁免

误报不改代码迁就 lint：在 `tests/meta/allowlist.txt` 登记一行豁免，
必须附原因注释。豁免在 review 中可见。（meta-lint 于批次 3 上线。）

## 等价性验证（变异测试）

**用在哪**：迁移存量测试、或为早已修复的历史 bug 补回归测试时——这两种情况都回不到
「未修复代码」，SOP 的先红后绿无从执行。

做法是反过来：**对修复点注入定向缺陷，确认预期的用例变红**。

四步协议，每条变异都要走完：

```bash
git status --porcelain          # 1. 必须为空
#  2. 精确改一处（手工编辑，或脚本做单次字符串替换；禁止 sed -i）
tests/vendor/bats-core/bin/bats tests/regression/<file>.bats   # 3. 记录变红的用例名
git checkout -- harness-template/                              # 4. 回滚
git status --porcelain          #    必须再次为空，且重跑全绿
```

**红线：任何变异都不得进入提交。** 产出是提交信息里的执行记录，不是代码改动。

验收门槛：**每条被迁移的断言都必须至少被一条变异点亮**。某条断言没有任何变异能点亮，
先分清是哪种情况——

| 情况 | 表现 | 怎么办 |
|------|------|--------|
| 断言没判别力 | 换任何实现都绿 | 回去加强断言 |
| 变异集有缺口 | 断言守的是另一个方向（比如「不许过严」），而变异全在放松 | 补一条反方向的变异 |

批次 1 就撞上第二种：21 条变异全在让门禁变松，4 条「正向归属」用例因此没被点亮；
补一条让 Tier 1 恒不命中的变异（门禁最大限度误红）后精确点亮了那 4 条。

## 写用例的约定

- 用 `helpers/fixtures.bash` 的 `make_spec` / `make_plan` 生成黄金形态，
  语法变体用 `sed`/`awk` 改写产物或放 `fixtures/` 静态文件；不要复制粘贴整段 heredoc。
- **构造函数 / 派生 / 静态文件的三档分界线**：
  - 跨用例复用、差异可用少量标量参数表达的**黄金形态** → 构造函数；
  - **单元素变体**（改一个单元格、改一个 AC 号、复制一行）→ 用例内 `sed`/`awk` 派生；
  - **多个陷阱元素同时出现在一份文档不同位置** → `fixtures/` 静态文件，
    因为它的价值在于可被逐字审阅，参数化会把陷阱藏进生成逻辑。
    详见 `fixtures/README.md`。
- **跨平台**：`sed -i` 在 BSD 上要后缀、GNU 上不要，两边不通用，一律改写到临时文件再 `mv`；
  BSD sed 的替换串不支持 `\n`，**复制行用 `awk`**。
- **yq 是 mikefarah v4，表达式语言不是 jq**：数组字面量比较（`.a == ["x","y"]`）会静默求值为
  false，数组断言走 `join(",")` 或 `length`。
- 沙箱用 `helpers/common.bash`：`setup_file` 里 `halo_template_install`（每文件装一次），
  `setup` 里 `halo_sandbox_clone`（每用例一个隔离副本，自动 cd）；
  静态 fixture 用 `halo_install_fixture <rel>` 叠加，语言形态用 `halo_set_language <lang>`。
- 断言出口语义（退出码、eval JSON 关键字段），不断言中间实现细节。
- 契约单测文件头注明被测函数的调用方清单，让改动者看到爆炸半径。
- **只服务单个文件的前置构造函数就留在那个文件里**，不要提到 `helpers/`——
  没有第二个调用方的 helper 会变成下一个「谁在用它」的谜团。

## 批次 3 待办注记

`red-many-ac` 的 SIGPIPE 竞态（#11）迁移时需要一个可复用的慢 yq 注入函数。
本批次不实现（没有调用方，YAGNI），接口先记在这里：

```bash
# halo_slow_yq_path <yq-arg-1> <yq-arg-2>
#   造一个把匹配指定参数的 yq 调用逐行慢放（每行 sleep 0.05）的 shim 目录，回显该路径，
#   供调用方 PATH="$(halo_slow_yq_path -r '.ac_ids[]?'):$PATH" 使用。
#   用途：把「读端提前关闭 → SIGPIPE(141) 在 pipefail 下毒化退出码」的竞态确定化为 100% 触发。
#   蓝本：见 git history 的 tests/smoke-test.sh 慢 yq shim（批次 1 前的 :1338-1356）。
```

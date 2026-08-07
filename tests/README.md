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
| `unit/` | 契约单测：被多个门禁共享的谓词（`_lib.sh` 等）的直接测试 |
| `regression/` | 回归语料库：一份 bug 报告 = 一个 `.bats` 文件 |
| `e2e/` | 端到端：init → spec → plan → 门禁 → 证据 黄金路径 |
| `meta/` | 原则守护 lint：把 AGENTS.md Gate Rules 变成机器断言 |
| `helpers/` | `common.bash`（沙箱）、`fixtures.bash`（spec/plan 构造函数） |
| `fixtures/` | 静态语法变体 fixture，按框架分目录 |
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
   - **竞态必须确定化**——不允许重复跑碰运气（参考 #11 注入慢 yq 的做法）。
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

## 写用例的约定

- 用 `helpers/fixtures.bash` 的 `make_spec` / `make_plan` 生成黄金形态，
  语法变体用 `sed` 改写产物或放 `fixtures/` 静态文件；不要复制粘贴整段 heredoc。
- 沙箱用 `helpers/common.bash`：`setup_file` 里 `halo_template_install`（每文件装一次），
  `setup` 里 `halo_sandbox_clone`（每用例一个隔离副本，自动 cd）。
- 断言出口语义（退出码、eval JSON 关键字段），不断言中间实现细节。
- 契约单测文件头注明被测函数的调用方清单，让改动者看到爆炸半径。

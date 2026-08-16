# 复核：init.sh 项目探测在 pipefail 下静默猝死

日期：2026-08-16
状态：已修复，回归测试入库
根因类别：**B. `set -euo pipefail` 退出码/管道语义**

## 这份文档为什么没有配对的上报原文

本缺陷不是外部上报，是**批次 0 新增的 macOS CI job 首次运行时自己抓到的**。
按 `tests/README.md` 的处置 SOP，上报原文放 `docs/bug_report/YYYY-MM-DD-<slug>.md`；
自查发现的缺陷没有原文可放，所以只有这份复核文档。证据链在下面「发现路径」一节，
不用「补写一份上报」来凑格式。

## 发现路径

- 触发运行：<https://github.com/Spadex/halo/actions/runs/31923714977>（`test` workflow，批次 0 提交推送后首跑）
- `test (ubuntu-latest)` ✅ 全绿
- `test (macos-latest)` ❌ 失败：
  - bats `tests/unit/fixtures.bats` 与 `harness-setup.bats` 的 `setup_file` 挂在 `halo_template_install`
  - legacy smoke-test §3 打印 `❌ init.sh exited non-zero`
  - legacy smoke-test §5 打印 `Pipeline executed (exit=127)`

设计文档 `docs/superpowers/specs/2026-08-07-halo-test-system-design.md` 把 macos runner 定为
「机器化拦截 BSD/平台类缺陷的唯一手段」。它在第一次运行就兑现了这个职责，
拦下的还不是平台工具链差异，而是一个**任何没装 Go 的用户都会撞上的产品缺陷**。

## 症状

`halo init` 在 Go 项目上运行时，输出停在：

```
🔍 Detecting project info...
```

之后进程以 127 退出，**不打印任何错误信息**。用户拿不到任何可行动的线索。

## 根因

`init.sh:10` 是 `set -euo pipefail`。探测段 `init.sh:124`（修复前）：

```bash
DETECTED_VERSION=$(go version 2>/dev/null | awk '{print $3}' | sed 's/go/>=/')
```

`go` 不存在时：

1. `go version` 以 127 退出（`2>/dev/null` 只吞掉了它的错误输出，没吞退出码）；
2. `pipefail` 让整条管道取到非零状态 127；
3. 命令替换随之非零，这是一条**独立的赋值语句**，不在 `if`/`&&` 等豁免位置；
4. `set -e` 触发，脚本静默退出。

三个特征叠加才让它这么难查：`2>/dev/null` 掩掉了唯一的线索、`pipefail` 把探测器的
状态搬运到了赋值上、`set -e` 让退出不留话。

同一段代码里的另外两个探测分支**都带兜底**：

| 分支 | 行 | 写法 |
|---|---|---|
| node | `:133` | `$(node --version 2>/dev/null \| sed 's/v/>=/' \|\| echo "")` ✅ |
| python | `:144` | `$(python3 --version 2>/dev/null \| awk '{print ">="$2}' \|\| echo "")` ✅ |
| **go** | `:124` | 无兜底 ❌ |

所以这不是「没想到探测器会不可用」，而是**同一语义在同一段代码里写出了两种形态**
（根因 H 的味道），漏掉兜底的那一份恰好没人踩到——因为开发机与 ubuntu CI 都装着 Go。

### 第二个调用点

`init.sh:153`（rust 分支）是同一缺陷的第二处：

```bash
DETECTED_NAME=$(grep '^name' Cargo.toml | head -1 | sed 's/.*= *"\(.*\)"/\1/')
```

`Cargo.toml` 里没有 `^name` 行时 grep 返回 1 → pipefail → 命令替换失败 → `set -e` 静默退出。
触发条件比 go 那处窄（workspace 根的 `Cargo.toml` 通常只有 `[workspace]`，正是这种形态），
但缺陷完全相同。修复一并覆盖，不留同根残余。

## 本地复现（确定性）

```bash
# 造一个不含 go 的干净 PATH（只留 yq / git 与系统工具）
env -i HOME="$HOME" PATH="$SHIM:/usr/bin:/bin:/usr/sbin:/sbin" /bin/bash -c "
  cd <go 项目>; bash .halo/framework/init.sh --non-interactive --lang=go --name=testapp --ci=github"
# 修复前：输出停在「🔍 Detecting project info...」，exit 127
# 修复后：exit 0，manifest 的 .project.version_constraint 为默认值 >=1.0
```

## 影响面

- **所有未安装 Go 的机器上，Go 项目无法完成 `halo init`**，且没有错误提示。
- `install.sh --init` 同样受影响（它内联调用 init.sh）。
- 级联：init 失败 → `halo/kernel/` 未落地 → 后续 `pipeline.sh` 找不到脚本，报 127。
  smoke-test §5 的断言过宽（`Pipeline executed (exit=127)` 被记为通过），
  把这个级联症状吞掉了——已记入下方待办。

## 修复

两处都改成与 node/python 一致的 fail-open 形态，并在代码里注明失败方向：

- `init.sh:124` 追加 `|| echo ""` → 探测失败时 `VERSION` 回落到 `:180` 的默认值 `>=1.0`
- `init.sh:153` 追加 `2>/dev/null` 与 `|| echo "unknown"`

探测结果只是默认值，用户随时可用 `--lang` / `--name` 等参数覆盖，**探测器不可用不是错误**，
不该让它掐死初始化。

## 回归测试

`tests/regression/2026-08-16-init-detection-probe-pipefail.bats`，5 条，双向：

| 方向 | 用例 |
|---|---|
| 缺陷方向 | 探测器返回 127 时 init 仍成功、manifest 生成 |
| 缺陷方向 | 探测失败时 `version_constraint` 回落为 `>=1.0` |
| 反向（不许因修复变瞎） | 探测成功时 `version_constraint` 仍是 `>=1.22.5` |
| 缺陷方向 | `Cargo.toml` 无 name 行时 init 仍成功 |
| 反向 | `Cargo.toml` 有 name 行时仍探测到 crate 名 |

**确定化手段**：用 PATH 前置的 `go` shim 控制探测器的退出码，而不是真的卸载 Go。
这样用例在装了 Go 和没装 Go 的机器上行为一致，不靠环境碰运气
（与 `#11` 注入慢 yq 的思路同源）。

**先红后绿**：修复前实测 1/2/4 号红（go 侧 status 127、rust 侧 status 1）、3/5 号绿；
修复后 5/5 绿。3/5 号在修复前就是绿的，正是它们保证了修复不是「把探测删掉」。

## 机器防线为什么没拦住

| 问题 | 答案 |
|---|---|
| 为什么已有测试没抓到？ | smoke-test 与 bats 都只在装了 Go 的机器上跑过（开发机 + ubuntu CI）。缺陷的触发条件是「探测器不可用」，而**从来没有测试制造过这个条件**。 |
| 为什么 meta-lint 没抓到？ | meta-lint 尚未上线（批次 3）。设计文档已把「命令替换包管道无 `\|\| true` 兜底」列入 pipefail 反模式扫描规则——本次缺陷是这条规则的直接证据，规则的模式库应把 `$(...\|...)` 后无 `\|\|` 的赋值纳入。 |
| 为什么现在抓到了？ | 批次 0 新增的 macos runner。它的价值不止于 BSD 工具链差异，还在于**它是一台与开发机装机清单不同的机器**——这一条应写进设计文档的理由说明。 |

## 待办（不在本次修复内）

| # | 事项 | 归属 |
|---|---|---|
| 1 | smoke-test §5 的 `Pipeline executed (exit=$?)` 断言过宽，任何退出码都算通过，掩盖了本次的级联症状 | 批次 4 E2E 迁移时收紧为出口语义断言 |
| 2 | meta-lint 的 pipefail 规则需覆盖「命令替换内含管道且无 `\|\|` 兜底的赋值」 | 批次 3 |
| 3 | `init.sh` 探测段的三个分支应收敛为一个共享 helper（如 `probe_version <cmd> <post-filter>`），从形态上消除漂移 | 独立重构，需先有本回归测试兜底 |

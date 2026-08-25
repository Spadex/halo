# 复核：ac-coverage 抽不到函数名时在 pipefail 下硬崩

日期：2026-08-25
状态：已修复，回归测试入库
根因类别：**B. `set -euo pipefail` 退出码/管道语义**

## 这份文档为什么没有配对的上报原文

本缺陷不是外部上报，是**批次 3 meta-lint 上线前的存量噪声复核自己抓到的**。
按 `tests/README.md:57-58` 的处置 SOP，自查发现的缺陷只写 analysis，
证据链放在下面「发现路径」一节，不为凑格式补造一份「上报原文」。

## 发现路径

- 起点：`docs/superpowers/plans/2026-08-25-halo-legacy-noise-inventory.md`，
  基线 `c093b71`。该文档统计了设计文档 `:114-131` 五条 meta-lint 规则在存量代码上的命中面。
- 规则 2 的第三子条（「命令替换含 grep 无 `|| true` 兜底」）列出 8 处命中，
  其中 `ac-coverage.sh:188` 被判为**无害**，理由是「`head` 在管道末段吞掉了 grep 的退出码，
  实际不会致命」。
- 复核该判定时发现两处硬错误（见「原判定错在哪」），实测确认它是**门禁硬崩**，
  不是无害噪声。

**这一处此前从未被登记过。** 它不在设计文档 `:13` 的「已知未修」名单里，
也没有任何测试覆盖到触发形态。

## 原判定错在哪

调研文档的原话是「因为 `head` 在管道末段吞掉了 grep 的退出码，实际不会致命」。两处都错：

1. **`head -1` 不在末段。** 完整管道是
   `grep -oE … | head -1 | sed … | sed … | sed …`，末段是第三个 `sed`。
   调研文档引用原文时把三个 `sed` 缩写成一个，恰好模糊掉了这一点。
2. **在 `pipefail` 下，末段是谁根本无关。** `pipefail` 返回管道中**最右侧非零**的退出码。
   `head`/`sed` 都返回 0，`grep` 未命中返回 1 → 整条管道返回 1。

调研文档在规则 1 里还写着「`:185` 补 `|| true` 之后 `:186` 才可达」——
同一循环体、同一形态的 `:188` 却被判无害。它内部自相矛盾，且倒向了错误的一边。

## 症状

`ac-coverage.sh` 在打印

```
🔍 AC Coverage: spec.md [node]

📋 Spec AC count: 2
```

之后**直接终止**，退出码 1。AC 覆盖矩阵（`:195-198` 的表头及其后所有行）一行都没有，
`--json-out` 指定的 gate JSON **不落盘**。

调用方 `pipeline.sh:397-411` 把非零退出记为 FAIL 并中止整条流水线，
但输出里没有任何解释——没有 uncovered 清单，没有覆盖率，没有 JSON。

## 根因

`ac-coverage.sh:3` source `_lib.sh`，继承 `_lib.sh:12` 的 `set -euo pipefail`。
覆盖循环里有两处同型的命令替换：

| 行 | 作用 | 兜底 |
|---|---|---|
| `:185` | 从 match line 抽 AC 号 | `\|\| true` ✅ |
| `:188` | 从 match line 抽函数名 | 无 ❌（修复前） |

修复前的 `:188`：

```bash
func_name=$(echo "$match_line" | grep -oE 'func [A-Za-z0-9_]+|def [a-z_0-9]+|(describe|it|test)\(' | head -1 | sed 's/^func //' | sed 's/^def //' | sed 's/($//')
```

grep 未命中时：

1. `grep -oE` 以 1 退出；
2. `pipefail` 让整条管道取到 1（`head`/`sed` 全返回 0，不影响）；
3. 命令替换随之非零，这是一条**独立的赋值语句**，不在 `if`/`&&` 等豁免位置；
4. `set -e` 触发，门禁在循环中途静默退出。

与 `#17`（`2026-08-16-init-detection-probe-pipefail`）是同一形态的第三次复发：
**同一段代码里同一语义写出了两种形态，漏掉兜底的那一份恰好没人踩到。**

### 为什么 grep 会未命中

两个正则的口径不同，这才是触发条件的来源：

| 用途 | 正则 | 口径 |
|---|---|---|
| 选行（`:108`，node 分支） | `(describe\|it\|test).*AC[_-]?([0-9]+)` | 行内**任意位置**有 it/test/describe 和 AC 号即可 |
| 抽名（`:188`） | `(describe\|it\|test)\(` | 名字必须**紧跟左括号** |

选行的口径比抽名宽。jest 的参数化与修饰写法全部落在这个缝里：

- `it.each([[1], [2]])("AC-1 …")` —— `it` 与 `(` 之间隔着 `.each`
- `test.concurrent("AC-2 …")`
- `describe.skip("AC-3 …")`

go 与 python 分支不受影响：它们的选行正则本身就要求 `func Test…` / `def test_ac…` 形态，
与抽名正则口径一致。**这是 node 独有的缺口。**

## 本地复现（确定性）

```bash
bash -c '
set -euo pipefail
line="it.each([[1], [2]])(\"AC-1 charges every line item %i\", (n) => {"
fn=$(echo "$line" | grep -oE "func [A-Za-z0-9_]+|def [a-z_0-9]+|(describe|it|test)\(" | head -1 | sed "s/($//")
echo "NOT REACHED"
'
# 修复前：不打印 NOT REACHED，退出码 1
```

门禁层面的复现见回归测试的 fixture `tests/fixtures/ac/node-unextractable-func-token/`。

## 影响面

- **任何用 jest 参数化写法（`it.each` / `test.each`）且在测试标题里写 AC 号的 node 项目，
  AC 覆盖门禁整体不可用。** 这是 jest 的常见写法，不是边角形态。
- gate JSON 不落盘 → `pipeline.sh:396/409` 的 `collect_gate_json` 拿不到文件 →
  eval run 的 `metrics.ac_total` / `ac_covered` / `ac_uncovered` 全部缺失。
- 症状是**假红**（流水线中止）而非假绿，所以不会放行错误的交付。
  但它是**没有解释的假红**：用户看到门禁失败却拿不到任何 uncovered 信息，
  唯一的排查路径是读门禁源码。

## 修复

`:188` 追加 `|| true`，与 `:185` 对齐，并补失败方向注释（`AGENTS.md` Gate Rules 要求）。

方向是 **fail-closed**：抽不到函数名时 `func_name` 为空，`:189` 记成 `"unknown"`，
Tier 2 的 `:226`（`$1==n && $2!="unknown"`）把它排除出候选集，该 AC 判 uncovered。
**抽不到名字的测试不会被算作覆盖**，只会让 AC 更容易判未覆盖——正确的方向。

## 回归测试

`tests/regression/2026-08-25-ac-coverage-func-name-pipefail.bats`，6 条，双向：

| 方向 | 用例 |
|---|---|
| 缺陷方向 | 抽不到函数名时门禁跑完，矩阵表头打出来 |
| 缺陷方向 | gate JSON 落盘且 `.gate == "ac-coverage"` |
| 缺陷方向 | 退出是**有话的判红**（含 `FAIL — uncovered:`），不是崩溃 |
| 反向（不许换成假绿） | 抽不到名字的 AC-1 判 `uncovered`，不是 `covered` |
| 反向（不许打坏正常识别） | 普通写法的 AC-2 仍判 `covered` |
| 反向 | AC-2 仍解析到自己的 token |

**为什么鉴别断言选「矩阵打出来了」而不是退出码**：AC-1 本就未覆盖，
门禁修复前后都是非零退出。只有矩阵和 gate JSON 能区分「崩了」与「判红了」。

**先红后绿**：修复前实测 6/6 红，输出停在 `📋 Spec AC count: 2`、`ac.json` 不存在；
修复后 6/6 绿。

## 机器防线为什么没拦住

| 问题 | 答案 |
|---|---|
| 为什么已有测试没抓到？ | 现有 AC 用例的 fixture 全是 go / python 形态（`tests/fixtures/ac/` 下五份，无一份是 node）。触发条件是「node 选行正则命中但抽名正则不命中」，**从来没有测试制造过这个条件**。 |
| 为什么 meta-lint 没抓到？ | meta-lint 尚未上线（批次 3）。更要紧的是：批次 3 的前置调研**扫到了这一处，然后判它无害**。所以规则 2c 上线不是充分条件——规则的判定标准必须写清「`pipefail` 下取最右侧非零码，管道末段是谁与危险性无关」，否则同一个误判会在 allowlist 登记时重演一次。 |
| 为什么现在抓到了？ | 复核调研文档结论时逐条实跑 `bash -c 'set -euo pipefail; …'`，而不是照着「不会致命」的判断往下走。 |

## 待办（不在本次修复内）

| # | 事项 | 归属 |
|---|---|---|
| 1 | meta-lint 规则 2c 上线，且判定标准须写明「末段是谁不影响 pipefail 的取值」 | 批次 3 |
| 2 | `:108` 选行正则与 `:188` 抽名正则的口径差本身是缺陷来源。根治应让两者共用一个 node 测试标识形态的定义，而不是各写一份 | 独立重构，需先有本回归测试兜底 |
| 3 | `ac-coverage.sh:266` 的 `grep -A 5 … \| grep -qiE` 是同一根因 B 的另一处（SIGPIPE 形态），设计文档 `:160` 已归批次 3 | 批次 3 |

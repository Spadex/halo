# Halo Bug Report — ac-coverage gate 对 python 项目必然 FAIL

- 上报日期：2026-07-12
- 组件：`halo/kernel/delivery/gates/ac-coverage.sh`
- 严重级：High（阻断所有 python 项目的 `pipeline.sh` 完成门禁；无法通过全管道验证）
- kernel_version：1.0.0
- 复现环境：macOS (darwin 25.3.0)，bash，Python 3.12.13，uv 0.11.6

---

## 1. 现象（Symptom）

在一个符合 halo manifest 约定的 python 项目里运行全管道：

```
bash halo/kernel/delivery/pipeline.sh
```

在第 7 步 `ac-coverage` 处 FAIL，且**只打印到 AC 计数就中断**，没有覆盖矩阵：

```
🔄 [7] ac-coverage          → halo/kernel/delivery/gates/ac-coverage.sh <spec> .
🔍 AC Coverage: spec.md [python]

📋 Spec AC count: 3
❌ [7] ac-coverage          FAIL
⛔ Pipeline stopped at step 7: ac-coverage
```

前 6 步（bootstrap / spec-lint / prismspec-lint / build / lint / unit-test）全部 PASS，`uv run pytest` 实际 **6 passed**（含 `def test_ac1` / `def test_ac2` / `def test_ac3`）。即：AC 测试真实存在且通过，门禁却判 0 覆盖并崩溃。

对**任何**遵循 manifest 记录的 python 测试约定（`func_regex: def test_ac([0-9]+)`，小写）的项目，该门禁都必然 FAIL。

---

## 2. 根因（Root Cause）

三处代码共同构成失效链：

| 位置 | 内容 | 问题 |
|---|---|---|
| `halo/kernel/_lib.sh:12` | `set -euo pipefail` | 门禁 `source` 它，全程 errexit + pipefail |
| `halo/kernel/delivery/gates/ac-coverage.sh:101` | `FUNC_REGEX='def test_ac([0-9]+)'` | python **发现**正则：小写、硬编码 |
| `halo/kernel/delivery/gates/ac-coverage.sh:142` | `ac_num=$(echo "$match_line" \| grep -oE 'AC[_-]?([0-9]+)' \| grep -oE '[0-9]+' \| head -1)` | AC 编号**提取**正则：大写、**大小写敏感** |

### 失效链

1. 第 101 行的 FUNC_REGEX 用小写 `def test_ac` 成功发现测试行 `def test_ac1():`。
2. 第 142 行却用**大写、大小写敏感**的 `grep -oE 'AC[_-]?([0-9]+)'` 去提取编号——小写 `ac1` 不匹配大写 `AC`，第一个 grep 返回 exit 1。
3. 在 `set -euo pipefail` 下，该命令替换 pipeline 返回非零 → `ac_num=$(...)` 赋值失败 → **errexit 在到达第 143 行的空值保护 `[[ -z "$ac_num" ]] && continue` 之前就硬退出整个门禁**。
4. 门禁以 exit 1 结束，覆盖矩阵未打印，pipeline 判 FAIL。

### 这是两个缺陷

- **缺陷 A（主因，契约不一致）**：发现正则（小写 `def test_ac`，行 101）与提取正则（大写 `AC`，行 142）大小写约定冲突。即便没有 set -e，python 每条 AC 也会被判 "Uncovered"。
- **缺陷 B（放大器，容错缺失）**：行 143 `[[ -z "$ac_num" ]] && continue` 表明作者**本意**是要优雅跳过提取失败的行；但在 `set -euo pipefail` 下，行 142 的 pipeline 一旦非零就先硬崩，保护逻辑不可达。任何提取落空都会让整个门禁崩溃而非跳过。

---

## 3. 最小复现（Minimal Reproduction）

无需完整项目，直接在 bash 里验证两个缺陷：

```bash
# 缺陷 A：小写测试名被大写、大小写敏感正则提取落空
echo "def test_ac1():" | grep -oE 'def test_ac([0-9]+)'      # → def test_ac1（发现命中）
echo "def test_ac1():" | grep -oE 'AC[_-]?([0-9]+)'; echo $?  # → 无输出，exit 1（提取落空）

# 缺陷 B：pipefail + errexit 下，赋值失败即硬退出
set -euo pipefail
ac_num=$(echo "def test_ac1():" | grep -oE 'AC[_-]?([0-9]+)' | grep -oE '[0-9]+' | head -1)
echo "这一行不会被执行"   # 上一行已使脚本退出
```

对照：加 `-i`（大小写不敏感）即可提取成功：

```bash
echo "def test_ac1():" | grep -ioE 'AC[_-]?([0-9]+)'   # → ac1
```

---

## 4. 建议修复（Proposed Fix）

对 `halo/kernel/delivery/gates/ac-coverage.sh:142`，同时修两个缺陷：

```bash
# 修复前
ac_num=$(echo "$match_line" | grep -oE 'AC[_-]?([0-9]+)' | grep -oE '[0-9]+' | head -1)

# 修复后：-i 解决大小写契约不一致（缺陷 A）；|| true 让提取落空时优雅跳过而非硬崩（缺陷 B）
ac_num=$(echo "$match_line" | grep -ioE 'AC[_-]?([0-9]+)' | grep -oE '[0-9]+' | head -1 || true)
```

补充建议：
- 建议对全文件审计所有 `$(... grep ...)` 命令替换在 `set -euo pipefail` 下的容错（凡"未命中即正常"的 grep 都应 `|| true`）。
- 建议为 python 增加一条覆盖用例的门禁自测，避免回归（发现正则与提取正则应共享同一大小写约定，或统一走 FUNC_REGEX 的捕获组提取编号，而不是二次 grep）。
- 可考虑让提取直接复用 FUNC_REGEX 的捕获组（`([0-9]+)`），从源头消除两套正则不一致的风险。

---

## 5. 影响面（Impact）

- 语言 `python`：**必然 FAIL**（本报告主体）。
- 语言 `node/js/ts`：行 98 FUNC_REGEX `(describe|it|test).*AC[_-]?([0-9]+)` 用大写 `AC`，与行 142 一致，**不受缺陷 A 影响**；但缺陷 B（提取落空即硬崩）在边界输入下仍是潜在风险。
- 语言 `go`：行 95/105 FUNC_REGEX `func Test(AC|_AC)([0-9]+)` 大写，与行 142 一致，同上。

即缺陷 A 是 **python 专属**；缺陷 B 是**跨语言的容错隐患**。

---

## 6. 交接证据文件清单（Evidence Files）

| 文件 | 作用 |
|---|---|
| `halo/kernel/delivery/gates/ac-coverage.sh` | 缺陷源文件（行 101 发现正则、行 142 提取正则、行 143 不可达的空值保护） |
| `halo/kernel/_lib.sh`（行 12 `set -euo pipefail`） | errexit/pipefail 来源，放大缺陷 B |
| `halo/state/eval-runs/20260712T143807Z-20707.json` | 全管道 eval 结果：`pipeline.status=fail`、`steps_failed=1`、`ac_total=0/ac_covered=0`（门禁崩溃导致计数归零） |
| `halo/state/loops/20260712T143807Z-20707.json` | 本次运行的 loop 状态快照 |
| `halo/specs/workspace-scaffold/verify.md`（§4、§5） | 复现该项目的验证证据与豁免记录、前因后果 |
| `halo/specs/workspace-scaffold/spec.md`（§9、§13） | AC 形式化说明与验证计划降级记录，解释为何 AC 只有 3 条 test-backed |

> 注：`halo/specs/workspace-scaffold/spec.md`、`plan.md`、`verify.md` 是本次触发缺陷的真实项目上下文；`.halo/sdd/workspace-scaffold/T1..T4/` 下有各任务的实现与评审证据（该目录被 `.gitignore` 忽略，如需一并交接需手动打包）。

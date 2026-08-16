# Bug 报告名录

本目录存放外部上报原文与 halo 侧的独立复核。处置流程见 `tests/README.md`。

这份名录解决三件事：

1. **历史资产的命名映射**——早期报告的文件名不符合现行 SOP 的 `YYYY-MM-DD-<slug>.md`，
   重命名会打断 CHANGELOG 与历史提交里的引用，所以保留原名，在这里登记映射；
2. **报告 ↔ 回归测试的对应关系**——批次 3 的「报告↔测试对应检查」按本表对拍；
3. **缺 analysis 的原因**——写清楚，而不是事后补一份假的复核。

## 三条既定决定

- **不重命名历史报告。** SOP 的命名约定对**新报告**生效。
- **不补写 analysis。** `tests/README.md` 对 analysis 的定义是「**当时**不采信报告结论、
  自行验证根因的独立复核」。事后补写一份当时并不存在的「复核」是伪造过程证据，比缺失更坏。
  缺 analysis 的四份报告全部早于 SOP 成文（2026-08-07）。
- **`tests/regression/*.bats` 的命名规则**：
  - 报告已合规 → bats 文件名与报告 basename **逐字相同**，机器可直接对拍；
  - 历史遗留报告 → 日期取**修复提交的作者日期**（可考据、唯一、与文件头 `Fixed by` 自洽），
    slug 取语义 slug，映射登记在本表。

## 批次 3 的对拍规则

> `docs/bug_report/` 下存在 `<base>-analysis.md` 的报告 ⇒ 必须存在
> `tests/regression/<base>.bats`，**除非**该 `<base>` 在本表中登记了映射或豁免（附原因）。

本表同时兜住一个坑：`spec-lint-ac-gap-analysis.md` 以 `-analysis` 结尾却**没有配对原文**，
朴素的「去掉 `-analysis` 后缀找原文」逻辑会去找不存在的 `spec-lint-ac-gap.md`。

## 名录

| 报告 | 上报编号 | 修复提交 | 修复日期 | 根因类别 | 回归测试 | analysis |
|------|---------|---------|---------|---------|---------|---------|
| `halo-ac-coverage-bug-report.md` | #5 | `de6c249` | 2026-07-12 | B + F | `2026-07-12-ac-coverage-python-lowercase.bats` | ❌ 早于 SOP |
| `spec-lint-ac-cross-reference-duplicate.md` | #7 | `45d5f7f` | 2026-07-19 | A | `2026-07-19-spec-lint-ac-cross-reference-duplicate.bats` | ❌ 早于 SOP |
| `ac-coverage-bug/`（目录） | #8 | `f60637d` | 2026-07-25 | A + F | `2026-07-25-ac-coverage-cross-spec-attribution.bats` | ❌ 早于 SOP |
| `spec-lint-ac-gap-analysis.md` | #9 | `334bdb6` | 2026-07-26 | A | `2026-07-26-spec-lint-ac-number-gap.bats` | ⚠️ 命名例外：本身即复核，无配对原文 |
| `2026-07-31-sdd-gate-defects.md` | #10 | `04300a7` | 2026-07-31 | G + C | 批次 3 待迁 | ✅ |
| `2026-08-02-tdd-cycle-evidence-sigpipe.md` | #11 | `c75d0c4` | 2026-08-02 | B + D | 批次 3 待迁 | ✅ |
| `2026-08-03-halo-gate-findings.md` | 多条（含 #12/#13） | 多个，见 analysis | 2026-08-03 | 多类 | 批次 2/3 待迁 | ✅ |
| `2026-08-03-halo-gate-findings_2.md` | 多条（含 #15） | 多个，见 analysis | 2026-08-03 | C + D | 批次 2/3 待迁 | ✅ |
| `2026-08-03-fastapi-collection-root-route-dropped.md` | #16 | `55db4cb` | 2026-08-03 | F | 批次 2 待迁 | ✅ |
| `2026-08-03-user-report.md` | #14 | `1f993a4` | 2026-08-03 | A | `2026-08-03-user-report.bats` | ✅ |
| `2026-08-07-runningtime-report/`（目录） | — | `3e25d7e` | 2026-08-07 | A + H | `2026-08-07-runningtime-report.bats` | ✅ |
| `2026-08-16-init-detection-probe-pipefail-analysis.md` | — | `1a9773e` | 2026-08-16 | B | `2026-08-16-init-detection-probe-pipefail.bats` | ⚠️ 自查发现，无上报原文 |

根因类别的含义见 `tests/README.md` 的根因类别表。

### 关于「无上报原文」的两类情况

| 情况 | 例子 | 该有什么 |
|------|------|---------|
| 自查/CI 发现 | `2026-08-16-init-detection-probe-pipefail` | 只有 analysis，正文里必须写清**发现路径**（哪次 CI、哪个 run） |
| 上报方直接给复核 | `spec-lint-ac-gap-analysis.md` | 保留原样，在本表标注命名例外 |

两类都**不许**为了凑格式补造一份「上报原文」。

## 一个观察：纯 AC 类报告是复发最多的那一类

设计文档 `docs/superpowers/specs/2026-08-07-halo-test-system-design.md` 统计的根因里，
A 类「词法上把提及当成声明」复发 5 次（#7 → #8 → #9 → #14 → runningtime）。
这五份里有三份缺 analysis——它们恰好是 SOP 成文之前的那批。
处置纪律成文之后，同类根因没有再复发过。

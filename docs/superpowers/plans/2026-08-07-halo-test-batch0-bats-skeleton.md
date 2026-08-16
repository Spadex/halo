# Halo 测试体系批次 0：bats 骨架实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 搭建 bats-core 测试基础设施（vendor、runner、helpers、CI 双平台、维护者手册），此后新测试只写 bats，smoke-test.sh 冻结（只删不加）。

**Architecture:** bats-core 以 git submodule 引入并锁定版本；`tests/run.sh` 是唯一入口，按套件目录（unit/meta/regression/e2e）发现并运行 bats 用例，双轨期串行追加存量 smoke-test；`helpers/common.bash` 提供「每文件装一次 harness 模板、每用例克隆副本」的沙箱机制；`helpers/fixtures.bash` 提供参数化 spec/plan 构造函数替代内嵌 heredoc。

**Tech Stack:** bash、bats-core v1.12.0、bats-support v0.3.0、bats-assert v2.1.0、yq（mikefarah v4）、GitHub Actions（ubuntu + macos matrix）。

**设计依据:** `docs/superpowers/specs/2026-08-07-halo-test-system-design.md`

## Global Constraints

- 除 vendored bats 外不引入任何新依赖；测试运行环境要求与现状一致（bash、yq、git）。
- 所有新增 `.sh` / `.bash` 文件必须通过 `bash -n` 和 `shellcheck --severity=warning`（`.bats` 文件不进 shellcheck，bats 语法非纯 bash）。
- 所有脚本必须兼容 macOS（BSD 工具链）与 Linux：不用 `sed -i` 无后缀形式、不用 GNU 专属 flag。
- 新脚本自身不得出现设计文档「根因 B/D」反模式：不用 `cmd | grep -q` 作管道读端末端判定、不消费无 `sort` 的 `find` 输出做决策、命令替换包 grep 时必须 `|| true` 兜底。
- `tests/README.md` 用简体中文书写（本仓中文优先）；`AGENTS.md` 保持英文。
- smoke-test.sh 本计划内不做任何修改。
- 提交信息结尾带 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`。

---

### Task 1: vendor bats submodule + `tests/run.sh` + sanity 用例

**Files:**
- Create: `tests/vendor/bats-core`（submodule，锁 v1.12.0）
- Create: `tests/vendor/bats-support`（submodule，锁 v0.3.0）
- Create: `tests/vendor/bats-assert`（submodule，锁 v2.1.0）
- Create: `tests/run.sh`
- Create: `tests/unit/sanity.bats`

**Interfaces:**
- Produces: `bash tests/run.sh [unit|regression|e2e|meta|legacy|all]`，默认 `all`；任一套件失败则非零退出。空套件目录跳过并明说。后续所有任务和 CI 都以此为入口。
- Produces: `tests/vendor/bats-core/bin/bats` 可执行路径（helpers 与 CI 依赖）。

- [x] **Step 1: 添加三个 submodule 并锁定版本**

```bash
cd /Users/huxiao/Project/spadex/halo
git submodule add https://github.com/bats-core/bats-core.git tests/vendor/bats-core
git -C tests/vendor/bats-core checkout v1.12.0
git submodule add https://github.com/bats-core/bats-support.git tests/vendor/bats-support
git -C tests/vendor/bats-support checkout v0.3.0
git submodule add https://github.com/bats-core/bats-assert.git tests/vendor/bats-assert
git -C tests/vendor/bats-assert checkout v2.1.0
```

验证：`tests/vendor/bats-core/bin/bats --version` 输出 `Bats 1.12.0`。

- [x] **Step 2: 写 sanity 用例（先写测试）**

创建 `tests/unit/sanity.bats`：

```bash
#!/usr/bin/env bats
# Sanity: bats 骨架、断言库、必备工具就位。

setup() {
  load "../vendor/bats-support/load"
  load "../vendor/bats-assert/load"
}

@test "bats runs and assertions work" {
  run echo "halo"
  assert_success
  assert_output "halo"
}

@test "required tools are available" {
  command -v yq
  command -v git
}
```

- [x] **Step 3: 直接用 bats 跑 sanity，确认基础设施可用**

Run: `tests/vendor/bats-core/bin/bats tests/unit/sanity.bats`
Expected: `2 tests, 0 failures`

- [x] **Step 4: 写 `tests/run.sh`**

```bash
#!/usr/bin/env bash
# tests/run.sh — Halo 测试统一入口。
# Usage: bash tests/run.sh [unit|regression|e2e|meta|legacy|all]
# 套件目录为空时跳过并提示；任一套件失败则最终非零退出（不吞退出码）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BATS_BIN="$SCRIPT_DIR/vendor/bats-core/bin/bats"
SUITE="${1:-all}"
FAILED=0

if [[ ! -x "$BATS_BIN" ]]; then
  echo "bats not found at tests/vendor/bats-core." >&2
  echo "Run: git submodule update --init" >&2
  exit 1
fi

run_bats_suite() {
  local name="$1"
  local dir="$SCRIPT_DIR/$name"
  local count=0
  if [[ -d "$dir" ]]; then
    # find 输出仅用于计数，不依赖顺序（fail direction: find 报错时 pipefail 会中止
    # 整个 runner → 非零退出 → CI 红，属 fail-closed；count=0 的 skip 分支只在
    # 目录确实为空/不存在时走到，不会把失败伪装成跳过）
    count=$(find "$dir" -name '*.bats' -type f | wc -l | tr -d ' ')
  fi
  if [[ "$count" -eq 0 ]]; then
    echo "── suite ${name}: no cases yet, skipped ──"
    return 0
  fi
  echo "── suite ${name} (${count} files) ──"
  if ! "$BATS_BIN" --recursive "$dir"; then
    FAILED=1
  fi
}

run_legacy() {
  echo "── legacy: smoke-test.sh ──"
  if ! bash "$SCRIPT_DIR/smoke-test.sh"; then
    FAILED=1
  fi
  echo "── legacy: ac-coverage-test.sh ──"
  if ! bash "$SCRIPT_DIR/ac-coverage-test.sh"; then
    FAILED=1
  fi
}

case "$SUITE" in
  unit | regression | e2e | meta)
    run_bats_suite "$SUITE"
    ;;
  legacy)
    run_legacy
    ;;
  all)
    run_bats_suite unit
    run_bats_suite meta
    run_bats_suite regression
    run_bats_suite e2e
    run_legacy
    ;;
  *)
    echo "Unknown suite: $SUITE (expected unit|regression|e2e|meta|legacy|all)" >&2
    exit 2
    ;;
esac

exit "$FAILED"
```

- [x] **Step 5: 验证 run.sh 各路径**

Run: `bash tests/run.sh unit`
Expected: sanity 2 tests 通过，退出码 0。

Run: `bash tests/run.sh meta`
Expected: 输出 `suite meta: no cases yet, skipped`，退出码 0。

Run: `bash tests/run.sh nonsense; echo "exit=$?"`
Expected: `exit=2`。

Run: `bash tests/run.sh`（全量，含 legacy 双轨）
Expected: sanity 通过 + smoke-test、ac-coverage-test 照常全绿，最终退出码 0。

- [x] **Step 6: 静态检查**

Run: `bash -n tests/run.sh && shellcheck --severity=warning tests/run.sh`
Expected: 无输出，退出码 0。

- [x] **Step 7: Commit**

```bash
git add .gitmodules tests/vendor tests/run.sh tests/unit/sanity.bats
git commit -m "Add bats skeleton: vendored submodules, unified runner, sanity case"
```

---

### Task 2: `tests/helpers/common.bash` 沙箱机制 + 验证用例

**Files:**
- Create: `tests/helpers/common.bash`
- Create: `tests/unit/harness-setup.bats`

**Interfaces:**
- Consumes: Task 1 的 vendor 路径 `tests/vendor/bats-{support,assert}/load.bash`。
- Produces（后续所有 bats 用例依赖的约定）:
  - `load ../helpers/common` 后可用：`halo_require_tools`、`halo_template_install`、`halo_sandbox_clone`。
  - `halo_template_install`：在 `$BATS_FILE_TMPDIR/template` 建 Go 项目并完成 install + init，导出 `HALO_TEMPLATE_DIR`。在 `setup_file()` 中调用（每文件一次）。
  - `halo_sandbox_clone`：把模板复制为 `$BATS_TEST_TMPDIR/project`，导出 `SANDBOX` 并 `cd` 进去。在 `setup()` 中调用（每用例一次）。
  - 沙箱内关键路径：门禁 `$SANDBOX/halo/kernel/delivery/gates/*.sh`、SDD 脚本 `$SANDBOX/halo/kernel/orchestrator/sdd/*.sh`、PrismSpec `$SANDBOX/prismspec/bin/*.sh`、specs 根 `$SANDBOX/halo/specs/`。
  - `REPO_DIR` 环境变量指向本仓根。

- [x] **Step 1: 写验证用例（先写测试）**

创建 `tests/unit/harness-setup.bats`：

```bash
#!/usr/bin/env bats
# 验证 helpers/common.bash 的沙箱契约：
# 模板每文件装一次，用例各拿隔离副本，副本内核可直接调用。

load "../helpers/common"

setup_file() {
  halo_require_tools
  halo_template_install
}

setup() {
  halo_sandbox_clone
}

@test "template install produces manifest and kernel" {
  [ -f "$SANDBOX/halo/manifest.yaml" ]
  [ -d "$SANDBOX/halo/kernel/delivery/gates" ]
  [ -f "$SANDBOX/prismspec/bin/lint.sh" ]
}

@test "sandbox clone is isolated from template" {
  touch "$SANDBOX/pollution-marker"
  [ ! -e "$HALO_TEMPLATE_DIR/pollution-marker" ]
}

@test "sandbox cwd is the project root" {
  [ "$(pwd)" = "$SANDBOX" ]
  [ -f halo/manifest.yaml ]
}
```

- [x] **Step 2: 运行确认失败**

Run: `bash tests/run.sh unit`
Expected: FAIL（`helpers/common.bash` 尚不存在，bats 在 load 阶段报错；具体报错文案不限，退出码非零即可）。

- [x] **Step 3: 写 `tests/helpers/common.bash`**

```bash
#!/usr/bin/env bash
# tests/helpers/common.bash — Halo bats 套件共享 setup。
#
# 用法（.bats 文件内）：
#   load "../helpers/common"
#   setup_file() { halo_require_tools; halo_template_install; }
#   setup()      { halo_sandbox_clone; }
#
# BATS_FILE_TMPDIR / BATS_TEST_TMPDIR 由 bats 创建和清理，无需 teardown。

HELPERS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HELPERS_DIR/../.." && pwd)"
export REPO_DIR

# shellcheck source=/dev/null
source "$HELPERS_DIR/../vendor/bats-support/load.bash"
# shellcheck source=/dev/null
source "$HELPERS_DIR/../vendor/bats-assert/load.bash"

# 缺工具时跳过整个文件（与 smoke-test 的 skip 语义一致：环境缺失≠失败）。
halo_require_tools() {
  local tool
  for tool in yq git; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      skip "requires $tool"
    fi
  done
}

# 每个测试文件安装一次 harness 模板（install + init 较慢，~秒级）。
# 产出：$HALO_TEMPLATE_DIR —— 已完成 install.sh + init.sh 的 Go 项目。
halo_template_install() {
  export HALO_TEMPLATE_DIR="$BATS_FILE_TMPDIR/template"
  mkdir -p "$HALO_TEMPLATE_DIR"
  git -C "$HALO_TEMPLATE_DIR" init --quiet
  cat > "$HALO_TEMPLATE_DIR/go.mod" << 'EOF'
module github.com/example/testapp

go 1.22

require github.com/gin-gonic/gin v1.9.1
require gorm.io/gorm v1.25.0
EOF
  bash "$REPO_DIR/install.sh" "$HALO_TEMPLATE_DIR" > /dev/null
  (
    cd "$HALO_TEMPLATE_DIR" || exit
    bash .halo/framework/init.sh --non-interactive --lang=go --name=testapp --ci=github > /dev/null
  )
}

# 每条用例克隆一个隔离副本并 cd 进去（门禁脚本按 cwd 定位 halo/specs）。
# 产出：$SANDBOX。
halo_sandbox_clone() {
  export SANDBOX="$BATS_TEST_TMPDIR/project"
  cp -R "$HALO_TEMPLATE_DIR" "$SANDBOX"
  cd "$SANDBOX" || return 1
}
```

- [x] **Step 4: 运行确认通过**

Run: `bash tests/run.sh unit`
Expected: sanity 2 条 + harness-setup 3 条，共 5 tests, 0 failures。

- [x] **Step 5: 静态检查**

Run: `bash -n tests/helpers/common.bash && shellcheck --severity=warning tests/helpers/common.bash`
Expected: 无输出，退出码 0。

- [x] **Step 6: Commit**

```bash
git add tests/helpers/common.bash tests/unit/harness-setup.bats
git commit -m "Add bats sandbox helpers: per-file template install, per-test clone"
```

---

### Task 3: `tests/helpers/fixtures.bash` spec/plan 构造函数 + lint 验证用例

**Files:**
- Create: `tests/helpers/fixtures.bash`
- Create: `tests/unit/fixtures.bats`

**Interfaces:**
- Consumes: Task 2 的 `halo_template_install` / `halo_sandbox_clone`（用例在沙箱内跑真实门禁验证 fixture）。
- Produces（批次 1+ 迁移的基础工具）:
  - `make_spec <specs_root> <id> [ac_count] [ac_start] [mode]` — 写出 `<specs_root>/<id>/spec.md`，现代目录布局，默认 2 个 AC、从 AC-1 起、tdd 模式。生成的 spec 必须通过 `spec-lint.sh` 与 `prismspec/bin/lint.sh … spec`。
  - `make_plan <specs_root> <id> [ac_count] [ac_start]` — 写出 `<specs_root>/<id>/plan.md`，每个 AC 一组 RED-n + T-n 任务。与同参数 `make_spec` 配套时必须通过 `plan-lint.sh` 与 `prismspec/bin/lint.sh … plan`。
  - 语法变体（交叉引用、真断号等）不做进构造函数：由用例对产物做 `sed` 改写（沿用 smoke-test 现行做法），静态变体后续放 `tests/fixtures/`。

- [x] **Step 1: 写验证用例（先写测试）**

创建 `tests/unit/fixtures.bats`：

```bash
#!/usr/bin/env bats
# 验证 fixture 构造函数产物能通过真实门禁：
# 构造函数是后续所有迁移用例的地基，它自身跑偏会让整个语料库失真。

load "../helpers/common"
load "../helpers/fixtures"

setup_file() {
  halo_require_tools
  halo_template_install
}

setup() {
  halo_sandbox_clone
}

@test "make_spec default passes spec-lint and prismspec lint" {
  make_spec halo/specs fixture-default
  run bash halo/kernel/delivery/gates/spec-lint.sh halo/specs/fixture-default/spec.md
  assert_success
  run bash prismspec/bin/lint.sh halo/specs/fixture-default/spec.md spec
  assert_success
}

@test "make_spec with non-1 start passes without false AC gap" {
  make_spec halo/specs fixture-global 2 12
  run bash halo/kernel/delivery/gates/spec-lint.sh halo/specs/fixture-global/spec.md
  assert_success
  refute_output --partial "AC number gaps"
}

@test "make_plan matching make_spec passes plan-lint and prismspec lint" {
  make_spec halo/specs fixture-plan
  make_plan halo/specs fixture-plan
  run bash halo/kernel/orchestrator/sdd/plan-lint.sh fixture-plan
  assert_success
  run bash prismspec/bin/lint.sh halo/specs/fixture-plan plan
  assert_success
}

@test "make_spec honours ac_count" {
  make_spec halo/specs fixture-many 4
  run grep -c '^| AC-' halo/specs/fixture-many/spec.md
  assert_output "4"
}
```

- [x] **Step 2: 运行确认失败**

Run: `bash tests/run.sh unit`
Expected: fixtures.bats 全部 FAIL（`helpers/fixtures.bash` 尚不存在，load 阶段报错）；其余文件仍绿。

- [x] **Step 3: 写 `tests/helpers/fixtures.bash`**

内容以 smoke-test 现行 modern-feature spec/plan fixture 为蓝本（它们已被全部门禁接受）：

```bash
#!/usr/bin/env bash
# tests/helpers/fixtures.bash — 参数化 spec/plan 构造函数。
# 蓝本：smoke-test.sh 的 modern-feature fixture（已被 spec-lint、
# prismspec lint、plan-lint、task-next 全链路接受的最小形态）。
#
# 语法变体（交叉引用、断号、列序等）不进构造函数：
# 用例拿产物做 sed 改写，保持构造函数只有一种"黄金形态"。

# make_spec <specs_root> <id> [ac_count=2] [ac_start=1] [mode=tdd]
make_spec() {
  local root="$1" id="$2" ac_count="${3:-2}" ac_start="${4:-1}" mode="${5:-tdd}"
  local dir="$root/$id"
  mkdir -p "$dir"

  local ac_rows="" i ac
  for ((i = 0; i < ac_count; i++)); do
    ac=$((ac_start + i))
    ac_rows+="| AC-${ac} | Step ${ac} | Result ${ac} | TestAC${ac} |"$'\n'
  done

  cat > "$dir/spec.md" << EOF
---
id: ${id}
status: drafted
execution_mode: ${mode}
mode_source: model-selected
approval: inferred
owner: bats
created_at: 2026-01-01T00:00:00Z
updated_at: 2026-01-01T00:00:00Z
---

# Spec: ${id}

## Intent

Add a small behavior with AC tracing.

## Scope

### In

- Create behavior.

### Out

- Export behavior.

## Context Basis

| Source | Constraint | Why it matters |
|--------|------------|----------------|
| user | Bats fixture for gate contracts. | Use a minimal fixture. |
| code / tests | No production code is required for this fixture. | Keep scope small and AC ids stable. |
| open questions / conflicts | None. | No blocking decision required. |

## Architecture

Use the existing handler boundary. No new subsystem is required for this fixture.

## Interface

| Interface | Contract |
|-----------|----------|
| Handler | Behaviors must be observable through AC-named tests. |

## Invariants

| Invariant | Verification |
|-----------|--------------|
| AC ids remain stable and traceable. | spec-lint and ac-coverage fixtures |

## Acceptance Criteria

| # | When | Then | Verification |
|---|------|------|--------------|
${ac_rows}
## Design Decisions

| # | Decision | Rationale | Reversible? |
|---|----------|-----------|-------------|
| D-1 | Use existing handler | Minimal change | yes |

## Risk Notes

| Risk | Mitigation | Verification |
|------|------------|--------------|
| None | N/A | Tests |

## Execution Policy

- Mode: \`${mode}\`
- Reason: bats fixture validates the modern template.

## Verification Plan

| Gate / Test | Required? | Notes |
|-------------|-----------|-------|
| spec-lint | yes | |
| unit-test | yes | |
EOF
}

# make_plan <specs_root> <id> [ac_count=2] [ac_start=1]
# 每个 AC 生成一组 RED-n（红测试任务）+ T-n（实现任务），n 从 1 计数。
make_plan() {
  local root="$1" id="$2" ac_count="${3:-2}" ac_start="${4:-1}"
  local dir="$root/$id"
  mkdir -p "$dir"

  local red_tasks="" impl_tasks="" i ac n
  for ((i = 0; i < ac_count; i++)); do
    ac=$((ac_start + i))
    n=$((i + 1))
    red_tasks+="- [ ] RED-${n}: Add failing test for AC-${ac}
  - Ref: AC-${ac}
  - Expected failure: handler does not implement AC-${ac} yet
  - Test file: \`internal/handler/item_test.go\`
  - Verification: \`go test ./internal/handler -run TestAC${ac}\`
  - Done when:
    - [ ] Expected failure is captured in \`.halo/sdd/${id}/T${n}/tdd-evidence.json\`

"
    impl_tasks+="- [ ] T${n}: Implement behavior for AC-${ac}
  - Ref: AC-${ac}
  - Mode: tdd
  - Scope: Implement the smallest path needed for AC-${ac}.
  - Interfaces:
    - Inputs: request
    - Outputs: response
    - Touched files/contracts: handler
  - Files: \`internal/handler/item.go\`
  - Verification: \`TestAC${ac}\`
  - Evidence:
    - Brief: \`.halo/sdd/${id}/T${n}/brief.md\`
    - Review package: \`.halo/sdd/${id}/T${n}/review-package.md\`
  - Done when:
    - [ ] AC-${ac} passes focused verification and evidence exists.

"
  done

  cat > "$dir/plan.md" << EOF
# Plan: ${id}

## Source

- Spec: \`halo/specs/${id}/spec.md\`
- Execution mode: tdd

## Implementation Notes

## Global Constraints

- Versions / dependencies: use existing Go module.
- Naming / style: keep AC test names.
- Security / permissions: no permission change.
- Data / migration: no migration.
- Compatibility: no API break.
- Out-of-scope: export behavior.

## Tasks

${red_tasks}${impl_tasks}
EOF
}
```

- [x] **Step 4: 运行确认通过**

Run: `bash tests/run.sh unit`
Expected: sanity 2 + harness-setup 3 + fixtures 4，共 9 tests, 0 failures。

若 lint 用例失败：diff 产物与 smoke-test 内嵌 fixture（`tests/smoke-test.sh:455-537` 与 `:692-760`），逐段对齐，不改门禁。

- [x] **Step 5: 静态检查**

Run: `bash -n tests/helpers/fixtures.bash && shellcheck --severity=warning tests/helpers/fixtures.bash`
Expected: 无输出，退出码 0。

- [x] **Step 6: Commit**

```bash
git add tests/helpers/fixtures.bash tests/unit/fixtures.bats
git commit -m "Add parameterized spec/plan fixture constructors validated by real gates"
```

---

### Task 4: CI test workflow（ubuntu + macos matrix）

**Files:**
- Create: `.github/workflows/test.yml`

**Interfaces:**
- Consumes: Task 1 的 `bash tests/run.sh`（含 submodule 依赖）。
- Produces: push/PR 双平台测试门禁；macos runner 承担 BSD 工具链回归拦截（设计依据：#12 的 BSD awk 缺陷现仅靠代码注释防回退）。

- [x] **Step 1: 写 workflow**

创建 `.github/workflows/test.yml`：

```yaml
name: test

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: true

      - name: Install yq (Linux)
        if: runner.os == 'Linux'
        run: |
          sudo wget -qO /usr/local/bin/yq \
            https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_amd64
          sudo chmod +x /usr/local/bin/yq

      - name: Install yq (macOS)
        if: runner.os == 'macOS'
        run: brew install yq

      - name: Run test suite
        run: bash tests/run.sh
```

- [x] **Step 2: 本地校验 YAML 与入口**

Run: `yq -e '.jobs.test.strategy.matrix.os | length == 2' .github/workflows/test.yml`
Expected: `true`。

Run: `bash tests/run.sh`（等价于 CI 将执行的命令）
Expected: 全绿退出码 0。

- [ ] **Step 3: Commit 并推送验证**（部分完成：commit 已做（`2251d4b`），push 未做）

```bash
git add .github/workflows/test.yml
git commit -m "Add CI test workflow on ubuntu and macos"
git push
```

推送后用 `gh run watch` 确认两个平台的 job 都绿。macos job 若因 brew/yq 安装抖动失败，重跑一次再判定；持续失败则回到 workflow 修依赖安装，不得跳过 macos。

**当前状态：workflow 文件已提交，但批次 0 的 8 个提交尚未推送到 `origin/main`，`test` workflow 从未在 GitHub Actions 上运行过。Linux 侧完全未验证，macOS 侧只有本地 `bash tests/run.sh` 的证据。这是批次 0 唯一未闭合的一步。**

---

### Task 5: `tests/README.md` 维护者手册 + `AGENTS.md` 修订

**Files:**
- Create: `tests/README.md`
- Modify: `AGENTS.md`（`## Verification` 段，约 110-128 行）

**Interfaces:**
- Consumes: Task 1-4 全部产出（手册描述的就是它们）。
- Produces: bug 处置 SOP 的规范入口；AGENTS.md 引导所有进仓 Agent 到手册与 `tests/run.sh`。

- [x] **Step 1: 写 `tests/README.md`**

```markdown
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
| `regression/` | 回归语料库：一份 bug 报告 = 一个 `.bats` 文件 （批次 1 起）|
| `e2e/` | 端到端：init → spec → plan → 门禁 → 证据 黄金路径 （批次 4 起）|
| `meta/` | 原则守护 lint：把 AGENTS.md Gate Rules 变成机器断言 （批次 3 起）|
| `helpers/` | `common.bash`（沙箱）、`fixtures.bash`（spec/plan 构造函数） |
| `fixtures/` | 静态语法变体 fixture，按框架分目录 （随迁移批次填充）|
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
```

- [x] **Step 2: 修订 `AGENTS.md` Verification 段**

把现有 Verification 代码块中的 `bash tests/smoke-test.sh` 替换为 `bash tests/run.sh`，并在代码块前加一句 submodule 初始化提示。修改后该段为：

````markdown
## Verification

Run these before reporting completion (first time: `git submodule update --init`):

```bash
bash -n init.sh install.sh tests/run.sh tests/smoke-test.sh tests/helpers/*.bash $(find harness-template prismspec/bin -name '*.sh')
shellcheck --severity=warning init.sh install.sh tests/run.sh tests/smoke-test.sh tests/helpers/*.bash $(find harness-template prismspec/bin -name '*.sh')
bash tests/run.sh
bash examples/go-gin-gorm/try-it.sh
bash examples/py-fastapi/try-it.sh
git diff --check
```
````

并在 `## Design Rules` 列表末尾追加两行：

```markdown
- Bug handling follows `tests/README.md`: report under `docs/bug_report/`, regression case under `tests/regression/`, red-then-green, shipped in the same commit as the fix.
- `tests/smoke-test.sh` is frozen: new tests are written as bats cases under `tests/`; smoke-test only shrinks as batches migrate.
```

- [x] **Step 3: 验证**

Run: `bash tests/run.sh && git diff --check`
Expected: 全绿。

Run: `rg -n "smoke-test" AGENTS.md`
Expected: 仅剩 bash -n / shellcheck 行（双轨期 smoke-test.sh 仍需语法检查）与冻结说明，Verification 的执行入口已是 `tests/run.sh`。

- [x] **Step 4: Commit**

```bash
git add tests/README.md AGENTS.md
git commit -m "Add test maintainer handbook; route verification through tests/run.sh"
```

---

## 批次 0 完成定义

| 条件 | 状态 | 证据 |
|------|------|------|
| `bash tests/run.sh` 本地全绿（9 条 bats 用例 + legacy 双轨） | ✅ | macOS 实测：unit 9/9、smoke-test 167/167、ac-coverage 6/6，退出码 0 |
| CI `test` workflow 在 ubuntu 与 macos 双平台绿 | ❌ | 8 个提交未推送，workflow 从未在 GitHub Actions 上运行 |
| `tests/README.md` 存在且 AGENTS.md 指向它 | ✅ | `tests/README.md`（80 行）；`AGENTS.md:61` Design Rules + `:112-123` Verification |
| smoke-test.sh 零改动（冻结从下一个提交起生效） | ✅ | `git log 4a543e1..HEAD -- tests/smoke-test.sh` 为空 |

**批次 0 未闭合**：唯一缺口是 CI 双平台验证（Task 4 Step 3 的 push 部分）。推送后确认两平台 job 绿，批次 0 即可关闭。

## 实施过程中的偏离记录

| 提交 | 与本计划的差异 | 原因 |
|------|----------------|------|
| `1e5fbc8` | `tests/run.sh` 中 `run_bats_suite` 的 fail-direction 注释重写；`tests/README.md` 目录表为 `regression/` `e2e/` `meta/` `fixtures/` 补批次标注 | 代码评审 minor：原注释把 fail 方向说反了（实际是 fail-closed），且手册未说明空目录属预期状态。本计划正文中的两处代码块已同步为最终实现。 |

计划正文中 Task 1 Step 4 与 Task 5 Step 1 的代码块已按 `1e5fbc8` 的最终形态回写，与仓库当前文件一致。

## 明确不做（后续批次）

- 存量迁移（批次 1-2）、meta-lint 五条规则与报告↔测试对应检查（批次 3）、release-check 扩展与 VERSION 检查（随批次 3）、删除 smoke-test.sh（批次 4）。

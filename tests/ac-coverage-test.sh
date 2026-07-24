#!/usr/bin/env bash
# ac-coverage-test.sh — Regression test for the ac-coverage gate's cross-spec
# attribution.
#
# Reproduces a project that hosts TWO specs whose tests both number themselves
# test_acN and live in the same directory (the real layrax monorepo shape:
# data-sync's test_sync.py and layout-migration's test_migration_*.py share
# apps/layrax-layout/tests/). Asserts that:
#   - each AC resolves to its OWN spec's test, never a foreign spec's same number;
#   - an AC with no spec-owned test FAILS the gate instead of borrowing a
#     foreign spec's test_acN (the reported bug silently passed it).
# Usage: bash tests/ac-coverage-test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KERNEL_SRC="$REPO_DIR/harness-template/halo/kernel"
GATE_REL="halo/kernel/delivery/gates/ac-coverage.sh"

PASS=0
FAIL=0
SANDBOX=""

pass() { PASS=$((PASS + 1)); printf "  ✅ %s\n" "$*"; }
fail() { FAIL=$((FAIL + 1)); printf "  ❌ %s\n" "$*"; }

check_eq() { # <actual> <expected> <label>
  if [[ "$1" == "$2" ]]; then pass "$3 ($1)"; else fail "$3: got '$1' want '$2'"; fi
}

cleanup() { [[ -n "$SANDBOX" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"; }
trap cleanup EXIT

for tool in yq python3; do
  command -v "$tool" &>/dev/null || { echo "ac-coverage test requires $tool. Skipping."; exit 0; }
done

SANDBOX=$(mktemp -d)
echo "══════════════════════════════════"
echo "AC-Coverage Cross-Spec Regression"
echo "Sandbox: $SANDBOX"
echo "══════════════════════════════════"
echo ""

# ── Build a two-spec python project ──
mkdir -p "$SANDBOX/halo/specs/spec-alpha" "$SANDBOX/halo/specs/spec-beta" "$SANDBOX/tests"
cp -R "$KERNEL_SRC" "$SANDBOX/halo/kernel"

cat > "$SANDBOX/halo/manifest.yaml" <<'YAML'
schema_version: "halo.manifest.v1"
kind: "HaloManifest"
project:
  name: sandbox
  language: python
specs:
  dir: "halo/specs"
YAML

# spec-alpha binds its own tests for AC-1/AC-2; AC-3 is verified by another gate
# (no test named) and alpha has NO test_ac3 — only beta does.
cat > "$SANDBOX/halo/specs/spec-alpha/spec.md" <<'MD'
# 技术方案：alpha

## 9. 验收标准

| 编号 | 前置条件 | 操作 | 期望结果 | 验证方式 |
|---|---|---|---|---|
| AC-1 | g | w | alpha 行为一 | `test_ac1_alpha_thing` |
| AC-2 | g | w | alpha 行为二 | `test_ac2_alpha_other` |
| AC-3 | g | w | alpha 行为三 | drift-check gate |
MD

cat > "$SANDBOX/halo/specs/spec-beta/spec.md" <<'MD'
# 技术方案：beta

## 9. 验收标准

| 编号 | 前置条件 | 操作 | 期望结果 | 验证方式 |
|---|---|---|---|---|
| AC-1 | g | w | beta 导出 | `test_ac1_beta_export` |
| AC-2 | g | w | beta 导入 | `test_ac2_beta_import` |
| AC-3 | g | w | beta 清理 | `test_ac3_beta_prune` |
MD

cat > "$SANDBOX/tests/test_alpha.py" <<'PY'
def test_ac1_alpha_thing():
    assert True

def test_ac2_alpha_other():
    assert True
PY

cat > "$SANDBOX/tests/test_beta.py" <<'PY'
def test_ac1_beta_export():
    assert True

def test_ac2_beta_import():
    assert True

def test_ac3_beta_prune():
    assert True
PY

run_gate() { # <spec-rel-path> <json-out-abs>  → returns gate exit code
  ( cd "$SANDBOX" && bash "$GATE_REL" "$1" . --json-out="$2" >/dev/null 2>&1 )
}

json_field() { # <json-file> <ac> <field>
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
ac, field = sys.argv[2], sys.argv[3]
for f in data.get("findings", []):
    if f.get("ac") == ac:
        print(f.get(field, ""))
        break
PY
}

# ── Case 1: spec-alpha — must FAIL, AC-3 has no alpha-owned test ──
ALPHA_JSON="$SANDBOX/alpha.json"
if run_gate "halo/specs/spec-alpha/spec.md" "$ALPHA_JSON"; then
  fail "spec-alpha gate should FAIL (AC-3 has no alpha-owned test) but passed"
else
  pass "spec-alpha gate FAILS on unproven AC-3 coverage"
fi
check_eq "$(json_field "$ALPHA_JSON" AC-1 test)" "test_ac1_alpha_thing" "AC-1 → alpha's own test"
check_eq "$(json_field "$ALPHA_JSON" AC-3 status)" "uncovered" "AC-3 not borrowed from beta"

# ── Case 2: spec-beta — all ACs own their tests → PASS, attributed to beta ──
BETA_JSON="$SANDBOX/beta.json"
if run_gate "halo/specs/spec-beta/spec.md" "$BETA_JSON"; then
  pass "spec-beta gate PASSES (all ACs own their tests)"
else
  fail "spec-beta gate should PASS but failed"
fi
check_eq "$(json_field "$BETA_JSON" AC-1 test)" "test_ac1_beta_export" "beta AC-1 → beta's own test"
check_eq "$(json_field "$BETA_JSON" AC-3 test)" "test_ac3_beta_prune" "beta AC-3 → beta's own test"

echo ""
echo "══════════════════════════════════"
echo "📊 ac-coverage regression: ✅ $PASS  ❌ $FAIL"
if [[ "$FAIL" -eq 0 ]]; then echo "✅ PASS"; exit 0; else echo "❌ FAIL"; exit 1; fi

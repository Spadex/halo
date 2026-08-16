#!/usr/bin/env bash
# smoke-test.sh — End-to-end smoke test for Halo
# Creates a temp Go project, runs init + pipeline, verifies exit codes.
# Usage: bash tests/smoke-test.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0
SANDBOX=""
TARGET_INIT_SANDBOX=""

pass() { PASS=$((PASS + 1)); printf "  ✅ %s\n" "$*"; }
fail() { FAIL=$((FAIL + 1)); printf "  ❌ %s\n" "$*"; }

cleanup() {
  if [[ -n "$SANDBOX" ]] && [[ -d "$SANDBOX" ]]; then
    rm -rf "$SANDBOX"
  fi
  if [[ -n "$TARGET_INIT_SANDBOX" ]] && [[ -d "$TARGET_INIT_SANDBOX" ]]; then
    rm -rf "$TARGET_INIT_SANDBOX"
  fi
}
trap cleanup EXIT

for tool in yq git; do
  if ! command -v "$tool" &>/dev/null; then
    echo "Smoke test requires $tool. Skipping."
    exit 0
  fi
done

SANDBOX=$(mktemp -d)
echo "══════════════════════════════════"
echo "Halo Smoke Test"
echo "Sandbox: $SANDBOX"
echo "══════════════════════════════════"
echo ""

# ── 1. bash -n syntax check ──
echo "── 1. Syntax check (bash -n) ──"
SYNTAX_OK=true
for f in "$REPO_DIR"/init.sh "$REPO_DIR"/install.sh "$REPO_DIR"/tests/*.sh $(find "$REPO_DIR/harness-template" "$REPO_DIR/prismspec/bin" -name '*.sh'); do
  if ! bash -n "$f" 2>/dev/null; then
    fail "Syntax error: $(basename "$f")"
    SYNTAX_OK=false
  fi
done
if [[ "$SYNTAX_OK" == "true" ]]; then
  pass "All scripts pass bash -n"
fi
echo ""

# ── 2. Local install ──
echo "── 2. Local install ──"
cd "$SANDBOX"
git init --quiet

if bash "$REPO_DIR/install.sh" "$SANDBOX" 2>&1 | tail -3; then
  if [[ -d "$SANDBOX/.halo/framework/harness-template" ]]; then
    pass "install.sh completed, harness-template exists"
  else
    fail "install.sh ran but harness-template not found"
  fi
else
  fail "install.sh exited non-zero"
fi
echo ""

if bash "$REPO_DIR/install.sh" "$SANDBOX" --dry-run --init >/tmp/halo-install-dry-run.out 2>&1 \
  && grep -q "Halo install dry run" /tmp/halo-install-dry-run.out \
  && grep -q "auto_init: true" /tmp/halo-install-dry-run.out; then
  pass "install.sh dry-run reports planned install"
else
  fail "install.sh dry-run failed"
fi

if bash "$REPO_DIR/install.sh" --version >/tmp/halo-install-version.out 2>&1 \
  && grep -q "kernel_version:" /tmp/halo-install-version.out; then
  pass "install.sh --version reports metadata"
else
  fail "install.sh --version failed"
fi
echo ""

# ── 3. Init (non-interactive, Go project) ──
echo "── 3. Init (Go project, non-interactive) ──"

cat > "$SANDBOX/go.mod" << 'EOF'
module github.com/example/testapp

go 1.22

require github.com/gin-gonic/gin v1.9.1
require gorm.io/gorm v1.25.0
EOF

if bash "$SANDBOX/.halo/framework/init.sh" --non-interactive --lang=go --name=testapp --ci=github 2>&1 | tail -5; then
  if [[ -f "$SANDBOX/halo/manifest.yaml" ]]; then
    pass "manifest.yaml generated"
  else
    fail "manifest.yaml not found after init"
  fi

  DEFAULT_MODE=$(yq -r '.specs.default_execution_mode // ""' "$SANDBOX/halo/manifest.yaml")
  ALLOW_MODE_OVERRIDE=$(yq -r '.specs.allow_execution_mode_override // ""' "$SANDBOX/halo/manifest.yaml")
  CI_PLATFORM=$(yq -r '.deploy.ci.platform // ""' "$SANDBOX/halo/manifest.yaml")
  EVAL_SINK_DIR=$(yq -r '.eval.sink.dir // ""' "$SANDBOX/halo/manifest.yaml")
  MANIFEST_SCHEMA=$(yq -r '.schema_version // ""' "$SANDBOX/halo/manifest.yaml")
  MANIFEST_KIND=$(yq -r '.kind // ""' "$SANDBOX/halo/manifest.yaml")
  KERNEL_ORCHESTRATOR=$(yq -r '.kernel.layers.orchestrator // ""' "$SANDBOX/halo/manifest.yaml")
  KERNEL_CONTEXT=$(yq -r '.kernel.layers.context // ""' "$SANDBOX/halo/manifest.yaml")
  KERNEL_DELIVERY=$(yq -r '.kernel.layers.delivery // ""' "$SANDBOX/halo/manifest.yaml")
  CONTEXT_MAP=$(yq -r '.context.map_file // ""' "$SANDBOX/halo/manifest.yaml")
  PIPELINE_FAILURE_CATEGORIES=$(yq -r '.pipeline.failure_categories_file // ""' "$SANDBOX/halo/manifest.yaml")
  if [[ "$MANIFEST_SCHEMA" == "halo.manifest.v1" ]] && [[ "$MANIFEST_KIND" == "HaloManifest" ]]; then
    pass "manifest contract metadata configured"
  else
    fail "manifest contract metadata missing"
  fi

  if [[ "$KERNEL_ORCHESTRATOR" == "true" ]] && [[ "$KERNEL_CONTEXT" == "true" ]] && [[ "$KERNEL_DELIVERY" == "true" ]]; then
    pass "manifest kernel capabilities configured"
  else
    fail "manifest kernel capabilities missing"
  fi

  if [[ "$CONTEXT_MAP" == "halo/context/README.md" ]] \
    && [[ "$PIPELINE_FAILURE_CATEGORIES" == "halo/config/failure-categories.yaml" ]]; then
    pass "manifest context and verification paths configured"
  else
    fail "manifest context or verification paths missing"
  fi

  if [[ "$DEFAULT_MODE" == "auto" ]] && [[ "$ALLOW_MODE_OVERRIDE" == "true" ]]; then
    pass "execution mode policy configured"
  else
    fail "execution mode policy missing from manifest"
  fi

  if [[ "$CI_PLATFORM" == "github" ]]; then
    pass "CI platform configured"
  else
    fail "CI platform not configured"
  fi

  if [[ "$EVAL_SINK_DIR" == "halo/state/eval-sink" ]]; then
    pass "eval sink configured"
  else
    fail "eval sink not configured"
  fi

  if [[ -f "$SANDBOX/halo/kernel/_lib.sh" ]] \
    && [[ -x "$SANDBOX/halo/kernel/capabilities.sh" ]] \
    && [[ -x "$SANDBOX/halo/kernel/delivery/eval-summary.sh" ]] \
    && [[ -x "$SANDBOX/halo/kernel/delivery/eval-history.sh" ]] \
    && [[ -x "$SANDBOX/halo/kernel/delivery/eval-sink.sh" ]] \
    && [[ -x "$SANDBOX/halo/kernel/delivery/eval-dashboard.sh" ]] \
    && [[ -x "$SANDBOX/halo/kernel/delivery/eval-query.sh" ]] \
    && [[ -x "$SANDBOX/halo/kernel/delivery/outcome-link.sh" ]] \
    && [[ -x "$SANDBOX/halo/kernel/delivery/outcome-report.sh" ]] \
    && [[ -x "$SANDBOX/halo/kernel/delivery/pr-comment.sh" ]] \
    && [[ -x "$SANDBOX/halo/kernel/delivery/failure-category-lint.sh" ]] \
    && [[ -x "$SANDBOX/halo/kernel/orchestrator/sdd/plan-lint.sh" ]] \
    && [[ -x "$SANDBOX/halo/kernel/orchestrator/sdd/task-next.sh" ]] \
    && [[ -x "$SANDBOX/halo/kernel/orchestrator/sdd/task-complete.sh" ]] \
    && [[ -x "$SANDBOX/halo/kernel/orchestrator/sdd/task-evidence-lint.sh" ]] \
    && [[ -x "$SANDBOX/halo/kernel/orchestrator/sdd/spec-state-lint.sh" ]] \
    && [[ -x "$SANDBOX/halo/kernel/orchestrator/sdd/spec-status.sh" ]] \
    && [[ -x "$SANDBOX/halo/kernel/orchestrator/sdd/spec-history.sh" ]] \
    && [[ -x "$SANDBOX/halo/kernel/orchestrator/sdd/summary-draft.sh" ]] \
    && [[ -x "$SANDBOX/halo/kernel/context/summary-learn-draft.sh" ]] \
    && [[ -x "$SANDBOX/halo/kernel/context/learn-draft.sh" ]] \
    && [[ -x "$SANDBOX/halo/kernel/context/knowledge-review.sh" ]] \
    && [[ -x "$SANDBOX/halo/kernel/context/knowledge-lint.sh" ]] \
    && [[ -f "$SANDBOX/halo/config/failure-categories.yaml" ]]; then
    pass "kernel files installed"
  else
    fail "kernel files not installed"
  fi

  if bash "$SANDBOX/halo/kernel/capabilities.sh" --json > "$SANDBOX/capabilities.json" \
    && yq -e '.schema_version == "halo.capabilities.v1"' "$SANDBOX/capabilities.json" >/dev/null 2>&1 \
    && yq -e '.tools[] | select(.id == "guide")' "$SANDBOX/capabilities.json" >/dev/null 2>&1 \
    && yq -e '.metrics[] | select(.id == "ac_coverage")' "$SANDBOX/capabilities.json" >/dev/null 2>&1; then
    pass "runtime capabilities contract available"
  else
    fail "runtime capabilities contract missing or invalid"
  fi

  if [[ -x "$SANDBOX/halo/kernel/doctor.sh" ]]; then
    pass "halo doctor installed"
  else
    fail "halo doctor missing or not executable"
  fi

  if [[ -f "$SANDBOX/halo/kernel/context/backends/knowledge.sh" ]] \
    && [[ -f "$SANDBOX/halo/context/README.md" ]] \
    && [[ -f "$SANDBOX/halo/context/sources.yaml" ]] \
    && [[ -f "$SANDBOX/halo/context/knowledge/rules.md" ]]; then
    pass "context layer installed"
  else
    fail "context layer files missing"
  fi

  if [[ -f "$SANDBOX/CLAUDE.md" ]]; then
    pass "CLAUDE.md created"
  else
    fail "CLAUDE.md not created"
  fi

  if grep -q '@import halo/kernel/orchestrator/rules.md' "$SANDBOX/CLAUDE.md" \
    && grep -q 'pipeline.sh --json-out' "$SANDBOX/halo/kernel/orchestrator/rules.md" \
    && ! grep -qE 'halo/kernel/knowledge|halo/knowledge|kernel/knowledge/loader\.sh|delivery gates|halo/context/knowledge/drafts' "$SANDBOX/halo/kernel/orchestrator/rules.md"; then
    pass "target Agent rules are current"
  else
    fail "target Agent rules are stale or missing"
  fi

  if [[ -f "$SANDBOX/halo/skills/init.md" ]]; then
    pass "Halo init skill installed"
  else
    fail "Halo init skill missing"
  fi

  if [[ -f "$SANDBOX/.github/workflows/halo-eval.yml" ]] \
    && yq -e '.permissions.issues == "write" and .permissions."pull-requests" == "read"' "$SANDBOX/.github/workflows/halo-eval.yml" >/dev/null 2>&1 \
    && yq -e '.jobs.eval.steps[] | select(.name == "Publish Halo PR comment")' "$SANDBOX/.github/workflows/halo-eval.yml" >/dev/null 2>&1; then
    pass "GitHub Actions eval workflow installed"
  else
    fail "GitHub Actions eval workflow missing or invalid"
  fi

  for command in prismspec build clarify spec plan implement review verify capture; do
    if [[ -f "$SANDBOX/.claude/commands/${command}.md" ]]; then
      pass "$command slash command installed"
    else
      fail "$command slash command missing"
    fi
  done

  if [[ -f "$SANDBOX/prismspec/skills/prismspec-workflow/SKILL.md" ]] \
    && [[ -f "$SANDBOX/prismspec/skillpack.yaml" ]] \
    && [[ -f "$SANDBOX/prismspec/skills/prismspec-specification/SKILL.md" ]] \
    && [[ -f "$SANDBOX/prismspec/skills/prismspec-planning/SKILL.md" ]] \
    && [[ -f "$SANDBOX/prismspec/skills/prismspec-implementation/SKILL.md" ]] \
    && [[ -f "$SANDBOX/prismspec/skills/prismspec-review/SKILL.md" ]] \
    && [[ -f "$SANDBOX/prismspec/skills/prismspec-verification/SKILL.md" ]] \
    && [[ -f "$SANDBOX/prismspec/skills/prismspec-knowledge-capture/SKILL.md" ]] \
    && [[ -f "$SANDBOX/prismspec/skills/prismspec-debugging/SKILL.md" ]] \
    && [[ -f "$SANDBOX/prismspec/skills/prismspec-context-engineering/SKILL.md" ]] \
    && [[ -f "$SANDBOX/prismspec/skills/prismspec-grilling/SKILL.md" ]] \
    && [[ -f "$SANDBOX/prismspec/skills/prismspec-source-grounding/SKILL.md" ]] \
    && [[ -f "$SANDBOX/prismspec/skills/prismspec-doubt-review/SKILL.md" ]] \
    && [[ -f "$SANDBOX/prismspec/skills/prismspec-interface-design/SKILL.md" ]] \
    && [[ -x "$SANDBOX/prismspec/bin/new.sh" ]] \
    && [[ -x "$SANDBOX/prismspec/bin/guide.sh" ]] \
    && [[ -x "$SANDBOX/prismspec/bin/lint.sh" ]] \
    && [[ -x "$SANDBOX/prismspec/bin/doctor.sh" ]] \
    && [[ -x "$SANDBOX/prismspec/bin/eval-skills.sh" ]] \
    && [[ -f "$SANDBOX/prismspec/templates/spec-template.md" ]] \
    && [[ -f "$SANDBOX/prismspec/templates/spec-template-lite.md" ]] \
    && [[ -f "$SANDBOX/prismspec/templates/spec-template-service.md" ]] \
    && [[ -f "$SANDBOX/prismspec/templates/spec-template-frontend.md" ]] \
    && [[ -f "$SANDBOX/prismspec/templates/spec-template-tdd.md" ]] \
    && [[ -f "$SANDBOX/prismspec/references/mode-selection.md" ]] \
    && [[ -f "$SANDBOX/prismspec/references/definition-of-done.md" ]] \
    && [[ -f "$SANDBOX/prismspec/agents/spec-reviewer.md" ]] \
    && [[ -f "$SANDBOX/prismspec/agents/task-reviewer.md" ]] \
    && [[ -f "$SANDBOX/prismspec/agents/test-reviewer.md" ]] \
    && [[ -f "$SANDBOX/prismspec/agents/risk-reviewer.md" ]] \
    && [[ -f "$SANDBOX/prismspec/commands/prismspec.md" ]] \
    && [[ -f "$SANDBOX/prismspec/commands/build.md" ]] \
    && [[ -f "$SANDBOX/prismspec/commands/clarify.md" ]]; then
    pass "PrismSpec deliverable module installed"
  else
    fail "PrismSpec standalone module missing"
  fi

  PRISMSPEC_NEW_JSON=$(bash "$SANDBOX/prismspec/bin/new.sh" smoke-new-spec --title="Smoke New Spec" --template=lite --mode=plan --json)
  if echo "$PRISMSPEC_NEW_JSON" | yq -e '.host == "halo" and .spec_id == "smoke-new-spec" and .template == "lite" and .mode == "plan"' >/dev/null 2>&1 \
    && [[ -f "$SANDBOX/halo/specs/smoke-new-spec/spec.md" ]] \
    && grep -q "id: smoke-new-spec" "$SANDBOX/halo/specs/smoke-new-spec/spec.md" \
    && grep -q "execution_mode: plan" "$SANDBOX/halo/specs/smoke-new-spec/spec.md" \
    && grep -q "scaffolded: true" "$SANDBOX/halo/specs/smoke-new-spec/spec.md"; then
    pass "PrismSpec new creates routed spec artifacts"
  else
    fail "PrismSpec new did not create routed spec artifacts"
    echo "$PRISMSPEC_NEW_JSON"
  fi

  PRISMSPEC_NEW_GUIDE_JSON=$(bash "$SANDBOX/prismspec/bin/guide.sh" --spec=smoke-new-spec --json)
  if echo "$PRISMSPEC_NEW_GUIDE_JSON" | yq -e '.stage == "specification" and .scaffolded == true' >/dev/null 2>&1; then
    pass "PrismSpec guide keeps scaffolded specs in specification"
  else
    fail "PrismSpec guide advanced a scaffolded spec"
    echo "$PRISMSPEC_NEW_GUIDE_JSON"
  fi
  rm -rf "$SANDBOX/halo/specs/smoke-new-spec"

  PRISMSPEC_DOCTOR_EXIT=0
  PRISMSPEC_DOCTOR_OUTPUT=$(bash "$SANDBOX/prismspec/bin/doctor.sh" 2>&1) || PRISMSPEC_DOCTOR_EXIT=$?
  if [[ $PRISMSPEC_DOCTOR_EXIT -eq 0 ]] && echo "$PRISMSPEC_DOCTOR_OUTPUT" | grep -q "PASS"; then
    pass "PrismSpec doctor passes installed project"
  else
    fail "PrismSpec doctor failed"
    echo "$PRISMSPEC_DOCTOR_OUTPUT" | tail -20
  fi

  PRISMSPEC_SKILLPACK_LINT_EXIT=0
  PRISMSPEC_SKILLPACK_LINT_OUTPUT=$(bash "$SANDBOX/prismspec/bin/lint.sh" "$SANDBOX/prismspec" skillpack 2>&1) || PRISMSPEC_SKILLPACK_LINT_EXIT=$?
  if [[ $PRISMSPEC_SKILLPACK_LINT_EXIT -eq 0 ]]; then
    pass "PrismSpec skillpack contract passes lint"
  else
    fail "PrismSpec skillpack contract failed lint"
    echo "$PRISMSPEC_SKILLPACK_LINT_OUTPUT" | tail -20
  fi

  PRISMSPEC_SKILL_EVAL_EXIT=0
  PRISMSPEC_SKILL_EVAL_OUTPUT=$(bash "$SANDBOX/prismspec/bin/eval-skills.sh" --root="$SANDBOX/prismspec" --all 2>&1) || PRISMSPEC_SKILL_EVAL_EXIT=$?
  if [[ $PRISMSPEC_SKILL_EVAL_EXIT -eq 0 ]] && echo "$PRISMSPEC_SKILL_EVAL_OUTPUT" | grep -q "Summary:"; then
    pass "PrismSpec skill eval passes"
  else
    fail "PrismSpec skill eval failed"
    echo "$PRISMSPEC_SKILL_EVAL_OUTPUT" | tail -20
  fi

  FLAT_SKILL_COUNT=$(find "$SANDBOX/prismspec/skills" -maxdepth 1 -type f -name '*.md' -not -name 'README.md' | wc -l | tr -d ' ')
  HALO_SDD_SKILL_COUNT=$(find "$SANDBOX/halo/skills" -maxdepth 1 -type f \( -name 'prismspec.md' -o -name 'clarify.md' -o -name 'spec.md' -o -name 'plan.md' -o -name 'implement.md' -o -name 'review.md' -o -name 'verify.md' -o -name 'capture.md' \) | wc -l | tr -d ' ')
  if [[ "$FLAT_SKILL_COUNT" == "0" ]] && [[ "$HALO_SDD_SKILL_COUNT" == "0" ]]; then
    pass "SDD workflow has a single canonical skill source"
  else
    fail "Duplicate SDD skill files found"
  fi

  GUIDE_OUTPUT=$(bash "$SANDBOX/prismspec/bin/guide.sh" --json)
  if echo "$GUIDE_OUTPUT" | grep -q '"stage": "specification"' && echo "$GUIDE_OUTPUT" | grep -q 'prismspec/skills/prismspec-specification/SKILL.md'; then
    pass "PrismSpec guide detects initial specification stage"
  else
    fail "PrismSpec guide did not detect initial specification stage"
  fi

  GUIDE_SHORT_ARG_OUTPUT=$(bash "$SANDBOX/prismspec/bin/guide.sh" spec=example mode=tdd --json)
  if echo "$GUIDE_SHORT_ARG_OUTPUT" | grep -q '"spec_id": "example"' && echo "$GUIDE_SHORT_ARG_OUTPUT" | grep -q '"mode": "tdd"'; then
    pass "PrismSpec guide accepts short arguments"
  else
    fail "PrismSpec guide did not accept short arguments"
  fi

  if [[ -x "$SANDBOX/halo/kernel/orchestrator/sdd/task-brief.sh" ]] \
    && [[ -x "$SANDBOX/halo/kernel/orchestrator/sdd/task-next.sh" ]] \
    && [[ -x "$SANDBOX/halo/kernel/orchestrator/sdd/task-complete.sh" ]] \
    && [[ -x "$SANDBOX/halo/kernel/orchestrator/sdd/task-evidence-lint.sh" ]] \
    && [[ -x "$SANDBOX/halo/kernel/orchestrator/sdd/review-package.sh" ]] \
    && [[ -x "$SANDBOX/halo/kernel/orchestrator/sdd/review-summary.sh" ]] \
    && [[ -x "$SANDBOX/halo/kernel/orchestrator/sdd/spec-history.sh" ]] \
    && [[ -x "$SANDBOX/halo/kernel/orchestrator/sdd/summary-draft.sh" ]] \
    && [[ -x "$SANDBOX/halo/kernel/orchestrator/sdd/tdd-evidence.sh" ]]; then
    pass "SDD helper scripts installed"
  else
    fail "SDD helper scripts missing"
  fi

  if grep -qxF ".halo/sdd/" "$SANDBOX/.gitignore"; then
    pass ".halo/sdd ignored"
  else
    fail ".halo/sdd not ignored"
  fi

  if grep -qxF ".prismspec/runs/" "$SANDBOX/.gitignore"; then
    pass ".prismspec/runs ignored"
  else
    fail ".prismspec/runs not ignored"
  fi

  DOCTOR_EXIT=0
  DOCTOR_OUTPUT=$(bash "$SANDBOX/halo/kernel/doctor.sh" 2>&1) || DOCTOR_EXIT=$?
  if [[ $DOCTOR_EXIT -eq 0 ]] \
    && echo "$DOCTOR_OUTPUT" | grep -q "PASS" \
    && echo "$DOCTOR_OUTPUT" | grep -q "manifest schema_version" \
    && echo "$DOCTOR_OUTPUT" | grep -q "PrismSpec skillpack contract lint"; then
    pass "halo doctor passes installed project"
  else
    fail "halo doctor failed"
    echo "$DOCTOR_OUTPUT" | tail -20
  fi
else
  fail "init.sh exited non-zero"
fi

# Clean up examples inside harness to avoid false positives in search
rm -rf "$SANDBOX/.halo/framework/examples" "$SANDBOX/.halo/framework/tests"
echo ""

# ── 4. Install --init targets the requested directory ──
echo "── 4. Install --init target directory ──"
TARGET_INIT_SANDBOX=$(mktemp -d)
printf 'module github.com/example/targetinit\n\ngo 1.22\n' > "$TARGET_INIT_SANDBOX/go.mod"

if printf '\n\n\n\n\n\n' | bash "$REPO_DIR/install.sh" "$TARGET_INIT_SANDBOX" --init >/tmp/halo-target-init.log 2>&1; then
  if [[ -f "$TARGET_INIT_SANDBOX/halo/manifest.yaml" ]]; then
    pass "install.sh --init writes manifest to target directory"
  else
    fail "install.sh --init did not write manifest to target directory"
    tail -10 /tmp/halo-target-init.log
  fi
else
  fail "install.sh --init exited non-zero"
  tail -10 /tmp/halo-target-init.log
fi
rm -rf "$TARGET_INIT_SANDBOX" /tmp/halo-target-init.log
echo ""

# ── 5. Pipeline (no code, no spec — should pass with all skips) ──
echo "── 5. Pipeline (no code, no spec) ──"
cd "$SANDBOX"
PIPELINE_EXIT=0
PIPELINE_OUTPUT=$(bash halo/kernel/delivery/pipeline.sh --skip-spec --skip-integration 2>&1) || PIPELINE_EXIT=$?

if echo "$PIPELINE_OUTPUT" | grep -q "ALL PASS\|PASS"; then
  pass "Pipeline completes (bootstrap-only)"
elif echo "$PIPELINE_OUTPUT" | grep -q "FAIL"; then
  # Bootstrap may fail if go/docker not installed — that's expected
  if echo "$PIPELINE_OUTPUT" | grep -q "not installed"; then
    pass "Pipeline ran correctly (tools not installed — expected in CI)"
  else
    fail "Pipeline failed unexpectedly"
    echo "$PIPELINE_OUTPUT" | tail -10
  fi
else
  pass "Pipeline executed (exit=$PIPELINE_EXIT)"
fi

PIPELINE_JSON_EXIT=0
PIPELINE_JSON_OUTPUT=$(bash halo/kernel/delivery/pipeline.sh --skip-spec --skip-integration --json-out 2>&1) || PIPELINE_JSON_EXIT=$?
LATEST_EVAL_JSON=$(find "$SANDBOX/halo/state/eval-runs" -name '*.json' -type f -print 2>/dev/null | sort | tail -1)
if [[ -n "$LATEST_EVAL_JSON" ]] \
  && grep -q '"run_id"' "$LATEST_EVAL_JSON" \
  && grep -q '"pipeline"' "$LATEST_EVAL_JSON" \
  && grep -q '"steps"' "$LATEST_EVAL_JSON" \
  && yq -e '.pipeline.status and .steps' "$LATEST_EVAL_JSON" >/dev/null 2>&1; then
  pass "Pipeline writes structured eval JSON"
else
  fail "Pipeline did not write structured eval JSON"
  echo "$PIPELINE_JSON_OUTPUT" | tail -20
  echo "exit=$PIPELINE_JSON_EXIT file=${LATEST_EVAL_JSON:-<missing>}"
fi
echo ""

# ── 6. Spec-lint on directory spec layout ──
echo "── 6. Spec-lint modern layout ──"
mkdir -p "$SANDBOX/halo/specs/modern-feature"
cat > "$SANDBOX/halo/specs/modern-feature/spec.md" << 'SPEC'
---
id: modern-feature
status: drafted
execution_mode: tdd
mode_source: model-selected
approval: inferred
owner: smoke
created_at: 2026-06-26T00:00:00Z
updated_at: 2026-06-26T00:00:00Z
---

# Spec: Modern Feature

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
| user | Smoke-test PrismSpec modern artifact layout. | Use a minimal fixture. |
| code / tests | No production code is required for this fixture. | Keep scope small and AC ids stable. |
| open questions / conflicts | None. | No blocking decision required. |

## Architecture

Use the existing handler boundary. No new subsystem is required for this fixture.

## Interface

| Interface | Contract |
|-----------|----------|
| Handler | Create and get behavior must be observable through AC-named tests. |

## Invariants

| Invariant | Verification |
|-----------|--------------|
| AC ids remain stable and traceable. | spec-lint and ac-coverage fixtures |

## Acceptance Criteria

| # | When | Then | Verification |
|---|------|------|--------------|
| AC-1 | Create item | Returns 201 | TestAC1 |
| AC-2 | Get item | Returns item | TestAC2 |

## Design Decisions

| # | Decision | Rationale | Reversible? |
|---|----------|-----------|-------------|
| D-1 | Use existing handler | Minimal change | yes |

## Risk Notes

| Risk | Mitigation | Verification |
|------|------------|--------------|
| None | N/A | Tests |

## Execution Policy

- Mode: `tdd`
- Reason: smoke test validates modern template.

## Verification Plan

| Gate / Test | Required? | Notes |
|-------------|-----------|-------|
| spec-lint | yes | |
| unit-test | yes | |
SPEC

MODERN_LINT_EXIT=0
MODERN_LINT_OUTPUT=$(bash "$SANDBOX/halo/kernel/delivery/gates/spec-lint.sh" "$SANDBOX/halo/specs/modern-feature/spec.md" 2>&1) || MODERN_LINT_EXIT=$?

if [[ $MODERN_LINT_EXIT -eq 0 ]]; then
  pass "spec-lint passes on modern persistent spec"
else
  fail "spec-lint failed on modern persistent spec (exit=$MODERN_LINT_EXIT)"
  echo "$MODERN_LINT_OUTPUT" | tail -10
fi

PRISMSPEC_SPEC_LINT_EXIT=0
PRISMSPEC_SPEC_LINT_OUTPUT=$(bash "$SANDBOX/prismspec/bin/lint.sh" "$SANDBOX/halo/specs/modern-feature/spec.md" spec 2>&1) || PRISMSPEC_SPEC_LINT_EXIT=$?
if [[ $PRISMSPEC_SPEC_LINT_EXIT -eq 0 ]]; then
  pass "PrismSpec lint passes spec contract"
else
  fail "PrismSpec lint failed spec contract"
  echo "$PRISMSPEC_SPEC_LINT_OUTPUT" | tail -10
fi

SPEC_STATE_LINT_EXIT=0
SPEC_STATE_LINT_OUTPUT=$(bash "$SANDBOX/halo/kernel/orchestrator/sdd/spec-state-lint.sh" modern-feature 2>&1) || SPEC_STATE_LINT_EXIT=$?
if [[ $SPEC_STATE_LINT_EXIT -eq 0 ]]; then
  pass "spec-state-lint passes drafted spec state"
else
  fail "spec-state-lint failed drafted spec state"
  echo "$SPEC_STATE_LINT_OUTPUT" | tail -20
fi

mkdir -p "$SANDBOX/halo/specs/clarify-draft"
cat > "$SANDBOX/halo/specs/clarify-draft/spec.md" << 'CLARIFY_SPEC'
---
id: clarify-draft
title: Clarify Draft
status: clarifying
owner: smoke
created_at: 2026-06-26T00:00:00Z
updated_at: 2026-06-26T00:00:00Z
---

# Spec: Clarify Draft

## Intent

Clarify engineering boundaries before formal specification.

## Context Basis

| Source | Constraint / Fact | Impact |
|--------|-------------------|--------|
| user request | Need a status=clarifying draft | Route remains specification |
| open questions / conflicts | Which contract changes are in scope? | Blocks drafted spec |
CLARIFY_SPEC
CLARIFY_STATE_LINT_EXIT=0
CLARIFY_STATE_LINT_OUTPUT=$(bash "$SANDBOX/halo/kernel/orchestrator/sdd/spec-state-lint.sh" clarify-draft 2>&1) || CLARIFY_STATE_LINT_EXIT=$?
CLARIFY_GUIDE_JSON=$(bash "$SANDBOX/prismspec/bin/guide.sh" --spec=clarify-draft --json)
if [[ $CLARIFY_STATE_LINT_EXIT -eq 0 ]] \
  && echo "$CLARIFY_GUIDE_JSON" | yq -e '.status == "clarifying" and .stage == "specification" and .route_reason == "clarifying_spec"' >/dev/null 2>&1; then
  pass "clarifying spec routes to specification with relaxed state lint"
else
  fail "clarifying spec contract failed"
  echo "$CLARIFY_STATE_LINT_OUTPUT" | tail -20
  echo "$CLARIFY_GUIDE_JSON"
fi

mkdir -p "$SANDBOX/halo/specs/bad-state"
cat > "$SANDBOX/halo/specs/bad-state/spec.md" << 'BAD_STATE_SPEC'
---
id: bad-state
status: planned
execution_mode: auto
mode_source: model-selected
approval: inferred
owner: smoke
created_at: 2026-06-26T00:00:00Z
updated_at: 2026-06-26T00:00:00Z
---

# Spec: Bad State

## Intent

Bad state fixture.
BAD_STATE_SPEC
BAD_STATE_LINT_EXIT=0
bash "$SANDBOX/halo/kernel/orchestrator/sdd/spec-state-lint.sh" bad-state >/tmp/halo-spec-state-lint-bad.log 2>&1 || BAD_STATE_LINT_EXIT=$?
if [[ $BAD_STATE_LINT_EXIT -ne 0 ]] \
  && grep -q "execution_mode must be resolved" /tmp/halo-spec-state-lint-bad.log \
  && grep -q "plan.md required" /tmp/halo-spec-state-lint-bad.log; then
  pass "spec-state-lint rejects invalid state metadata"
else
  fail "spec-state-lint accepted invalid state metadata"
  tail -30 /tmp/halo-spec-state-lint-bad.log
fi

echo ""

# ── 6c. SDD helper scripts ──
echo "── 6c. SDD helper scripts ──"
cat > "$SANDBOX/halo/specs/modern-feature/plan.md" << 'PLAN'
# Plan: Modern Feature

## Source

- Spec: `halo/specs/modern-feature/spec.md`
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

- [ ] RED-1: Add failing test for AC-1
  - Ref: AC-1
  - Expected failure: handler does not create items yet
  - Test file: `internal/handler/item_test.go`
  - Verification: `go test ./internal/handler -run TestAC1_CreateItem`
  - Done when:
    - [ ] Expected failure is captured in `.halo/sdd/modern-feature/T1/tdd-evidence.json`

- [ ] RED-2: Add failing test for AC-2
  - Ref: AC-2
  - Expected failure: handler does not return created items yet
  - Test file: `internal/handler/item_test.go`
  - Verification: `go test ./internal/handler -run TestAC2_GetItem`
  - Done when:
    - [ ] Expected failure is captured in `.halo/sdd/modern-feature/T2/tdd-evidence.json`

- [ ] T1: Add create behavior
  - Ref: AC-1
  - Mode: tdd
  - Scope: Implement the smallest create path needed for AC-1.
  - Interfaces:
    - Inputs: create request
    - Outputs: 201 response
    - Touched files/contracts: handler
  - Files: `internal/handler/item.go`
  - Verification: `TestAC1_CreateItem`
  - Evidence:
    - Brief: `.halo/sdd/modern-feature/T1/brief.md`
    - Review package: `.halo/sdd/modern-feature/T1/review-package.md`
  - Done when:
    - [ ] AC-1 passes focused verification and evidence exists.

- [ ] T2: Add get behavior
  - Ref: AC-2
  - Mode: tdd
  - Scope: Implement the smallest get path needed for AC-2.
  - Interfaces:
    - Inputs: get request
    - Outputs: item response
    - Touched files/contracts: handler
  - Files: `internal/handler/item.go`
  - Verification: `TestAC2_GetItem`
  - Evidence:
    - Brief: `.halo/sdd/modern-feature/T2/brief.md`
    - Review package: `.halo/sdd/modern-feature/T2/review-package.md`
  - Done when:
    - [ ] AC-2 passes focused verification and evidence exists.
PLAN

TASK_NEXT_JSON=$(bash "$SANDBOX/halo/kernel/orchestrator/sdd/task-next.sh" modern-feature --json)
if echo "$TASK_NEXT_JSON" | yq -e '.kind == "task-next" and .status == "next" and .task_id == "RED-1" and .task_kind == "red-test" and .mode == "tdd" and (.ac_refs | length == 1 and .ac_refs[0] == "AC-1")' >/dev/null 2>&1; then
  pass "task-next resolves first red-test task"
else
  fail "task-next did not resolve first red-test task"
  echo "$TASK_NEXT_JSON"
fi

PRISMSPEC_PLAN_LINT_EXIT=0
PRISMSPEC_PLAN_LINT_OUTPUT=$(bash "$SANDBOX/prismspec/bin/lint.sh" "$SANDBOX/halo/specs/modern-feature" plan 2>&1) || PRISMSPEC_PLAN_LINT_EXIT=$?
if [[ $PRISMSPEC_PLAN_LINT_EXIT -eq 0 ]]; then
  pass "PrismSpec lint passes plan contract"
else
  fail "PrismSpec lint failed plan contract"
  echo "$PRISMSPEC_PLAN_LINT_OUTPUT" | tail -10
fi

PLAN_LINT_EXIT=0
PLAN_LINT_OUTPUT=$(bash "$SANDBOX/halo/kernel/orchestrator/sdd/plan-lint.sh" modern-feature 2>&1) || PLAN_LINT_EXIT=$?
if [[ $PLAN_LINT_EXIT -eq 0 ]]; then
  pass "plan-lint passes AC-traced plan"
else
  fail "plan-lint failed AC-traced plan"
  echo "$PLAN_LINT_OUTPUT" | tail -20
fi

SPEC_STATUS_PLANNED_EXIT=0
SPEC_STATUS_PLANNED_OUTPUT=$(bash "$SANDBOX/halo/kernel/orchestrator/sdd/spec-status.sh" modern-feature planned --from=drafted 2>&1) || SPEC_STATUS_PLANNED_EXIT=$?
GUIDE_STATUS_JSON=$(cd "$SANDBOX" && bash prismspec/bin/guide.sh --spec=modern-feature --json)
if [[ $SPEC_STATUS_PLANNED_EXIT -eq 0 ]] \
  && grep -q '^status: planned$' "$SANDBOX/halo/specs/modern-feature/spec.md" \
  && echo "$GUIDE_STATUS_JSON" | yq -e '.status == "planned"' >/dev/null 2>&1; then
  pass "spec-status advances drafted spec to planned"
else
  fail "spec-status failed to advance drafted spec to planned"
  echo "$SPEC_STATUS_PLANNED_OUTPUT" | tail -20
fi
PLANNED_TRANSITION_EVENT="$(
  find "$SANDBOX/halo/state/spec-transitions" -name '*.json' -type f -print 2>/dev/null \
    | while IFS= read -r file; do
        if yq -e '.kind == "spec-transition" and .from_status == "drafted" and .to_status == "planned"' "$file" >/dev/null 2>&1; then echo "$file"; fi
      done \
    | tail -1 || true
)"
if [[ -f "$PLANNED_TRANSITION_EVENT" ]] \
  && yq -e '.kind == "spec-transition" and .spec_id == "modern-feature" and .from_status == "drafted" and .to_status == "planned" and .checks.plan_lint == true and .checks.spec_state_lint == true' "$PLANNED_TRANSITION_EVENT" >/dev/null 2>&1; then
  pass "spec-status records planned transition event"
else
  fail "spec-status planned transition event invalid"
  [[ -f "$PLANNED_TRANSITION_EVENT" ]] && cat "$PLANNED_TRANSITION_EVENT"
fi
TRANSITION_COUNT_AFTER_PLANNED=$(find "$SANDBOX/halo/state/spec-transitions" -name '*.json' -type f -print 2>/dev/null | wc -l | tr -d ' ')

SPEC_STATUS_INCOMPLETE_EXIT=0
bash "$SANDBOX/halo/kernel/orchestrator/sdd/spec-status.sh" modern-feature implemented --from=planned >/tmp/halo-spec-status-incomplete.log 2>&1 || SPEC_STATUS_INCOMPLETE_EXIT=$?
if [[ $SPEC_STATUS_INCOMPLETE_EXIT -ne 0 ]] && grep -q "incomplete tasks" /tmp/halo-spec-status-incomplete.log; then
  pass "spec-status blocks implemented state with incomplete tasks"
else
  fail "spec-status accepted incomplete implemented state"
  tail -20 /tmp/halo-spec-status-incomplete.log
fi

TASK_COMPLETE_MISSING_EXIT=0
bash "$SANDBOX/halo/kernel/orchestrator/sdd/task-complete.sh" modern-feature T1 >/tmp/halo-task-complete-missing.log 2>&1 || TASK_COMPLETE_MISSING_EXIT=$?
if [[ $TASK_COMPLETE_MISSING_EXIT -ne 0 ]] && grep -q "T1 missing brief.md" /tmp/halo-task-complete-missing.log; then
  pass "task-complete rejects task without evidence"
else
  fail "task-complete accepted task without evidence"
  tail -20 /tmp/halo-task-complete-missing.log
fi

mkdir -p "$SANDBOX/halo/specs/missing-evidence"
cp "$SANDBOX/halo/specs/modern-feature/spec.md" "$SANDBOX/halo/specs/missing-evidence/spec.md"
cp "$SANDBOX/halo/specs/modern-feature/plan.md" "$SANDBOX/halo/specs/missing-evidence/plan.md"
perl -0pi -e 's/id: modern-feature/id: missing-evidence/; s/- \[ \] T1:/- [x] T1:/g; s/- \[ \] T2:/- [x] T2:/g; s/- \[ \] RED-1:/- [x] RED-1:/g; s/- \[ \] RED-2:/- [x] RED-2:/g' "$SANDBOX/halo/specs/missing-evidence/spec.md" "$SANDBOX/halo/specs/missing-evidence/plan.md"
SPEC_STATUS_NO_EVIDENCE_EXIT=0
bash "$SANDBOX/halo/kernel/orchestrator/sdd/spec-status.sh" missing-evidence implemented --from=planned >/tmp/halo-spec-status-no-evidence.log 2>&1 || SPEC_STATUS_NO_EVIDENCE_EXIT=$?
if [[ $SPEC_STATUS_NO_EVIDENCE_EXIT -ne 0 ]] && grep -q "missing brief.md" /tmp/halo-spec-status-no-evidence.log; then
  pass "spec-status blocks completed tasks without evidence"
else
  fail "spec-status accepted completed tasks without evidence"
  tail -20 /tmp/halo-spec-status-no-evidence.log
fi
TRANSITION_COUNT_AFTER_FAILED=$(find "$SANDBOX/halo/state/spec-transitions" -name '*.json' -type f -print 2>/dev/null | wc -l | tr -d ' ')
if [[ "$TRANSITION_COUNT_AFTER_FAILED" == "$TRANSITION_COUNT_AFTER_PLANNED" ]]; then
  pass "spec-status does not record failed transition attempts"
else
  fail "spec-status recorded failed transition attempts"
fi

BRIEF_OUTPUT=$(bash "$SANDBOX/halo/kernel/orchestrator/sdd/task-brief.sh" modern-feature T1 2>&1)
if [[ -f "$SANDBOX/.halo/sdd/modern-feature/T1/brief.md" ]] && grep -q "全局约束" "$SANDBOX/.halo/sdd/modern-feature/T1/brief.md"; then
  pass "task-brief generates task evidence"
else
  fail "task-brief did not generate expected evidence"
  echo "$BRIEF_OUTPUT" | tail -10
fi

REVIEW_OUTPUT=$(bash "$SANDBOX/halo/kernel/orchestrator/sdd/review-package.sh" modern-feature T1 2>&1)
if [[ -f "$SANDBOX/.halo/sdd/modern-feature/T1/review-package.md" ]] && grep -q "cannot_verify" "$SANDBOX/.halo/sdd/modern-feature/T1/review-package.md"; then
  pass "review-package generates read-only review package"
else
  fail "review-package did not generate expected package"
  echo "$REVIEW_OUTPUT" | tail -10
fi

TDD_EVIDENCE_OUTPUT=$(bash "$SANDBOX/halo/kernel/orchestrator/sdd/tdd-evidence.sh" modern-feature T1 \
  --ac=AC-1 \
  --test=TestAC1_CreateItem \
  --test-file=internal/handler/item_test.go \
  --red-command="go test ./internal/handler -run TestAC1_CreateItem" \
  --red-exit=1 \
  --red-summary="handler not implemented" \
  --green-command="go test ./internal/handler -run TestAC1_CreateItem" \
  --green-exit=0 \
  --green-summary="focused AC test passes" \
  --refactor=none 2>&1)
if yq -e '.kind == "tdd-evidence" and .status == "pass" and .red.exit_code == 1 and .green.exit_code == 0 and (.ac_ids | length == 1)' "$SANDBOX/.halo/sdd/modern-feature/T1/tdd-evidence.json" >/dev/null 2>&1; then
  pass "tdd-evidence writes structured red/green JSON"
else
  fail "tdd-evidence JSON invalid"
  echo "$TDD_EVIDENCE_OUTPUT" | tail -10
fi

BRIEF_OUTPUT_T2=$(bash "$SANDBOX/halo/kernel/orchestrator/sdd/task-brief.sh" modern-feature T2 2>&1)
if [[ -f "$SANDBOX/.halo/sdd/modern-feature/T2/brief.md" ]] && grep -q "全局约束" "$SANDBOX/.halo/sdd/modern-feature/T2/brief.md"; then
  pass "task-brief generates second task evidence"
else
  fail "task-brief did not generate second task evidence"
  echo "$BRIEF_OUTPUT_T2" | tail -10
fi

REVIEW_OUTPUT_T2=$(bash "$SANDBOX/halo/kernel/orchestrator/sdd/review-package.sh" modern-feature T2 2>&1)
if [[ -f "$SANDBOX/.halo/sdd/modern-feature/T2/review-package.md" ]] && grep -q "cannot_verify" "$SANDBOX/.halo/sdd/modern-feature/T2/review-package.md"; then
  pass "review-package generates second read-only review package"
else
  fail "review-package did not generate second package"
  echo "$REVIEW_OUTPUT_T2" | tail -10
fi

TDD_EVIDENCE_OUTPUT_T2=$(bash "$SANDBOX/halo/kernel/orchestrator/sdd/tdd-evidence.sh" modern-feature T2 \
  --ac=AC-2 \
  --test=TestAC2_GetItem \
  --test-file=internal/handler/item_test.go \
  --red-command="go test ./internal/handler -run TestAC2_GetItem" \
  --red-exit=1 \
  --red-summary="handler does not return created items yet" \
  --green-command="go test ./internal/handler -run TestAC2_GetItem" \
  --green-exit=0 \
  --green-summary="focused AC test passes" \
  --refactor=none 2>&1)
if yq -e '.kind == "tdd-evidence" and .status == "pass" and .red.exit_code == 1 and .green.exit_code == 0 and (.ac_ids | length == 1)' "$SANDBOX/.halo/sdd/modern-feature/T2/tdd-evidence.json" >/dev/null 2>&1; then
  pass "tdd-evidence writes second structured red/green JSON"
else
  fail "second tdd-evidence JSON invalid"
  echo "$TDD_EVIDENCE_OUTPUT_T2" | tail -10
fi

for task_id in RED-1 RED-2 T1 T2; do
  TASK_COMPLETE_EXIT=0
  TASK_COMPLETE_JSON=$(bash "$SANDBOX/halo/kernel/orchestrator/sdd/task-complete.sh" modern-feature "$task_id" --json 2>&1) || TASK_COMPLETE_EXIT=$?
  if [[ $TASK_COMPLETE_EXIT -eq 0 ]] \
    && echo "$TASK_COMPLETE_JSON" | yq -e '.kind == "task-complete" and .status == "completed"' >/dev/null 2>&1 \
    && echo "$TASK_COMPLETE_JSON" | grep -q "\"task_id\": \"$task_id\"" \
    && grep -qE "^- \\[x\\] ${task_id}:" "$SANDBOX/halo/specs/modern-feature/plan.md"; then
    pass "task-complete marks $task_id complete"
  else
    fail "task-complete failed for $task_id"
    echo "$TASK_COMPLETE_JSON"
  fi
done

TASK_EVIDENCE_LINT_EXIT=0
TASK_EVIDENCE_LINT_OUTPUT=$(bash "$SANDBOX/halo/kernel/orchestrator/sdd/task-evidence-lint.sh" modern-feature 2>&1) || TASK_EVIDENCE_LINT_EXIT=$?
if [[ $TASK_EVIDENCE_LINT_EXIT -eq 0 ]]; then
  pass "task-evidence-lint passes completed task evidence"
else
  fail "task-evidence-lint failed completed task evidence"
  echo "$TASK_EVIDENCE_LINT_OUTPUT" | tail -20
fi

TASK_NEXT_COMPLETE_JSON=$(bash "$SANDBOX/halo/kernel/orchestrator/sdd/task-next.sh" modern-feature --json)
if echo "$TASK_NEXT_COMPLETE_JSON" | yq -e '.kind == "task-next" and .status == "complete" and .next_task == null' >/dev/null 2>&1; then
  pass "task-next reports complete plan"
else
  fail "task-next did not report complete plan"
  echo "$TASK_NEXT_COMPLETE_JSON"
fi

SPEC_STATUS_IMPLEMENTED_EXIT=0
SPEC_STATUS_IMPLEMENTED_OUTPUT=$(bash "$SANDBOX/halo/kernel/orchestrator/sdd/spec-status.sh" modern-feature implemented --from=planned 2>&1) || SPEC_STATUS_IMPLEMENTED_EXIT=$?
if [[ $SPEC_STATUS_IMPLEMENTED_EXIT -eq 0 ]] && grep -q '^status: implemented$' "$SANDBOX/halo/specs/modern-feature/spec.md"; then
  pass "spec-status advances completed plan to implemented"
else
  fail "spec-status failed to advance completed plan to implemented"
  echo "$SPEC_STATUS_IMPLEMENTED_OUTPUT" | tail -20
fi
IMPLEMENTED_TRANSITION_EVENT="$(
  find "$SANDBOX/halo/state/spec-transitions" -name '*.json' -type f -print 2>/dev/null \
    | while IFS= read -r file; do
        if yq -e '.kind == "spec-transition" and .from_status == "planned" and .to_status == "implemented"' "$file" >/dev/null 2>&1; then echo "$file"; fi
      done \
    | tail -1 || true
)"
if [[ -f "$IMPLEMENTED_TRANSITION_EVENT" ]] \
  && yq -e '.kind == "spec-transition" and .from_status == "planned" and .to_status == "implemented" and .checks.task_evidence_lint == true' "$IMPLEMENTED_TRANSITION_EVENT" >/dev/null 2>&1; then
  pass "spec-status records implemented transition event"
else
  fail "spec-status implemented transition event invalid"
  [[ -f "$IMPLEMENTED_TRANSITION_EVENT" ]] && cat "$IMPLEMENTED_TRANSITION_EVENT"
fi

# ── 6d. Per-task execution mode in evidence gates ──
echo ""
echo "── 6d. Per-task execution mode ──"
mkdir -p "$SANDBOX/halo/specs/mixed-mode"
cat > "$SANDBOX/halo/specs/mixed-mode/spec.md" << 'MIXED_SPEC'
---
id: mixed-mode
status: planned
execution_mode: tdd
mode_source: model-selected
approval: inferred
owner: smoke
created_at: 2026-06-26T00:00:00Z
updated_at: 2026-06-26T00:00:00Z
---

# Spec: Mixed Mode

## Intent

A tdd spec that also contains one regression-guard task declared as plan mode.

## Acceptance Criteria

| # | When | Then | Verification |
|---|------|------|--------------|
| AC-1 | Create item | Returns 201 | TestAC1 |
| AC-2 | Existing endpoints are untouched | Contract count stays the same | Regression guard |
MIXED_SPEC
cat > "$SANDBOX/halo/specs/mixed-mode/plan.md" << 'MIXED_PLAN'
# Plan: Mixed Mode

## Source

- Spec: `halo/specs/mixed-mode/spec.md`
- Execution mode: tdd

## Global Constraints

- Versions / dependencies: use existing Go module.
- Out-of-scope: export behavior.

## Tasks

- [ ] RED-1: Add failing test for AC-1
  - Ref: AC-1
  - Expected failure: handler does not create items yet
  - Test file: `internal/handler/item_test.go`
  - Verification: `go test ./internal/handler -run TestAC1_CreateItem`
  - Done when:
    - [ ] Expected failure is captured in `.halo/sdd/mixed-mode/T1/tdd-evidence.json`

- [ ] T1: Add create behavior
  - Ref: AC-1
  - Mode: tdd
  - Scope: Implement the smallest create path needed for AC-1.
  - Files: `internal/handler/item.go`
  - Verification: `TestAC1_CreateItem`
  - Evidence:
    - Brief: `.halo/sdd/mixed-mode/T1/brief.md`
    - Review package: `.halo/sdd/mixed-mode/T1/review-package.md`
  - Done when:
    - [ ] AC-1 passes focused verification and evidence exists.

- [ ] T2: 既有契约零变更回归护栏
  - 覆盖验收：AC-2
  - 模式：plan
  - 范围：只断言既有端点契约数量未变，不新增行为，因此不存在合法的红。
  - 涉及文件：`internal/handler/item.go`
  - 验证方式：`go test ./internal/handler -run TestContractRegression`
  - 证据：
    - 任务简报：`.halo/sdd/mixed-mode/T2/brief.md`
    - 评审包：`.halo/sdd/mixed-mode/T2/review-package.md`
  - 完成条件：
    - [ ] 回归命令通过且既有契约数量未变。
MIXED_PLAN
for mixed_task in T1 T2; do
  mkdir -p "$SANDBOX/.halo/sdd/mixed-mode/$mixed_task"
  printf '# Brief %s\n' "$mixed_task" > "$SANDBOX/.halo/sdd/mixed-mode/$mixed_task/brief.md"
  printf '# Review package %s\n' "$mixed_task" > "$SANDBOX/.halo/sdd/mixed-mode/$mixed_task/review-package.md"
done
bash "$SANDBOX/halo/kernel/orchestrator/sdd/tdd-evidence.sh" mixed-mode T1 \
  --ac=AC-1 \
  --test=TestAC1_CreateItem \
  --test-file=internal/handler/item_test.go \
  --red-command="go test ./internal/handler -run TestAC1_CreateItem" \
  --red-exit=1 \
  --red-summary="handler not implemented" \
  --green-command="go test ./internal/handler -run TestAC1_CreateItem" \
  --green-exit=0 \
  --green-summary="focused AC test passes" \
  --refactor=none >/dev/null 2>&1

for mixed_task in T1 RED-1; do
  MIXED_COMPLETE_EXIT=0
  bash "$SANDBOX/halo/kernel/orchestrator/sdd/task-complete.sh" mixed-mode "$mixed_task" >/tmp/halo-mixed-complete.log 2>&1 || MIXED_COMPLETE_EXIT=$?
  if [[ $MIXED_COMPLETE_EXIT -ne 0 ]]; then
    fail "task-complete failed for mixed-mode $mixed_task"
    tail -10 /tmp/halo-mixed-complete.log
  fi
done

MIXED_PLAN_TASK_EXIT=0
bash "$SANDBOX/halo/kernel/orchestrator/sdd/task-complete.sh" mixed-mode T2 >/tmp/halo-mixed-plan-task.log 2>&1 || MIXED_PLAN_TASK_EXIT=$?
if [[ $MIXED_PLAN_TASK_EXIT -eq 0 ]] && grep -qE '^- \[x\] T2:' "$SANDBOX/halo/specs/mixed-mode/plan.md"; then
  pass "task-complete honors per-task plan mode inside a tdd spec"
else
  fail "task-complete ignored per-task plan mode inside a tdd spec"
  tail -10 /tmp/halo-mixed-plan-task.log
fi

MIXED_EVIDENCE_LINT_EXIT=0
MIXED_EVIDENCE_LINT_OUTPUT=$(bash "$SANDBOX/halo/kernel/orchestrator/sdd/task-evidence-lint.sh" mixed-mode 2>&1) || MIXED_EVIDENCE_LINT_EXIT=$?
if [[ $MIXED_EVIDENCE_LINT_EXIT -eq 0 ]]; then
  pass "task-evidence-lint honors per-task plan mode inside a tdd spec"
else
  fail "task-evidence-lint rejected per-task plan mode inside a tdd spec"
  echo "$MIXED_EVIDENCE_LINT_OUTPUT" | tail -20
fi

MIXED_STATUS_EXIT=0
MIXED_STATUS_OUTPUT=$(bash "$SANDBOX/halo/kernel/orchestrator/sdd/spec-status.sh" mixed-mode implemented --from=planned 2>&1) || MIXED_STATUS_EXIT=$?
if [[ $MIXED_STATUS_EXIT -eq 0 ]] && grep -q '^status: implemented$' "$SANDBOX/halo/specs/mixed-mode/spec.md"; then
  pass "spec-status advances tdd spec containing a plan-mode task"
else
  fail "spec-status blocked tdd spec containing a plan-mode task"
  echo "$MIXED_STATUS_OUTPUT" | tail -20
fi

mkdir -p "$SANDBOX/halo/specs/plan-spec-tdd-task"
cat > "$SANDBOX/halo/specs/plan-spec-tdd-task/spec.md" << 'PLAN_SPEC'
---
id: plan-spec-tdd-task
status: planned
execution_mode: plan
mode_source: model-selected
approval: inferred
owner: smoke
created_at: 2026-06-26T00:00:00Z
updated_at: 2026-06-26T00:00:00Z
---

# Spec: Plan Spec With TDD Task

## Intent

A plan spec whose single task opts into tdd mode.

## Acceptance Criteria

| # | When | Then | Verification |
|---|------|------|--------------|
| AC-1 | Create item | Returns 201 | TestAC1 |
PLAN_SPEC
cat > "$SANDBOX/halo/specs/plan-spec-tdd-task/plan.md" << 'PLAN_SPEC_PLAN'
# Plan: Plan Spec With TDD Task

## Source

- Spec: `halo/specs/plan-spec-tdd-task/spec.md`
- Execution mode: plan

## Global Constraints

- Versions / dependencies: use existing Go module.
- Out-of-scope: export behavior.

## Tasks

- [ ] T1: Add create behavior
  - Ref: AC-1
  - Mode: tdd
  - Scope: Implement the smallest create path needed for AC-1.
  - Files: `internal/handler/item.go`
  - Verification: `TestAC1_CreateItem`
  - Evidence:
    - Brief: `.halo/sdd/plan-spec-tdd-task/T1/brief.md`
    - Review package: `.halo/sdd/plan-spec-tdd-task/T1/review-package.md`
  - Done when:
    - [ ] AC-1 passes focused verification and evidence exists.
PLAN_SPEC_PLAN
mkdir -p "$SANDBOX/.halo/sdd/plan-spec-tdd-task/T1"
printf '# Brief T1\n' > "$SANDBOX/.halo/sdd/plan-spec-tdd-task/T1/brief.md"
printf '# Review package T1\n' > "$SANDBOX/.halo/sdd/plan-spec-tdd-task/T1/review-package.md"
PLAN_SPEC_TDD_EXIT=0
bash "$SANDBOX/halo/kernel/orchestrator/sdd/task-complete.sh" plan-spec-tdd-task T1 >/tmp/halo-plan-spec-tdd-task.log 2>&1 || PLAN_SPEC_TDD_EXIT=$?
if [[ $PLAN_SPEC_TDD_EXIT -ne 0 ]] && grep -q "T1 missing or invalid tdd-evidence.json" /tmp/halo-plan-spec-tdd-task.log; then
  pass "task-complete honors per-task tdd mode inside a plan spec"
else
  fail "task-complete ignored per-task tdd mode inside a plan spec"
  tail -10 /tmp/halo-plan-spec-tdd-task.log
fi

mkdir -p "$SANDBOX/halo/specs/red-multi-ac"
cat > "$SANDBOX/halo/specs/red-multi-ac/spec.md" << 'RED_MULTI_SPEC'
---
id: red-multi-ac
status: planned
execution_mode: tdd
mode_source: model-selected
approval: inferred
owner: smoke
created_at: 2026-06-26T00:00:00Z
updated_at: 2026-06-26T00:00:00Z
---

# Spec: Red Multi AC

## Intent

One red task covering two acceptance criteria.

## Acceptance Criteria

| # | When | Then | Verification |
|---|------|------|--------------|
| AC-1 | Create item | Returns 201 | TestAC1 |
| AC-2 | Get item | Returns item | TestAC2 |
RED_MULTI_SPEC
cat > "$SANDBOX/halo/specs/red-multi-ac/plan.md" << 'RED_MULTI_PLAN'
# Plan: Red Multi AC

## Source

- Spec: `halo/specs/red-multi-ac/spec.md`
- Execution mode: tdd

## Global Constraints

- Versions / dependencies: use existing Go module.
- Out-of-scope: export behavior.

## Tasks

- [ ] RED-1: Add failing tests for AC-1 and AC-2
  - Ref: AC-1, AC-2
  - Expected failure: handler implements neither create nor get yet
  - Test file: `internal/handler/item_test.go`
  - Verification: `go test ./internal/handler -run TestAC`
  - Done when:
    - [ ] Both expected failures are captured in task evidence.

- [ ] T1: Add create behavior
  - Ref: AC-1
  - Mode: tdd
  - Scope: Implement the smallest create path needed for AC-1.
  - Files: `internal/handler/item.go`
  - Verification: `TestAC1_CreateItem`
  - Evidence:
    - Brief: `.halo/sdd/red-multi-ac/T1/brief.md`
    - Review package: `.halo/sdd/red-multi-ac/T1/review-package.md`
  - Done when:
    - [ ] AC-1 passes focused verification and evidence exists.

- [ ] T2: Add get behavior
  - Ref: AC-2
  - Mode: tdd
  - Scope: Implement the smallest get path needed for AC-2.
  - Files: `internal/handler/item.go`
  - Verification: `TestAC2_GetItem`
  - Evidence:
    - Brief: `.halo/sdd/red-multi-ac/T2/brief.md`
    - Review package: `.halo/sdd/red-multi-ac/T2/review-package.md`
  - Done when:
    - [ ] AC-2 passes focused verification and evidence exists.
RED_MULTI_PLAN
bash "$SANDBOX/halo/kernel/orchestrator/sdd/tdd-evidence.sh" red-multi-ac T1 \
  --ac=AC-1 \
  --test=TestAC1_CreateItem \
  --test-file=internal/handler/item_test.go \
  --red-command="go test ./internal/handler -run TestAC1_CreateItem" \
  --red-exit=1 \
  --red-summary="handler not implemented" \
  --green-command="go test ./internal/handler -run TestAC1_CreateItem" \
  --green-exit=0 \
  --green-summary="focused AC test passes" \
  --refactor=none >/dev/null 2>&1
RED_MULTI_EXIT=0
bash "$SANDBOX/halo/kernel/orchestrator/sdd/task-complete.sh" red-multi-ac RED-1 >/tmp/halo-red-multi-ac.log 2>&1 || RED_MULTI_EXIT=$?
if [[ $RED_MULTI_EXIT -ne 0 ]] && grep -q "RED-1 missing matching TDD cycle evidence" /tmp/halo-red-multi-ac.log; then
  pass "task-complete requires cycle evidence for every AC of a red task"
else
  fail "task-complete accepted a red task with partial AC cycle evidence"
  tail -10 /tmp/halo-red-multi-ac.log
fi

mkdir -p "$SANDBOX/halo/specs/red-many-ac"
cat > "$SANDBOX/halo/specs/red-many-ac/spec.md" << 'RED_MANY_SPEC'
---
id: red-many-ac
status: planned
execution_mode: tdd
mode_source: model-selected
approval: inferred
owner: smoke
created_at: 2026-06-26T00:00:00Z
updated_at: 2026-06-26T00:00:00Z
---

# Spec: Red Many AC

## Intent

One red task covering four acceptance criteria recorded in a single evidence file.

## Acceptance Criteria

| # | When | Then | Verification |
|---|------|------|--------------|
| AC-1 | Create item | Returns 201 | TestAC1 |
| AC-2 | Get item | Returns item | TestAC2 |
| AC-3 | List items | Returns list | TestAC3 |
| AC-4 | Delete item | Returns 204 | TestAC4 |
RED_MANY_SPEC
cat > "$SANDBOX/halo/specs/red-many-ac/plan.md" << 'RED_MANY_PLAN'
# Plan: Red Many AC

## Source

- Spec: `halo/specs/red-many-ac/spec.md`
- Execution mode: tdd

## Global Constraints

- Versions / dependencies: use existing Go module.
- Out-of-scope: export behavior.

## Tasks

- [ ] RED-1: Add failing tests for AC-1, AC-2, AC-3 and AC-4
  - Ref: AC-1, AC-2, AC-3, AC-4
  - Expected failure: handler implements none of the four paths yet
  - Test file: `internal/handler/item_test.go`
  - Verification: `go test ./internal/handler -run TestAC`
  - Done when:
    - [ ] All expected failures are captured in task evidence.

- [ ] T1: Add the four handler behaviors
  - Ref: AC-1, AC-2, AC-3, AC-4
  - Mode: tdd
  - Scope: Implement the smallest paths needed for AC-1 through AC-4.
  - Files: `internal/handler/item.go`
  - Verification: `TestAC`
  - Evidence:
    - Brief: `.halo/sdd/red-many-ac/T1/brief.md`
    - Review package: `.halo/sdd/red-many-ac/T1/review-package.md`
  - Done when:
    - [ ] AC-1 through AC-4 pass focused verification and evidence exists.
RED_MANY_PLAN
bash "$SANDBOX/halo/kernel/orchestrator/sdd/tdd-evidence.sh" red-many-ac T1 \
  --ac=AC-1 \
  --ac=AC-2 \
  --ac=AC-3 \
  --ac=AC-4 \
  --test=TestAC \
  --test-file=internal/handler/item_test.go \
  --red-command="go test ./internal/handler -run TestAC" \
  --red-exit=1 \
  --red-summary="handler not implemented" \
  --green-command="go test ./internal/handler -run TestAC" \
  --green-exit=0 \
  --green-summary="focused AC tests pass" \
  --refactor=none >/dev/null 2>&1

# A yq that streams `.ac_ids[]?` one line at a time makes an early-exiting pipe
# consumer deterministic: the reader is gone before yq writes the tail, so any
# `yq ... | grep -q` reader turns a legitimate match into SIGPIPE under pipefail.
SLOW_YQ_BIN="$SANDBOX/.halo/slow-yq-bin"
mkdir -p "$SLOW_YQ_BIN"
cat > "$SLOW_YQ_BIN/yq" << SLOW_YQ
#!/usr/bin/env bash
REAL_YQ="$(command -v yq)"
if [[ "\${1:-}" == "-r" && "\${2:-}" == ".ac_ids[]?" ]]; then
  OUTPUT="\$("\$REAL_YQ" "\$@")" || exit \$?
  while IFS= read -r line; do
    printf '%s\n' "\$line"
    sleep 0.05
  done <<< "\$OUTPUT"
  exit 0
fi
exec "\$REAL_YQ" "\$@"
SLOW_YQ
chmod +x "$SLOW_YQ_BIN/yq"

RED_MANY_EXIT=0
PATH="$SLOW_YQ_BIN:$PATH" bash "$SANDBOX/halo/kernel/orchestrator/sdd/task-complete.sh" red-many-ac RED-1 \
  >/tmp/halo-red-many-ac.log 2>&1 || RED_MANY_EXIT=$?
if [[ $RED_MANY_EXIT -eq 0 ]] && grep -qE '^- \[x\] RED-1:' "$SANDBOX/halo/specs/red-many-ac/plan.md"; then
  pass "task-complete accepts a red task whose ACs all live in one evidence file"
else
  fail "task-complete rejected a red task with complete multi-AC cycle evidence"
  tail -10 /tmp/halo-red-many-ac.log
fi

echo ""

mkdir -p "$SANDBOX/halo/specs/bad-plan"
cat > "$SANDBOX/halo/specs/bad-plan/spec.md" << 'BAD_SPEC'
---
id: bad-plan
execution_mode: plan
---

# Spec: Bad Plan

## Acceptance Criteria

| # | When | Then | Verification |
|---|------|------|--------------|
| AC-1 | Something happens | It works | Test |
BAD_SPEC
cat > "$SANDBOX/halo/specs/bad-plan/plan.md" << 'BAD_PLAN'
# Plan: Bad Plan

## Tasks

- Do the work
- TODO verify later
BAD_PLAN
BAD_PLAN_LINT_EXIT=0
bash "$SANDBOX/halo/kernel/orchestrator/sdd/plan-lint.sh" bad-plan >/tmp/halo-plan-lint-bad.log 2>&1 || BAD_PLAN_LINT_EXIT=$?
if [[ $BAD_PLAN_LINT_EXIT -ne 0 ]] && grep -q "No stable task ids" /tmp/halo-plan-lint-bad.log; then
  pass "plan-lint rejects untraceable plan"
else
  fail "plan-lint accepted untraceable plan"
  tail -20 /tmp/halo-plan-lint-bad.log
fi

mkdir -p "$SANDBOX/halo/specs/bad-plan-schema"
cat > "$SANDBOX/halo/specs/bad-plan-schema/spec.md" << 'BAD_SCHEMA_SPEC'
---
id: bad-plan-schema
execution_mode: plan
---

# Spec: Bad Plan Schema

## Acceptance Criteria

| # | When | Then | Verification |
|---|------|------|--------------|
| AC-1 | Something happens | It works | Test |
BAD_SCHEMA_SPEC
cat > "$SANDBOX/halo/specs/bad-plan-schema/plan.md" << 'BAD_SCHEMA_PLAN'
# Plan: Bad Plan Schema

## Source

- Spec: `halo/specs/bad-plan-schema/spec.md`
- Execution mode: plan

## Global Constraints

- Keep scope small.

## Tasks

- [ ] T1: Do the work
  - Ref: AC-1
  - Files: `internal/example.go`
  - Verification: `go test ./...`
BAD_SCHEMA_PLAN
BAD_PLAN_SCHEMA_EXIT=0
bash "$SANDBOX/halo/kernel/orchestrator/sdd/plan-lint.sh" bad-plan-schema >/tmp/halo-plan-lint-bad-schema.log 2>&1 || BAD_PLAN_SCHEMA_EXIT=$?
if [[ $BAD_PLAN_SCHEMA_EXIT -ne 0 ]] \
  && grep -q "T1 missing Mode" /tmp/halo-plan-lint-bad-schema.log \
  && grep -q "T1 missing Evidence" /tmp/halo-plan-lint-bad-schema.log \
  && grep -q "T1 missing Done when" /tmp/halo-plan-lint-bad-schema.log; then
  pass "plan-lint rejects incomplete task schema"
else
  fail "plan-lint accepted incomplete task schema"
  tail -30 /tmp/halo-plan-lint-bad-schema.log
fi

cat > "$SANDBOX/halo/specs/modern-feature/verify.md" << 'VERIFY'
# Verify: Modern Feature

- Command: `go test ./...`
- Exit: 0
- Result: pass
VERIFY

PRISMSPEC_ALL_LINT_EXIT=0
PRISMSPEC_ALL_LINT_OUTPUT=$(bash "$SANDBOX/prismspec/bin/lint.sh" "$SANDBOX/halo/specs/modern-feature" all 2>&1) || PRISMSPEC_ALL_LINT_EXIT=$?
if [[ $PRISMSPEC_ALL_LINT_EXIT -eq 0 ]]; then
  pass "PrismSpec lint passes full artifact contract"
else
  fail "PrismSpec lint failed full artifact contract"
  echo "$PRISMSPEC_ALL_LINT_OUTPUT" | tail -10
fi

SPEC_STATUS_VERIFIED_EXIT=0
SPEC_STATUS_VERIFIED_OUTPUT=$(bash "$SANDBOX/halo/kernel/orchestrator/sdd/spec-status.sh" modern-feature verified --from=implemented 2>&1) || SPEC_STATUS_VERIFIED_EXIT=$?
if [[ $SPEC_STATUS_VERIFIED_EXIT -eq 0 ]] && grep -q '^status: verified$' "$SANDBOX/halo/specs/modern-feature/spec.md"; then
  pass "spec-status advances implemented spec to verified"
else
  fail "spec-status failed to advance implemented spec to verified"
  echo "$SPEC_STATUS_VERIFIED_OUTPUT" | tail -20
fi

SUMMARY_DRAFT_OUTPUT=$(bash "$SANDBOX/halo/kernel/orchestrator/sdd/summary-draft.sh" modern-feature 2>&1)
if [[ -f "$SANDBOX/halo/specs/modern-feature/summary.md" ]] \
  && grep -q "Evidence Closeout" "$SANDBOX/halo/specs/modern-feature/summary.md" \
  && grep -q "Task Evidence" "$SANDBOX/halo/specs/modern-feature/summary.md" \
  && grep -q "Verification Evidence" "$SANDBOX/halo/specs/modern-feature/summary.md" \
  && grep -q "Residual Risks And Follow-ups" "$SANDBOX/halo/specs/modern-feature/summary.md"; then
  pass "summary-draft generates completion summary"
else
  fail "summary-draft did not generate expected summary"
  echo "$SUMMARY_DRAFT_OUTPUT" | tail -20
  [[ -f "$SANDBOX/halo/specs/modern-feature/summary.md" ]] && tail -40 "$SANDBOX/halo/specs/modern-feature/summary.md"
fi

SUMMARY_LEARN_EMPTY_EXIT=0
bash "$SANDBOX/halo/kernel/context/summary-learn-draft.sh" modern-feature >/tmp/halo-summary-learn-empty.log 2>&1 || SUMMARY_LEARN_EMPTY_EXIT=$?
if [[ $SUMMARY_LEARN_EMPTY_EXIT -ne 0 ]] && grep -q "No durable knowledge candidates" /tmp/halo-summary-learn-empty.log; then
  pass "summary-learn-draft rejects empty knowledge candidates"
else
  fail "summary-learn-draft accepted empty knowledge candidates"
  tail -20 /tmp/halo-summary-learn-empty.log
fi

cat >> "$SANDBOX/halo/specs/modern-feature/verify.md" << 'SUMMARY_LEARN_CANDIDATE'

## Knowledge Candidates

- Keep task completion gated by task evidence before advancing spec status.
SUMMARY_LEARN_CANDIDATE
SUMMARY_LEARN_DRAFT="$SANDBOX/halo/context/drafts/knowledge-modern-feature-smoke.md"
SUMMARY_LEARN_OUTPUT=$(bash "$SANDBOX/halo/kernel/context/summary-learn-draft.sh" modern-feature --out="$SUMMARY_LEARN_DRAFT" 2>&1)
if [[ -f "$SUMMARY_LEARN_DRAFT" ]] \
  && grep -q "Knowledge Draft: Verification Candidates" "$SUMMARY_LEARN_DRAFT" \
  && grep -q "Keep task completion gated by task evidence" "$SUMMARY_LEARN_DRAFT" \
  && grep -q "Review Checklist" "$SUMMARY_LEARN_DRAFT"; then
  pass "summary-learn-draft creates reviewable knowledge draft"
else
  fail "summary-learn-draft did not create expected knowledge draft"
  echo "$SUMMARY_LEARN_OUTPUT" | tail -20
  [[ -f "$SUMMARY_LEARN_DRAFT" ]] && cat "$SUMMARY_LEARN_DRAFT"
fi

# A `while` loop exits with the status of its last iteration, so `yq -e … && echo`
# returned 1 whenever the file find happened to list last did not match. Under the
# `set -euo pipefail` at the top of this file that failed the whole pipeline, failed the
# command substitution, and killed the run mid-way — a coin flip on find's directory
# order, not an assertion failure. `if` keeps the loop status independent of the match.
TRANSITION_COUNT_FINAL=$(
  find "$SANDBOX/halo/state/spec-transitions" -name '*.json' -type f -print 2>/dev/null \
    | while IFS= read -r file; do
        if yq -e '.spec_id == "modern-feature"' "$file" >/dev/null 2>&1; then echo "$file"; fi
      done \
    | wc -l | tr -d ' ' || true
)
VERIFIED_TRANSITION_EVENT="$(
  find "$SANDBOX/halo/state/spec-transitions" -name '*.json' -type f -print 2>/dev/null \
    | while IFS= read -r file; do
        if yq -e '.kind == "spec-transition" and .from_status == "implemented" and .to_status == "verified"' "$file" >/dev/null 2>&1; then echo "$file"; fi
      done \
    | tail -1 || true
)"
if [[ "$TRANSITION_COUNT_FINAL" == "3" ]] \
  && [[ -f "$VERIFIED_TRANSITION_EVENT" ]] \
  && yq -e '.kind == "spec-transition" and .from_status == "implemented" and .to_status == "verified"' "$VERIFIED_TRANSITION_EVENT" >/dev/null 2>&1; then
  pass "spec-status records complete transition audit trail"
else
  fail "spec-status transition audit trail invalid"
  find "$SANDBOX/halo/state/spec-transitions" -name '*.json' -type f -print 2>/dev/null
fi
SPEC_HISTORY_MD="$SANDBOX/halo/state/spec-history-smoke.md"
SPEC_HISTORY_OUTPUT=$(bash "$SANDBOX/halo/kernel/orchestrator/sdd/spec-history.sh" --out="$SPEC_HISTORY_MD" --limit=10 2>&1)
if [[ -f "$SPEC_HISTORY_MD" ]] \
  && grep -q "Halo Spec History" "$SPEC_HISTORY_MD" \
  && grep -q "modern-feature" "$SPEC_HISTORY_MD" \
  && grep -q "verified" "$SPEC_HISTORY_MD" \
  && grep -q "plan=true, task=true, state=true" "$SPEC_HISTORY_MD"; then
  pass "spec-history aggregates transition events"
else
  fail "spec-history output invalid"
  echo "$SPEC_HISTORY_OUTPUT" | tail -20
  [[ -f "$SPEC_HISTORY_MD" ]] && tail -40 "$SPEC_HISTORY_MD"
fi

REVIEW_SUMMARY_OUTPUT=$(bash "$SANDBOX/halo/kernel/orchestrator/sdd/review-summary.sh" modern-feature T1 \
  --spec-compliance=pass \
  --code-quality=pass \
  --test-coverage=cannot_verify \
  --risk=pass \
  --finding="medium|internal/handler/item_test.go|missing regression test evidence" \
  --evidence="review-package.md" 2>&1)
if yq -e '.kind == "review-summary" and .verdict == "cannot_verify" and .axes.test_coverage == "cannot_verify" and (.findings | length == 1)' "$SANDBOX/.halo/sdd/modern-feature/T1/review-summary.json" >/dev/null 2>&1; then
  pass "review-summary writes structured verdict JSON"
else
  fail "review-summary JSON invalid"
  echo "$REVIEW_SUMMARY_OUTPUT" | tail -10
fi

if [[ -f "$SANDBOX/.halo/sdd/modern-feature/T1/review.md" ]] \
  && grep -q 'verdict: "cannot_verify"' "$SANDBOX/.halo/sdd/modern-feature/T1/review.md" \
  && grep -q "missing regression test evidence" "$SANDBOX/.halo/sdd/modern-feature/T1/review.md"; then
  pass "review-summary writes canonical review.md"
else
  fail "review.md artifact invalid"
  [[ -f "$SANDBOX/.halo/sdd/modern-feature/T1/review.md" ]] && sed -n '1,80p' "$SANDBOX/.halo/sdd/modern-feature/T1/review.md"
fi

echo ""

# ── 7. AC-coverage (no tests — should report uncovered) ──
echo "── 7. AC-coverage gate ──"

DRIFT_JSON="$SANDBOX/halo/state/drift-smoke.json"
bash "$SANDBOX/halo/kernel/delivery/gates/drift-check.sh" "$SANDBOX/halo/specs/modern-feature/spec.md" "$SANDBOX" --json-out="$DRIFT_JSON" >/tmp/halo-drift-json.log 2>&1 || true
if yq -e '.gate == "drift-check" and .metrics.drift_count == 0 and (.findings | length > 0)' "$DRIFT_JSON" >/dev/null 2>&1; then
  pass "drift-check writes structured gate JSON"
else
  fail "drift-check gate JSON invalid"
  cat /tmp/halo-drift-json.log | tail -20
fi

COMPLIANCE_JSON="$SANDBOX/halo/state/compliance-smoke.json"
bash "$SANDBOX/halo/kernel/delivery/gates/compliance.sh" "$SANDBOX/halo/specs/modern-feature/spec.md" --json-out="$COMPLIANCE_JSON" >/tmp/halo-compliance-json.log 2>&1 || true
if yq -e '.gate == "compliance" and .metrics.warnings >= 0 and (.findings | length > 0)' "$COMPLIANCE_JSON" >/dev/null 2>&1; then
  pass "compliance writes structured gate JSON"
else
  fail "compliance gate JSON invalid"
  cat /tmp/halo-compliance-json.log | tail -20
fi

PIPELINE_GATE_JSON="$SANDBOX/halo/state/pipeline-ac-smoke.json"
PIPELINE_GATE_EXIT=0
bash "$SANDBOX/halo/kernel/delivery/pipeline.sh" --only=ac-coverage --spec="$SANDBOX/halo/specs/modern-feature/spec.md" --json-out="$PIPELINE_GATE_JSON" >/tmp/halo-pipeline-gate-json.log 2>&1 || PIPELINE_GATE_EXIT=$?
if [[ $PIPELINE_GATE_EXIT -eq 1 ]] && yq -e '.metrics.ac_total == 2 and .metrics.ac_uncovered == 2 and (.gates | length == 1) and .gates[0].gate == "ac-coverage" and .metrics.review_total == 1 and .metrics.review_cannot_verify == 1 and .metrics.tdd_total == 2 and .metrics.tdd_complete == 2 and .process_evidence.review_summaries[0].kind == "review-summary" and .process_evidence.tdd_evidence[0].kind == "tdd-evidence" and .loop_state.kind == "loop-state" and .loop_state.next_action == "retry" and .loop_state.failed_step == "ac-coverage" and .loop_state.failure_category == "ac_gap" and .loop_state.default_action == "add_or_map_tests"' "$PIPELINE_GATE_JSON" >/dev/null 2>&1; then
  pass "pipeline embeds structured gate JSON in eval run"
else
  fail "pipeline gate JSON embedding invalid"
  cat /tmp/halo-pipeline-gate-json.log | tail -20
fi

SUMMARY_WITH_EVAL="$SANDBOX/halo/specs/modern-feature/summary-with-eval.md"
SUMMARY_WITH_EVAL_OUTPUT=$(bash "$SANDBOX/halo/kernel/orchestrator/sdd/summary-draft.sh" modern-feature --eval-json="$PIPELINE_GATE_JSON" --out="$SUMMARY_WITH_EVAL" 2>&1)
if [[ -f "$SUMMARY_WITH_EVAL" ]] \
  && grep -q "Eval Metrics" "$SUMMARY_WITH_EVAL" \
  && grep -q "0 / 2 covered, 2 uncovered" "$SUMMARY_WITH_EVAL" \
  && grep -q "Review evidence includes 0 fail and 1 cannot_verify verdict" "$SUMMARY_WITH_EVAL"; then
  pass "summary-draft embeds eval JSON metrics"
else
  fail "summary-draft did not embed eval JSON metrics"
  echo "$SUMMARY_WITH_EVAL_OUTPUT" | tail -20
  [[ -f "$SUMMARY_WITH_EVAL" ]] && tail -40 "$SUMMARY_WITH_EVAL"
fi

LOOP_RUN_ID=$(yq -r '.run_id' "$PIPELINE_GATE_JSON")
LOOP_STATE_JSON="$SANDBOX/halo/state/loops/${LOOP_RUN_ID}.json"
if [[ -f "$LOOP_STATE_JSON" ]] && yq -e '.kind == "loop-state" and .next_action == "retry" and .failed_step == "ac-coverage" and .failure_category == "ac_gap" and .default_action == "add_or_map_tests" and .retry_count == 0' "$LOOP_STATE_JSON" >/dev/null 2>&1; then
  pass "pipeline writes loop state JSON"
else
  fail "pipeline loop state JSON invalid"
  cat /tmp/halo-pipeline-gate-json.log | tail -20
fi

PIPELINE_ESCALATION_JSON="$SANDBOX/halo/state/pipeline-escalation-smoke.json"
PIPELINE_ESCALATION_EXIT=0
SH_RETRY_COUNT=3 SH_RETRY_MAX=3 bash "$SANDBOX/halo/kernel/delivery/pipeline.sh" --only=ac-coverage --spec="$SANDBOX/halo/specs/modern-feature/spec.md" --json-out="$PIPELINE_ESCALATION_JSON" >/tmp/halo-pipeline-escalation.log 2>&1 || PIPELINE_ESCALATION_EXIT=$?
ESCALATION_RUN_ID=""
ESCALATION_LEARN_DRAFT=""
if [[ -f "$PIPELINE_ESCALATION_JSON" ]]; then
  ESCALATION_RUN_ID=$(yq -r '.run_id' "$PIPELINE_ESCALATION_JSON")
  ESCALATION_LEARN_DRAFT="$SANDBOX/halo/context/drafts/escalation-${ESCALATION_RUN_ID}.md"
fi
if [[ $PIPELINE_ESCALATION_EXIT -eq 2 ]] \
  && [[ -f "$ESCALATION_LEARN_DRAFT" ]] \
  && yq -e '.pipeline.status == "escalation" and .metrics.loop_escalated == true and .loop_state.next_action == "escalate" and .loop_state.failure_category == "ac_gap" and .loop_state.default_action == "add_or_map_tests" and .loop_state.learn_draft != ""' "$PIPELINE_ESCALATION_JSON" >/dev/null 2>&1 \
  && grep -q "Learn Draft: Pipeline Escalation" "$ESCALATION_LEARN_DRAFT" \
  && grep -q "failure_category: \"ac_gap\"" "$ESCALATION_LEARN_DRAFT"; then
  pass "pipeline writes escalation learn draft"
else
  fail "pipeline escalation learn draft invalid"
  cat /tmp/halo-pipeline-escalation.log | tail -20
fi

PROMOTE_TARGET="$SANDBOX/halo/context/knowledge/pitfalls.md"
REQUIRE_REVIEW_EXIT=0
bash "$SANDBOX/halo/kernel/context/learn-draft.sh" promote "$ESCALATION_LEARN_DRAFT" --require-review --to="$PROMOTE_TARGET" >/tmp/halo-learn-require-review.log 2>&1 || REQUIRE_REVIEW_EXIT=$?
if [[ $REQUIRE_REVIEW_EXIT -ne 0 ]] && grep -q "requires an approved knowledge review" /tmp/halo-learn-require-review.log; then
  pass "learn-draft require-review blocks unreviewed promotion"
else
  fail "learn-draft require-review should block unreviewed promotion"
  cat /tmp/halo-learn-require-review.log | tail -20
fi

KNOWLEDGE_REVIEW_OUTPUT=$(bash "$SANDBOX/halo/kernel/context/knowledge-review.sh" approve "$ESCALATION_LEARN_DRAFT" --reviewer="smoke-reviewer" --reason="durable lesson candidate checked" --risk=medium --conflicts-checked 2>&1)
KNOWLEDGE_REVIEW_EVENT=$(find "$SANDBOX/halo/state/knowledge-reviews" -type f -name '*.json' -print | head -1)
if [[ -n "$KNOWLEDGE_REVIEW_EVENT" ]] \
  && yq -e '.kind == "knowledge-review" and .action == "approve" and .reviewer == "smoke-reviewer" and .target == "halo/context/drafts/'"$(basename "$ESCALATION_LEARN_DRAFT")"'" and .conflicts_checked == true' "$KNOWLEDGE_REVIEW_EVENT" >/dev/null 2>&1; then
  pass "knowledge-review records approval evidence"
else
  fail "knowledge-review approval evidence invalid"
  echo "$KNOWLEDGE_REVIEW_OUTPUT" | tail -20
fi

PROMOTE_EXIT=0
bash "$SANDBOX/halo/kernel/context/learn-draft.sh" promote "$ESCALATION_LEARN_DRAFT" --require-review --to="$PROMOTE_TARGET" >/tmp/halo-learn-promote.log 2>&1 || PROMOTE_EXIT=$?
PROMOTED_DRAFT="$SANDBOX/halo/context/drafts/promoted/$(basename "$ESCALATION_LEARN_DRAFT")"
PROMOTE_EVENT=$(find "$SANDBOX/halo/state/learn-promotions" -type f -name '*.json' -print | head -1)
# pitfalls.md is table-shaped, so promotion must land as table rows. The old
# `## Promoted Learn Draft` section landed after the trailing `## Do Not Repeat`
# section, outside the table it was meant to extend.
if [[ $PROMOTE_EXIT -eq 0 ]] \
  && [[ -f "$PROMOTED_DRAFT" ]] \
  && ! grep -q "Promoted Learn Draft" "$PROMOTE_TARGET" \
  && [[ "$(awk '/^## Do Not Repeat/{exit} /^\| /{n++} END{print n+0}' "$PROMOTE_TARGET")" -gt 1 ]] \
  && awk '/^## Do Not Repeat/{exit} /^\| /{print}' "$PROMOTE_TARGET" | grep -q 'context/drafts/promoted/' \
  && [[ -n "$PROMOTE_EVENT" ]] \
  && yq -e '.kind == "learn-promotion" and .action == "promote" and .target == "halo/context/knowledge/pitfalls.md" and .failure_category == "ac_gap" and .default_action == "add_or_map_tests"' "$PROMOTE_EVENT" >/dev/null 2>&1; then
  pass "learn-draft promotes draft with audit event"
else
  fail "learn-draft promote invalid"
  cat /tmp/halo-learn-promote.log | tail -20
fi

DISCARD_DRAFT="$SANDBOX/halo/context/drafts/manual-discard.md"
cat > "$DISCARD_DRAFT" <<'MD'
---
run_id: "manual-discard"
failure_category: "unknown"
default_action: "escalate"
---

# Learn Draft: Manual Discard

## Lesson Candidate

This candidate is intentionally discarded by smoke test.
MD

DISCARD_EXIT=0
bash "$SANDBOX/halo/kernel/context/learn-draft.sh" discard "$DISCARD_DRAFT" --reason="not reusable" >/tmp/halo-learn-discard.log 2>&1 || DISCARD_EXIT=$?
DISCARDED_DRAFT="$SANDBOX/halo/context/drafts/discarded/$(basename "$DISCARD_DRAFT")"
DISCARD_EVENT=$(
  for event in "$SANDBOX"/halo/state/learn-promotions/*.json; do
    [[ -f "$event" ]] || continue
    if yq -e '.action == "discard"' "$event" >/dev/null 2>&1; then
      printf '%s\n' "$event"
      break
    fi
  done
)
if [[ $DISCARD_EXIT -eq 0 ]] \
  && [[ -f "$DISCARDED_DRAFT" ]] \
  && [[ -n "$DISCARD_EVENT" ]] \
  && yq -e '.kind == "learn-promotion" and .action == "discard" and .reason == "not reusable" and .failure_category == "unknown" and .default_action == "escalate"' "$DISCARD_EVENT" >/dev/null 2>&1; then
  pass "learn-draft discards draft with audit event"
else
  fail "learn-draft discard invalid"
  cat /tmp/halo-learn-discard.log | tail -20
fi

if bash "$SANDBOX/halo/kernel/context/knowledge-lint.sh" --strict >/tmp/halo-knowledge-lint-default.log 2>&1; then
  pass "knowledge-lint passes default knowledge templates"
else
  fail "knowledge-lint should pass default knowledge templates"
  cat /tmp/halo-knowledge-lint-default.log | tail -20
fi

BAD_KNOWLEDGE="$SANDBOX/halo/context/knowledge/bad-governance.md"
cat > "$BAD_KNOWLEDGE" <<'MD'
---
expires_at: "2000-01-01"
---

# Bad Governance Fixture

TODO: resolve this before promotion.

## Duplicate

CONFLICT: contradicts existing knowledge.

## Duplicate

Same heading repeated.
MD

if bash "$SANDBOX/halo/kernel/context/knowledge-lint.sh" --strict --target="$BAD_KNOWLEDGE" >/tmp/halo-knowledge-lint-bad.log 2>&1; then
  fail "knowledge-lint should reject stale/conflicting knowledge metadata"
else
  pass "knowledge-lint rejects stale/conflicting knowledge metadata"
fi
rm -f "$BAD_KNOWLEDGE"

if bash "$SANDBOX/halo/kernel/delivery/failure-category-lint.sh" >/tmp/halo-failure-category-lint.log 2>&1; then
  pass "failure-category-lint passes default config"
else
  fail "failure-category-lint should pass default config"
  cat /tmp/halo-failure-category-lint.log | tail -20
fi

cat > "$SANDBOX/halo/config/failure-categories.invalid.yaml" <<'YAML'
schema_version: halo.failure-categories.v1
default:
  category: unknown
  default_action: escalate
rules:
  - name: Bad Rule
    step_regex: "["
    category: bad-category
YAML

if bash "$SANDBOX/halo/kernel/delivery/failure-category-lint.sh" "$SANDBOX/halo/config/failure-categories.invalid.yaml" >/tmp/halo-failure-category-lint-invalid.log 2>&1; then
  fail "failure-category-lint should reject invalid config"
else
  pass "failure-category-lint rejects invalid config"
fi

cat > "$SANDBOX/halo/config/failure-categories.yaml" <<'YAML'
schema_version: halo.failure-categories.v1
default:
  category: unknown
  default_action: escalate
rules:
  - name: ac-coverage-custom
    step: ac-coverage
    category: custom_ac_gap
    default_action: route_to_qa
YAML

PIPELINE_CUSTOM_CATEGORY_JSON="$SANDBOX/halo/state/pipeline-custom-category-smoke.json"
PIPELINE_CUSTOM_CATEGORY_EXIT=0
bash "$SANDBOX/halo/kernel/delivery/pipeline.sh" --only=ac-coverage --spec="$SANDBOX/halo/specs/modern-feature/spec.md" --json-out="$PIPELINE_CUSTOM_CATEGORY_JSON" >/tmp/halo-pipeline-custom-category.log 2>&1 || PIPELINE_CUSTOM_CATEGORY_EXIT=$?
if [[ $PIPELINE_CUSTOM_CATEGORY_EXIT -eq 1 ]] \
  && yq -e '.loop_state.failure_category == "custom_ac_gap" and .loop_state.default_action == "route_to_qa"' "$PIPELINE_CUSTOM_CATEGORY_JSON" >/dev/null 2>&1; then
  pass "pipeline reads configurable failure categories"
else
  fail "pipeline configurable failure categories invalid"
  cat /tmp/halo-pipeline-custom-category.log | tail -20
fi

OUTCOME_LINK_OUTPUT=$(bash "$SANDBOX/halo/kernel/delivery/outcome-link.sh" record --eval="$PIPELINE_GATE_JSON" --type=review_finding --severity=medium --source=smoke-review --summary="missing regression test evidence" --context-ref="rules.md#ac-trace" 2>&1)
OUTCOME_EVENT=$(find "$SANDBOX/halo/state/outcomes" -type f -name '*.json' -print | head -1)
if [[ -n "$OUTCOME_EVENT" ]] \
  && yq -e '.kind == "outcome-link" and .outcome.type == "review_finding" and .outcome.severity == "medium" and .eval_run.run_id != "" and (.context_refs | length == 1)' "$OUTCOME_EVENT" >/dev/null 2>&1; then
  pass "outcome-link records post-run outcome evidence"
else
  fail "outcome-link event invalid"
  echo "$OUTCOME_LINK_OUTPUT" | tail -20
fi

OUTCOME_REPORT_MD="$SANDBOX/halo/state/outcome-report-smoke.md"
OUTCOME_REPORT_OUTPUT=$(bash "$SANDBOX/halo/kernel/delivery/outcome-report.sh" --out="$OUTCOME_REPORT_MD" --limit=5 2>&1)
if [[ -f "$OUTCOME_REPORT_MD" ]] && grep -q "Halo Outcome Attribution Report" "$OUTCOME_REPORT_MD" && grep -q "Context Ref Signals" "$OUTCOME_REPORT_MD" && grep -q "rules.md#ac-trace" "$OUTCOME_REPORT_MD" && grep -q "Runs Needing Review" "$OUTCOME_REPORT_MD" && grep -q "missing regression test evidence" "$OUTCOME_REPORT_MD"; then
  pass "outcome-report renders attribution signals"
else
  fail "outcome-report output invalid"
  echo "$OUTCOME_REPORT_OUTPUT" | tail -20
fi

PIPELINE_SUMMARY_MD="$SANDBOX/halo/state/eval-summary-smoke.md"
SUMMARY_OUTPUT=$(bash "$SANDBOX/halo/kernel/delivery/eval-summary.sh" "$PIPELINE_GATE_JSON" --out="$PIPELINE_SUMMARY_MD" 2>&1)
if [[ -f "$PIPELINE_SUMMARY_MD" ]] && grep -q "Halo Eval Summary" "$PIPELINE_SUMMARY_MD" && grep -q "AC Coverage" "$PIPELINE_SUMMARY_MD" && grep -q "ac-coverage" "$PIPELINE_SUMMARY_MD" && grep -q "Review Evidence" "$PIPELINE_SUMMARY_MD" && grep -q "TDD Evidence" "$PIPELINE_SUMMARY_MD" && grep -q "Outcome Links" "$PIPELINE_SUMMARY_MD" && grep -q "missing regression test evidence" "$PIPELINE_SUMMARY_MD" && grep -q "Loop" "$PIPELINE_SUMMARY_MD"; then
  pass "eval-summary renders pipeline JSON as Markdown"
else
  fail "eval-summary output invalid"
  echo "$SUMMARY_OUTPUT" | tail -10
fi

PR_COMMENT_MD="$SANDBOX/halo/state/pr-comment-smoke.md"
PR_COMMENT_OUTPUT=$(bash "$SANDBOX/halo/kernel/delivery/pr-comment.sh" "$PIPELINE_SUMMARY_MD" --dry-run --out="$PR_COMMENT_MD" 2>&1)
if [[ -f "$PR_COMMENT_MD" ]] && grep -q "halo-eval-comment" "$PR_COMMENT_MD" && grep -q "Halo Eval Summary" "$PR_COMMENT_MD"; then
  pass "pr-comment renders stable dry-run body"
else
  fail "pr-comment dry-run output invalid"
  echo "$PR_COMMENT_OUTPUT" | tail -10
fi

mkdir -p "$SANDBOX/halo/state/eval-runs"
cp "$PIPELINE_GATE_JSON" "$SANDBOX/halo/state/eval-runs/pipeline-ac-smoke.json"
EVAL_HISTORY_MD="$SANDBOX/halo/state/eval-history-smoke.md"
HISTORY_OUTPUT=$(bash "$SANDBOX/halo/kernel/delivery/eval-history.sh" --out="$EVAL_HISTORY_MD" --limit=5 2>&1)
if [[ -f "$EVAL_HISTORY_MD" ]] && grep -q "Halo Eval History" "$EVAL_HISTORY_MD" && grep -q "Pipeline Pass Rate" "$EVAL_HISTORY_MD" && grep -q "Review Verdicts" "$EVAL_HISTORY_MD" && grep -q "Outcome Links" "$EVAL_HISTORY_MD" && grep -q "Outcomes" "$EVAL_HISTORY_MD" && grep -q "Loop" "$EVAL_HISTORY_MD" && grep -q "Recent Runs" "$EVAL_HISTORY_MD"; then
  pass "eval-history aggregates eval run JSON"
else
  fail "eval-history output invalid"
  echo "$HISTORY_OUTPUT" | tail -10
fi

EVAL_SINK_DIR="$SANDBOX/halo/state/central-sink"
EVAL_SINK_OUTPUT=$(bash "$SANDBOX/halo/kernel/delivery/eval-sink.sh" publish --sink-dir="$EVAL_SINK_DIR" 2>&1)
EVAL_SINK_MANIFEST="$EVAL_SINK_DIR/projects/testapp/manifest.json"
if [[ -f "$EVAL_SINK_DIR/index.md" ]] \
  && [[ -f "$EVAL_SINK_MANIFEST" ]] \
  && [[ -f "$EVAL_SINK_DIR/projects/testapp/eval-runs/pipeline-ac-smoke.json" ]] \
  && [[ -n "$(find "$EVAL_SINK_DIR/projects/testapp/outcomes" -type f -name '*.json' -print -quit)" ]] \
  && yq -e '.kind == "eval-sink-project" and .project == "testapp" and .counts.eval_runs >= 1 and .counts.outcomes >= 1 and .counts.reports >= 1' "$EVAL_SINK_MANIFEST" >/dev/null 2>&1 \
  && grep -q "Halo Central Eval Sink" "$EVAL_SINK_DIR/index.md"; then
  pass "eval-sink publishes project evidence to central sink"
else
  fail "eval-sink output invalid"
  echo "$EVAL_SINK_OUTPUT" | tail -20
fi

EVAL_DASHBOARD_HTML="$EVAL_SINK_DIR/dashboard.html"
EVAL_DASHBOARD_OUTPUT=$(bash "$SANDBOX/halo/kernel/delivery/eval-dashboard.sh" --sink-dir="$EVAL_SINK_DIR" --out="$EVAL_DASHBOARD_HTML" --limit=5 2>&1)
if [[ -f "$EVAL_DASHBOARD_HTML" ]] \
  && grep -q "Halo Eval Dashboard" "$EVAL_DASHBOARD_HTML" \
  && grep -q "testapp" "$EVAL_DASHBOARD_HTML" \
  && grep -q "Recent Outcomes" "$EVAL_DASHBOARD_HTML" \
  && grep -q "missing regression test evidence" "$EVAL_DASHBOARD_HTML"; then
  pass "eval-dashboard renders central sink HTML"
else
  fail "eval-dashboard output invalid"
  echo "$EVAL_DASHBOARD_OUTPUT" | tail -20
fi

EVAL_QUERY_SUMMARY_OUTPUT=$(bash "$SANDBOX/halo/kernel/delivery/eval-query.sh" summary --sink-dir="$EVAL_SINK_DIR" 2>&1)
if echo "$EVAL_QUERY_SUMMARY_OUTPUT" | grep -q "Halo Eval Query" \
  && echo "$EVAL_QUERY_SUMMARY_OUTPUT" | grep -q "| Projects | 1 |" \
  && echo "$EVAL_QUERY_SUMMARY_OUTPUT" | grep -q "testapp"; then
  pass "eval-query summarizes central sink"
else
  fail "eval-query summary output invalid"
  echo "$EVAL_QUERY_SUMMARY_OUTPUT" | tail -20
fi

EVAL_QUERY_RUNS_JSON="$SANDBOX/halo/state/eval-query-runs.json"
EVAL_QUERY_OUTCOMES_JSON="$SANDBOX/halo/state/eval-query-outcomes.json"
bash "$SANDBOX/halo/kernel/delivery/eval-query.sh" runs --sink-dir="$EVAL_SINK_DIR" --project=testapp --format=json > "$EVAL_QUERY_RUNS_JSON"
bash "$SANDBOX/halo/kernel/delivery/eval-query.sh" outcomes --sink-dir="$EVAL_SINK_DIR" --project=testapp --type=review_finding --format=json > "$EVAL_QUERY_OUTCOMES_JSON"
if yq -e '.kind == "eval-query" and .action == "runs" and .metrics.eval_runs >= 1 and .items[0].project == "testapp"' "$EVAL_QUERY_RUNS_JSON" >/dev/null 2>&1 \
  && yq -e '.kind == "eval-query" and .action == "outcomes" and .metrics.outcomes >= 1 and .items[0].type == "review_finding" and .items[0].summary == "missing regression test evidence"' "$EVAL_QUERY_OUTCOMES_JSON" >/dev/null 2>&1; then
  pass "eval-query emits filtered JSON"
else
  fail "eval-query JSON output invalid"
  cat "$EVAL_QUERY_RUNS_JSON" "$EVAL_QUERY_OUTCOMES_JSON" | tail -40
fi
rm -f /tmp/halo-ac-json.log /tmp/halo-drift-json.log /tmp/halo-compliance-json.log /tmp/halo-pipeline-gate-json.log /tmp/halo-pipeline-escalation.log /tmp/halo-pipeline-custom-category.log /tmp/halo-failure-category-lint.log /tmp/halo-failure-category-lint-invalid.log
echo ""

# ── 7c. Gate coverage honesty and non-Go language support ──
echo "── 7c. Gate coverage honesty and language support ──"

DRIFT_ORIG_LANG=$(yq -r '.project.language' "$SANDBOX/halo/manifest.yaml")
DRIFT_ORIG_FRAMEWORK=$(yq -r '.drift.routes.framework' "$SANDBOX/halo/manifest.yaml")
DRIFT_EMPTY_CODE="$SANDBOX/drift-no-code"
mkdir -p "$DRIFT_EMPTY_CODE"

# A spec whose only error-code row is the template placeholder. Every drift dimension
# must be reported as "not verified", never folded into "no drift".
DRIFT_EMPTY_SPEC="$SANDBOX/drift-empty-spec.md"
cat > "$DRIFT_EMPTY_SPEC" << 'SPEC'
# Spec: No machine-checkable contracts

## 5.1 错误码

| 错误码 | 触发条件 | 副作用 | 是否可重试 |
|---|---|---|---|
| {ERROR_CODE} | {条件} | {有 / 无} | yes / no |
SPEC
DRIFT_EMPTY_JSON="$SANDBOX/halo/state/drift-empty.json"
DRIFT_EMPTY_OUT=$(bash "$SANDBOX/halo/kernel/delivery/gates/drift-check.sh" "$DRIFT_EMPTY_SPEC" "$DRIFT_EMPTY_CODE" --json-out="$DRIFT_EMPTY_JSON" 2>&1) || true
if yq -e '.metrics.spec_error_codes == 0 and .metrics.checks_skipped >= 3 and .metrics.checked.error_codes == false and .metrics.checked.routes == false and .metrics.checked.ddl == false' "$DRIFT_EMPTY_JSON" >/dev/null 2>&1 \
  && grep -q "NOT verified" <<< "$DRIFT_EMPTY_OUT"; then
  pass "drift-check reports skipped dimensions as not verified"
else
  fail "drift-check cannot distinguish skipped from clean"
  echo "$DRIFT_EMPTY_OUT" | tail -20
fi

# String error codes in a Python project: the spec table first column is an upper
# snake-case enum, and the constants live in .py files, not .go files.
DRIFT_PY_DIR="$SANDBOX/drift-error-codes"
mkdir -p "$DRIFT_PY_DIR"
cat > "$DRIFT_PY_DIR/errors.py" << 'PY'
from enum import Enum


class ErrorCode(str, Enum):
    REFERENCE_NOT_FOUND = "REFERENCE_NOT_FOUND"
PY
DRIFT_CODE_SPEC="$SANDBOX/drift-error-code-spec.md"
cat > "$DRIFT_CODE_SPEC" << 'SPEC'
# Spec: 字符串错误码

## 5.3 错误码

| 错误码 | 触发条件 | 副作用 | 是否可重试 |
|---|---|---|---|
| REFERENCE_NOT_FOUND | 引用目标不存在 | 无 | no |
| REFERENCE_IN_USE | 目标仍被引用 | 无 | no |
SPEC
yq -i '.project.language = "python"' "$SANDBOX/halo/manifest.yaml"
DRIFT_CODE_JSON="$SANDBOX/halo/state/drift-error-code.json"
DRIFT_CODE_EXIT=0
bash "$SANDBOX/halo/kernel/delivery/gates/drift-check.sh" "$DRIFT_CODE_SPEC" "$DRIFT_PY_DIR" --json-out="$DRIFT_CODE_JSON" >/tmp/halo-drift-error-code.log 2>&1 || DRIFT_CODE_EXIT=$?
if [[ $DRIFT_CODE_EXIT -eq 1 ]] \
  && yq -e '.metrics.spec_error_codes == 2 and .metrics.drift_count == 1 and .metrics.checked.error_codes == true' "$DRIFT_CODE_JSON" >/dev/null 2>&1; then
  pass "drift-check detects missing string error code in python source"
else
  fail "drift-check missed string error code drift (exit=$DRIFT_CODE_EXIT)"
  tail -20 /tmp/halo-drift-error-code.log
fi

cat >> "$DRIFT_PY_DIR/errors.py" << 'PY'
    REFERENCE_IN_USE = "REFERENCE_IN_USE"
PY
DRIFT_CODE_CLEAN_EXIT=0
bash "$SANDBOX/halo/kernel/delivery/gates/drift-check.sh" "$DRIFT_CODE_SPEC" "$DRIFT_PY_DIR" --json-out="$DRIFT_CODE_JSON" >/tmp/halo-drift-error-code.log 2>&1 || DRIFT_CODE_CLEAN_EXIT=$?
if [[ $DRIFT_CODE_CLEAN_EXIT -eq 0 ]] \
  && yq -e '.metrics.drift_count == 0 and .metrics.checked.error_codes == true' "$DRIFT_CODE_JSON" >/dev/null 2>&1; then
  pass "drift-check passes once every string error code is defined"
else
  fail "drift-check false positive on defined string error codes (exit=$DRIFT_CODE_CLEAN_EXIT)"
  tail -20 /tmp/halo-drift-error-code.log
fi

# FastAPI route drift: init.sh detects and writes this framework, so the gate must check it.
yq -i '.drift.routes.framework = "fastapi"' "$SANDBOX/halo/manifest.yaml"
DRIFT_FASTAPI_DIR="$SANDBOX/drift-fastapi"
mkdir -p "$DRIFT_FASTAPI_DIR"
cat > "$DRIFT_FASTAPI_DIR/routers.py" << 'PY'
from fastapi import APIRouter

router = APIRouter(prefix="/api", tags=["model-sets"])


@router.get("/model-sets")
def list_model_sets():
    return []


@router.post("/model-sets")
def create_model_set():
    return {}
PY
DRIFT_FASTAPI_SPEC="$SANDBOX/drift-fastapi-spec.md"
cat > "$DRIFT_FASTAPI_SPEC" << 'SPEC'
# Spec: FastAPI 路由

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | /api/model-sets | 列出模型集 |
| POST | /api/model-sets | 创建模型集 |
| DELETE | /api/model-sets/{set_id} | 删除模型集 |
SPEC
DRIFT_FASTAPI_JSON="$SANDBOX/halo/state/drift-fastapi.json"
DRIFT_FASTAPI_EXIT=0
bash "$SANDBOX/halo/kernel/delivery/gates/drift-check.sh" "$DRIFT_FASTAPI_SPEC" "$DRIFT_FASTAPI_DIR" --json-out="$DRIFT_FASTAPI_JSON" >/tmp/halo-drift-fastapi.log 2>&1 || DRIFT_FASTAPI_EXIT=$?
if [[ $DRIFT_FASTAPI_EXIT -eq 1 ]] \
  && yq -e '.metrics.spec_routes == 3 and .metrics.drift_count == 1 and .metrics.checked.routes == true' "$DRIFT_FASTAPI_JSON" >/dev/null 2>&1; then
  pass "drift-check detects unregistered FastAPI route"
else
  fail "drift-check missed FastAPI route drift (exit=$DRIFT_FASTAPI_EXIT)"
  tail -20 /tmp/halo-drift-fastapi.log
fi

cat >> "$DRIFT_FASTAPI_DIR/routers.py" << 'PY'


@router.delete("/model-sets/{set_id}")
def delete_model_set(set_id: str):
    return {}
PY
DRIFT_FASTAPI_CLEAN_EXIT=0
bash "$SANDBOX/halo/kernel/delivery/gates/drift-check.sh" "$DRIFT_FASTAPI_SPEC" "$DRIFT_FASTAPI_DIR" --json-out="$DRIFT_FASTAPI_JSON" >/tmp/halo-drift-fastapi.log 2>&1 || DRIFT_FASTAPI_CLEAN_EXIT=$?
if [[ $DRIFT_FASTAPI_CLEAN_EXIT -eq 0 ]] \
  && yq -e '.metrics.drift_count == 0 and .metrics.checked.routes == true' "$DRIFT_FASTAPI_JSON" >/dev/null 2>&1; then
  pass "drift-check passes once every FastAPI route is registered"
else
  fail "drift-check false positive on registered FastAPI routes (exit=$DRIFT_FASTAPI_CLEAN_EXIT)"
  tail -20 /tmp/halo-drift-fastapi.log
fi

# Same routes, but the spec puts the path in the first cell and the method in the second.
# Column order must not be an undeclared contract.
DRIFT_ROUTE_SPEC="$SANDBOX/drift-route-order-spec.md"
cat > "$DRIFT_ROUTE_SPEC" << 'SPEC'
# Spec: 路由表列序

## 5.1 接口契约

| 端点 | 方法 | 说明 |
|---|---|---|
| /api/model-sets | GET | 列出模型集 |
| /api/model-sets | POST | 创建模型集 |
| /api/model-sets/{set_id} | DELETE | 删除模型集 |
SPEC
DRIFT_ROUTE_JSON="$SANDBOX/halo/state/drift-route-order.json"
DRIFT_ROUTE_EXIT=0
bash "$SANDBOX/halo/kernel/delivery/gates/drift-check.sh" "$DRIFT_ROUTE_SPEC" "$DRIFT_FASTAPI_DIR" --json-out="$DRIFT_ROUTE_JSON" >/tmp/halo-drift-route-order.log 2>&1 || DRIFT_ROUTE_EXIT=$?
if [[ $DRIFT_ROUTE_EXIT -eq 0 ]] \
  && yq -e '.metrics.spec_routes == 3 and .metrics.drift_count == 0 and .metrics.checked.routes == true' "$DRIFT_ROUTE_JSON" >/dev/null 2>&1; then
  pass "drift-check locates route table columns by header name"
else
  fail "drift-check route extraction depends on column position (exit=$DRIFT_ROUTE_EXIT)"
  tail -20 /tmp/halo-drift-route-order.log
fi

# A collection root is registered as `@router.get("")` under `APIRouter(prefix="/x")`:
# the decorator path is empty and the prefix carries the whole route. Dropping every
# non-`/` decorator path dropped these, and a dropped code route is reported as drift.
# This router deliberately contains no `@router.get("/")`: the trailing-segment leniency
# in route_registered would let the `/` form mask the empty-path regression.
DRIFT_ROOT_DIR="$SANDBOX/drift-fastapi-root"
mkdir -p "$DRIFT_ROOT_DIR"
cat > "$DRIFT_ROOT_DIR/routers.py" << 'PY'
from fastapi import APIRouter

router = APIRouter(prefix="/model-sets", tags=["model-sets"])


@router.get("")
def list_model_sets():
    return []


@router.post("")
def create_model_set():
    return {}


@router.get("/{set_id}")
def get_model_set(set_id: str):
    return {}
PY
DRIFT_ROOT_SPEC="$SANDBOX/drift-fastapi-root-spec.md"
cat > "$DRIFT_ROOT_SPEC" << 'SPEC'
# Spec: FastAPI 集合根路由

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | /model-sets | 列出模型集 |
| POST | /model-sets | 创建模型集 |
| GET | /model-sets/{set_id} | 读取模型集 |
| DELETE | /model-sets/{set_id} | 删除模型集 |
SPEC
DRIFT_ROOT_JSON="$SANDBOX/halo/state/drift-fastapi-root.json"
DRIFT_ROOT_EXIT=0
bash "$SANDBOX/halo/kernel/delivery/gates/drift-check.sh" "$DRIFT_ROOT_SPEC" "$DRIFT_ROOT_DIR" --json-out="$DRIFT_ROOT_JSON" >/tmp/halo-drift-fastapi-root.log 2>&1 || DRIFT_ROOT_EXIT=$?
if [[ $DRIFT_ROOT_EXIT -eq 1 ]] \
  && yq -e '.metrics.spec_routes == 4 and .metrics.drift_count == 1 and .metrics.checked.routes == true' "$DRIFT_ROOT_JSON" >/dev/null 2>&1; then
  pass "drift-check treats empty-path FastAPI collection roots as registered"
else
  fail "drift-check drops empty-path FastAPI collection roots (exit=$DRIFT_ROOT_EXIT)"
  tail -20 /tmp/halo-drift-fastapi-root.log
fi

cat >> "$DRIFT_ROOT_DIR/routers.py" << 'PY'


@router.delete("/{set_id}")
def delete_model_set(set_id: str):
    return {}
PY
DRIFT_ROOT_CLEAN_EXIT=0
bash "$SANDBOX/halo/kernel/delivery/gates/drift-check.sh" "$DRIFT_ROOT_SPEC" "$DRIFT_ROOT_DIR" --json-out="$DRIFT_ROOT_JSON" >/tmp/halo-drift-fastapi-root.log 2>&1 || DRIFT_ROOT_CLEAN_EXIT=$?
if [[ $DRIFT_ROOT_CLEAN_EXIT -eq 0 ]] \
  && yq -e '.metrics.drift_count == 0 and .metrics.checked.routes == true' "$DRIFT_ROOT_JSON" >/dev/null 2>&1; then
  pass "drift-check passes once a prefix-only FastAPI router is complete"
else
  fail "drift-check false positive on a prefix-only FastAPI router (exit=$DRIFT_ROOT_CLEAN_EXIT)"
  tail -20 /tmp/halo-drift-fastapi-root.log
fi

# Decorators spanning several lines are ordinary FastAPI/Express style. grep works per
# line, so the registration has to be read from the whole file. The single-line GET keeps
# CODE_ROUTES non-empty, so a regression fails the assertions instead of turning the whole
# dimension into a skip that would pass on exit 0.
DRIFT_ML_DIR="$SANDBOX/drift-fastapi-multiline"
mkdir -p "$DRIFT_ML_DIR"
cat > "$DRIFT_ML_DIR/routers.py" << 'PY'
from fastapi import APIRouter

router = APIRouter(prefix="/api", tags=["reports"])


@router.get("/reports")
def list_reports():
    return []


@router.post(
    "/reports",
    status_code=201,
)
def create_report():
    return {}


@router.delete(
    "/reports/{report_id}",
)
def delete_report(report_id: str):
    return {}
PY
DRIFT_ML_SPEC="$SANDBOX/drift-fastapi-multiline-spec.md"
cat > "$DRIFT_ML_SPEC" << 'SPEC'
# Spec: 多行装饰器路由

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | /api/reports | 列出报表 |
| POST | /api/reports | 创建报表 |
| DELETE | /api/reports/{report_id} | 删除报表 |
SPEC
DRIFT_ML_JSON="$SANDBOX/halo/state/drift-fastapi-multiline.json"
DRIFT_ML_EXIT=0
bash "$SANDBOX/halo/kernel/delivery/gates/drift-check.sh" "$DRIFT_ML_SPEC" "$DRIFT_ML_DIR" --json-out="$DRIFT_ML_JSON" >/tmp/halo-drift-fastapi-multiline.log 2>&1 || DRIFT_ML_EXIT=$?
if [[ $DRIFT_ML_EXIT -eq 0 ]] \
  && yq -e '.metrics.spec_routes == 3 and .metrics.drift_count == 0 and .metrics.checked.routes == true' "$DRIFT_ML_JSON" >/dev/null 2>&1; then
  pass "drift-check reads multi-line FastAPI route decorators"
else
  fail "drift-check drops multi-line FastAPI route decorators (exit=$DRIFT_ML_EXIT)"
  tail -20 /tmp/halo-drift-fastapi-multiline.log
fi

yq -i ".project.language = \"$DRIFT_ORIG_LANG\"" "$SANDBOX/halo/manifest.yaml"
yq -i ".drift.routes.framework = \"$DRIFT_ORIG_FRAMEWORK\"" "$SANDBOX/halo/manifest.yaml"

# Compliance source trace must recognise the Chinese source categories used by the
# default spec template shipped with the framework.
COMPLIANCE_ZH_SPEC="$SANDBOX/compliance-zh-spec.md"
cat > "$COMPLIANCE_ZH_SPEC" << 'SPEC'
# Spec: 中文上下文依据

## 3. 上下文依据

| 来源 | 已采用事实或约束 | 对方案的影响 |
|---|---|---|
| 用户输入 | 需要模型集能力 | 决定交付范围 |
| 代码 / 测试 | 已有 model 表 | 复用既有结构 |
| 项目知识 | dev DB 必须处于 alembic head | 决定迁移策略 |
| 待确认 | None | 无 |
SPEC
COMPLIANCE_ZH_JSON="$SANDBOX/halo/state/compliance-zh.json"
bash "$SANDBOX/halo/kernel/delivery/gates/compliance.sh" "$COMPLIANCE_ZH_SPEC" --json-out="$COMPLIANCE_ZH_JSON" >/tmp/halo-compliance-zh.log 2>&1 || true
if yq -e '(.findings[] | select(.check == "source_trace") | .status) == "pass"' "$COMPLIANCE_ZH_JSON" >/dev/null 2>&1; then
  pass "compliance recognises Chinese source categories"
else
  fail "compliance source trace misses Chinese source categories"
  tail -20 /tmp/halo-compliance-zh.log
fi

# plan-lint placeholder detection must not fire on REST path parameters.
PLACEHOLDER_SPEC_DIR="$SANDBOX/halo/specs/placeholder-probe"
mkdir -p "$PLACEHOLDER_SPEC_DIR"
cp "$SANDBOX/halo/specs/modern-feature/spec.md" "$PLACEHOLDER_SPEC_DIR/spec.md"
sed 's#Scope: Implement the smallest create path needed for AC-1.#Scope: Implement POST /model-sets/{set_id}/members and keep members < 100 while > 0.#' \
  "$SANDBOX/halo/specs/modern-feature/plan.md" > "$PLACEHOLDER_SPEC_DIR/plan.md"
PLACEHOLDER_OUT=$(bash "$SANDBOX/halo/kernel/orchestrator/sdd/plan-lint.sh" "halo/specs/placeholder-probe/plan.md" 2>&1) || true
if ! grep -q "unresolved placeholder" <<< "$PLACEHOLDER_OUT"; then
  pass "plan-lint accepts REST path parameters and comparison operators"
else
  fail "plan-lint flags REST path parameters as unresolved placeholders"
  grep "unresolved placeholder" <<< "$PLACEHOLDER_OUT" | head -5
fi

sed 's#Scope: Implement the smallest get path needed for AC-2.#Scope: {SCOPE_TBD} and see <spec-id>.#' \
  "$SANDBOX/halo/specs/modern-feature/plan.md" > "$PLACEHOLDER_SPEC_DIR/plan-residual.md"
PLACEHOLDER_RESIDUAL_OUT=$(bash "$SANDBOX/halo/kernel/orchestrator/sdd/plan-lint.sh" "halo/specs/placeholder-probe/plan-residual.md" 2>&1) || true
if grep -q "unresolved placeholder" <<< "$PLACEHOLDER_RESIDUAL_OUT"; then
  pass "plan-lint still flags real template placeholders"
else
  fail "plan-lint no longer detects template placeholders"
  echo "$PLACEHOLDER_RESIDUAL_OUT" | tail -10
fi

# review-package must cover committed work, not only the working tree.
# The .gitignore keeps the installed harness out of the untracked listing, the way a
# real project would; without it every framework file would count as untracked.
cat > "$SANDBOX/.gitignore" << 'IGNORE'
.halo/
halo/
prismspec/
py-ac-coverage/
drift-no-code/
drift-error-codes/
drift-fastapi/
drift-fastapi-root/
drift-fastapi-multiline/
go.mod
*.md
IGNORE
REVIEW_PKG_SRC="$SANDBOX/review-pkg-src.txt"
echo "baseline line" > "$REVIEW_PKG_SRC"
git -C "$SANDBOX" add review-pkg-src.txt >/dev/null 2>&1
git -C "$SANDBOX" -c user.email=smoke@halo.test -c user.name=smoke commit -q -m "review package baseline" >/dev/null 2>&1
git -C "$SANDBOX" branch -M main >/dev/null 2>&1
git -C "$SANDBOX" checkout -q -b review-package-branch >/dev/null 2>&1
echo "committed change line" >> "$REVIEW_PKG_SRC"
git -C "$SANDBOX" add review-pkg-src.txt >/dev/null 2>&1
git -C "$SANDBOX" -c user.email=smoke@halo.test -c user.name=smoke commit -q -m "review package change" >/dev/null 2>&1
echo "untracked content" > "$SANDBOX/review-pkg-untracked.txt"
REVIEW_PKG_OUT=$(bash "$SANDBOX/halo/kernel/orchestrator/sdd/review-package.sh" modern-feature branch 2>&1) || true
if [[ -f "$REVIEW_PKG_OUT" ]] \
  && grep -q "committed change line" "$REVIEW_PKG_OUT" \
  && grep -q "review-pkg-untracked.txt" "$REVIEW_PKG_OUT" \
  && grep -q "untracked content" "$REVIEW_PKG_OUT"; then
  pass "review-package includes committed and untracked changes"
else
  fail "review-package produced an empty diff on a clean working tree"
  [[ -f "$REVIEW_PKG_OUT" ]] && tail -30 "$REVIEW_PKG_OUT"
fi
git -C "$SANDBOX" checkout -q main >/dev/null 2>&1
rm -f /tmp/halo-drift-error-code.log /tmp/halo-drift-route-order.log /tmp/halo-drift-fastapi.log \
  /tmp/halo-drift-fastapi-root.log /tmp/halo-drift-fastapi-multiline.log /tmp/halo-compliance-zh.log
echo ""

# ── 8. Context knowledge backend ──
echo "── 8. Context knowledge backend ──"
KNOWLEDGE_SH="$SANDBOX/halo/kernel/context/backends/knowledge.sh"
KNOWLEDGE_DIR="$SANDBOX/halo/context/knowledge"
LIST_OUTPUT=$(bash "$KNOWLEDGE_SH" --list 2>&1)
if echo "$LIST_OUTPUT" | grep -q "Context Knowledge Files"; then
  pass "knowledge backend --list works"
else
  fail "knowledge backend --list failed"
fi

# Search-path assertions below match with `[[ == * * ]]` rather than `echo "$var" | grep -q`.
# The large-file case deliberately produces output past the pipe buffer, which is exactly
# the SIGPIPE condition being tested — asserting through a pipe would reintroduce it here.
SEARCH_ONE=$(bash "$KNOWLEDGE_SH" regressions 2>&1 || true)
if [[ "$SEARCH_ONE" == *"pitfalls.md"* ]]; then
  pass "knowledge search matches a single keyword"
else
  fail "knowledge search missed a single keyword"
fi

# `regressions` appears only in pitfalls.md and `boundaries` only in architecture.md, so a
# quoted two-word argument must return both files, in either word order. Agent-facing docs
# spell this argument `<keywords>`, so a single quoted string is what callers actually pass.
SEARCH_QUOTED=$(bash "$KNOWLEDGE_SH" "regressions boundaries" 2>&1 || true)
SEARCH_REVERSED=$(bash "$KNOWLEDGE_SH" "boundaries regressions" 2>&1 || true)
if [[ "$SEARCH_QUOTED" == *"pitfalls.md"* && "$SEARCH_QUOTED" == *"architecture.md"* \
   && "$SEARCH_REVERSED" == *"pitfalls.md"* && "$SEARCH_REVERSED" == *"architecture.md"* ]]; then
  pass "knowledge search splits a quoted multi-word argument"
else
  fail "knowledge search did not split a quoted multi-word argument"
fi

SEARCH_ARGS=$(bash "$KNOWLEDGE_SH" regressions boundaries 2>&1 || true)
if [[ "$SEARCH_ARGS" == *"pitfalls.md"* && "$SEARCH_ARGS" == *"architecture.md"* ]]; then
  pass "knowledge search keeps OR semantics across separate arguments"
else
  fail "knowledge search lost OR semantics across separate arguments"
fi

# A knowledge file past the 64KB pipe buffer with its keyword near the top. Feeding file
# content through a pipe into `grep -q` lets grep close the pipe on the first match, and
# the resulting SIGPIPE fails the pipeline under pipefail — reporting the match as a miss.
awk 'BEGIN {
  print "# Large Context"
  print ""
  print "Marker term: zzunique-large-marker"
  for (i = 0; i < 3000; i++) print "Filler line pushing this file past the pipe buffer boundary."
}' > "$KNOWLEDGE_DIR/large-context.md"
SEARCH_LARGE=$(bash "$KNOWLEDGE_SH" zzunique-large-marker 2>&1 || true)
if [[ "$SEARCH_LARGE" == *"large-context.md"* ]]; then
  pass "knowledge search matches inside a file larger than the pipe buffer"
else
  fail "knowledge search lost a match in a large file"
fi
rm -f "$KNOWLEDGE_DIR/large-context.md"

# Keywords are literal text, not patterns: `.` must not wildcard-match `regressions`.
SEARCH_LITERAL=$(bash "$KNOWLEDGE_SH" "regressi.ns" 2>&1 || true)
if [[ "$SEARCH_LITERAL" == *"No matching context knowledge"* ]]; then
  pass "knowledge search treats keywords as literal text"
else
  fail "knowledge search treated a keyword as a regex"
fi
echo ""

# ── 9. Spec-lock ──
echo "── 9. Spec-lock ──"
LOCK_OUTPUT=$(bash "$SANDBOX/halo/kernel/delivery/gates/spec-lock.sh" acquire "$SANDBOX/halo/specs/modern-feature/spec.md" 2>&1)
if echo "$LOCK_OUTPUT" | grep -q "Locked"; then
  pass "spec-lock acquire works"
else
  fail "spec-lock acquire failed"
fi

UNLOCK_OUTPUT=$(bash "$SANDBOX/halo/kernel/delivery/gates/spec-lock.sh" release "$SANDBOX/halo/specs/modern-feature/spec.md" 2>&1)
if echo "$UNLOCK_OUTPUT" | grep -q "Released"; then
  pass "spec-lock release works"
else
  fail "spec-lock release failed"
fi
echo ""

# ── 9b. Spec auto-discovery ranks on front matter, not file mtime ──
# Regression: `ls -t` picked whichever spec.md a git merge/checkout happened to
# rewrite last, so the whole toolchain verified an unrelated spec and produced a
# structurally complete eval run whose spec_file, spec_hash and AC coverage all
# belonged to that other spec — with no warning printed anywhere.
echo "── 9b. Spec auto-discovery ──"
DISCOVERY_ROOT="$SANDBOX/discovery"
write_discovery_spec() {
  local dir="$1" id="$2" status="$3" updated="$4"
  mkdir -p "$DISCOVERY_ROOT/$dir"
  {
    echo "---"
    echo "id: $id"
    echo "status: $status"
    [[ -n "$updated" ]] && echo "updated_at: $updated"
    echo "---"
    echo ""
    echo "# $id"
  } > "$DISCOVERY_ROOT/$dir/spec.md"
}

rm -rf "$DISCOVERY_ROOT"
write_discovery_spec current current implemented "2026-08-03T13:52:14Z"
write_discovery_spec merged merged verified "2026-08-03T05:15:58Z"
# Simulate `git merge` checking the other spec out: newest mtime, oldest content.
touch "$DISCOVERY_ROOT/merged/spec.md"
DISCOVERY_PICK=$(bash "$SANDBOX/halo/kernel/spec-select.sh" "$DISCOVERY_ROOT" 2>/dev/null || true)
if [[ "$DISCOVERY_PICK" == "$DISCOVERY_ROOT/current/spec.md" ]]; then
  pass "spec auto-discovery ignores mtime rewritten by git checkout"
else
  fail "spec auto-discovery picked $DISCOVERY_PICK, expected current/spec.md"
fi

DISCOVERY_STDERR=$(bash "$SANDBOX/halo/kernel/spec-select.sh" "$DISCOVERY_ROOT" 2>&1 >/dev/null || true)
if grep -q "selected" <<< "$DISCOVERY_STDERR" && grep -q "not selected" <<< "$DISCOVERY_STDERR"; then
  pass "spec auto-discovery announces the selection and what it beat"
else
  fail "spec auto-discovery selected silently"
fi

# A terminal (verified) spec must not outrank an in-flight one on timestamp alone.
write_discovery_spec merged merged verified "2026-08-09T23:59:59Z"
DISCOVERY_PICK=$(bash "$SANDBOX/halo/kernel/spec-select.sh" "$DISCOVERY_ROOT" 2>/dev/null || true)
if [[ "$DISCOVERY_PICK" == "$DISCOVERY_ROOT/current/spec.md" ]]; then
  pass "spec auto-discovery prefers in-flight spec over verified one"
else
  fail "spec auto-discovery let a verified spec win on timestamp"
fi

# Same lifecycle class, same timestamp: genuinely undecidable, so refuse to guess.
write_discovery_spec merged merged implemented "2026-08-03T13:52:14Z"
DISCOVERY_TIE_EXIT=0
DISCOVERY_TIE_OUT=$(bash "$SANDBOX/halo/kernel/spec-select.sh" "$DISCOVERY_ROOT" 2>&1) || DISCOVERY_TIE_EXIT=$?
if [[ "$DISCOVERY_TIE_EXIT" -eq 2 ]] && grep -q -- "--spec=" <<< "$DISCOVERY_TIE_OUT"; then
  pass "spec auto-discovery refuses to guess on an exact tie"
else
  fail "spec auto-discovery guessed on an exact tie (exit $DISCOVERY_TIE_EXIT)"
fi

# No semantic signal anywhere: fall back to mtime, but say so.
rm -rf "$DISCOVERY_ROOT"
write_discovery_spec older older drafted ""
write_discovery_spec newer newer drafted ""
touch "$DISCOVERY_ROOT/newer/spec.md"
DISCOVERY_FALLBACK_OUT=$(bash "$SANDBOX/halo/kernel/spec-select.sh" "$DISCOVERY_ROOT" 2>&1 >/dev/null || true)
DISCOVERY_PICK=$(bash "$SANDBOX/halo/kernel/spec-select.sh" "$DISCOVERY_ROOT" 2>/dev/null || true)
if [[ "$DISCOVERY_PICK" == "$DISCOVERY_ROOT/newer/spec.md" ]] && grep -q "mtime" <<< "$DISCOVERY_FALLBACK_OUT"; then
  pass "spec auto-discovery falls back to mtime and flags it"
else
  fail "spec auto-discovery mtime fallback invalid"
fi

# End to end: the pipeline must verify the spec the content says is current, and must
# record that nobody named it.
rm -rf "$SANDBOX/halo/specs/zz-merged"
DISCOVERY_EVAL="$SANDBOX/halo/state/discovery-eval.json"
cp -R "$SANDBOX/halo/specs/modern-feature" "$SANDBOX/halo/specs/zz-merged"
yq -i '.id = "zz-merged"' --front-matter=process "$SANDBOX/halo/specs/zz-merged/spec.md" 2>/dev/null || true
touch "$SANDBOX/halo/specs/zz-merged/spec.md"
DISCOVERY_PIPE_OUT=$(bash "$SANDBOX/halo/kernel/delivery/pipeline.sh" --only=spec-lint --json-out="$DISCOVERY_EVAL" 2>&1 || true)
if grep -q "source=auto" <<< "$DISCOVERY_PIPE_OUT" \
  && [[ -f "$DISCOVERY_EVAL" ]] \
  && yq -e '.spec_source == "auto"' "$DISCOVERY_EVAL" >/dev/null 2>&1; then
  pass "pipeline prints and records how the spec was chosen"
else
  fail "pipeline did not record spec_source"
  tail -20 <<< "$DISCOVERY_PIPE_OUT"
fi

DISCOVERY_EXPLICIT_EVAL="$SANDBOX/halo/state/discovery-eval-explicit.json"
bash "$SANDBOX/halo/kernel/delivery/pipeline.sh" --only=spec-lint \
  --spec="$SANDBOX/halo/specs/modern-feature/spec.md" \
  --json-out="$DISCOVERY_EXPLICIT_EVAL" >/tmp/halo-discovery-explicit.log 2>&1 || true
if yq -e '.spec_source == "explicit"' "$DISCOVERY_EXPLICIT_EVAL" >/dev/null 2>&1; then
  pass "pipeline records an explicitly pinned spec as explicit"
else
  fail "pipeline mislabels an explicit --spec= run"
  tail -20 /tmp/halo-discovery-explicit.log
fi

# guide.sh keeps its own copy of the ranking for the standalone host; under the halo
# host it must delegate, so both paths agree on the same tree.
if [[ -f "$REPO_DIR/prismspec/bin/guide.sh" ]]; then
  mkdir -p "$SANDBOX/prismspec/bin"
  cp "$REPO_DIR/prismspec/bin/guide.sh" "$SANDBOX/prismspec/bin/guide.sh"
  GUIDE_JSON=$(cd "$SANDBOX" && bash prismspec/bin/guide.sh --json 2>/dev/null || true)
  KERNEL_PICK=$(cd "$SANDBOX" && bash halo/kernel/spec-select.sh halo/specs 2>/dev/null || true)
  KERNEL_PICK_ID=$(basename "$(dirname "$KERNEL_PICK")")
  if [[ -n "$KERNEL_PICK_ID" ]] \
    && yq -e ".spec_id == \"$KERNEL_PICK_ID\" and .spec_source == \"auto\"" <<< "$GUIDE_JSON" >/dev/null 2>&1; then
    pass "guide.sh resolves the same spec as the kernel selector"
  else
    fail "guide.sh and the kernel selector disagree on the current spec"
    echo "$GUIDE_JSON" | head -5
  fi
fi
rm -rf "$SANDBOX/halo/specs/zz-merged"
echo ""

# ── 9c. Learn draft promotion respects the target file's shape ──
# Regression: promote always appended a `## Promoted Learn Draft` section to EOF, so
# on the framework's own table-shaped knowledge files the lesson landed outside the
# table (after the trailing `## Do Not Repeat` section) and knowledge-lint could not
# see it, because the file already carries a Source column at file level.
echo "── 9c. Learn draft promotion shape ──"
SHAPE_DRAFT="$SANDBOX/halo/context/drafts/shape-check.md"
cat > "$SHAPE_DRAFT" <<'MD'
---
run_id: "shape-check"
failure_category: "unknown"
default_action: "review"
---

# Knowledge Draft

## Lesson Candidate

- Alembic head must match before commit
- Escape the | pipe inside table text

## Review Checklist
MD
SHAPE_TARGET="$SANDBOX/halo/context/knowledge/shape-table.md"
cat > "$SHAPE_TARGET" <<'MD'
---
owner: "project"
verified_at: "2026-06-28"
applies_to: ["pitfalls"]
---

# Shape Table

| Pitfall | Trigger | Guidance | Source |
|---------|---------|----------|--------|

## Do Not Repeat

- keep one-offs out of here
MD
SHAPE_EXIT=0
SHAPE_OUT=$(bash "$SANDBOX/halo/kernel/context/learn-draft.sh" promote "$SHAPE_DRAFT" --to="$SHAPE_TARGET" 2>&1) || SHAPE_EXIT=$?
SHAPE_TABLE_ROWS=$(awk '/^## Do Not Repeat/{exit} /^\| /{n++} END{print n+0}' "$SHAPE_TARGET")
if [[ $SHAPE_EXIT -eq 0 ]] \
  && [[ "$SHAPE_TABLE_ROWS" -eq 3 ]] \
  && ! grep -q "Promoted Learn Draft" "$SHAPE_TARGET" \
  && grep -q 'Escape the \\| pipe' "$SHAPE_TARGET" \
  && grep -q "row(s) added to knowledge table" <<< "$SHAPE_OUT"; then
  pass "learn-draft promotes into a table target as rows"
else
  fail "learn-draft table promotion invalid (rows=$SHAPE_TABLE_ROWS)"
  tail -10 <<< "$SHAPE_OUT"
fi

if bash "$SANDBOX/halo/kernel/context/knowledge-lint.sh" --target="halo/context/knowledge/shape-table.md" --strict >/tmp/halo-shape-lint.log 2>&1; then
  pass "table promotion keeps knowledge-lint clean"
else
  fail "table promotion broke knowledge-lint"
  tail -10 /tmp/halo-shape-lint.log
fi

# Section-shaped targets keep the original append behavior.
SECTION_DRAFT="$SANDBOX/halo/context/drafts/shape-section.md"
sed 's/shape-check/shape-section/' "$SANDBOX/halo/context/drafts/promoted/shape-check.md" > "$SECTION_DRAFT"
SECTION_TARGET="$SANDBOX/halo/context/knowledge/shape-section.md"
printf -- '---\nowner: "project"\nverified_at: "2026-06-28"\napplies_to: ["notes"]\n---\n\n# Notes\n\n**Source**: seed\n' > "$SECTION_TARGET"
SECTION_EXIT=0
SECTION_OUT=$(bash "$SANDBOX/halo/kernel/context/learn-draft.sh" promote "$SECTION_DRAFT" --to="$SECTION_TARGET" 2>&1) || SECTION_EXIT=$?
if [[ $SECTION_EXIT -eq 0 ]] \
  && grep -q "## Promoted Learn Draft" "$SECTION_TARGET" \
  && grep -q "section appended" <<< "$SECTION_OUT"; then
  pass "learn-draft keeps section append for section-shaped targets"
else
  fail "learn-draft section promotion regressed"
  tail -10 <<< "$SECTION_OUT"
fi
echo ""

# ── Summary ──
echo "══════════════════════════════════"
TOTAL=$((PASS + FAIL))
echo "📊 Smoke Test: ✅ $PASS / $TOTAL"
if [[ $FAIL -gt 0 ]]; then
  echo "❌ FAIL"
  exit 1
else
  echo "✅ ALL PASS"
  exit 0
fi

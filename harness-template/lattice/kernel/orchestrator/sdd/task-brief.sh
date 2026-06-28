#!/usr/bin/env bash
# task-brief.sh - Build a compact, file-backed task brief for implementers/reviewers.
# Usage: task-brief.sh <spec-id> <task-id> [output-file]
source "$(dirname "$0")/../../_lib.sh"

SPEC_ID="${1:-}"
TASK_ID="${2:-}"
OUT="${3:-}"

if [[ -z "$SPEC_ID" || -z "$TASK_ID" ]]; then
  echo "Usage: task-brief.sh <spec-id> <task-id> [output-file]"
  exit 1
fi

SPEC_DIR="$PROJECT_ROOT/lattice/specs/$SPEC_ID"
SPEC_FILE="$SPEC_DIR/spec.md"
PLAN_FILE="$SPEC_DIR/plan.md"

[[ -f "$SPEC_FILE" ]] || { echo "Spec not found: $SPEC_FILE"; exit 1; }
[[ -f "$PLAN_FILE" ]] || { echo "Plan not found: $PLAN_FILE"; exit 1; }

TASK_DIR="$PROJECT_ROOT/.lattice/sdd/$SPEC_ID/$TASK_ID"
mkdir -p "$TASK_DIR"
OUT="${OUT:-$TASK_DIR/brief.md}"

extract_section() {
  local heading="$1" file="$2"
  awk -v heading="$heading" '
    $0 ~ "^## " heading "$" { in_section=1; print; next }
    in_section && /^## / { exit }
    in_section { print }
  ' "$file"
}

extract_task() {
  local task_id="$1" file="$2"
  awk -v task_id="$task_id" '
    $0 ~ "^- \\[[ xX]\\] " task_id ":" { in_task=1; print; next }
    in_task && /^- \[[ xX]\] [A-Z]+-[0-9]+:/ { exit }
    in_task && /^## / { exit }
    in_task { print }
  ' "$file"
}

{
  echo "# Task Brief: $SPEC_ID / $TASK_ID"
  echo ""
  echo "## Source"
  echo ""
  echo "- Spec: \`lattice/specs/$SPEC_ID/spec.md\`"
  echo "- Plan: \`lattice/specs/$SPEC_ID/plan.md\`"
  echo "- Task: \`$TASK_ID\`"
  echo ""
  echo "## Intent"
  echo ""
  extract_section "Intent" "$SPEC_FILE" | sed '1d'
  echo ""
  echo "## Execution Policy"
  echo ""
  extract_section "Execution Policy" "$SPEC_FILE" | sed '1d'
  echo ""
  echo "## Global Constraints"
  echo ""
  extract_section "Global Constraints" "$PLAN_FILE" | sed '1d'
  echo ""
  echo "## Task"
  echo ""
  extract_task "$TASK_ID" "$PLAN_FILE"
  echo ""
  echo "## Acceptance Criteria"
  echo ""
  extract_section "Acceptance Criteria" "$SPEC_FILE" | sed '1d'
  echo ""
  echo "## Review Contract"
  echo ""
  echo "- Keep changes scoped to this task and its referenced ACs."
  echo "- If the task cannot be verified from local files or tests, say so explicitly."
  echo "- Do not weaken tests, scope, or acceptance criteria to get green."
} > "$OUT"

echo "$OUT"

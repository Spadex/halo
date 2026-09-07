#!/usr/bin/env bash
# task-evidence-lint.sh — Validate evidence for completed plan tasks.
source "$(dirname "$0")/../../_lib.sh"

for arg in "$@"; do
  [[ "$arg" == "--help" || "$arg" == "-h" ]] && cli_help "task evidence lint" "Validate completed task evidence under .halo/sdd" \
    "task-evidence-lint.sh <spec-id|path/to/plan.md>" \
    "task-evidence-lint.sh modern-feature"
done

INPUT="${1:-}"

resolve_plan_file() {
  local input="$1" abs
  [[ -n "$input" ]] || { echo "Usage: task-evidence-lint.sh <spec-id|path/to/plan.md>"; exit 1; }
  if [[ "$input" == *.md || "$input" == */* ]]; then
    [[ "$input" == /* ]] && abs="$input" || abs="$PROJECT_ROOT/$input"
  else
    abs="$PROJECT_ROOT/halo/specs/$input/plan.md"
  fi
  [[ -f "$abs" ]] || { echo "Plan file not found: $input"; exit 1; }
  printf '%s' "$abs"
}

rel_path() {
  local path="$1"
  if [[ "$path" == "$PROJECT_ROOT/"* ]]; then
    printf '%s' "${path#$PROJECT_ROOT/}"
  else
    printf '%s' "$path"
  fi
}

frontmatter_value() {
  local key="$1" file="$2"
  awk -v key="$key" '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { exit }
    in_fm && index($0, key ":") == 1 {
      value = substr($0, length(key) + 2)
      gsub(/^[ \t]+|[ \t]+$/, "", value)
      gsub(/^["'\''`]+|["'\''`]+$/, "", value)
      print value
      exit
    }
  ' "$file"
}

task_body() {
  local task_id="$1" file="$2"
  awk -v task_id="$task_id" '
    $0 ~ "^- \\[[ xX]\\] " task_id ":" { in_task = 1; print; next }
    in_task && /^- \[[ xX]\] (T[0-9]+|RED-[0-9]+):/ { exit }
    in_task && /^##[[:space:]]+/ { exit }
    in_task { print }
  ' "$file"
}

task_mode() {
  local body="$1" line value
  line="$(grep -Eim1 '(Mode|模式)[[:space:]]*[:：][[:space:]]*`?(plan|tdd)`?' <<< "$body" || true)"
  [[ -n "$line" ]] || return 0
  value="$(sed -E 's/.*(Mode|模式)[[:space:]]*[:：][[:space:]]*//; s/`//g; s/[^A-Za-z].*$//' <<< "$line" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    plan|tdd) printf '%s' "$value" ;;
  esac
}

execution_mode() {
  local spec="$1" plan="$2" value=""
  if [[ -n "$spec" && -f "$spec" ]]; then
    value="$(frontmatter_value "execution_mode" "$spec")"
  fi
  [[ "$value" == "plan" || "$value" == "tdd" ]] || value="$(grep -Eim1 'Execution mode:[[:space:]]*(plan|tdd)' "$plan" 2>/dev/null | sed -E 's/.*Execution mode:[[:space:]]*//; s/[`"]//g' || true)"
  [[ "$value" == "plan" || "$value" == "tdd" ]] || value="$(grep -Eim1 '执行模式[[:space:]]*[:：][[:space:]]*(plan|tdd|`plan`|`tdd`)' "$plan" 2>/dev/null | sed -E 's/.*执行模式[[:space:]]*[:：][[:space:]]*//; s/[`"]//g' || true)"
  printf '%s' "${value:-unknown}"
}

completed_task_lines() {
  local file="$1"
  grep -E '^- \[[xX]\] T[0-9]+:' "$file" 2>/dev/null || true
}

extract_task_id() {
  local line="$1"
  sed -E 's/^- \[[xX]\] (T[0-9]+):.*/\1/' <<< "$line"
}

valid_tdd_evidence() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  yq -e '.kind == "tdd-evidence" and .status == "pass" and (.red.exit_code | tonumber) != 0 and (.green.exit_code | tonumber) == 0 and ((.ac_ids // []) | length > 0)' "$file" >/dev/null 2>&1
}

PLAN_FILE="$(resolve_plan_file "$INPUT")"
SPEC_DIR="$(dirname "$PLAN_FILE")"
SPEC_FILE="$SPEC_DIR/spec.md"
SPEC_ID="$(basename "$SPEC_DIR")"
PLAN_REL="$(rel_path "$PLAN_FILE")"
EVIDENCE_ROOT="$PROJECT_ROOT/.halo/sdd/$SPEC_ID"
MODE="$(execution_mode "$SPEC_FILE" "$PLAN_FILE")"

FAILS=0
WARNS=0
pass_msg() { pass "$*"; }
fail_msg() { fail "$*"; FAILS=$((FAILS + 1)); }
warn_msg() { warn "$*"; WARNS=$((WARNS + 1)); }

echo "🔍 Task Evidence Lint: $PLAN_REL"
echo ""
echo "── Completed task evidence ──"

TASK_COUNT=0
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  task_id="$(extract_task_id "$line")"
  task_dir="$EVIDENCE_ROOT/$task_id"
  TASK_COUNT=$((TASK_COUNT + 1))

  if [[ -f "$task_dir/brief.md" ]]; then
    pass_msg "$task_id brief.md"
  else
    fail_msg "$task_id missing brief.md"
  fi

  if [[ -f "$task_dir/review-package.md" ]]; then
    pass_msg "$task_id review-package.md"
  else
    fail_msg "$task_id missing review-package.md"
  fi

  # The per-task `Mode:` / `模式：` field is mandatory in plan-lint, so it wins over
  # the spec-level execution_mode; the spec level is only a fallback.
  effective_mode="$(task_mode "$(task_body "$task_id" "$PLAN_FILE")")"
  effective_mode="${effective_mode:-$MODE}"
  if [[ "$effective_mode" == "tdd" ]]; then
    if valid_tdd_evidence "$task_dir/tdd-evidence.json"; then
      pass_msg "$task_id tdd-evidence.json"
    else
      fail_msg "$task_id missing or invalid tdd-evidence.json"
    fi
  elif [[ "$effective_mode" == "plan" ]]; then
    pass_msg "$task_id plan mode (TDD evidence not required)"
  else
    # Failure direction: fail-closed. A third value (`unknown`, or anything a future
    # execution_mode() learns to emit) means no source declared the mode — not the spec
    # front-matter, not the plan header, not the task body. Whether TDD evidence is
    # required is therefore unknown, and an unknown requirement must not be reported as
    # met. Without this branch the whole dimension went silent while the summary below
    # still counted the task as checked: a pass built on a comparison never made.
    fail_msg "$task_id execution mode '$effective_mode' — TDD evidence requirement NOT verified"
  fi
done < <(completed_task_lines "$PLAN_FILE")

if [[ "$TASK_COUNT" -eq 0 ]]; then
  warn_msg "No completed T<n> tasks found"
else
  pass_msg "$TASK_COUNT completed task(s) checked"
fi

echo ""
echo "══════════════════════════════════"
printf "📊 Task Evidence Lint: %s fail(s), %s warning(s)\n" "$FAILS" "$WARNS"
if [[ "$FAILS" -eq 0 ]]; then
  echo "✅ PASS"
  exit 0
fi
echo "❌ FAIL"
exit 1

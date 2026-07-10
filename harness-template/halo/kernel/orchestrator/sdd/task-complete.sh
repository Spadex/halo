#!/usr/bin/env bash
# task-complete.sh — Mark one plan task complete only after required evidence exists.
source "$(dirname "$0")/../../_lib.sh"

usage_line="task-complete.sh <spec-id|path/to/plan.md> <task-id> [--json]"
for arg in "$@"; do
  [[ "$arg" == "--help" || "$arg" == "-h" ]] && cli_help "task complete" "Mark one plan task complete after evidence checks" \
    "$usage_line" \
    "task-complete.sh modern-feature T1 --json"
done

INPUT="${1:-}"
TASK_ID="${2:-}"
FORMAT="text"

shift $(( $# >= 2 ? 2 : $# ))
for arg in "$@"; do
  case "$arg" in
    --json) FORMAT="json" ;;
    *) echo "Unknown argument: $arg"; echo "Usage: $usage_line"; exit 1 ;;
  esac
done

resolve_plan_file() {
  local input="$1" abs
  [[ -n "$input" && -n "$TASK_ID" ]] || { echo "Usage: $usage_line"; exit 1; }
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

task_exists() {
  local task_id="$1" file="$2"
  grep -qE "^- \\[[ xX]\\] ${task_id}:" "$file"
}

task_is_complete() {
  local task_id="$1" file="$2"
  grep -qE "^- \\[[xX]\\] ${task_id}:" "$file"
}

valid_tdd_evidence() {
  local file="$1"
  [[ -f "$file" ]] || return 1
  yq -e '.kind == "tdd-evidence" and .status == "pass" and (.red.exit_code | tonumber) != 0 and (.green.exit_code | tonumber) == 0 and ((.ac_ids // []) | length > 0)' "$file" >/dev/null 2>&1
}

red_task_has_cycle_evidence() {
  local body="$1" ac evidence
  while IFS= read -r ac; do
    [[ -n "$ac" ]] || continue
    while IFS= read -r evidence; do
      [[ -n "$evidence" ]] || continue
      if valid_tdd_evidence "$evidence" && yq -r '.ac_ids[]?' "$evidence" 2>/dev/null | grep -qxF "$ac"; then
        return 0
      fi
    done < <(find "$EVIDENCE_ROOT" -path '*/tdd-evidence.json' -type f -print 2>/dev/null | sort)
  done < <(grep -oE 'AC-[0-9]+' <<< "$body" | sort -u || true)
  return 1
}

mark_task_complete() {
  local task_id="$1" file="$2" tmp
  tmp="$(mktemp)"
  awk -v task_id="$task_id" '
    $0 ~ "^- \\[ \\] " task_id ":" {
      sub(/^- \[ \]/, "- [x]")
    }
    { print }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

json_escape() {
  local value="${1:-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\r'/}"
  value="${value//$'\n'/\\n}"
  printf '%s' "$value"
}

json_result() {
  local status="$1" message="$2"
  printf '{\n'
  printf '  "schema_version": "halo.task-complete.v1",\n'
  printf '  "kind": "task-complete",\n'
  printf '  "status": "%s",\n' "$(json_escape "$status")"
  printf '  "spec_id": "%s",\n' "$(json_escape "$SPEC_ID")"
  printf '  "task_id": "%s",\n' "$(json_escape "$TASK_ID")"
  printf '  "plan_file": "%s",\n' "$(json_escape "$PLAN_REL")"
  printf '  "message": "%s"\n' "$(json_escape "$message")"
  printf '}\n'
}

fail_complete() {
  local message="$1"
  if [[ "$FORMAT" == "json" ]]; then
    json_result "fail" "$message"
  else
    echo "$message"
  fi
  exit 1
}

PLAN_FILE="$(resolve_plan_file "$INPUT")"
SPEC_DIR="$(dirname "$PLAN_FILE")"
SPEC_FILE="$SPEC_DIR/spec.md"
SPEC_ID="$(basename "$SPEC_DIR")"
PLAN_REL="$(rel_path "$PLAN_FILE")"
EVIDENCE_ROOT="$PROJECT_ROOT/.halo/sdd/$SPEC_ID"
MODE="unknown"

case "$TASK_ID" in
  T[0-9]*|RED-[0-9]*) ;;
  *) fail_complete "Invalid task id: $TASK_ID" ;;
esac

if [[ -f "$SPEC_FILE" ]]; then
  MODE="$(frontmatter_value "execution_mode" "$SPEC_FILE")"
fi
if [[ -z "$MODE" || "$MODE" == "unknown" ]]; then
  MODE="$(grep -Eim1 'Execution mode:[[:space:]]*(plan|tdd)' "$PLAN_FILE" 2>/dev/null | sed -E 's/.*Execution mode:[[:space:]]*//; s/[`"]//g' || true)"
fi
MODE="${MODE:-unknown}"

task_exists "$TASK_ID" "$PLAN_FILE" || fail_complete "Task not found in plan.md: $TASK_ID"
if task_is_complete "$TASK_ID" "$PLAN_FILE"; then
  [[ "$FORMAT" == "json" ]] && json_result "unchanged" "Task already complete" || echo "Task already complete: $TASK_ID"
  exit 0
fi

if [[ -x "$KERNEL_DIR/orchestrator/sdd/plan-lint.sh" ]]; then
  bash "$KERNEL_DIR/orchestrator/sdd/plan-lint.sh" "$PLAN_FILE" >/dev/null
fi

BODY="$(task_body "$TASK_ID" "$PLAN_FILE")"
if [[ "$TASK_ID" == T* ]]; then
  TASK_DIR="$EVIDENCE_ROOT/$TASK_ID"
  [[ -f "$TASK_DIR/brief.md" ]] || fail_complete "$TASK_ID missing brief.md"
  [[ -f "$TASK_DIR/review-package.md" ]] || fail_complete "$TASK_ID missing review-package.md"
  if [[ "$MODE" == "tdd" ]]; then
    valid_tdd_evidence "$TASK_DIR/tdd-evidence.json" || fail_complete "$TASK_ID missing or invalid tdd-evidence.json"
  fi
else
  red_task_has_cycle_evidence "$BODY" || fail_complete "$TASK_ID missing matching TDD cycle evidence"
fi

mark_task_complete "$TASK_ID" "$PLAN_FILE"

if [[ "$FORMAT" == "json" ]]; then
  json_result "completed" "Task marked complete"
else
  echo "Task marked complete: $TASK_ID"
fi

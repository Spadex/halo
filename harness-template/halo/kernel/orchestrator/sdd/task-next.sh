#!/usr/bin/env bash
# task-next.sh — Print the next incomplete PrismSpec/Halo plan task.
source "$(dirname "$0")/../../_lib.sh"

usage_line="task-next.sh <spec-id|path/to/plan.md> [--task=<id> | --all] [--json]"
for arg in "$@"; do
  [[ "$arg" == "--help" || "$arg" == "-h" ]] && cli_help "task next" "Print the next incomplete plan task" \
    "$usage_line" \
    "task-next.sh modern-feature --json" \
    "task-next.sh modern-feature --task=RED-1 --json" \
    "task-next.sh modern-feature --all --json"
done

INPUT="${1:-}"
FORMAT="text"
REQ_TASK_ID=""
TASK_FLAG="false"
LIST_ALL="false"

shift $(( $# >= 1 ? 1 : $# ))
for arg in "$@"; do
  case "$arg" in
    --json) FORMAT="json" ;;
    --all) LIST_ALL="true" ;;
    --task=*) REQ_TASK_ID="${arg#--task=}"; TASK_FLAG="true" ;;
    *) echo "Unknown argument: $arg"; echo "Usage: $usage_line"; exit 1 ;;
  esac
done
if [[ "$LIST_ALL" == "true" && "$TASK_FLAG" == "true" ]]; then
  echo "--task and --all are mutually exclusive"; echo "Usage: $usage_line"; exit 1
fi
if [[ "$TASK_FLAG" == "true" ]] && ! [[ "$REQ_TASK_ID" =~ ^(T|RED-)[0-9]+$ ]]; then
  echo "Invalid task id: $REQ_TASK_ID"; echo "Usage: $usage_line"; exit 1
fi

resolve_plan_file() {
  local input="$1" abs
  [[ -n "$input" ]] || { echo "Usage: $usage_line"; exit 1; }
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

spec_file_for_plan() {
  local plan="$1" dir
  dir="$(dirname "$plan")"
  [[ -f "$dir/spec.md" ]] && printf '%s' "$dir/spec.md"
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

extract_task_id() {
  local line="$1"
  sed -E 's/^- \[[ xX]\] ((T[0-9]+|RED-[0-9]+)):.*/\1/' <<< "$line"
}

extract_task_title() {
  local line="$1"
  sed -E 's/^- \[[ xX]\] (T[0-9]+|RED-[0-9]+):[[:space:]]*//' <<< "$line"
}

field_value() {
  local labels="$1" body="$2"
  grep -Eim1 "^[[:space:]]+-[[:space:]]+(${labels})[[:space:]]*[:：]" <<< "$body" \
    | sed -E "s/^[[:space:]]+-[[:space:]]+(${labels})[[:space:]]*[:：][[:space:]]*//; s/^[\`\"]+|[\`\"]+$//g" \
    || true
}

execution_mode() {
  local spec="$1" plan="$2" value
  if [[ -n "$spec" && -f "$spec" ]]; then
    value="$(grep -Eim1 '^execution_mode:[[:space:]]*(plan|tdd)' "$spec" 2>/dev/null | sed -E 's/.*execution_mode:[[:space:]]*//; s/[`"]//g' || true)"
  fi
  [[ -n "$value" ]] || value="$(grep -Eim1 'Execution mode:[[:space:]]*(plan|tdd)' "$plan" 2>/dev/null | sed -E 's/.*Execution mode:[[:space:]]*//; s/[`"]//g' || true)"
  [[ -n "$value" ]] || value="$(grep -Eim1 '执行模式[[:space:]]*[:：][[:space:]]*(plan|tdd|`plan`|`tdd`)' "$plan" 2>/dev/null | sed -E 's/.*执行模式[[:space:]]*[:：][[:space:]]*//; s/[`"]//g' || true)"
  printf '%s' "${value:-unknown}"
}

json_escape() {
  local value="${1:-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\r'/}"
  value="${value//$'\n'/\\n}"
  printf '%s' "$value"
}

json_ac_refs() {
  local refs="$1" first=true ac
  printf '['
  while IFS= read -r ac; do
    [[ -n "$ac" ]] || continue
    if [[ "$first" == "true" ]]; then
      first=false
    else
      printf ', '
    fi
    printf '"%s"' "$(json_escape "$ac")"
  done < <(grep -oE 'AC-[0-9]+' <<< "$refs" | sort -u || true)
  printf ']'
}

# Fill the TASK_* globals from one checkbox task line. Shared by the default
# next-task path, --task, and --all.
load_task_fields() {
  local line="$1"
  TASK_ID="$(extract_task_id "$line")"
  TITLE="$(extract_task_title "$line")"
  BODY="$(task_body "$TASK_ID" "$PLAN_FILE")"
  LINE_NUMBER="$(grep -nF -- "$line" "$PLAN_FILE" | head -1 | cut -d: -f1)"
  TASK_KIND="implementation"
  [[ "$TASK_ID" == RED-* ]] && TASK_KIND="red-test"
  COMPLETE="false"
  case "$line" in
    "- [x]"*|"- [X]"*) COMPLETE="true" ;;
  esac
  MODE="$(field_value "Mode|模式" "$BODY")"
  [[ -n "$MODE" ]] || MODE="$(execution_mode "$SPEC_FILE" "$PLAN_FILE")"
  SCOPE="$(field_value "Scope|范围" "$BODY")"
  VERIFICATION="$(field_value "Verification|验证方式" "$BODY")"
  # Declaration line first, whole-body fallback, then narrowed to the ACs this spec
  # declares: reporting a prose mention or another spec's AC here sends the
  # implementer off producing evidence for an AC this task never claimed.
  AC_REFS="$(task_covered_acs "$BODY" "$SPEC_FILE" | tr '\n' ' ')"
  EVIDENCE_ROOT=".halo/sdd/$SPEC_ID/$TASK_ID"
}

# Print the per-task JSON fields (task_id .. evidence_root) at the given indent.
# include_complete adds the checkbox state; the default next-task output omits it
# to stay byte-compatible with existing consumers.
print_task_fields() {
  local indent="$1" include_complete="$2"
  printf '%s"task_id": "%s",\n' "$indent" "$(json_escape "$TASK_ID")"
  printf '%s"task_kind": "%s",\n' "$indent" "$TASK_KIND"
  printf '%s"title": "%s",\n' "$indent" "$(json_escape "$TITLE")"
  printf '%s"line": %s,\n' "$indent" "${LINE_NUMBER:-0}"
  if [[ "$include_complete" == "true" ]]; then
    printf '%s"complete": %s,\n' "$indent" "$COMPLETE"
  fi
  printf '%s"mode": "%s",\n' "$indent" "$(json_escape "$MODE")"
  printf '%s"scope": "%s",\n' "$indent" "$(json_escape "$SCOPE")"
  printf '%s"ac_refs": %s,\n' "$indent" "$(json_ac_refs "$AC_REFS")"
  printf '%s"verification": "%s",\n' "$indent" "$(json_escape "$VERIFICATION")"
  printf '%s"evidence_root": "%s"\n' "$indent" "$(json_escape "$EVIDENCE_ROOT")"
}

PLAN_FILE="$(resolve_plan_file "$INPUT")"
SPEC_FILE="$(spec_file_for_plan "$PLAN_FILE")"
PLAN_REL="$(rel_path "$PLAN_FILE")"
SPEC_ID="$(basename "$(dirname "$PLAN_FILE")")"

# --task=<id>: inspect one task regardless of checkbox state. Plan-time preflight
# and post-hoc audits both need completed tasks, so completion is reported as a
# field, not applied as a filter.
if [[ "$TASK_FLAG" == "true" ]]; then
  TASK_LINE="$(grep -E "^- \[[ xX]\] ${REQ_TASK_ID}:" "$PLAN_FILE" 2>/dev/null | head -1 || true)"
  if [[ -z "$TASK_LINE" ]]; then
    if [[ "$FORMAT" == "json" ]]; then
      printf '{\n'
      printf '  "schema_version": "halo.task-next.v1",\n'
      printf '  "kind": "task-next",\n'
      printf '  "status": "not-found",\n'
      printf '  "spec_id": "%s",\n' "$(json_escape "$SPEC_ID")"
      printf '  "plan_file": "%s",\n' "$(json_escape "$PLAN_REL")"
      printf '  "task_id": "%s"\n' "$(json_escape "$REQ_TASK_ID")"
      printf '}\n'
    else
      echo "Task not found in plan.md: $REQ_TASK_ID"
    fi
    exit 1
  fi
  load_task_fields "$TASK_LINE"
  if [[ "$FORMAT" == "json" ]]; then
    printf '{\n'
    printf '  "schema_version": "halo.task-next.v1",\n'
    printf '  "kind": "task-next",\n'
    printf '  "status": "selected",\n'
    printf '  "spec_id": "%s",\n' "$(json_escape "$SPEC_ID")"
    printf '  "plan_file": "%s",\n' "$(json_escape "$PLAN_REL")"
    print_task_fields "  " "true"
    printf '}\n'
    exit 0
  fi
  echo "Task: $TASK_ID"
  echo "Kind: $TASK_KIND"
  echo "Title: $TITLE"
  echo "Complete: $COMPLETE"
  echo "Mode: $MODE"
  echo "AC refs: ${AC_REFS:-none}"
  echo "Plan: $PLAN_REL:$LINE_NUMBER"
  echo "Evidence root: $EVIDENCE_ROOT"
  echo ""
  echo "$BODY"
  exit 0
fi

# --all: list every task (completed included) with the same per-task view, so a
# plan author can preflight the gate-recognized AC set of each task in one call.
if [[ "$LIST_ALL" == "true" ]]; then
  if [[ "$FORMAT" == "json" ]]; then
    printf '{\n'
    printf '  "schema_version": "halo.task-next.v1",\n'
    printf '  "kind": "task-list",\n'
    printf '  "spec_id": "%s",\n' "$(json_escape "$SPEC_ID")"
    printf '  "plan_file": "%s",\n' "$(json_escape "$PLAN_REL")"
    printf '  "tasks": [\n'
    FIRST_TASK="true"
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      load_task_fields "$line"
      if [[ "$FIRST_TASK" == "true" ]]; then
        FIRST_TASK="false"
      else
        printf ',\n'
      fi
      printf '    {\n'
      print_task_fields "      " "true"
      printf '    }'
    done < <(grep -E '^- \[[ xX]\] (T[0-9]+|RED-[0-9]+):' "$PLAN_FILE" 2>/dev/null || true)
    if [[ "$FIRST_TASK" == "true" ]]; then
      printf '  ]\n'
    else
      printf '\n  ]\n'
    fi
    printf '}\n'
    exit 0
  fi
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    load_task_fields "$line"
    STATE="todo"
    [[ "$COMPLETE" == "true" ]] && STATE="done"
    echo "$TASK_ID [$STATE] $TASK_KIND line=$LINE_NUMBER ACs: ${AC_REFS:-none}"
  done < <(grep -E '^- \[[ xX]\] (T[0-9]+|RED-[0-9]+):' "$PLAN_FILE" 2>/dev/null || true)
  exit 0
fi

NEXT_LINE="$(grep -E '^- \[ \] (T[0-9]+|RED-[0-9]+):' "$PLAN_FILE" 2>/dev/null | head -1 || true)"

if [[ -z "$NEXT_LINE" ]]; then
  if [[ "$FORMAT" == "json" ]]; then
    printf '{\n'
    printf '  "schema_version": "halo.task-next.v1",\n'
    printf '  "kind": "task-next",\n'
    printf '  "status": "complete",\n'
    printf '  "spec_id": "%s",\n' "$(json_escape "$SPEC_ID")"
    printf '  "plan_file": "%s",\n' "$(json_escape "$PLAN_REL")"
    printf '  "next_task": null\n'
    printf '}\n'
  else
    echo "No incomplete tasks found: $PLAN_REL"
  fi
  exit 0
fi

load_task_fields "$NEXT_LINE"

if [[ "$FORMAT" == "json" ]]; then
  printf '{\n'
  printf '  "schema_version": "halo.task-next.v1",\n'
  printf '  "kind": "task-next",\n'
  printf '  "status": "next",\n'
  printf '  "spec_id": "%s",\n' "$(json_escape "$SPEC_ID")"
  printf '  "plan_file": "%s",\n' "$(json_escape "$PLAN_REL")"
  print_task_fields "  " "false"
  printf '}\n'
  exit 0
fi

echo "Next task: $TASK_ID"
echo "Kind: $TASK_KIND"
echo "Title: $TITLE"
echo "Mode: $MODE"
echo "AC refs: ${AC_REFS:-none}"
echo "Plan: $PLAN_REL:$LINE_NUMBER"
echo "Evidence root: $EVIDENCE_ROOT"
echo ""
echo "$BODY"

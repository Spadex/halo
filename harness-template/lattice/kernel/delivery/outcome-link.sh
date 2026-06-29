#!/usr/bin/env bash
# outcome-link.sh — Link post-run outcomes back to eval evidence.
source "$(dirname "$0")/../_lib.sh"

for arg in "$@"; do
  [[ "$arg" == "--help" || "$arg" == "-h" ]] && cli_help "outcome link" "Record outcome evidence linked to a Lattice eval run" \
    "outcome-link.sh record --eval=<run-id|eval.json> --type=<review_finding|rework|escaped_defect|incident|success> --severity=<none|low|medium|high|critical> --source=<source> --summary=<summary> [--context-ref=<ref>] [--owner=<name>]" \
    "outcome-link.sh record --eval=20260628T195355Z-5665 --type=escaped_defect --severity=high --source=production --summary=\"missing idempotency guard\" --context-ref=rules.md#idempotency"
done

ACTION="${1:-}"
EVAL_INPUT=""
TYPE=""
SEVERITY=""
SOURCE=""
SUMMARY=""
OWNER=""
OUT=""
CONTEXT_REFS=()

[[ $# -gt 0 ]] && shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --eval=*) EVAL_INPUT="${1#--eval=}" ;;
    --type=*) TYPE="${1#--type=}" ;;
    --severity=*) SEVERITY="${1#--severity=}" ;;
    --source=*) SOURCE="${1#--source=}" ;;
    --summary=*) SUMMARY="${1#--summary=}" ;;
    --owner=*) OWNER="${1#--owner=}" ;;
    --context-ref=*) CONTEXT_REFS+=("${1#--context-ref=}") ;;
    --out=*) OUT="${1#--out=}" ;;
    --eval|--type|--severity|--source|--summary|--owner|--context-ref|--out)
      key="$1"
      shift
      case "$key" in
        --eval) EVAL_INPUT="${1:-}" ;;
        --type) TYPE="${1:-}" ;;
        --severity) SEVERITY="${1:-}" ;;
        --source) SOURCE="${1:-}" ;;
        --summary) SUMMARY="${1:-}" ;;
        --owner) OWNER="${1:-}" ;;
        --context-ref) CONTEXT_REFS+=("${1:-}") ;;
        --out) OUT="${1:-}" ;;
      esac
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
  shift
done

json_escape() {
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

rel_path() {
  local path="$1"
  if [[ "$path" == "$PROJECT_ROOT/"* ]]; then
    printf '%s' "${path#$PROJECT_ROOT/}"
  else
    printf '%s' "$path"
  fi
}

safe_slug() {
  local s="$1"
  s="${s//[^A-Za-z0-9_.-]/-}"
  printf '%s' "$s"
}

json_get() {
  local file="$1" expr="$2" value
  value="$(yq -r "$expr // \"\"" "$file" 2>/dev/null || true)"
  [[ "$value" == "null" ]] && value=""
  printf '%s' "$value"
}

json_num() {
  local file="$1" expr="$2" value
  value="$(json_get "$file" "$expr")"
  if [[ "$value" =~ ^-?[0-9]+$ ]]; then
    printf '%s' "$value"
  else
    printf '0'
  fi
}

resolve_eval_json() {
  local input="$1" path
  [[ -n "$input" ]] || { echo "Missing --eval"; exit 1; }

  if [[ "$input" == /* ]]; then
    path="$input"
  elif [[ "$input" == *.json || "$input" == */* ]]; then
    path="$PROJECT_ROOT/$input"
  else
    path="$PROJECT_ROOT/lattice/state/eval-runs/$input.json"
  fi

  [[ -f "$path" ]] || { echo "Eval JSON not found: $input"; exit 1; }
  if ! yq -e '.run_id and .pipeline and .metrics' "$path" >/dev/null 2>&1; then
    echo "Invalid eval JSON: $(rel_path "$path")"
    exit 1
  fi
  printf '%s' "$path"
}

write_context_refs() {
  local idx
  for idx in "${!CONTEXT_REFS[@]}"; do
    [[ "$idx" -gt 0 ]] && printf ',\n'
    printf '    "%s"' "$(json_escape "${CONTEXT_REFS[$idx]}")"
  done
  [[ "${#CONTEXT_REFS[@]}" -gt 0 ]] && printf '\n'
}

case "$ACTION" in
  record) ;;
  *)
    echo "Usage: outcome-link.sh record --eval=<run-id|eval.json> --type=<type> --severity=<severity> --source=<source> --summary=<summary>"
    exit 1
    ;;
esac

case "$TYPE" in
  review_finding|rework|escaped_defect|incident|success) ;;
  "") echo "Missing --type"; exit 1 ;;
  *) echo "Invalid --type: $TYPE"; exit 1 ;;
esac

case "$SEVERITY" in
  none|low|medium|high|critical) ;;
  "") echo "Missing --severity"; exit 1 ;;
  *) echo "Invalid --severity: $SEVERITY"; exit 1 ;;
esac

[[ -n "$SOURCE" ]] || { echo "Missing --source"; exit 1; }
[[ -n "$SUMMARY" ]] || { echo "Missing --summary"; exit 1; }

EVAL_JSON="$(resolve_eval_json "$EVAL_INPUT")"
RUN_ID="$(json_get "$EVAL_JSON" '.run_id')"
SPEC_FILE="$(json_get "$EVAL_JSON" '.spec_file')"
GIT_SHA="$(json_get "$EVAL_JSON" '.git_sha')"
PIPELINE_STATUS="$(json_get "$EVAL_JSON" '.pipeline.status')"
CREATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
OUTCOME_ID="$(date -u +%Y%m%dT%H%M%SZ)-$(safe_slug "$TYPE")-$(safe_slug "$SEVERITY")-$$"

if [[ -z "$OUT" ]]; then
  OUT="$PROJECT_ROOT/lattice/state/outcomes/${OUTCOME_ID}.json"
elif [[ "$OUT" != /* ]]; then
  OUT="$PROJECT_ROOT/$OUT"
fi
mkdir -p "$(dirname "$OUT")"

{
  printf '{\n'
  printf '  "schema_version": "lattice.outcome-link.v1",\n'
  printf '  "kind": "outcome-link",\n'
  printf '  "outcome_id": "%s",\n' "$(json_escape "$OUTCOME_ID")"
  printf '  "created_at": "%s",\n' "$(json_escape "$CREATED_AT")"
  printf '  "eval_run": {\n'
  printf '    "run_id": "%s",\n' "$(json_escape "$RUN_ID")"
  printf '    "path": "%s",\n' "$(json_escape "$(rel_path "$EVAL_JSON")")"
  printf '    "spec_file": "%s",\n' "$(json_escape "$SPEC_FILE")"
  printf '    "git_sha": "%s",\n' "$(json_escape "$GIT_SHA")"
  printf '    "pipeline_status": "%s"\n' "$(json_escape "$PIPELINE_STATUS")"
  printf '  },\n'
  printf '  "outcome": {\n'
  printf '    "type": "%s",\n' "$(json_escape "$TYPE")"
  printf '    "severity": "%s",\n' "$(json_escape "$SEVERITY")"
  printf '    "source": "%s",\n' "$(json_escape "$SOURCE")"
  printf '    "summary": "%s",\n' "$(json_escape "$SUMMARY")"
  printf '    "owner": "%s"\n' "$(json_escape "$OWNER")"
  printf '  },\n'
  printf '  "context_refs": [\n'
  write_context_refs
  printf '  ],\n'
  printf '  "eval_metrics": {\n'
  printf '    "review_total": %s,\n' "$(json_num "$EVAL_JSON" '.metrics.review_total')"
  printf '    "review_failed": %s,\n' "$(json_num "$EVAL_JSON" '.metrics.review_failed')"
  printf '    "review_cannot_verify": %s\n' "$(json_num "$EVAL_JSON" '.metrics.review_cannot_verify')"
  printf '  }\n'
  printf '}\n'
} > "$OUT"

echo "Outcome link: $(rel_path "$OUT")"

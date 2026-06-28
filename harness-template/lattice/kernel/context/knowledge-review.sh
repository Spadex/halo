#!/usr/bin/env bash
# knowledge-review.sh — Record reviewer decisions for knowledge promotion.
source "$(dirname "$0")/../_lib.sh"

for arg in "$@"; do
  [[ "$arg" == "--help" || "$arg" == "-h" ]] && cli_help "knowledge review" "Record approve/reject decisions for context knowledge" \
    "knowledge-review.sh approve <draft-or-knowledge.md> --reviewer=<name> --reason=<reason> [--risk=low|medium|high] [--conflicts-checked]" \
    "knowledge-review.sh reject <draft-or-knowledge.md> --reviewer=<name> --reason=<reason>"
done

ACTION="${1:-}"
TARGET="${2:-}"
REVIEWER=""
REASON=""
RISK="medium"
CONFLICTS_CHECKED=false

shift $(( $# >= 2 ? 2 : $# ))
while [[ $# -gt 0 ]]; do
  case "$1" in
    --reviewer=*) REVIEWER="${1#--reviewer=}" ;;
    --reason=*) REASON="${1#--reason=}" ;;
    --risk=*) RISK="${1#--risk=}" ;;
    --conflicts-checked) CONFLICTS_CHECKED=true ;;
    --reviewer)
      shift
      REVIEWER="${1:-}"
      ;;
    --reason)
      shift
      REASON="${1:-}"
      ;;
    --risk)
      shift
      RISK="${1:-}"
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

target_path() {
  local path="$1" abs
  [[ -n "$path" ]] || { echo "Usage: knowledge-review.sh <approve|reject> <draft-or-knowledge.md>"; exit 1; }
  [[ "$path" == /* ]] && abs="$path" || abs="$PROJECT_ROOT/$path"
  [[ -f "$abs" ]] || { echo "Review target not found: $path"; exit 1; }
  case "$abs" in
    "$PROJECT_ROOT/lattice/context/drafts/"*|"$PROJECT_ROOT/lattice/context/knowledge/"*) printf '%s' "$abs" ;;
    *) echo "Target must be under lattice/context/drafts/ or lattice/context/knowledge/: $(rel_path "$abs")"; exit 1 ;;
  esac
}

case "$ACTION" in
  approve|reject) ;;
  *)
    echo "Usage: knowledge-review.sh <approve|reject> <draft-or-knowledge.md> --reviewer=<name> --reason=<reason>"
    exit 1
    ;;
esac

[[ -n "$REVIEWER" ]] || { echo "Missing --reviewer"; exit 1; }
[[ -n "$REASON" ]] || { echo "Missing --reason"; exit 1; }
case "$RISK" in
  low|medium|high) ;;
  *) echo "Invalid --risk: $RISK. Use low, medium, or high."; exit 1 ;;
esac

TARGET_ABS="$(target_path "$TARGET")"
TARGET_REL="$(rel_path "$TARGET_ABS")"
CREATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EVENT_ID="$(date -u +%Y%m%dT%H%M%SZ)-$(safe_slug "$(basename "$TARGET_ABS" .md)")-$$"
OUT="$PROJECT_ROOT/lattice/state/knowledge-reviews/${EVENT_ID}.json"
mkdir -p "$(dirname "$OUT")"

{
  printf '{\n'
  printf '  "schema_version": "lattice.knowledge-review.v1",\n'
  printf '  "kind": "knowledge-review",\n'
  printf '  "action": "%s",\n' "$(json_escape "$ACTION")"
  printf '  "created_at": "%s",\n' "$(json_escape "$CREATED_AT")"
  printf '  "target": "%s",\n' "$(json_escape "$TARGET_REL")"
  printf '  "reviewer": "%s",\n' "$(json_escape "$REVIEWER")"
  printf '  "reason": "%s",\n' "$(json_escape "$REASON")"
  printf '  "risk": "%s",\n' "$(json_escape "$RISK")"
  printf '  "conflicts_checked": %s\n' "$CONFLICTS_CHECKED"
  printf '}\n'
} > "$OUT"

echo "Knowledge review: $(rel_path "$OUT")"

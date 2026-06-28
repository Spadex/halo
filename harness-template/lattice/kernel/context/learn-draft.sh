#!/usr/bin/env bash
# learn-draft.sh — Promote or discard context learn drafts.
source "$(dirname "$0")/../_lib.sh"

for arg in "$@"; do
  [[ "$arg" == "--help" || "$arg" == "-h" ]] && cli_help "learn draft" "Promote or discard context learn drafts" \
    "learn-draft.sh promote <draft.md> [--to=lattice/context/knowledge/pitfalls.md]" \
    "learn-draft.sh discard <draft.md> --reason=<reason>"
done

ACTION="${1:-}"
DRAFT="${2:-}"
TARGET="lattice/context/knowledge/pitfalls.md"
REASON=""

shift $(( $# >= 2 ? 2 : $# ))
while [[ $# -gt 0 ]]; do
  case "$1" in
    --to=*) TARGET="${1#--to=}" ;;
    --reason=*) REASON="${1#--reason=}" ;;
    --to)
      shift
      TARGET="${1:-}"
      ;;
    --reason)
      shift
      REASON="${1:-}"
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

frontmatter_value() {
  local key="$1" file="$2"
  awk -F': *' -v key="$key" '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { exit }
    in_fm && $1 == key {
      value = $0
      sub("^[^:]+:[ ]*", "", value)
      gsub(/^"|"$/, "", value)
      print value
      exit
    }
  ' "$file"
}

lesson_candidate() {
  local file="$1"
  awk '
    /^## Lesson Candidate/ { capture = 1; next }
    /^## / && capture { exit }
    capture { print }
  ' "$file" | sed '/^[[:space:]]*$/d'
}

safe_draft_path() {
  local path="$1" abs
  [[ -n "$path" ]] || { echo "Usage: learn-draft.sh <promote|discard> <draft.md>"; exit 1; }
  [[ "$path" == /* ]] && abs="$path" || abs="$PROJECT_ROOT/$path"
  [[ -f "$abs" ]] || { echo "Draft not found: $path"; exit 1; }
  case "$abs" in
    "$PROJECT_ROOT/lattice/context/drafts/"*) printf '%s' "$abs" ;;
    *) echo "Draft must be under lattice/context/drafts/: $(rel_path "$abs")"; exit 1 ;;
  esac
}

safe_target_path() {
  local path="$1" abs
  [[ -n "$path" ]] || { echo "Target cannot be empty"; exit 1; }
  [[ "$path" == /* ]] && abs="$path" || abs="$PROJECT_ROOT/$path"
  case "$abs" in
    "$PROJECT_ROOT/lattice/context/knowledge/"*) printf '%s' "$abs" ;;
    *) echo "Target must be under lattice/context/knowledge/: $(rel_path "$abs")"; exit 1 ;;
  esac
}

write_event_json() {
  local action="$1" draft_rel="$2" archive_rel="$3" target_rel="$4" reason="$5" run_id="$6" category="$7" action_hint="$8" event_file="$9"
  mkdir -p "$(dirname "$event_file")"
  {
    printf '{\n'
    printf '  "schema_version": "lattice.learn-promotion.v1",\n'
    printf '  "kind": "learn-promotion",\n'
    printf '  "action": "%s",\n' "$(json_escape "$action")"
    printf '  "created_at": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '  "draft": "%s",\n' "$(json_escape "$draft_rel")"
    printf '  "archive": "%s",\n' "$(json_escape "$archive_rel")"
    printf '  "target": "%s",\n' "$(json_escape "$target_rel")"
    printf '  "reason": "%s",\n' "$(json_escape "$reason")"
    printf '  "run_id": "%s",\n' "$(json_escape "$run_id")"
    printf '  "failure_category": "%s",\n' "$(json_escape "$category")"
    printf '  "default_action": "%s"\n' "$(json_escape "$action_hint")"
    printf '}\n'
  } > "$event_file"
}

DRAFT_ABS="$(safe_draft_path "$DRAFT")"
DRAFT_REL="$(rel_path "$DRAFT_ABS")"
BASENAME="$(basename "$DRAFT_ABS")"
RUN_ID="$(frontmatter_value "run_id" "$DRAFT_ABS")"
FAILURE_CATEGORY="$(frontmatter_value "failure_category" "$DRAFT_ABS")"
DEFAULT_ACTION="$(frontmatter_value "default_action" "$DRAFT_ABS")"
[[ -n "$RUN_ID" ]] || RUN_ID="${BASENAME%.md}"
SAFE_RUN_ID="${RUN_ID//[^A-Za-z0-9_.-]/-}"
EVENT_ID="$(date -u +%Y%m%dT%H%M%SZ)-${SAFE_RUN_ID}-$$"
EVENT_FILE="$PROJECT_ROOT/lattice/state/learn-promotions/${EVENT_ID}.json"

archive_path() {
  local status="$1" basename="$2" archive
  archive="$PROJECT_ROOT/lattice/context/drafts/$status/$basename"
  if [[ -e "$archive" ]]; then
    archive="$PROJECT_ROOT/lattice/context/drafts/$status/${EVENT_ID}-${basename}"
  fi
  printf '%s' "$archive"
}

case "$ACTION" in
  promote)
    TARGET_ABS="$(safe_target_path "$TARGET")"
    TARGET_REL="$(rel_path "$TARGET_ABS")"
    ARCHIVE_ABS="$(archive_path "promoted" "$BASENAME")"
    ARCHIVE_REL="$(rel_path "$ARCHIVE_ABS")"
    LESSON="$(lesson_candidate "$DRAFT_ABS")"
    [[ -n "$LESSON" ]] || { echo "Draft has no Lesson Candidate section: $DRAFT_REL"; exit 1; }

    mkdir -p "$(dirname "$TARGET_ABS")" "$(dirname "$ARCHIVE_ABS")"
    {
      printf '\n## Promoted Learn Draft: %s\n\n' "$RUN_ID"
      printf '**Source draft**: `%s`  \n' "$ARCHIVE_REL"
      printf '**Promoted at**: `%s`  \n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      printf '**Failure category**: `%s`  \n' "${FAILURE_CATEGORY:-unknown}"
      printf '**Default action**: `%s`  \n\n' "${DEFAULT_ACTION:-unknown}"
      printf '%s\n' "$LESSON"
      printf '\n'
    } >> "$TARGET_ABS"
    mv "$DRAFT_ABS" "$ARCHIVE_ABS"
    write_event_json "promote" "$DRAFT_REL" "$ARCHIVE_REL" "$TARGET_REL" "" "$RUN_ID" "$FAILURE_CATEGORY" "$DEFAULT_ACTION" "$EVENT_FILE"
    echo "✅ Promoted learn draft → $TARGET_REL"
    echo "🧾 Event: $(rel_path "$EVENT_FILE")"
    if [[ -x "$PROJECT_ROOT/lattice/kernel/context/knowledge-lint.sh" ]]; then
      bash "$PROJECT_ROOT/lattice/kernel/context/knowledge-lint.sh" --target="$TARGET_REL" || true
    fi
    ;;
  discard)
    [[ -n "$REASON" ]] || { echo "Discard requires --reason=<reason>"; exit 1; }
    ARCHIVE_ABS="$(archive_path "discarded" "$BASENAME")"
    ARCHIVE_REL="$(rel_path "$ARCHIVE_ABS")"
    mkdir -p "$(dirname "$ARCHIVE_ABS")"
    mv "$DRAFT_ABS" "$ARCHIVE_ABS"
    write_event_json "discard" "$DRAFT_REL" "$ARCHIVE_REL" "" "$REASON" "$RUN_ID" "$FAILURE_CATEGORY" "$DEFAULT_ACTION" "$EVENT_FILE"
    echo "✅ Discarded learn draft"
    echo "🧾 Event: $(rel_path "$EVENT_FILE")"
    ;;
  *)
    echo "Usage: learn-draft.sh <promote|discard> <draft.md> [--to=...] [--reason=...]"
    exit 1
    ;;
esac

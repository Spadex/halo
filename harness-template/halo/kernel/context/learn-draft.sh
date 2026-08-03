#!/usr/bin/env bash
# learn-draft.sh — Promote or discard context learn drafts.
source "$(dirname "$0")/../_lib.sh"

for arg in "$@"; do
  [[ "$arg" == "--help" || "$arg" == "-h" ]] && cli_help "learn draft" "Promote or discard context learn drafts" \
    "learn-draft.sh promote <draft.md> [--to=halo/context/knowledge/pitfalls.md] [--require-review]" \
    "learn-draft.sh discard <draft.md> --reason=<reason>"
done

ACTION="${1:-}"
DRAFT="${2:-}"
TARGET="halo/context/knowledge/pitfalls.md"
REASON=""
REQUIRE_REVIEW=false

shift $(( $# >= 2 ? 2 : $# ))
while [[ $# -gt 0 ]]; do
  case "$1" in
    --to=*) TARGET="${1#--to=}" ;;
    --reason=*) REASON="${1#--reason=}" ;;
    --require-review) REQUIRE_REVIEW=true ;;
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

# Knowledge files ship as tables — the default promote target
# halo/context/knowledge/pitfalls.md is `| Pitfall | Trigger | Guidance | Source |`
# followed by a `## Do Not Repeat` section. Appending a `## Promoted Learn Draft`
# block to end-of-file therefore drops the lesson OUTSIDE the table, after that
# trailing section, and knowledge-lint cannot see it because the file already has a
# Source column at file level. Detect the target's shape and write a row instead.
#
# Emits the 1-based line number of the first table's header row, or nothing.
table_header_line() {
  local file="$1"
  awk '
    NR > 1 && $0 ~ /^[[:space:]]*\|[-:| \t]+$/ && $0 ~ /-/ && prev ~ /^[[:space:]]*\|/ {
      print NR - 1
      exit
    }
    { prev = $0 }
  ' "$file"
}

# Last line of that table body, so rows land inside the table rather than at EOF.
# Falls back to the separator line when the table has no rows yet.
table_last_row_line() {
  local file="$1" header="$2"
  awk -v h="$header" '
    NR < h + 2 { next }
    /^[[:space:]]*\|/ { last = NR; next }
    { exit }
    END { print (last ? last : h + 1) }
  ' "$file"
}

table_columns() {
  local file="$1" header="$2"
  sed -n "${header}p" "$file" | awk -F'|' '{
    for (i = 2; i < NF; i++) { c = $i; gsub(/^[ \t]+|[ \t]+$/, "", c); print c }
  }'
}

safe_draft_path() {
  local path="$1" abs
  [[ -n "$path" ]] || { echo "Usage: learn-draft.sh <promote|discard> <draft.md>"; exit 1; }
  [[ "$path" == /* ]] && abs="$path" || abs="$PROJECT_ROOT/$path"
  [[ -f "$abs" ]] || { echo "Draft not found: $path"; exit 1; }
  case "$abs" in
    "$PROJECT_ROOT/halo/context/drafts/"*) printf '%s' "$abs" ;;
    *) echo "Draft must be under halo/context/drafts/: $(rel_path "$abs")"; exit 1 ;;
  esac
}

safe_target_path() {
  local path="$1" abs
  [[ -n "$path" ]] || { echo "Target cannot be empty"; exit 1; }
  [[ "$path" == /* ]] && abs="$path" || abs="$PROJECT_ROOT/$path"
  case "$abs" in
    "$PROJECT_ROOT/halo/context/knowledge/"*) printf '%s' "$abs" ;;
    *) echo "Target must be under halo/context/knowledge/: $(rel_path "$abs")"; exit 1 ;;
  esac
}

write_event_json() {
  local action="$1" draft_rel="$2" archive_rel="$3" target_rel="$4" reason="$5" run_id="$6" category="$7" action_hint="$8" event_file="$9"
  mkdir -p "$(dirname "$event_file")"
  {
    printf '{\n'
    printf '  "schema_version": "halo.learn-promotion.v1",\n'
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

has_approved_review() {
  local draft_rel="$1" event
  for event in "$PROJECT_ROOT"/halo/state/knowledge-reviews/*.json; do
    [[ -f "$event" ]] || continue
    if yq -e ".kind == \"knowledge-review\" and .action == \"approve\" and .target == \"${draft_rel}\" and .conflicts_checked == true" "$event" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
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
EVENT_FILE="$PROJECT_ROOT/halo/state/learn-promotions/${EVENT_ID}.json"

archive_path() {
  local status="$1" basename="$2" archive
  archive="$PROJECT_ROOT/halo/context/drafts/$status/$basename"
  if [[ -e "$archive" ]]; then
    archive="$PROJECT_ROOT/halo/context/drafts/$status/${EVENT_ID}-${basename}"
  fi
  printf '%s' "$archive"
}

case "$ACTION" in
  promote)
    if [[ "$REQUIRE_REVIEW" == "true" ]] && ! has_approved_review "$DRAFT_REL"; then
      echo "Promotion requires an approved knowledge review with conflicts_checked=true: $DRAFT_REL"
      echo "Run: halo/kernel/context/knowledge-review.sh approve $DRAFT_REL --reviewer=<name> --reason=<reason> --conflicts-checked"
      exit 1
    fi
    TARGET_ABS="$(safe_target_path "$TARGET")"
    TARGET_REL="$(rel_path "$TARGET_ABS")"
    ARCHIVE_ABS="$(archive_path "promoted" "$BASENAME")"
    ARCHIVE_REL="$(rel_path "$ARCHIVE_ABS")"
    LESSON="$(lesson_candidate "$DRAFT_ABS")"
    [[ -n "$LESSON" ]] || { echo "Draft has no Lesson Candidate section: $DRAFT_REL"; exit 1; }

    mkdir -p "$(dirname "$TARGET_ABS")" "$(dirname "$ARCHIVE_ABS")"
    HEADER_LINE=""
    [[ -f "$TARGET_ABS" ]] && HEADER_LINE="$(table_header_line "$TARGET_ABS")"
    SHAPE_NOTE=""
    if [[ -n "$HEADER_LINE" ]]; then
      COLUMNS="$(table_columns "$TARGET_ABS" "$HEADER_LINE")"
      COL_COUNT="$(printf '%s\n' "$COLUMNS" | grep -c . || true)"
      SOURCE_COL="$({ printf '%s\n' "$COLUMNS" | grep -niE '^(source|来源|出处)$' || true; } | head -1 | cut -d: -f1)"
      INSERT_AFTER="$(table_last_row_line "$TARGET_ABS" "$HEADER_LINE")"
      ROWS_FILE="$(mktemp)"
      ROW_COUNT=0
      while IFS= read -r candidate; do
        [[ -n "$candidate" ]] || continue
        text="$(sed -E 's/^[[:space:]]*[-*][[:space:]]+//' <<< "$candidate")"
        # An unescaped pipe in the lesson text would silently add a column to the row.
        text="${text//|/\\|}"
        row=""
        for ((col = 1; col <= COL_COUNT; col++)); do
          if [[ "$col" -eq 1 ]]; then
            row+="| $text "
          elif [[ -n "$SOURCE_COL" && "$col" -eq "$SOURCE_COL" ]]; then
            row+="| \`$ARCHIVE_REL\` "
          else
            row+="| — "
          fi
        done
        printf '%s|\n' "$row" >> "$ROWS_FILE"
        ROW_COUNT=$((ROW_COUNT + 1))
      done <<< "$LESSON"
      TMP_TARGET="$(mktemp)"
      # Rows are read from a file, not passed through awk -v: awk expands backslash
      # escapes in -v values, which would undo the pipe escaping above.
      awk -v n="$INSERT_AFTER" -v rowfile="$ROWS_FILE" '
        { print }
        NR == n { while ((getline line < rowfile) > 0) print line; close(rowfile) }
      ' "$TARGET_ABS" > "$TMP_TARGET"
      mv "$TMP_TARGET" "$TARGET_ABS"
      rm -f "$ROWS_FILE"
      SHAPE_NOTE=" ($ROW_COUNT row(s) added to knowledge table)"
      # Promotion metadata is deliberately NOT written into the knowledge file here:
      # run id, failure category, and timestamp already live in the audit event under
      # halo/state/learn-promotions/ and in the archived draft. Knowledge files hold
      # the lesson, not the adjudication that produced it.
    else
      {
        printf '\n## Promoted Learn Draft: %s\n\n' "$RUN_ID"
        printf '**Source draft**: `%s`  \n' "$ARCHIVE_REL"
        printf '**Promoted at**: `%s`  \n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf '**Failure category**: `%s`  \n' "${FAILURE_CATEGORY:-unknown}"
        printf '**Default action**: `%s`  \n\n' "${DEFAULT_ACTION:-unknown}"
        printf '%s\n' "$LESSON"
        printf '\n'
      } >> "$TARGET_ABS"
      SHAPE_NOTE=" (section appended)"
    fi
    mv "$DRAFT_ABS" "$ARCHIVE_ABS"
    write_event_json "promote" "$DRAFT_REL" "$ARCHIVE_REL" "$TARGET_REL" "" "$RUN_ID" "$FAILURE_CATEGORY" "$DEFAULT_ACTION" "$EVENT_FILE"
    echo "✅ Promoted learn draft → ${TARGET_REL}${SHAPE_NOTE}"
    echo "🧾 Event: $(rel_path "$EVENT_FILE")"
    if [[ -x "$PROJECT_ROOT/halo/kernel/context/knowledge-lint.sh" ]]; then
      bash "$PROJECT_ROOT/halo/kernel/context/knowledge-lint.sh" --target="$TARGET_REL" || true
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

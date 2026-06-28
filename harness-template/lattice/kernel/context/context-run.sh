#!/usr/bin/env bash
# context-run.sh — Record which context basis was used for a spec.
source "$(dirname "$0")/../_lib.sh"

for arg in "$@"; do
  [[ "$arg" == "--help" || "$arg" == "-h" ]] && cli_help "context run" "Record per-spec context adoption evidence" \
    "context-run.sh <spec-id|path/to/context.md> [--out=<file>] [--strict]" \
    "context-run.sh modern-feature --strict"
done

INPUT=""
OUT=""
STRICT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out=*) OUT="${1#--out=}" ;;
    --out)
      shift
      OUT="${1:-}"
      ;;
    --strict) STRICT=true ;;
    -*)
      echo "Unknown option: $1"
      exit 1
      ;;
    *)
      if [[ -z "$INPUT" ]]; then
        INPUT="$1"
      else
        echo "Unexpected argument: $1"
        exit 1
      fi
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

resolve_context_file() {
  local input="$1" abs
  [[ -n "$input" ]] || { echo "Usage: context-run.sh <spec-id|path/to/context.md>"; exit 1; }
  if [[ "$input" == *.md || "$input" == */* ]]; then
    [[ "$input" == /* ]] && abs="$input" || abs="$PROJECT_ROOT/$input"
  else
    abs="$PROJECT_ROOT/lattice/specs/$input/context.md"
  fi
  [[ -f "$abs" ]] || { echo "Context file not found: $input"; exit 1; }
  printf '%s' "$abs"
}

section_table_rows() {
  local file="$1" heading="$2"
  awk -v heading="$heading" '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    /^##[[:space:]]+/ {
      title = $0
      sub(/^##+[[:space:]]+/, "", title)
      title = trim(title)
      in_section = (tolower(title) == tolower(heading))
      next
    }
    in_section && /^##[[:space:]]+/ { exit }
    in_section && /^\|/ {
      row = $0
      gsub(/^[|]|[|]$/, "", row)
      if (row ~ /^[-:|[:space:]]+$/) next
      if (row ~ /^[[:space:]]*(Type|Issue|Source \/ Topic|Gap|Item)[[:space:]]*\|/) next
      print row
    }
  ' "$file"
}

table_count() {
  local file="$1" heading="$2"
  section_table_rows "$file" "$heading" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' '
}

blocking_gap_count() {
  local file="$1"
  section_table_rows "$file" "Context Gaps" | awk -F'|' '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    {
      blocks = tolower(trim($2))
      if (blocks == "yes" || blocks == "true" || blocks == "block" || blocks == "blocking") count++
    }
    END { print count + 0 }
  '
}

json_array_from_section() {
  local file="$1" heading="$2" first_field="$3" second_field="$4"
  local index=0 row first second
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    first="$(awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $1); print $1}' <<< "$row")"
    second="$(awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' <<< "$row")"
    [[ "$first" == "N/A" && "$second" == "N/A" ]] && continue
    [[ $index -gt 0 ]] && printf ',\n'
    printf '    {"%s":"%s","%s":"%s"}' \
      "$(json_escape "$first_field")" "$(json_escape "$first")" \
      "$(json_escape "$second_field")" "$(json_escape "$second")"
    index=$((index + 1))
  done < <(section_table_rows "$file" "$heading")
  [[ $index -gt 0 ]] && printf '\n'
  return 0
}

CONTEXT_FILE="$(resolve_context_file "$INPUT")"
CONTEXT_REL="$(rel_path "$CONTEXT_FILE")"
SPEC_ID="$(basename "$(dirname "$CONTEXT_FILE")")"
CREATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$(safe_slug "$SPEC_ID")-$$"
GIT_SHA="$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")"

SELECTED_FACTS="$(table_count "$CONTEXT_FILE" "Selected Facts")"
CONSTRAINTS="$(table_count "$CONTEXT_FILE" "Constraints")"
CONFLICTS="$(table_count "$CONTEXT_FILE" "Conflicts / Ambiguities")"
EXCLUSIONS="$(table_count "$CONTEXT_FILE" "Exclusions")"
GAPS="$(table_count "$CONTEXT_FILE" "Context Gaps")"
BLOCKING_GAPS="$(blocking_gap_count "$CONTEXT_FILE")"

OUT="${OUT:-$PROJECT_ROOT/lattice/state/context-runs/${RUN_ID}.json}"
[[ "$OUT" == /* ]] || OUT="$PROJECT_ROOT/$OUT"
mkdir -p "$(dirname "$OUT")"

{
  printf '{\n'
  printf '  "schema_version": "lattice.context-run.v1",\n'
  printf '  "kind": "context-run",\n'
  printf '  "run_id": "%s",\n' "$(json_escape "$RUN_ID")"
  printf '  "created_at": "%s",\n' "$(json_escape "$CREATED_AT")"
  printf '  "spec_id": "%s",\n' "$(json_escape "$SPEC_ID")"
  printf '  "context_file": "%s",\n' "$(json_escape "$CONTEXT_REL")"
  printf '  "git_sha": "%s",\n' "$(json_escape "$GIT_SHA")"
  printf '  "metrics": {\n'
  printf '    "selected_facts": %s,\n' "$SELECTED_FACTS"
  printf '    "constraints": %s,\n' "$CONSTRAINTS"
  printf '    "conflicts": %s,\n' "$CONFLICTS"
  printf '    "exclusions": %s,\n' "$EXCLUSIONS"
  printf '    "context_gaps": %s,\n' "$GAPS"
  printf '    "blocking_gaps": %s\n' "$BLOCKING_GAPS"
  printf '  },\n'
  printf '  "selected_sources": [\n'
  json_array_from_section "$CONTEXT_FILE" "Selected Facts" "type" "source"
  printf '  ],\n'
  printf '  "excluded_sources": [\n'
  json_array_from_section "$CONTEXT_FILE" "Exclusions" "source" "reason"
  printf '  ],\n'
  printf '  "open_gaps": [\n'
  json_array_from_section "$CONTEXT_FILE" "Context Gaps" "gap" "blocks_planning"
  printf '  ]\n'
  printf '}\n'
} > "$OUT"

echo "Context run: $(rel_path "$OUT")"

if [[ "$STRICT" == "true" ]]; then
  if [[ "$SELECTED_FACTS" -eq 0 ]]; then
    echo "Strict context run failed: no selected facts"
    exit 1
  fi
  if [[ "$BLOCKING_GAPS" -gt 0 ]]; then
    echo "Strict context run failed: blocking context gaps remain"
    exit 1
  fi
fi

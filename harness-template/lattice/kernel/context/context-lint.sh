#!/usr/bin/env bash
# context-lint.sh — Sanity-check a per-spec context.md basis.
source "$(dirname "$0")/../_lib.sh"

for arg in "$@"; do
  [[ "$arg" == "--help" || "$arg" == "-h" ]] && cli_help "context lint" "Validate a per-spec context basis" \
    "context-lint.sh <spec-id|path/to/context.md> [--strict]" \
    "context-lint.sh modern-feature --strict"
done

INPUT=""
STRICT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
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

resolve_context_file() {
  local input="$1" abs
  [[ -n "$input" ]] || { echo "Usage: context-lint.sh <spec-id|path/to/context.md>"; exit 1; }
  if [[ "$input" == *.md || "$input" == */* ]]; then
    [[ "$input" == /* ]] && abs="$input" || abs="$PROJECT_ROOT/$input"
  else
    abs="$PROJECT_ROOT/lattice/specs/$input/context.md"
  fi
  [[ -f "$abs" ]] || { echo "Context file not found: $input"; exit 1; }
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

trim() {
  local s="${1:-}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

lower() {
  printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'
}

section_exists() {
  local file="$1" heading="$2"
  awk -v heading="$heading" '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    /^##[[:space:]]+/ {
      title = $0
      sub(/^##+[[:space:]]+/, "", title)
      title = trim(title)
      if (tolower(title) == tolower(heading)) found = 1
    }
    END { exit found ? 0 : 1 }
  ' "$file"
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

cell() {
  local row="$1" index="$2"
  awk -F'|' -v index="$index" '{gsub(/^[ \t]+|[ \t]+$/, "", $index); print $index}' <<< "$row"
}

placeholder_like() {
  local raw value
  raw="$(trim "$1")"
  value="$(lower "$raw")"
  [[ -z "$value" ]] && return 0
  [[ "$value" =~ (todo|tbd|fixme) ]] && return 0
  [[ "$value" == *"path/to/"* ]] && return 0
  [[ "$value" == *"{spec-id}"* || "$value" == *"<spec-id>"* ]] && return 0
  [[ "$value" == "feature / bugfix / refactor / docs / config" ]] && return 0
  [[ "$value" == "plan / tdd / undecided" ]] && return 0
  [[ "$value" == "api / schema / ui / job / config / docs" ]] && return 0
  [[ "$value" == "unit / integration / e2e / manual / gate" ]] && return 0
  [[ "$value" == "compatibility / security / data / performance / release" ]] && return 0
  [[ "$value" == "yes / no" ]] && return 0
  return 1
}

none_like() {
  local value
  value="$(lower "$(trim "$1")")"
  [[ "$value" == "none" || "$value" == "n/a" || "$value" == "na" || "$value" == "-" ]]
}

FAILS=0
WARNS=0

pass_msg() { pass "$*"; }
fail_msg() { fail "$*"; FAILS=$((FAILS + 1)); }
warn_msg() { warn "$*"; WARNS=$((WARNS + 1)); }

CONTEXT_FILE="$(resolve_context_file "$INPUT")"
CONTEXT_REL="$(rel_path "$CONTEXT_FILE")"

echo "🔍 Context Lint: $CONTEXT_REL"
echo ""

REQUIRED_SECTIONS=(
  "Decision Frame"
  "Selected Facts"
  "Constraints"
  "Conflicts / Ambiguities"
  "Exclusions"
  "Context Gaps"
)

echo "── Section completeness ──"
for section in "${REQUIRED_SECTIONS[@]}"; do
  if section_exists "$CONTEXT_FILE" "$section"; then
    pass_msg "$section"
  else
    fail_msg "Missing section: $section"
  fi
done
echo ""

echo "── Decision frame ──"
DECISION_ROWS=0
DECISION_PLACEHOLDERS=0
while IFS= read -r row; do
  [[ -n "$row" ]] || continue
  DECISION_ROWS=$((DECISION_ROWS + 1))
  item="$(cell "$row" 1)"
  value="$(cell "$row" 2)"
  if placeholder_like "$item" || placeholder_like "$value"; then
    DECISION_PLACEHOLDERS=$((DECISION_PLACEHOLDERS + 1))
  fi
done < <(section_table_rows "$CONTEXT_FILE" "Decision Frame")

if [[ "$DECISION_ROWS" -gt 0 && "$DECISION_PLACEHOLDERS" -eq 0 ]]; then
  pass_msg "Decision frame has concrete values"
else
  fail_msg "Decision frame has missing or placeholder values"
fi
echo ""

echo "── Selected facts ──"
SELECTED_FACTS=0
BAD_SELECTED_FACTS=0
while IFS= read -r row; do
  [[ -n "$row" ]] || continue
  type="$(cell "$row" 1)"
  source="$(cell "$row" 2)"
  fact="$(cell "$row" 3)"
  impact="$(cell "$row" 4)"
  if none_like "$type" && none_like "$fact"; then
    continue
  fi
  SELECTED_FACTS=$((SELECTED_FACTS + 1))
  if placeholder_like "$type" || placeholder_like "$source" || placeholder_like "$fact" || placeholder_like "$impact"; then
    BAD_SELECTED_FACTS=$((BAD_SELECTED_FACTS + 1))
  fi
done < <(section_table_rows "$CONTEXT_FILE" "Selected Facts")

if [[ "$SELECTED_FACTS" -gt 0 && "$BAD_SELECTED_FACTS" -eq 0 ]]; then
  pass_msg "$SELECTED_FACTS selected fact(s)"
else
  fail_msg "Selected Facts must include at least one complete, decision-relevant row"
fi
echo ""

echo "── Supporting tables ──"
BAD_SUPPORTING_ROWS=0
BLOCKING_GAPS=0

while IFS= read -r row; do
  [[ -n "$row" ]] || continue
  constraint="$(cell "$row" 2)"
  source="$(cell "$row" 3)"
  impact="$(cell "$row" 4)"
  if none_like "$constraint"; then
    continue
  fi
  if placeholder_like "$constraint" || placeholder_like "$source" || placeholder_like "$impact"; then
    BAD_SUPPORTING_ROWS=$((BAD_SUPPORTING_ROWS + 1))
  fi
done < <(section_table_rows "$CONTEXT_FILE" "Constraints")

while IFS= read -r row; do
  [[ -n "$row" ]] || continue
  issue="$(cell "$row" 1)"
  decision="$(cell "$row" 3)"
  if none_like "$issue"; then
    continue
  fi
  if placeholder_like "$issue" || placeholder_like "$decision"; then
    BAD_SUPPORTING_ROWS=$((BAD_SUPPORTING_ROWS + 1))
  fi
done < <(section_table_rows "$CONTEXT_FILE" "Conflicts / Ambiguities")

while IFS= read -r row; do
  [[ -n "$row" ]] || continue
  source="$(cell "$row" 1)"
  reason="$(cell "$row" 2)"
  if none_like "$source"; then
    continue
  fi
  if placeholder_like "$source" || placeholder_like "$reason"; then
    BAD_SUPPORTING_ROWS=$((BAD_SUPPORTING_ROWS + 1))
  fi
done < <(section_table_rows "$CONTEXT_FILE" "Exclusions")

while IFS= read -r row; do
  [[ -n "$row" ]] || continue
  gap="$(cell "$row" 1)"
  blocks="$(lower "$(cell "$row" 2)")"
  action="$(cell "$row" 3)"
  if none_like "$gap"; then
    continue
  fi
  if [[ "$blocks" == "yes" || "$blocks" == "true" || "$blocks" == "block" || "$blocks" == "blocking" ]]; then
    BLOCKING_GAPS=$((BLOCKING_GAPS + 1))
  fi
  if placeholder_like "$gap" || placeholder_like "$blocks" || placeholder_like "$action"; then
    BAD_SUPPORTING_ROWS=$((BAD_SUPPORTING_ROWS + 1))
  fi
done < <(section_table_rows "$CONTEXT_FILE" "Context Gaps")

if [[ "$BAD_SUPPORTING_ROWS" -eq 0 ]]; then
  pass_msg "Supporting tables have no unfinished placeholders"
else
  fail_msg "$BAD_SUPPORTING_ROWS supporting row(s) contain unfinished placeholders"
fi

if [[ "$BLOCKING_GAPS" -eq 0 ]]; then
  pass_msg "No blocking context gaps"
elif [[ "$STRICT" == "true" ]]; then
  fail_msg "$BLOCKING_GAPS blocking context gap(s) remain"
else
  warn_msg "$BLOCKING_GAPS blocking context gap(s) remain"
fi
echo ""

if grep -Eiq '\b(TODO|TBD|FIXME)\b' "$CONTEXT_FILE"; then
  fail_msg "Unresolved TODO/TBD/FIXME marker found"
fi

echo "══════════════════════════════════"
printf "📊 Context Lint: %s fail(s), %s warning(s)\n" "$FAILS" "$WARNS"
if [[ "$FAILS" -eq 0 ]]; then
  echo "✅ PASS"
  exit 0
fi
echo "❌ FAIL"
exit 1

#!/usr/bin/env bash
# knowledge-lint.sh — Lightweight governance checks for project knowledge.
source "$(dirname "$0")/../_lib.sh"

MODE="advisory"
TARGET=""

for arg in "$@"; do
  [[ "$arg" == "--help" || "$arg" == "-h" ]] && cli_help "knowledge lint" "Check context knowledge for lightweight governance issues" \
    "knowledge-lint.sh                         Advisory check for lattice/context/knowledge" \
    "knowledge-lint.sh --strict                Fail on warnings" \
    "knowledge-lint.sh --target=<path.md>      Check one promoted knowledge file"
done

while [[ $# -gt 0 ]]; do
  arg="$1"
  case "$arg" in
    --strict) MODE="strict" ;;
    --target=*) TARGET="${arg#--target=}" ;;
    --target)
      shift
      TARGET="${1:-}"
      ;;
    *)
      echo "Unknown option: $arg"
      exit 1
      ;;
  esac
  shift
done

knowledge_dir=$(manifest_get '.context.knowledge.dir')
KNOWLEDGE_DIR="${PROJECT_ROOT}/${knowledge_dir:-lattice/context/knowledge}"
WARNINGS=0

rel_path() {
  local path="$1"
  if [[ "$path" == "$PROJECT_ROOT/"* ]]; then
    printf '%s' "${path#$PROJECT_ROOT/}"
  else
    printf '%s' "$path"
  fi
}

file_list() {
  if [[ -n "$TARGET" ]]; then
    local abs
    [[ "$TARGET" == /* ]] && abs="$TARGET" || abs="$PROJECT_ROOT/$TARGET"
    [[ -f "$abs" ]] || { echo "Target knowledge file not found: $TARGET"; exit 1; }
    case "$abs" in
      "$KNOWLEDGE_DIR/"*) printf '%s\n' "$abs" ;;
      *) echo "Target must be under $(rel_path "$KNOWLEDGE_DIR"): $(rel_path "$abs")"; exit 1 ;;
    esac
    return 0
  fi

  [[ -d "$KNOWLEDGE_DIR" ]] || return 0
  find "$KNOWLEDGE_DIR" -type f -name "*.md" 2>/dev/null | sort
}

warn_issue() {
  local file="$1" code="$2" message="$3"
  WARNINGS=$((WARNINGS + 1))
  printf 'WARN [%s] %s: %s\n' "$code" "$(rel_path "$file")" "$message"
}

check_source() {
  local file="$1"
  if grep -Eq '(^\*\*Source\*\*:|^Source:|[|][[:space:]]*Source[[:space:]]*[|])' "$file"; then
    return 0
  fi
  warn_issue "$file" "missing-source" "knowledge entries should carry a Source field or Source column"
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

has_frontmatter() {
  local file="$1"
  [[ "$(sed -n '1p' "$file")" == "---" ]] && awk 'NR > 1 && $0 == "---" { found = 1; exit } END { exit(found ? 0 : 1) }' "$file"
}

check_metadata() {
  local file="$1" owner verified_at applies_to today
  today="$(date -u +%Y-%m-%d)"

  if ! has_frontmatter "$file"; then
    warn_issue "$file" "missing-metadata" "knowledge files should include front matter metadata"
    return 0
  fi

  owner="$(frontmatter_value "owner" "$file")"
  verified_at="$(frontmatter_value "verified_at" "$file")"
  applies_to="$(frontmatter_value "applies_to" "$file")"

  [[ -n "$owner" ]] || warn_issue "$file" "missing-owner" "front matter should include owner"
  [[ -n "$applies_to" ]] || warn_issue "$file" "missing-applies-to" "front matter should include applies_to"

  if [[ -z "$verified_at" ]]; then
    warn_issue "$file" "missing-verified-at" "front matter should include verified_at"
  elif ! [[ "$verified_at" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    warn_issue "$file" "invalid-verified-at" "verified_at should use YYYY-MM-DD"
  elif [[ "$verified_at" > "$today" ]]; then
    warn_issue "$file" "future-verified-at" "verified_at $verified_at is after $today"
  fi
}

check_placeholders() {
  local file="$1"
  if grep -Eiq '\b(TODO|TBD|FIXME)\b' "$file"; then
    warn_issue "$file" "placeholder" "unresolved TODO/TBD/FIXME marker found"
  fi
}

check_conflicts() {
  local file="$1"
  if grep -Eiq '\b(CONFLICT|CONFLICTS|conflict:|冲突)\b' "$file"; then
    warn_issue "$file" "conflict-marker" "explicit conflict marker requires human resolution before promotion"
  fi
}

check_expiry() {
  local file="$1"
  local today
  today="$(date -u +%Y-%m-%d)"
  while IFS= read -r expiry; do
    [[ -n "$expiry" ]] || continue
    if [[ "$expiry" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && [[ "$expiry" < "$today" ]]; then
      warn_issue "$file" "expired" "expires_at $expiry is before $today"
    fi
  done < <(awk -F': *' '
    tolower($1) == "expires_at" {
      value = $0
      sub("^[^:]+:[ ]*", "", value)
      gsub(/^"|"$/, "", value)
      print value
    }
  ' "$file")
}

check_duplicates() {
  local file="$1"
  while IFS= read -r title; do
    warn_issue "$file" "duplicate-heading" "duplicate heading: $title"
  done < <(awk '
    /^##[[:space:]]+/ {
      title = tolower($0)
      sub(/^##+[[:space:]]+/, "", title)
      gsub(/[[:space:]]+/, " ", title)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", title)
      if (title != "") count[title]++
    }
    END {
      for (title in count) {
        if (count[title] > 1) print title
      }
    }
  ' "$file")
}

echo "🔎 Knowledge Lint"
echo "Root: $(rel_path "$KNOWLEDGE_DIR")"
echo "Mode: $MODE"
echo ""

FILES=0
while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  FILES=$((FILES + 1))
  check_metadata "$file"
  check_source "$file"
  check_placeholders "$file"
  check_conflicts "$file"
  check_expiry "$file"
  check_duplicates "$file"
done < <(file_list)

if [[ $FILES -eq 0 ]]; then
  echo "No knowledge files found"
fi

if [[ $WARNINGS -eq 0 ]]; then
  echo "PASS knowledge lint: $FILES file(s), 0 warning(s)"
  exit 0
fi

echo "WARN knowledge lint: $FILES file(s), $WARNINGS warning(s)"
if [[ "$MODE" == "strict" ]]; then
  exit 1
fi
exit 0

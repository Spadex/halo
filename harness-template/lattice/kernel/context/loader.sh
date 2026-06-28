#!/usr/bin/env bash
# loader.sh — Lattice context loader
source "$(dirname "$0")/../_lib.sh"

for arg in "$@"; do
  [[ "$arg" == "--help" || "$arg" == "-h" ]] && cli_help "context load" "Load project and central context knowledge by keyword" \
    "loader.sh <keyword> [keyword2] ...   Match and output context entries by keyword" \
    "loader.sh --list                     List context indexes" \
    "loader.sh --all                      Output all context entry contents"
done

project_dir=$(manifest_get '.context.knowledge.project_dir')
central_dir=$(manifest_get '.context.knowledge.central_dir')
PROJECT_KNOWLEDGE_DIR="${PROJECT_ROOT}/${project_dir:-lattice/context/knowledge/project}"
CENTRAL_KNOWLEDGE_DIR="${PROJECT_ROOT}/${central_dir:-lattice/context/knowledge/central}"

MODE="search"
KEYWORDS=()

for arg in "$@"; do
  case "$arg" in
    --all)  MODE="all" ;;
    --list) MODE="list" ;;
    *)      KEYWORDS+=("$arg") ;;
  esac
done

print_index() {
  local label="$1" dir="$2" index_file="$2/index.md"
  echo "## $label"
  echo ""
  if [[ -f "$index_file" ]]; then
    cat "$index_file"
  else
    echo "_No index found at ${index_file}_"
  fi
  echo ""
}

print_entry_files() {
  local label="$1" dir="$2"
  [[ -d "$dir" ]] || return 0
  while IFS= read -r -d '' f; do
    echo "────────────────────────────────"
    echo "📄 $label / $(basename "$f")"
    echo "────────────────────────────────"
    cat "$f"
    echo ""
  done < <(find "$dir" -maxdepth 1 -name "*.md" ! -name "index.md" ! -name "README.md" -print0 2>/dev/null | sort -z)
}

if [[ "$MODE" == "list" ]]; then
  echo "📚 Context Index"
  echo ""
  print_index "Project Context Knowledge" "$PROJECT_KNOWLEDGE_DIR"
  print_index "Central Context Knowledge" "$CENTRAL_KNOWLEDGE_DIR"
  exit 0
fi

if [[ "$MODE" == "all" ]]; then
  echo "📚 Loading all context knowledge entries"
  echo ""
  print_entry_files "project" "$PROJECT_KNOWLEDGE_DIR"
  print_entry_files "central" "$CENTRAL_KNOWLEDGE_DIR"
  exit 0
fi

synonym_match() {
  local keyword="$1" text="$2" syn_file syn_line syn_word
  echo "$text" | grep -qi "$keyword" && return 0

  for syn_file in "$PROJECT_KNOWLEDGE_DIR/synonyms.txt" "$CENTRAL_KNOWLEDGE_DIR/synonyms.txt"; do
    [[ -f "$syn_file" ]] || continue
    while IFS= read -r syn_line; do
      [[ -z "$syn_line" || "$syn_line" == \#* ]] && continue
      if echo "$syn_line" | grep -qi "$keyword"; then
        for syn_word in $syn_line; do
          echo "$text" | grep -qi "$syn_word" && return 0
        done
      fi
    done < "$syn_file"
  done

  return 1
}

search_index() {
  local label="$1" dir="$2" index_file="$2/index.md"
  [[ -f "$index_file" ]] || return 0

  while IFS= read -r line; do
    local slug="" matched_kw="" kw local_file
    for kw in "${KEYWORDS[@]}"; do
      if synonym_match "$kw" "$line"; then
        slug=$(echo "$line" | sed -n 's/.*`\([^`]*\)`.*/\1/p')
        matched_kw="$kw"
        break
      fi
    done

    if [[ -n "$slug" ]]; then
      local_file="$dir/${slug}.md"
      if [[ -f "$local_file" ]]; then
        echo "────────────────────────────────"
        echo "📄 $label / ${slug}.md (matched keyword: $matched_kw)"
        echo "────────────────────────────────"
        cat "$local_file"
        echo ""
        ((MATCHED++)) || true
      fi
    fi
  done < "$index_file"
}

if [[ ${#KEYWORDS[@]} -eq 0 ]]; then
  echo "Usage: loader.sh <keyword1> [keyword2] ..."
  echo "       loader.sh --all | --list"
  exit 1
fi

echo "🔍 Searching context keywords: ${KEYWORDS[*]}"
echo ""

MATCHED=0
search_index "project" "$PROJECT_KNOWLEDGE_DIR"
search_index "central" "$CENTRAL_KNOWLEDGE_DIR"

if [[ $MATCHED -eq 0 ]]; then
  echo "⏭️  No matching context knowledge found (exact + synonym match)"
  echo "💡 Try broader keywords, or run loader.sh --list to see indexes"
else
  echo "📊 Loaded $MATCHED context knowledge entries"
fi

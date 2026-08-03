#!/usr/bin/env bash
# knowledge.sh — Search curated project context knowledge.
#
# This is a retrieval backend, not the Context Discovery workflow.
source "$(dirname "$0")/../../_lib.sh"

for arg in "$@"; do
  [[ "$arg" == "--help" || "$arg" == "-h" ]] && cli_help "context knowledge" "Search project context knowledge files" \
    "knowledge.sh <keyword> [keyword2] ...   Search knowledge files (matches any keyword)" \
    "knowledge.sh --list                     List knowledge files" \
    "knowledge.sh --all                      Output all knowledge files"
done

knowledge_dir=$(manifest_get '.context.knowledge.dir')
KNOWLEDGE_DIR="${PROJECT_ROOT}/${knowledge_dir:-halo/context/knowledge}"

MODE="search"
KEYWORDS=()

for arg in "$@"; do
  case "$arg" in
    --all)  MODE="all" ;;
    --list) MODE="list" ;;
    # Agent-facing docs spell this argument `<keywords>` (orchestrator/rules.md,
    # prismspec-specification/SKILL.md), so a single quoted multi-word string is the
    # natural thing to pass. Split it on whitespace: an unsplit argument is matched as
    # one literal substring and only hits when every word sits adjacent on the same line.
    *)
      read -r -a arg_words <<< "$arg"
      if [[ ${#arg_words[@]} -gt 0 ]]; then
        KEYWORDS+=("${arg_words[@]}")
      fi
      ;;
  esac
done

knowledge_files() {
  [[ -d "$KNOWLEDGE_DIR" ]] || return 0
  find "$KNOWLEDGE_DIR" -type f -name "*.md" 2>/dev/null | sort
}

print_file() {
  local file="$1"
  local label="${file#$PROJECT_ROOT/}"
  echo "────────────────────────────────"
  echo "📄 $label"
  echo "────────────────────────────────"
  cat "$file"
  echo ""
}

if [[ "$MODE" == "list" ]]; then
  echo "📚 Context Knowledge Files"
  echo ""
  knowledge_files | sed "s#^$PROJECT_ROOT/##"
  exit 0
fi

if [[ "$MODE" == "all" ]]; then
  echo "📚 Loading all context knowledge files"
  echo ""
  while IFS= read -r file; do
    [[ -n "$file" ]] && print_file "$file"
  done < <(knowledge_files)
  exit 0
fi

if [[ ${#KEYWORDS[@]} -eq 0 ]]; then
  echo "Usage: knowledge.sh <keyword1> [keyword2] ...   (matches any keyword)"
  echo "       knowledge.sh --all | --list"
  exit 1
fi

echo "🔍 Searching context knowledge: ${KEYWORDS[*]}"
echo ""

MATCHED=0
while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  for kw in "${KEYWORDS[@]}"; do
    # Let grep read the file directly. Piping content in lets `grep -q` close the pipe at
    # the first match, and the resulting SIGPIPE fails the pipeline under the `set -o
    # pipefail` inherited from _lib.sh, reporting a real match as no match once a file
    # grows past the pipe buffer. -F keeps the keyword literal, so a `.` cannot
    # wildcard-match and an unbalanced `[` cannot make grep error out into silence.
    if grep -qiF -- "$kw" "$file"; then
      print_file "$file"
      MATCHED=$((MATCHED + 1))
      break
    fi
  done
done < <(knowledge_files)

if [[ $MATCHED -eq 0 ]]; then
  echo "⏭️  No matching context knowledge found"
  echo "💡 Try broader keywords, or run knowledge.sh --list to see available files"
else
  echo "📊 Loaded $MATCHED context knowledge files"
fi

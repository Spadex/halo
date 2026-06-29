#!/usr/bin/env bash
# summary-learn-draft.sh — Convert verify.md knowledge candidates into a reviewable knowledge draft.
source "$(dirname "$0")/../_lib.sh"

usage_line="summary-learn-draft.sh <spec-id|path/to/verify.md> [--out=<file>]"
for arg in "$@"; do
  [[ "$arg" == "--help" || "$arg" == "-h" ]] && cli_help "knowledge draft" "Create a knowledge draft from verify.md Knowledge Candidates" \
    "$usage_line" \
    "summary-learn-draft.sh checkout-flow"
done

INPUT="${1:-}"
OUT=""

shift $(( $# >= 1 ? 1 : $# ))
for arg in "$@"; do
  case "$arg" in
    --out=*) OUT="${arg#--out=}" ;;
    *) echo "Unknown argument: $arg"; echo "Usage: $usage_line"; exit 1 ;;
  esac
done

resolve_source_file() {
  local input="$1" abs
  [[ -n "$input" ]] || { echo "Usage: $usage_line"; exit 1; }
  if [[ "$input" == *.md || "$input" == */* ]]; then
    [[ "$input" == /* ]] && abs="$input" || abs="$PROJECT_ROOT/$input"
  else
    abs="$PROJECT_ROOT/lattice/specs/$input/verify.md"
  fi
  [[ -f "$abs" ]] || { echo "Verification file not found: $input"; exit 1; }
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

extract_candidates() {
  local file="$1"
  awk '
    /^## Knowledge Candidates[[:space:]]*$/ { capture = 1; next }
    capture && /^##[[:space:]]+/ { exit }
    capture { print }
  ' "$file" \
    | sed -E 's/^[[:space:]]*-[[:space:]]*//' \
    | sed '/^[[:space:]]*$/d' \
    | grep -Eiv '^(none|n/a|no durable lesson|no durable lessons|no durable lesson selected|no reusable lesson|no knowledge candidate)' \
    || true
}

SOURCE_FILE="$(resolve_source_file "$INPUT")"
SOURCE_DIR="$(dirname "$SOURCE_FILE")"
SPEC_ID="$(basename "$SOURCE_DIR")"
SOURCE_REL="$(rel_path "$SOURCE_FILE")"
CANDIDATES="$(extract_candidates "$SOURCE_FILE")"

if [[ -z "$CANDIDATES" ]]; then
  echo "No durable knowledge candidates found in: $SOURCE_REL"
  exit 1
fi

if [[ -z "$OUT" ]]; then
  OUT="$PROJECT_ROOT/lattice/context/drafts/knowledge-${SPEC_ID}-$(date -u +%Y%m%dT%H%M%SZ).md"
elif [[ "$OUT" != /* ]]; then
  OUT="$PROJECT_ROOT/$OUT"
fi

case "$OUT" in
  "$PROJECT_ROOT/lattice/context/drafts/"*) ;;
  *) echo "Output must be under lattice/context/drafts/: $(rel_path "$OUT")"; exit 1 ;;
esac

mkdir -p "$(dirname "$OUT")"
{
  echo "---"
  echo "run_id: \"knowledge-${SPEC_ID}\""
  echo "failure_category: \"knowledge_candidate\""
  echo "default_action: \"review_and_promote_if_durable\""
  echo "source_file: \"${SOURCE_REL}\""
  echo "created_at: \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
  echo "---"
  echo ""
  echo "# Knowledge Draft: Verification Candidates"
  echo ""
  echo "## Source"
  echo ""
  echo "- Source: \`${SOURCE_REL}\`"
  echo "- Spec: \`lattice/specs/${SPEC_ID}/spec.md\`"
  echo ""
  echo "## Lesson Candidate"
  echo ""
  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    echo "- $candidate"
  done <<< "$CANDIDATES"
  echo ""
  echo "## Review Checklist"
  echo ""
  echo "- [ ] Durable beyond this implementation"
  echo "- [ ] Reusable for future specs or reviews"
  echo "- [ ] Non-secret and safe to store in repo knowledge"
  echo "- [ ] Does not conflict with existing project knowledge"
} > "$OUT"

echo "$(rel_path "$OUT")"

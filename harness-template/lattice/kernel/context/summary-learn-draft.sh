#!/usr/bin/env bash
# summary-learn-draft.sh — Convert summary.md knowledge candidates into a reviewable learn draft.
source "$(dirname "$0")/../_lib.sh"

usage_line="summary-learn-draft.sh <spec-id|path/to/summary.md> [--out=<file>]"
for arg in "$@"; do
  [[ "$arg" == "--help" || "$arg" == "-h" ]] && cli_help "summary learn draft" "Create a learn draft from summary.md Knowledge Candidates" \
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

resolve_summary_file() {
  local input="$1" abs
  [[ -n "$input" ]] || { echo "Usage: $usage_line"; exit 1; }
  if [[ "$input" == *.md || "$input" == */* ]]; then
    [[ "$input" == /* ]] && abs="$input" || abs="$PROJECT_ROOT/$input"
  else
    abs="$PROJECT_ROOT/lattice/specs/$input/summary.md"
  fi
  [[ -f "$abs" ]] || { echo "Summary file not found: $input"; exit 1; }
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

SUMMARY_FILE="$(resolve_summary_file "$INPUT")"
SUMMARY_DIR="$(dirname "$SUMMARY_FILE")"
SPEC_ID="$(basename "$SUMMARY_DIR")"
SUMMARY_REL="$(rel_path "$SUMMARY_FILE")"
CANDIDATES="$(extract_candidates "$SUMMARY_FILE")"

if [[ -z "$CANDIDATES" ]]; then
  echo "No durable knowledge candidates found in: $SUMMARY_REL"
  exit 1
fi

if [[ -z "$OUT" ]]; then
  OUT="$PROJECT_ROOT/lattice/context/drafts/summary-${SPEC_ID}-$(date -u +%Y%m%dT%H%M%SZ).md"
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
  echo "run_id: \"summary-${SPEC_ID}\""
  echo "failure_category: \"knowledge_candidate\""
  echo "default_action: \"review_and_promote_if_durable\""
  echo "source_summary: \"${SUMMARY_REL}\""
  echo "created_at: \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
  echo "---"
  echo ""
  echo "# Learn Draft: Summary Knowledge Candidates"
  echo ""
  echo "## Source"
  echo ""
  echo "- Summary: \`${SUMMARY_REL}\`"
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

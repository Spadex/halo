#!/usr/bin/env bash
# review-package.sh - Build a read-only diff package for task/branch review.
# Usage: review-package.sh [--base=<ref>] <spec-id> [task-id] [output-file]
source "$(dirname "$0")/../../_lib.sh"

BASE_REF=""
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --base=*) BASE_REF="${arg#--base=}" ;;
    --help|-h)
      echo "Usage: review-package.sh [--base=<ref>] <spec-id> [task-id] [output-file]"
      echo ""
      echo "Covers committed, staged, unstaged, and untracked changes."
      echo "--base defaults to the merge base with the repository's default branch."
      exit 0
      ;;
    *) POSITIONAL+=("$arg") ;;
  esac
done

SPEC_ID="${POSITIONAL[0]:-}"
TASK_ID="${POSITIONAL[1]:-branch}"
OUT="${POSITIONAL[2]:-}"

if [[ -z "$SPEC_ID" ]]; then
  echo "Usage: review-package.sh [--base=<ref>] <spec-id> [task-id] [output-file]"
  exit 1
fi

SPEC_DIR="$PROJECT_ROOT/halo/specs/$SPEC_ID"
SPEC_FILE="$SPEC_DIR/spec.md"
PLAN_FILE="$SPEC_DIR/plan.md"

[[ -f "$SPEC_FILE" ]] || { echo "Spec not found: $SPEC_FILE"; exit 1; }
[[ -f "$PLAN_FILE" ]] || { echo "Plan not found: $PLAN_FILE"; exit 1; }

TASK_DIR="$PROJECT_ROOT/.halo/sdd/$SPEC_ID/$TASK_ID"
mkdir -p "$TASK_DIR"
OUT="${OUT:-$TASK_DIR/review-package.md}"

git_cmd() {
  git -C "$PROJECT_ROOT" "$@" 2>/dev/null || true
}

git_ok() {
  git -C "$PROJECT_ROOT" "$@" >/dev/null 2>&1
}

# Resolve the commit this branch diverged from. Without it the package only shows the
# working tree, which is empty for any project that commits per task — the framework's
# own SDD discipline — leaving the reviewer with a zero-information package.
resolve_base_ref() {
  local candidate merged head_ref
  if [[ -n "$BASE_REF" ]]; then
    git_ok rev-parse --verify "$BASE_REF^{commit}" && { printf '%s' "$BASE_REF"; return 0; }
    printf '' ; return 1
  fi
  git_ok rev-parse --verify HEAD || { printf ''; return 1; }
  head_ref="$(git_cmd rev-parse --abbrev-ref HEAD)"
  for candidate in \
    "$(git_cmd symbolic-ref --quiet --short refs/remotes/origin/HEAD)" \
    origin/main origin/master main master; do
    [[ -n "$candidate" ]] || continue
    [[ "$candidate" == "$head_ref" ]] && continue
    git_ok rev-parse --verify "$candidate^{commit}" || continue
    merged="$(git_cmd merge-base HEAD "$candidate")"
    [[ -n "$merged" ]] || continue
    printf '%s' "$merged"
    return 0
  done
  printf ''
  return 1
}

BASE="$(resolve_base_ref || true)"

# Untracked content is included only when the listing is small. A large listing almost
# always means .gitignore is missing entries, and inlining it would bury the real diff.
UNTRACKED_FILES="$(git_cmd ls-files --others --exclude-standard)"
UNTRACKED_COUNT=$(printf '%s' "$UNTRACKED_FILES" | grep -c . || true)
UNTRACKED_CONTENT_LIMIT=50

emit_or_none() {
  local content="$1"
  if [[ -n "$content" ]]; then
    printf '%s\n' "$content"
  else
    echo "(none)"
  fi
}

{
  echo "# Review Package: $SPEC_ID / $TASK_ID"
  echo ""
  echo "## Read-only Review Contract"
  echo ""
  echo "Reviewer must not modify the working tree. Return both verdicts:"
  echo ""
  echo "- Spec compliance: pass | fail | cannot_verify"
  echo "- Code quality: pass | fail | cannot_verify"
  echo ""
  echo "Use \`cannot_verify\` when the diff does not contain enough evidence."
  echo "Ground every fail in file/line evidence or a missing test/gate."
  echo ""
  echo "## Sources"
  echo ""
  echo "- Spec: \`halo/specs/$SPEC_ID/spec.md\`"
  echo "- Plan: \`halo/specs/$SPEC_ID/plan.md\`"
  echo "- Task: \`$TASK_ID\`"
  if [[ -n "$BASE" ]]; then
    echo "- Diff base: \`$BASE\` (committed range \`$BASE...HEAD\`)"
  else
    echo "- Diff base: none resolved — committed work is NOT in this package"
  fi
  echo ""
  echo "## Git Status"
  echo ""
  echo '```text'
  emit_or_none "$(git_cmd status --short)"
  echo '```'
  echo ""
  echo "## Diff Stat"
  echo ""
  echo '```text'
  if [[ -n "$BASE" ]]; then
    echo "# committed ($BASE...HEAD)"
    emit_or_none "$(git_cmd diff --stat "$BASE...HEAD")"
    echo "# uncommitted (staged + worktree)"
    emit_or_none "$(git_cmd diff --stat HEAD -- .)"
  else
    emit_or_none "$(git_cmd diff --stat)"
  fi
  echo '```'
  echo ""
  echo "## Committed Diff"
  echo ""
  echo '```diff'
  if [[ -n "$BASE" ]]; then
    emit_or_none "$(git_cmd diff "$BASE...HEAD")"
  else
    echo "(no base ref resolved)"
  fi
  echo '```'
  echo ""
  echo "## Uncommitted Diff (staged + worktree)"
  echo ""
  echo '```diff'
  if git_ok rev-parse --verify HEAD; then
    emit_or_none "$(git_cmd diff HEAD -- .)"
  else
    emit_or_none "$(git_cmd diff -- .)"
  fi
  echo '```'
  echo ""
  echo "## Untracked Files"
  echo ""
  echo '```text'
  emit_or_none "$UNTRACKED_FILES"
  echo '```'
  if [[ "$UNTRACKED_COUNT" -gt 0 && "$UNTRACKED_COUNT" -le "$UNTRACKED_CONTENT_LIMIT" ]]; then
    echo ""
    echo "### Untracked Content"
    echo ""
    echo '```diff'
    while IFS= read -r untracked; do
      [[ -n "$untracked" ]] || continue
      git_cmd diff --no-index --no-color -- /dev/null "$untracked"
    done <<< "$UNTRACKED_FILES"
    echo '```'
  elif [[ "$UNTRACKED_COUNT" -gt "$UNTRACKED_CONTENT_LIMIT" ]]; then
    echo ""
    echo "> $UNTRACKED_COUNT untracked files exceed the inline limit of $UNTRACKED_CONTENT_LIMIT."
    echo "> Content was omitted; add build output to .gitignore or commit the new files."
  fi
  echo ""
  echo "## Expected Review Output"
  echo ""
  echo '```markdown'
  echo "## Verdict"
  echo ""
  echo "- Spec compliance: pass | fail | cannot_verify"
  echo "- Code quality: pass | fail | cannot_verify"
  echo ""
  echo "## Findings"
  echo ""
  echo "- [severity] file:line - issue"
  echo ""
  echo "## Evidence Checked"
  echo ""
  echo "- ..."
  echo '```'
} > "$OUT"

echo "$OUT"

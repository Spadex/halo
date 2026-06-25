#!/usr/bin/env bash
# spec-lint.sh — Spec structure validation
# Reads manifest.yaml for spec config; sections are configurable via specs.required_sections
# Usage: spec-lint.sh [spec-file]  (omit to auto-discover latest spec)
# Exit codes: 0=all pass, 1=errors found
source "$(dirname "$0")/../../_lib.sh"

SPEC="${1:-}"
if [[ -z "$SPEC" ]]; then
  SPEC=$(find_spec) || { echo "⚠️  No spec file found, skipping"; exit 0; }
fi
[[ -f "$SPEC" ]] || { echo "File not found: $SPEC"; exit 1; }

echo "🔍 Spec Lint: $(basename "$SPEC")"
echo ""

# ── 1. Required sections check ──
echo "── Section completeness ──"

SECTION_COUNT=$(yq '.specs.required_sections | length // 0' "$MANIFEST" 2>/dev/null || echo 0)

if [[ "$SECTION_COUNT" -gt 0 ]]; then
  REQUIRED_SECTIONS=()
  for i in $(seq 0 $((SECTION_COUNT - 1))); do
    section=$(yq -r ".specs.required_sections[$i]" "$MANIFEST")
    [[ -n "$section" && "$section" != "null" ]] && REQUIRED_SECTIONS+=("$section")
  done
else
  REQUIRED_SECTIONS=(
    "Background & Goals"
    "Naming Conventions"
    "Technical Design"
    "API Design"
    "Data Model"
    "Design Alternatives"
    "Acceptance Criteria"
    "Risk Review"
    "Test Strategy"
    "Release Checklist"
    "Rollout & Rollback"
    "Decision Log"
  )
fi

for section in "${REQUIRED_SECTIONS[@]}"; do
  if grep -qi "$section" "$SPEC"; then
    pass "$section"
  else
    fail "Missing section: $section"
  fi
done

# Conditional: financial safety section
if grep -qEi 'asset|deduct|balance|cost|fund|charge' "$SPEC"; then
  if grep -qi "Financial Safety\|Fund Safety" "$SPEC"; then
    pass "Financial Safety section (asset keywords detected)"
  else
    fail "Asset keywords detected but missing Financial Safety section"
  fi
fi

echo ""

# ── 2. AC numbering continuity ──
echo "── AC numbering check ──"

AC_NUMS=$(grep -o 'AC-[0-9]*' "$SPEC" | sed 's/AC-//' | sort -n | uniq)
AC_COUNT=$(echo "$AC_NUMS" | grep -c . || true)

if [[ "$AC_COUNT" -eq 0 ]]; then
  fail "No AC numbers found"
else
  pass "$AC_COUNT ACs found"

  EXPECTED=1
  GAPS=""
  while IFS= read -r num; do
    if [[ "$num" -ne "$EXPECTED" ]]; then
      GAPS="$GAPS $EXPECTED"
    fi
    EXPECTED=$((num + 1))
  done <<< "$AC_NUMS"

  if [[ -z "$GAPS" ]]; then
    pass "AC numbers sequential (1-$((EXPECTED - 1)))"
  else
    fail "AC number gaps:$GAPS"
  fi

  TABLE_ACS=$(grep -E '^\| *AC-[0-9]+ *\|' "$SPEC" | grep -o 'AC-[0-9]*' | sort)
  TABLE_DUPES=$(echo "$TABLE_ACS" | uniq -d)
  if [[ -z "$TABLE_DUPES" ]]; then
    pass "No duplicate AC rows in table"
  else
    fail "Duplicate AC rows: $TABLE_DUPES"
  fi
fi

echo ""

# ── 3. JSON comment check ──
echo "── JSON format check ──"

IN_JSON=0
JSON_COMMENT_LINES=""
LINE_NUM=0
while IFS= read -r line; do
  ((LINE_NUM++))
  if [[ "$line" =~ ^\`\`\`json ]]; then IN_JSON=1
  elif [[ "$line" =~ ^\`\`\` ]] && [[ $IN_JSON -eq 1 ]]; then IN_JSON=0
  elif [[ $IN_JSON -eq 1 ]] && echo "$line" | grep -qE '^\s*//' ; then
    JSON_COMMENT_LINES="$JSON_COMMENT_LINES L$LINE_NUM"
  fi
done < "$SPEC"

if [[ -z "$JSON_COMMENT_LINES" ]]; then
  pass "No // comments in JSON blocks"
else
  fail "JSON blocks contain // comments:$JSON_COMMENT_LINES"
fi

echo ""

# ── 4. DDL-ER consistency ──
echo "── DDL-ER consistency ──"

DDL_TABLES=$(grep -i 'CREATE TABLE' "$SPEC" | sed 's/.*`\([^`]*\)`.*/\1/' | sort)
DDL_COUNT=$(echo "$DDL_TABLES" | grep -c . || true)

if [[ "$DDL_COUNT" -eq 0 ]]; then
  warn "No CREATE TABLE statements found"
else
  pass "DDL tables: $DDL_COUNT"
fi

echo ""

# ── 5. Mermaid diagram check ──
echo "── Mermaid diagram check ──"

MERMAID_COUNT=$(grep -c '```mermaid' "$SPEC" || true)
if [[ "$MERMAID_COUNT" -ge 2 ]]; then
  pass "Mermaid diagrams: $MERMAID_COUNT"
else
  warn "Only $MERMAID_COUNT Mermaid diagrams (recommend at least 2)"
fi

echo ""

# ── 6. Decision log check ──
echo "── Decision log check ──"

D_ITEMS=$(grep -c 'D-[0-9]' "$SPEC" || true)
if [[ "$D_ITEMS" -gt 0 ]]; then
  pass "Decision items: $D_ITEMS"
  UNCONFIRMED=$(grep -cE 'TBD|Pending|pending' "$SPEC" || true)
  if [[ "$UNCONFIRMED" -gt 0 ]]; then
    warn "$UNCONFIRMED decisions pending confirmation"
  else
    pass "All decisions confirmed"
  fi
else
  warn "Decision log is empty"
fi

echo ""

# ── 7. Risk review completeness ──
echo "── Risk review check ──"

RISK_COUNT=$(yq '.specs.risk_categories | length // 0' "$MANIFEST" 2>/dev/null || echo 0)
if [[ "$RISK_COUNT" -gt 0 ]]; then
  RISK_CATEGORIES=()
  for i in $(seq 0 $((RISK_COUNT - 1))); do
    cat_val=$(yq -r ".specs.risk_categories[$i]" "$MANIFEST")
    [[ -n "$cat_val" && "$cat_val" != "null" ]] && RISK_CATEGORIES+=("$cat_val")
  done
else
  RISK_CATEGORIES=("Financial Safety" "Technical Risk" "Data Risk" "Release Process")
fi

for cat_val in "${RISK_CATEGORIES[@]}"; do
  if grep -qi "$cat_val" "$SPEC"; then
    pass "Risk category: $cat_val"
  else
    fail "Missing risk category: $cat_val"
  fi
done

print_summary "Spec Lint"

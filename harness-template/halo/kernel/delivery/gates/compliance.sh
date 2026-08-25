#!/usr/bin/env bash
# compliance.sh — Compliance audit gate (soft gate)
# Checks whether the agent followed Halo behavioral rules.
# Exit codes: 0=compliant, 1=warnings when --strict is enabled
source "$(dirname "$0")/../../_lib.sh"

for arg in "$@"; do
  [[ "$arg" == "--help" || "$arg" == "-h" ]] && cli_help "delivery gate compliance" "Check agent behavioral compliance (soft gate)" \
    "compliance.sh [spec-file]    Check spec Context Basis and knowledge references" \
    "compliance.sh --strict       Strict mode (warnings treated as failures)" \
    "compliance.sh --json-out[=<file>] Write structured gate JSON"
done

STRICT=false
WRITE_JSON=false
JSON_OUT=""
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=true ;;
    --json-out) WRITE_JSON=true ;;
    --json-out=*) WRITE_JSON=true; JSON_OUT="${arg#--json-out=}" ;;
    --help|-h) ;;
    *) POSITIONAL+=("$arg") ;;
  esac
done

SPEC="${POSITIONAL[0]:-}"
if [[ -z "$SPEC" ]]; then
  # stderr is no longer suppressed here: it now carries which spec auto-discovery
  # picked and what it beat, which is exactly what a reader needs to spot a run that
  # verified the wrong spec.
  SPEC_RC=0
  SPEC=$(find_spec) || SPEC_RC=$?
  if [[ "$SPEC_RC" -eq 2 ]]; then
    echo "❌ Spec auto-discovery is ambiguous — pass the spec path explicitly"; exit 1
  elif [[ "$SPEC_RC" -ne 0 ]]; then
    echo "⚠️  No spec file found, skipping compliance check"; exit 0
  fi
fi

# exit 1, matching ac-coverage.sh / drift-check.sh / spec-lint.sh at this same guard.
# The skip branch above is "auto-discovery found no candidate at all"; reaching here means
# a caller named a spec that is not there, which is a missing input, not an empty workload.
# Passing it would report green on a spec this gate never read.
[[ -f "$SPEC" ]] || { echo "Spec file not found: $SPEC"; exit 1; }

knowledge_dir=$(manifest_get '.context.knowledge.dir')
PROJECT_KNOWLEDGE_DIR="${PROJECT_ROOT}/${knowledge_dir:-halo/context/knowledge}"

echo "🔍 Compliance Audit: $(basename "$SPEC")"
echo ""

WARNINGS=0
GATE_FINDINGS=()

json_escape() {
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

record_finding() {
  local check_name="$1" status="$2" message="$3"
  GATE_FINDINGS+=("$(printf '{"check":"%s","status":"%s","message":"%s"}' \
    "$(json_escape "$check_name")" \
    "$(json_escape "$status")" \
    "$(json_escape "$message")")")
}

write_gate_json() {
  [[ "$WRITE_JSON" == "true" ]] || return 0
  local status="$1" out="$JSON_OUT"
  [[ -n "$out" ]] || out="$PROJECT_ROOT/halo/state/gates/compliance.json"
  [[ "$out" == /* ]] || out="$PROJECT_ROOT/$out"
  mkdir -p "$(dirname "$out")"
  {
    printf '{\n'
    printf '  "gate": "compliance",\n'
    printf '  "status": "%s",\n' "$(json_escape "$status")"
    printf '  "spec_file": "%s",\n' "$(json_escape "${SPEC#$PROJECT_ROOT/}")"
    printf '  "strict": %s,\n' "$([[ "$STRICT" == "true" ]] && echo true || echo false)"
    printf '  "metrics": {\n'
    printf '    "warnings": %s,\n' "$WARNINGS"
    printf '    "knowledge_files": %s\n' "${TOTAL_KB:-0}"
    printf '  },\n'
    printf '  "findings": [\n'
    local idx
    for idx in "${!GATE_FINDINGS[@]}"; do
      printf '    %s' "${GATE_FINDINGS[$idx]}"
      [[ "$idx" -lt $((${#GATE_FINDINGS[@]} - 1)) ]] && printf ','
      printf '\n'
    done
    printf '  ]\n'
    printf '}\n'
  } > "$out"
}

echo "── Context basis check ──"
if grep -qiE '^## +.*(Context|Context Basis|上下文依据)' "$SPEC"; then
  echo "  ✅ Spec includes Context Basis"
  record_finding "context_basis" "pass" "spec includes Context Basis"
  if grep -qiE 'Selected Facts|Constraints|Conflicts|Context Gaps|Open Questions|Sources|References|N/A|None' "$SPEC"; then
    echo "  ✅ Context Basis records sources, constraints, gaps, or explicit N/A"
    record_finding "context_structure" "pass" "structured decision sections found"
  else
    echo "  ⚠️  Context Basis is present but lacks source, constraint, gap, or N/A markers"
    WARNINGS=$((WARNINGS + 1))
    record_finding "context_structure" "warning" "Context Basis lacks traceable structure"
  fi
else
  echo "  ⚠️  Missing Context Basis section in spec.md"
  echo "     Expected Specification to persist selected facts, constraints, conflicts, or explicit N/A in spec.md."
  WARNINGS=$((WARNINGS + 1))
  record_finding "context_basis" "warning" "missing Context Basis section"
fi

echo ""
echo "── Knowledge source check ──"
KNOWLEDGE_FILES=$(find "$PROJECT_KNOWLEDGE_DIR" -name "*.md" -not -name "README.md" 2>/dev/null || true)
TOTAL_KB=0
SEARCH_FILES=("$SPEC")

while IFS= read -r kb_file; do
  [[ -z "$kb_file" ]] && continue
  TOTAL_KB=$((TOTAL_KB + 1))
done <<< "$KNOWLEDGE_FILES"

if [[ "$TOTAL_KB" -gt 0 ]] && grep -qiE 'halo/context/knowledge|knowledge/' "${SEARCH_FILES[@]}" 2>/dev/null; then
  echo "  ✅ Spec references project knowledge paths"
  record_finding "knowledge_reference" "pass" "spec references project knowledge paths"
elif [[ "$TOTAL_KB" -gt 0 ]]; then
  echo "  ⚠️  Spec does not reference project knowledge paths"
  echo "     Found $TOTAL_KB entries under halo/context/knowledge."
  echo "     This is acceptable only when the current change does not depend on durable project knowledge."
  WARNINGS=$((WARNINGS + 1))
  record_finding "knowledge_reference" "warning" "spec does not reference project knowledge paths"
elif [[ "$TOTAL_KB" -eq 0 ]]; then
  echo "  ⏭️  Context knowledge is empty, skipping"
  record_finding "knowledge_reference" "skip" "context knowledge is empty"
fi

echo ""
echo "── Source trace check ──"
# Chinese categories are listed alongside the English ones because the default spec
# template ships a Chinese Context Basis table (`| 用户输入 | ... |`). Without them the
# framework warns on every spec written from its own template.
if grep -qiE '\| *(user|code|test|schema|contract|knowledge|external|用户输入|用户决策|用户|代码( ?/ ?测试)?|测试|契约|模式|项目知识|知识|历史 ?spec|外部依赖|外部|待确认) *\|' "${SEARCH_FILES[@]}" 2>/dev/null; then
  echo "  ✅ Context basis records source categories"
  record_finding "source_trace" "pass" "context basis records source categories"
else
  echo "  ⚠️  Context basis does not clearly record source categories"
  WARNINGS=$((WARNINGS + 1))
  record_finding "source_trace" "warning" "context basis does not clearly record source categories"
fi

echo ""
echo "── Ambiguity tracking check ──"
if grep -qiE 'Open Questions|Context Gaps|Conflicts|Ambiguities|None|N/A' "${SEARCH_FILES[@]}" 2>/dev/null; then
  echo "  ✅ Context basis records ambiguities or explicitly marks none"
  record_finding "ambiguity_tracking" "pass" "context basis records ambiguities or marks none"
else
  echo "  ⚠️  No ambiguity or gap records found in context basis"
  WARNINGS=$((WARNINGS + 1))
  record_finding "ambiguity_tracking" "warning" "no ambiguity or gap records found"
fi

echo ""
echo "══════════════════════════════════"
if [[ "$WARNINGS" -eq 0 ]]; then
  echo "📊 Compliance Audit: ✅ no warnings"
  write_gate_json "pass"
  exit 0
fi

echo "📊 Compliance Audit: ⚠️  $WARNINGS warnings (soft rule)"
if [[ "$STRICT" == "true" ]]; then
  echo "❌ FAIL (strict mode)"
  write_gate_json "fail"
  exit 1
fi

echo "✅ PASS (soft gate, warnings for review reference)"
write_gate_json "warn"
exit 0

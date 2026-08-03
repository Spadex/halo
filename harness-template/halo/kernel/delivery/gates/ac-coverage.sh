#!/usr/bin/env bash
# ac-coverage.sh — AC↔Test traceability coverage
source "$(dirname "$0")/../../_lib.sh"

for arg in "$@"; do
  [[ "$arg" == "--help" || "$arg" == "-h" ]] && cli_help "delivery gate ac-coverage" "Check AC number to test coverage" \
    "ac-coverage.sh [spec-file] [test-dir]    Check spec AC vs TestAC{nn} mapping" \
    "ac-coverage.sh --deep [spec] [test-dir]  Also detect empty tests and assertion drift" \
    "ac-coverage.sh --json-out[=<file>]       Write structured gate JSON" \
    "" \
    "Omit arguments to auto-discover latest spec and search project root"
done

DEEP_MODE=false
WRITE_JSON=false
JSON_OUT=""
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --deep) DEEP_MODE=true ;;
    --json-out) WRITE_JSON=true ;;
    --json-out=*) WRITE_JSON=true; JSON_OUT="${arg#--json-out=}" ;;
    --help|-h) ;;
    *) POSITIONAL+=("$arg") ;;
  esac
done
SPEC="${POSITIONAL[0]:-}"
TEST_DIR_ARG="${POSITIONAL[1]:-}"
SPEC="${SPEC:-}"
if [[ -z "$SPEC" ]]; then
  # An ambiguous auto-discovery must not degrade into "no spec found, skipping":
  # that would turn a deliberate refusal to guess into a silently skipped gate.
  SPEC_RC=0
  SPEC=$(find_spec) || SPEC_RC=$?
  if [[ "$SPEC_RC" -eq 2 ]]; then
    echo "❌ Spec auto-discovery is ambiguous — pass the spec path explicitly"; exit 1
  elif [[ "$SPEC_RC" -ne 0 ]]; then
    echo "⚠️  No spec file found, skipping"; exit 0
  fi
fi
TEST_DIR="${TEST_DIR_ARG:-$PROJECT_ROOT}"

[[ -f "$SPEC" ]] || { echo "Spec file not found: $SPEC"; exit 1; }

# PROJECT_LANG, not LANG: LANG is the locale environment variable, and overwriting it with
# a project language leaves every child process (awk, grep, sort) in an invalid locale.
PROJECT_LANG=$(get_language)
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
  local ac="$1" status="$2" test_name="$3" message="$4"
  GATE_FINDINGS+=("$(printf '{"ac":"%s","status":"%s","test":"%s","message":"%s"}' \
    "$(json_escape "$ac")" \
    "$(json_escape "$status")" \
    "$(json_escape "$test_name")" \
    "$(json_escape "$message")")")
}

write_gate_json() {
  [[ "$WRITE_JSON" == "true" ]] || return 0
  local status="$1" out="$JSON_OUT"
  [[ -n "$out" ]] || out="$PROJECT_ROOT/halo/state/gates/ac-coverage.json"
  [[ "$out" == /* ]] || out="$PROJECT_ROOT/$out"
  mkdir -p "$(dirname "$out")"
  {
    printf '{\n'
    printf '  "gate": "ac-coverage",\n'
    printf '  "status": "%s",\n' "$(json_escape "$status")"
    printf '  "spec_file": "%s",\n' "$(json_escape "${SPEC#$PROJECT_ROOT/}")"
    printf '  "language": "%s",\n' "$(json_escape "$PROJECT_LANG")"
    printf '  "metrics": {\n'
    printf '    "ac_total": %s,\n' "${SPEC_COUNT:-0}"
    printf '    "ac_covered": %s,\n' "${COVERED_COUNT:-0}"
    printf '    "ac_uncovered": %s,\n' "$(( ${SPEC_COUNT:-0} - ${COVERED_COUNT:-0} ))"
    printf '    "coverage_percent": %s,\n' "${PERCENT:-0}"
    printf '    "deep_warnings": %s\n' "${DEEP_WARNINGS:-0}"
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

echo "🔍 AC Coverage: $(basename "$SPEC") [$PROJECT_LANG]"
echo ""

case "$PROJECT_LANG" in
  go)
    FUNC_REGEX='func Test(AC|_AC)([0-9]+)'
    ;;
  node|javascript|typescript)
    FUNC_REGEX='(describe|it|test).*AC[_-]?([0-9]+)'
    ;;
  python)
    FUNC_REGEX='def test_ac([0-9]+)'
    ;;
  *)
    echo "⚠️  Unknown language: $PROJECT_LANG, using Go defaults"
    FUNC_REGEX='func Test(AC|_AC)([0-9]+)'
    ;;
esac

# Shape of a test identifier the spec author may write in an AC row's last
# ("verification") cell. This is the spec's OWN, authoritative AC→test binding —
# unlike a bare AC number it is spec-local, so it cannot collide across specs.
# Node test titles are free-form strings, not stable identifiers, so no token is
# extracted for node; those ACs use the numeric fallback below.
case "$PROJECT_LANG" in
  go)                          DECL_TOKEN_REGEX='Test[A-Za-z0-9_]+' ;;
  python)                      DECL_TOKEN_REGEX='test_[a-z0-9_]+' ;;
  node|javascript|typescript)  DECL_TOKEN_REGEX='' ;;
  *)                           DECL_TOKEN_REGEX='Test[A-Za-z0-9_]+' ;;
esac

# A test that a DIFFERENT spec binds in its own AC table is owned by that spec and
# must never satisfy this spec's ACs, even when they share an AC number (the
# cross-spec test_acN collision this gate previously mis-attributed). Collect that
# owned set once from sibling specs so the numeric fallback can exclude it.
SPECS_DIR=$(manifest_get ".specs.dir"); SPECS_DIR="${SPECS_DIR:-halo/specs}"
SPECS_ABS="$PROJECT_ROOT/$SPECS_DIR"
build_foreign_owned() {
  [[ -n "$DECL_TOKEN_REGEX" && -d "$SPECS_ABS" ]] || return 0
  local f
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    [[ "$f" -ef "$SPEC" ]] && continue
    { grep -E '^\| *AC-[0-9]+ *\|' "$f" 2>/dev/null || true; } | grep -oE "$DECL_TOKEN_REGEX" 2>/dev/null || true
  done < <(find "$SPECS_ABS" -name 'spec.md' -type f 2>/dev/null || true)
}
FOREIGN_OWNED=$(build_foreign_owned | sort -u)

# Take only each row's first cell. Scanning the whole row let an in-cell
# cross-reference ("| AC-3 | … | differs from upstream-spec AC-14 |") enter this
# spec's AC set, inflating Spec AC count and failing coverage for an AC this spec
# never declared.
SPEC_ACS=$(spec_declared_acs "$SPEC" | sort -t- -k2 -n | uniq)
SPEC_COUNT=$(echo "$SPEC_ACS" | grep -c . || true)

if [[ "$SPEC_COUNT" -eq 0 ]]; then
  echo "⚠️  No AC numbers found in spec"
  write_gate_json "skip"
  exit 0
fi

echo "📋 Spec AC count: $SPEC_COUNT"

case "$PROJECT_LANG" in
  node|javascript|typescript)
    TEST_FILES=$(find "$TEST_DIR" \( -path '*/node_modules/*' -o -path '*/.halo/*' -o -path '*/halo/*' -o -path '*/prismspec/*' \) -prune -o \( -name "*.test.ts" -o -name "*.test.js" -o -name "*.spec.ts" -o -name "*.spec.js" \) -type f -print 2>/dev/null || true)
    ;;
  go)
    TEST_FILES=$(find "$TEST_DIR" \( -path '*/vendor/*' -o -path '*/.halo/*' -o -path '*/halo/*' -o -path '*/prismspec/*' \) -prune -o -name "*_test.go" -type f -print 2>/dev/null || true)
    ;;
  python)
    TEST_FILES=$(find "$TEST_DIR" \( -path '*/.venv/*' -o -path '*/.halo/*' -o -path '*/halo/*' -o -path '*/prismspec/*' \) -prune -o -name "test_*.py" -type f -print 2>/dev/null || true)
    ;;
  *)
    TEST_FILES=$(find "$TEST_DIR" \( -path '*/vendor/*' -o -path '*/.halo/*' -o -path '*/halo/*' -o -path '*/prismspec/*' \) -prune -o -name "*_test.go" -type f -print 2>/dev/null || true)
    ;;
esac

COVERAGE_ROWS=""

if [[ -n "$TEST_FILES" ]]; then
  while IFS= read -r test_file; do
    [[ -z "$test_file" ]] && continue
    while IFS= read -r match_line; do
      [[ -z "$match_line" ]] && continue
      ac_num=$(echo "$match_line" | grep -ioE 'AC[_-]?([0-9]+)' | grep -oE '[0-9]+' | head -1 || true)
      [[ -z "$ac_num" ]] && continue
      ac_num=$((10#$ac_num))
      func_name=$(echo "$match_line" | grep -oE 'func [A-Za-z0-9_]+|def [a-z_0-9]+|(describe|it|test)\(' | head -1 | sed 's/^func //' | sed 's/^def //' | sed 's/($//')
      COVERAGE_ROWS+="$ac_num|${func_name:-unknown}|$test_file"$'\n'
    done < <(grep -E "$FUNC_REGEX" "$test_file" 2>/dev/null || true)
  done <<< "$TEST_FILES"
fi

echo ""
echo "📋 AC Coverage Matrix:"
echo ""
echo "| AC | Spec Description | Test Function | Status |"
echo "|----|------------------|---------------|--------|"

COVERED_COUNT=0
UNCOVERED=""
RESOLVED=""   # "num|status|func" per AC; reused by deep mode so it analyzes the resolved test
while IFS= read -r ac; do
  num=${ac#AC-}
  row=$(grep -E "^\| *$ac *\|" "$SPEC" | head -1 || true)
  desc=$(printf '%s' "$row" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $3); print $3}')
  [[ -z "$desc" ]] && desc="—"

  # The spec's own authoritative binding lives in the AC row's last non-empty cell.
  verif=$(printf '%s' "$row" | awk -F'|' '{for(i=NF;i>=1;i--){gsub(/^[ \t]+|[ \t]+$/,"",$i); if($i!=""){print $i; exit}}}')
  decl=""
  [[ -n "$DECL_TOKEN_REGEX" ]] && decl=$(printf '%s' "$verif" | grep -oE "$DECL_TOKEN_REGEX" | head -1 || true)

  func_name=""
  note=""
  if [[ -n "$decl" ]]; then
    # Tier 1 — spec names a specific test: covered iff that exact function exists.
    if printf '%s\n' "$COVERAGE_ROWS" | awk -F'|' -v d="$decl" '$2==d{f=1} END{exit !f}'; then
      func_name="$decl"
    else
      note="declared test \`$decl\` not found"
    fi
  else
    # Tier 2 — no declared test: numeric fallback, excluding tests owned by other
    # specs, with cross-spec ambiguity treated as unproven (not silently covered).
    cands=$(printf '%s\n' "$COVERAGE_ROWS" | awk -F'|' -v n="$num" '$1==n && $2!="unknown"{print $2}' | sort -u | sed '/^$/d')
    if [[ -n "$FOREIGN_OWNED" && -n "$cands" ]]; then
      cands=$(comm -23 <(printf '%s\n' "$cands") <(printf '%s\n' "$FOREIGN_OWNED"))
    fi
    ccount=$(printf '%s' "$cands" | grep -c . || true)
    if [[ "$ccount" -eq 1 ]]; then
      func_name=$(printf '%s\n' "$cands" | head -1)
    elif [[ "$ccount" -ge 2 ]]; then
      note="ambiguous across specs: $(printf '%s' "$cands" | tr '\n' ' ' | sed 's/ *$//')"
    else
      note="no spec-owned test found"
    fi
  fi

  if [[ -n "$func_name" ]]; then
    echo "| $ac | $desc | \`$func_name\` | ✅ |"
    COVERED_COUNT=$((COVERED_COUNT + 1))
    RESOLVED+="$num|covered|$func_name"$'\n'
    record_finding "$ac" "covered" "$func_name" "$desc"
  else
    echo "| $ac | $desc | — | ❌ ${note:-Uncovered} |"
    UNCOVERED="$UNCOVERED $ac"
    RESOLVED+="$num|uncovered|"$'\n'
    record_finding "$ac" "uncovered" "" "${desc}${note:+ — $note}"
  fi
done <<< "$SPEC_ACS"

DEEP_WARNINGS=0
if [[ "$DEEP_MODE" == "true" ]] && [[ -n "$TEST_FILES" ]]; then
  echo ""
  echo "🔬 Deep Analysis (experimental):"
  echo ""

  while IFS= read -r ac; do
    num=${ac#AC-}
    func_name=$(printf '%s\n' "$RESOLVED" | awk -F'|' -v n="$num" '$1==n && $2=="covered"{print $3; exit}')
    [[ -z "$func_name" ]] && continue

    while IFS= read -r test_file; do
      [[ -z "$test_file" ]] && continue
      if grep -A 5 "$func_name" "$test_file" 2>/dev/null | grep -qiE 't\.Skip|pytest\.skip|\.skip\(|pending\('; then
        echo "  ⚠️  $ac ($func_name): contains Skip/Pending — test not actually running"
        DEEP_WARNINGS=$((DEEP_WARNINGS + 1))
        record_finding "$ac" "warning" "$func_name" "contains Skip/Pending"
      fi

      func_body=$(sed -n "/func.*$func_name/,/^}/p" "$test_file" 2>/dev/null || \
                  sed -n "/def.*$func_name/,/^def\|^class/p" "$test_file" 2>/dev/null || true)
      if [[ -n "$func_body" ]]; then
        has_assert=$(echo "$func_body" | grep -ciE 'assert|expect|should|require|Equal|Error|Nil|True|False|Contains|Len' || true)
        if [[ "$has_assert" -eq 0 ]]; then
          echo "  ⚠️  $ac ($func_name): no assertions detected — may be empty test"
          DEEP_WARNINGS=$((DEEP_WARNINGS + 1))
          record_finding "$ac" "warning" "$func_name" "no assertions detected"
        fi
      fi
    done <<< "$TEST_FILES"
  done <<< "$SPEC_ACS"

  if [[ "$DEEP_WARNINGS" -eq 0 ]]; then
    echo "  ✅ No suspicious tests found"
  else
    echo ""
    echo "  $DEEP_WARNINGS warnings (non-blocking, for review reference)"
  fi
fi

PERCENT=0
[[ "$SPEC_COUNT" -gt 0 ]] && PERCENT=$((COVERED_COUNT * 100 / SPEC_COUNT))

echo ""
echo "══════════════════════════════════"
echo "📊 AC Coverage: $COVERED_COUNT/$SPEC_COUNT ($PERCENT%)"

if [[ -n "$UNCOVERED" ]]; then
  echo "❌ FAIL — uncovered:$UNCOVERED"
  write_gate_json "fail"
  exit 1
else
  echo "✅ PASS — all ACs covered"
  write_gate_json "pass"
  exit 0
fi

#!/usr/bin/env bash
# pipeline.sh — Delivery pipeline
# Exit codes: 0=all green, 1=failure(retryable), 2=escalation(needs human)
source "$(dirname "$0")/../_lib.sh"

for arg in "$@"; do
  [[ "$arg" == "--help" || "$arg" == "-h" ]] && cli_help "delivery pipeline" "Run manifest-driven delivery pipeline" \
    "pipeline.sh                          Run full pipeline" \
    "pipeline.sh --only=<step>            Run specific step (e.g. --only=build)" \
    "pipeline.sh --spec=<file>            Specify spec file" \
    "pipeline.sh --json-out[=<file>]      Write structured eval run JSON" \
    "pipeline.sh --skip-spec              Skip spec-related steps" \
    "pipeline.sh --skip-integration       Skip integration tests" \
    "" \
    "Environment variables:" \
    "  SH_RETRY_COUNT                     Current retry count (set by agent)" \
    "  SH_RETRY_MAX                       Max retries (default 3)"
done

SKIP_SPEC=false
SKIP_INTEGRATION=false
ONLY_STEP=""
USER_SPEC=""
WRITE_JSON=false
JSON_OUT=""

for arg in "$@"; do
  case "$arg" in
    --skip-spec)       SKIP_SPEC=true ;;
    --skip-integration) SKIP_INTEGRATION=true ;;
    --only=*)          ONLY_STEP="${arg#--only=}" ;;
    --spec=*)          USER_SPEC="${arg#--spec=}" ;;
    --json-out)        WRITE_JSON=true ;;
    --json-out=*)      WRITE_JSON=true; JSON_OUT="${arg#--json-out=}" ;;
  esac
done

SH_RETRY_COUNT="${SH_RETRY_COUNT:-0}"
SH_RETRY_MAX="${SH_RETRY_MAX:-3}"
RUN_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
RUN_STARTED_SEC="$(date +%s)"
RUN_ID="${RUN_STARTED_AT//:/}"
RUN_ID="${RUN_ID//-/}"

json_escape() {
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

hash_file() {
  local file="$1"
  [[ -f "$file" ]] || { echo ""; return 0; }
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print "sha256:" $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print "sha256:" $1}'
  else
    echo ""
  fi
}

json_step_entries=()
record_step() {
  local step_name="$1" status="$2" command="$3" exit_code="$4" duration_ms="$5" summary="$6"
  json_step_entries+=("$(printf '{"name":"%s","status":"%s","command":"%s","exit_code":%s,"duration_ms":%s,"summary":"%s"}' \
    "$(json_escape "$step_name")" \
    "$(json_escape "$status")" \
    "$(json_escape "$command")" \
    "${exit_code:-null}" \
    "${duration_ms:-0}" \
    "$(json_escape "$summary")")")
}

echo "══════════════════════════════════"
echo "Lattice — Delivery Pipeline"
echo "Project: $(manifest_get '.project.name') ($(get_language))"
[[ "$SH_RETRY_COUNT" -gt 0 ]] && echo "Retry: $SH_RETRY_COUNT / $SH_RETRY_MAX"
echo "══════════════════════════════════"
echo ""

HAS_SPEC=false
SPEC_FILE="${USER_SPEC:-}"
if [[ -n "$SPEC_FILE" ]] && [[ -f "$SPEC_FILE" ]]; then
  HAS_SPEC=true
  export SPEC_FILE
elif spec=$(find_spec 2>/dev/null); then
  HAS_SPEC=true
  SPEC_FILE="$spec"
  export SPEC_FILE
else
  SPEC_FILE=""
fi

HAS_CODE=false
LANG=$(get_language)
case "$LANG" in
  go)     [[ -n "$(find "$PROJECT_ROOT" -maxdepth 5 -name '*.go' -not -path '*/vendor/*' 2>/dev/null | head -1)" ]] && HAS_CODE=true || true ;;
  node)   [[ -f "$PROJECT_ROOT/package.json" ]] && HAS_CODE=true ;;
  python) [[ -n "$(find "$PROJECT_ROOT" -maxdepth 5 -name '*.py' 2>/dev/null | head -1)" ]] && HAS_CODE=true || true ;;
  *)      HAS_CODE=true ;;
esac

HAS_INTEGRATION=false
if [[ -d "$PROJECT_ROOT/tests/integration" ]] || [[ -d "$PROJECT_ROOT/test/integration" ]]; then
  HAS_INTEGRATION=true
fi

should_skip() {
  local skip_when="$1"
  case "$skip_when" in
    no_spec)        [[ "$HAS_SPEC" == "false" ]] || [[ "$SKIP_SPEC" == "true" ]] ;;
    no_code)        [[ "$HAS_CODE" == "false" ]] ;;
    no_integration) [[ "$HAS_INTEGRATION" == "false" ]] || [[ "$SKIP_INTEGRATION" == "true" ]] ;;
    never)          return 1 ;;
    *)              return 1 ;;
  esac
}

STEP_COUNT=$(yq '.pipeline.steps | length' "$MANIFEST")
STEP_NUM=0
STEP_PASS=0
STEP_FAIL=0
STEP_SKIP=0

for i in $(seq 0 $((STEP_COUNT - 1))); do
  name=$(yq -r ".pipeline.steps[$i].name" "$MANIFEST")
  run=$(yq -r ".pipeline.steps[$i].run" "$MANIFEST")
  skip_when=$(yq -r ".pipeline.steps[$i].skip_when // \"never\"" "$MANIFEST")

  [[ -z "$name" || "$name" == "null" ]] && continue
  ((STEP_NUM++)) || true

  if [[ -n "$ONLY_STEP" ]] && [[ "$name" != "$ONLY_STEP" ]]; then
    continue
  fi

  if should_skip "$skip_when"; then
    printf "⏭️  [%d] %-20s SKIP (%s)\n" "$STEP_NUM" "$name" "$skip_when"
    ((STEP_SKIP++)) || true
    record_step "$name" "skip" "$run" "0" "0" "$skip_when"
    continue
  fi

  run="${run//\$\{SPEC_FILE\}/$SPEC_FILE}"
  run="${run//\$\{commands.build\}/$(manifest_get_cmd 'commands.build')}"
  run="${run//\$\{commands.lint\}/$(manifest_get_cmd 'commands.lint')}"
  run="${run//\$\{commands.test\}/$(manifest_get_cmd 'commands.test')}"
  run="${run//\$\{commands.integration_test\}/$(manifest_get_cmd 'commands.integration_test')}"

  printf "🔄 [%d] %-20s → %s\n" "$STEP_NUM" "$name" "$run"

  step_started_sec="$(date +%s)"
  if output=$(run_cmd "$run" 2>&1); then
    step_duration_ms=$(( ($(date +%s) - step_started_sec) * 1000 ))
    [[ -n "$output" ]] && printf '%s\n' "$output" | tail -20
    printf "✅ [%d] %-20s PASS\n\n" "$STEP_NUM" "$name"
    ((STEP_PASS++)) || true
    record_step "$name" "pass" "$run" "0" "$step_duration_ms" "$(printf '%s\n' "$output" | tail -20)"
  else
    step_exit=$?
    step_duration_ms=$(( ($(date +%s) - step_started_sec) * 1000 ))
    printf '%s\n' "$output"
    printf "❌ [%d] %-20s FAIL\n\n" "$STEP_NUM" "$name"
    ((STEP_FAIL++)) || true
    record_step "$name" "fail" "$run" "$step_exit" "$step_duration_ms" "$(printf '%s\n' "$output" | tail -40)"
    echo "⛔ Pipeline stopped at step $STEP_NUM: $name"
    break
  fi
done

echo ""
echo "══════════════════════════════════"
echo "📊 Pipeline: ✅ $STEP_PASS  ❌ $STEP_FAIL  ⏭️  $STEP_SKIP / $STEP_NUM total steps"

RUN_ENDED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
RUN_DURATION_MS=$(( ($(date +%s) - RUN_STARTED_SEC) * 1000 ))
PIPELINE_STATUS="pass"
EXIT_CODE=0
if [[ $STEP_FAIL -gt 0 ]]; then
  PIPELINE_STATUS="fail"
  EXIT_CODE=1
  if [[ "$SH_RETRY_COUNT" -ge "$SH_RETRY_MAX" ]]; then
    PIPELINE_STATUS="escalation"
    EXIT_CODE=2
  fi
fi

write_eval_json() {
  [[ "$WRITE_JSON" == "true" ]] || return 0
  local out="$JSON_OUT"
  if [[ -z "$out" ]]; then
    mkdir -p "$PROJECT_ROOT/lattice/state/eval-runs"
    out="$PROJECT_ROOT/lattice/state/eval-runs/${RUN_ID}.json"
  elif [[ "$out" != /* ]]; then
    out="$PROJECT_ROOT/$out"
  fi
  mkdir -p "$(dirname "$out")"

  local git_sha kernel_version spec_hash spec_rel agent_name
  git_sha="$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || true)"
  kernel_version=""
  [[ -f "$KERNEL_DIR/VERSION" ]] && kernel_version="$(tr -d '\n' < "$KERNEL_DIR/VERSION")"
  spec_hash="$(hash_file "$SPEC_FILE")"
  spec_rel="${SPEC_FILE#$PROJECT_ROOT/}"
  agent_name="${LATTICE_AGENT:-${AGENT_NAME:-unknown}}"

  {
    printf '{\n'
    printf '  "run_id": "%s",\n' "$(json_escape "$RUN_ID")"
    printf '  "started_at": "%s",\n' "$(json_escape "$RUN_STARTED_AT")"
    printf '  "ended_at": "%s",\n' "$(json_escape "$RUN_ENDED_AT")"
    printf '  "project": "%s",\n' "$(json_escape "$(manifest_get '.project.name')")"
    printf '  "language": "%s",\n' "$(json_escape "$(get_language)")"
    printf '  "git_sha": "%s",\n' "$(json_escape "$git_sha")"
    printf '  "spec_file": "%s",\n' "$(json_escape "$spec_rel")"
    printf '  "spec_hash": "%s",\n' "$(json_escape "$spec_hash")"
    printf '  "agent": "%s",\n' "$(json_escape "$agent_name")"
    printf '  "kernel_version": "%s",\n' "$(json_escape "$kernel_version")"
    printf '  "pipeline": {\n'
    printf '    "status": "%s",\n' "$PIPELINE_STATUS"
    printf '    "duration_ms": %s,\n' "$RUN_DURATION_MS"
    printf '    "retry_count": %s,\n' "$SH_RETRY_COUNT"
    printf '    "retry_max": %s,\n' "$SH_RETRY_MAX"
    printf '    "exit_code": %s\n' "$EXIT_CODE"
    printf '  },\n'
    printf '  "metrics": {\n'
    printf '    "steps_total": %s,\n' "$STEP_NUM"
    printf '    "steps_passed": %s,\n' "$STEP_PASS"
    printf '    "steps_failed": %s,\n' "$STEP_FAIL"
    printf '    "steps_skipped": %s\n' "$STEP_SKIP"
    printf '  },\n'
    printf '  "steps": [\n'
    local idx
    for idx in "${!json_step_entries[@]}"; do
      printf '    %s' "${json_step_entries[$idx]}"
      [[ "$idx" -lt $((${#json_step_entries[@]} - 1)) ]] && printf ','
      printf '\n'
    done
    printf '  ]\n'
    printf '}\n'
  } > "$out"

  echo "🧾 Eval JSON: ${out#$PROJECT_ROOT/}"
}

write_eval_json

if [[ $STEP_FAIL -gt 0 ]]; then
  if [[ "$SH_RETRY_COUNT" -ge "$SH_RETRY_MAX" ]]; then
    echo ""
    echo "⚠️  ESCALATION — $SH_RETRY_COUNT retries exhausted"
    echo "══════════════════════════════════"
    echo "Diagnostics:"
    echo "  Failed step: $name"
    echo "  Project: $(manifest_get '.project.name')"
    echo "  Language: $(get_language)"
    echo "  Retries: $SH_RETRY_COUNT / $SH_RETRY_MAX"
    echo ""
    echo "Suggestions:"
    echo "  1. Review the full output of the failed step"
    echo "  2. Determine if it's a code issue or environment issue"
    echo "  3. Consider reducing spec scope or splitting the task"
    echo "══════════════════════════════════"
    echo "❌ ESCALATION — needs human intervention"
    exit 2
  fi
  echo ""
  echo "Hint: Agent can set SH_RETRY_COUNT=$((SH_RETRY_COUNT + 1)) and re-run"
  echo "❌ FAIL"
  exit 1
else
  echo "✅ ALL PASS"
  exit 0
fi

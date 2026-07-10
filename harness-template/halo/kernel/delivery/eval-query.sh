#!/usr/bin/env bash
# eval-query.sh — Query a central eval sink as Markdown or JSON.
source "$(dirname "$0")/../_lib.sh"

for arg in "$@"; do
  [[ "$arg" == "--help" || "$arg" == "-h" ]] && cli_help "eval query" "Query a central eval sink" \
    "eval-query.sh summary  [--sink-dir=<dir>] [--format=markdown|json]" \
    "eval-query.sh runs     [--project=<name>] [--status=<status>] [--limit=20] [--format=markdown|json]" \
    "eval-query.sh outcomes [--project=<name>] [--type=<type>] [--severity=<severity>] [--limit=20] [--format=markdown|json]"
done

ACTION="${1:-summary}"
[[ $# -gt 0 ]] && shift

SINK_DIR="$(manifest_get '.eval.sink.dir')"
SINK_DIR="${SINK_DIR:-halo/state/eval-sink}"
PROJECT_FILTER=""
STATUS_FILTER=""
TYPE_FILTER=""
SEVERITY_FILTER=""
FORMAT="markdown"
LIMIT=20

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sink-dir=*) SINK_DIR="${1#--sink-dir=}" ;;
    --project=*) PROJECT_FILTER="${1#--project=}" ;;
    --status=*) STATUS_FILTER="${1#--status=}" ;;
    --type=*) TYPE_FILTER="${1#--type=}" ;;
    --severity=*) SEVERITY_FILTER="${1#--severity=}" ;;
    --format=*) FORMAT="${1#--format=}" ;;
    --limit=*) LIMIT="${1#--limit=}" ;;
    --sink-dir|--project|--status|--type|--severity|--format|--limit)
      key="$1"
      shift
      case "$key" in
        --sink-dir) SINK_DIR="${1:-}" ;;
        --project) PROJECT_FILTER="${1:-}" ;;
        --status) STATUS_FILTER="${1:-}" ;;
        --type) TYPE_FILTER="${1:-}" ;;
        --severity) SEVERITY_FILTER="${1:-}" ;;
        --format) FORMAT="${1:-}" ;;
        --limit) LIMIT="${1:-}" ;;
      esac
      ;;
    -*)
      echo "Unknown option: $1"
      exit 1
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
  shift
done

[[ "$SINK_DIR" == /* ]] || SINK_DIR="$PROJECT_ROOT/$SINK_DIR"

case "$FORMAT" in
  markdown|json) ;;
  *) echo "format must be markdown or json"; exit 1 ;;
esac

if ! [[ "$LIMIT" =~ ^[0-9]+$ ]] || [[ "$LIMIT" -eq 0 ]]; then
  echo "limit must be a positive integer"
  exit 1
fi

json_escape() {
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

md_escape() {
  local value="${1:-}"
  value="${value//$'\r'/}"
  value="${value//$'\n'/<br>}"
  value="${value//|/\\|}"
  printf '%s' "$value"
}

json_get() {
  local file="$1" expr="$2" value
  value="$(yq -r "$expr // \"\"" "$file" 2>/dev/null || true)"
  [[ "$value" == "null" ]] && value=""
  printf '%s' "$value"
}

json_num() {
  local file="$1" expr="$2" value
  value="$(json_get "$file" "$expr")"
  if [[ "$value" =~ ^-?[0-9]+$ ]]; then
    printf '%s' "$value"
  else
    printf '0'
  fi
}

project_dir_for_file() {
  local file="$1" dir
  dir="$(dirname "$file")"
  while [[ "$dir" != "/" && "$(basename "$dir")" != "projects" ]]; do
    if [[ -f "$dir/manifest.json" ]]; then
      printf '%s' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  printf ''
}

project_name_for_file() {
  local file="$1" project_dir manifest project
  project_dir="$(project_dir_for_file "$file")"
  manifest="$project_dir/manifest.json"
  project="$(json_get "$manifest" '.project')"
  printf '%s' "${project:-unknown}"
}

matches_project() {
  local project="$1" slug="$2"
  [[ -z "$PROJECT_FILTER" || "$project" == "$PROJECT_FILTER" || "$slug" == "$PROJECT_FILTER" ]]
}

declare -a MANIFEST_FILES=()
declare -a RUN_FILES=()
declare -a OUTCOME_FILES=()

if [[ -d "$SINK_DIR/projects" ]]; then
  while IFS= read -r file; do
    MANIFEST_FILES+=("$file")
  done < <(find "$SINK_DIR/projects" -mindepth 2 -maxdepth 2 -type f -name 'manifest.json' -print 2>/dev/null | sort)

  while IFS= read -r file; do
    if yq -e '.run_id and .pipeline and .metrics' "$file" >/dev/null 2>&1; then
      RUN_FILES+=("$file")
    fi
  done < <(find "$SINK_DIR/projects" -path '*/eval-runs/*.json' -type f -print 2>/dev/null | sort)

  while IFS= read -r file; do
    if yq -e '.eval_run.run_id and .outcome.type' "$file" >/dev/null 2>&1; then
      OUTCOME_FILES+=("$file")
    fi
  done < <(find "$SINK_DIR/projects" -path '*/outcomes/*.json' -type f -print 2>/dev/null | sort)
fi

PROJECT_TOTAL=0
RUN_TOTAL=0
RUN_PASS=0
RUN_FAIL=0
RUN_ESCALATION=0
OUTCOME_TOTAL=0
OUTCOME_NEGATIVE=0
OUTCOME_SUCCESS=0
OUTCOME_HIGH_CRITICAL=0

if [[ "${#MANIFEST_FILES[@]}" -gt 0 ]]; then
  for manifest in "${MANIFEST_FILES[@]}"; do
    project="$(json_get "$manifest" '.project')"
    slug="$(json_get "$manifest" '.project_slug')"
    matches_project "$project" "$slug" || continue
    PROJECT_TOTAL=$((PROJECT_TOTAL + 1))
  done
fi

if [[ "${#RUN_FILES[@]}" -gt 0 ]]; then
  for file in "${RUN_FILES[@]}"; do
    project="$(project_name_for_file "$file")"
    slug="$(basename "$(project_dir_for_file "$file")")"
    status="$(json_get "$file" '.pipeline.status')"
    matches_project "$project" "$slug" || continue
    [[ -n "$STATUS_FILTER" && "$status" != "$STATUS_FILTER" ]] && continue
    RUN_TOTAL=$((RUN_TOTAL + 1))
    case "$status" in
      pass) RUN_PASS=$((RUN_PASS + 1)) ;;
      fail) RUN_FAIL=$((RUN_FAIL + 1)) ;;
      escalation) RUN_ESCALATION=$((RUN_ESCALATION + 1)) ;;
    esac
  done
fi

if [[ "${#OUTCOME_FILES[@]}" -gt 0 ]]; then
  for file in "${OUTCOME_FILES[@]}"; do
    project="$(project_name_for_file "$file")"
    slug="$(basename "$(project_dir_for_file "$file")")"
    type="$(json_get "$file" '.outcome.type')"
    severity="$(json_get "$file" '.outcome.severity')"
    matches_project "$project" "$slug" || continue
    [[ -n "$TYPE_FILTER" && "$type" != "$TYPE_FILTER" ]] && continue
    [[ -n "$SEVERITY_FILTER" && "$severity" != "$SEVERITY_FILTER" ]] && continue
    OUTCOME_TOTAL=$((OUTCOME_TOTAL + 1))
    case "$type" in
      rework|escaped_defect|incident) OUTCOME_NEGATIVE=$((OUTCOME_NEGATIVE + 1)) ;;
      success) OUTCOME_SUCCESS=$((OUTCOME_SUCCESS + 1)) ;;
    esac
    case "$severity" in
      high|critical) OUTCOME_HIGH_CRITICAL=$((OUTCOME_HIGH_CRITICAL + 1)) ;;
    esac
  done
fi

render_summary_markdown() {
  echo "# Halo Eval Query"
  echo ""
  echo "| Metric | Value |"
  echo "|---|---:|"
  echo "| Projects | $PROJECT_TOTAL |"
  echo "| Eval Runs | $RUN_TOTAL |"
  echo "| Passing Runs | $RUN_PASS |"
  echo "| Failing Runs | $RUN_FAIL |"
  echo "| Escalations | $RUN_ESCALATION |"
  echo "| Outcomes | $OUTCOME_TOTAL |"
  echo "| Negative Outcomes | $OUTCOME_NEGATIVE |"
  echo "| High/Critical Outcomes | $OUTCOME_HIGH_CRITICAL |"
  echo "| Success Signals | $OUTCOME_SUCCESS |"
  echo ""
  echo "## Projects"
  echo ""
  echo "| Project | Eval Runs | Outcomes | Reports | Git | Updated |"
  echo "|---|---:|---:|---:|---|---|"

  local count=0 manifest project slug eval_count outcome_count report_count git_sha published_at
  if [[ "${#MANIFEST_FILES[@]}" -gt 0 ]]; then
    for manifest in "${MANIFEST_FILES[@]}"; do
      project="$(json_get "$manifest" '.project')"
      slug="$(json_get "$manifest" '.project_slug')"
      matches_project "$project" "$slug" || continue
      eval_count="$(json_num "$manifest" '.counts.eval_runs')"
      outcome_count="$(json_num "$manifest" '.counts.outcomes')"
      report_count="$(json_num "$manifest" '.counts.reports')"
      git_sha="$(json_get "$manifest" '.git_sha')"
      published_at="$(json_get "$manifest" '.published_at')"
      echo "| $(md_escape "${project:-unknown}") | $eval_count | $outcome_count | $report_count | $(md_escape "${git_sha:-unknown}") | $(md_escape "${published_at:-unknown}") |"
      count=$((count + 1))
    done
  fi
  [[ "$count" -eq 0 ]] && echo "| _none_ | 0 | 0 | 0 | - | - |"
  return 0
}

render_runs_markdown() {
  echo "# Halo Eval Runs"
  echo ""
  echo "| Project | Run | Status | Spec | Git | AC | Drift | Review | Loop |"
  echo "|---|---|---|---|---|---:|---:|---|---|"

  local matched=0 emitted=0 i file project slug status run_id spec git ac_total ac_covered drift review_total review_failed review_cannot_verify retry_count next_action
  if [[ "${#RUN_FILES[@]}" -gt 0 ]]; then
    for ((i = ${#RUN_FILES[@]} - 1; i >= 0; i--)); do
      file="${RUN_FILES[$i]}"
      project="$(project_name_for_file "$file")"
      slug="$(basename "$(project_dir_for_file "$file")")"
      status="$(json_get "$file" '.pipeline.status')"
      matches_project "$project" "$slug" || continue
      [[ -n "$STATUS_FILTER" && "$status" != "$STATUS_FILTER" ]] && continue
      matched=$((matched + 1))
      [[ "$emitted" -ge "$LIMIT" ]] && continue
      run_id="$(json_get "$file" '.run_id')"
      spec="$(json_get "$file" '.spec_file')"
      git="$(json_get "$file" '.git_sha')"
      ac_total="$(json_num "$file" '.metrics.ac_total')"
      ac_covered="$(json_num "$file" '.metrics.ac_covered')"
      drift="$(json_num "$file" '.metrics.drift_count')"
      review_total="$(json_num "$file" '.metrics.review_total')"
      review_failed="$(json_num "$file" '.metrics.review_failed')"
      review_cannot_verify="$(json_num "$file" '.metrics.review_cannot_verify')"
      retry_count="$(json_num "$file" '.loop_state.retry_count')"
      next_action="$(json_get "$file" '.loop_state.next_action')"
      echo "| $(md_escape "$project") | $(md_escape "${run_id:-unknown}") | $(md_escape "${status:-unknown}") | $(md_escape "${spec:-none}") | $(md_escape "${git:-unknown}") | $ac_covered/$ac_total | $drift | $review_failed fail / $review_cannot_verify cannot_verify / $review_total | retry=$retry_count, next=$(md_escape "${next_action:-unknown}") |"
      emitted=$((emitted + 1))
    done
  fi
  [[ "$matched" -eq 0 ]] && echo "| _none_ | - | - | - | - | - | - | - | - |"
  return 0
}

render_outcomes_markdown() {
  echo "# Halo Eval Outcomes"
  echo ""
  echo "| Project | Run | Type | Severity | Source | Context Refs | Summary |"
  echo "|---|---|---|---|---|---|---|"

  local matched=0 emitted=0 i file project slug run_id type severity source refs summary
  if [[ "${#OUTCOME_FILES[@]}" -gt 0 ]]; then
    for ((i = ${#OUTCOME_FILES[@]} - 1; i >= 0; i--)); do
      file="${OUTCOME_FILES[$i]}"
      project="$(project_name_for_file "$file")"
      slug="$(basename "$(project_dir_for_file "$file")")"
      type="$(json_get "$file" '.outcome.type')"
      severity="$(json_get "$file" '.outcome.severity')"
      matches_project "$project" "$slug" || continue
      [[ -n "$TYPE_FILTER" && "$type" != "$TYPE_FILTER" ]] && continue
      [[ -n "$SEVERITY_FILTER" && "$severity" != "$SEVERITY_FILTER" ]] && continue
      matched=$((matched + 1))
      [[ "$emitted" -ge "$LIMIT" ]] && continue
      run_id="$(json_get "$file" '.eval_run.run_id')"
      source="$(json_get "$file" '.outcome.source')"
      refs="$(yq -r '(.context_refs // []) | join(", ")' "$file" 2>/dev/null || true)"
      summary="$(json_get "$file" '.outcome.summary')"
      echo "| $(md_escape "$project") | $(md_escape "${run_id:-unknown}") | $(md_escape "${type:-unknown}") | $(md_escape "${severity:-unknown}") | $(md_escape "${source:-unknown}") | $(md_escape "$refs") | $(md_escape "$summary") |"
      emitted=$((emitted + 1))
    done
  fi
  [[ "$matched" -eq 0 ]] && echo "| _none_ | - | - | - | - | - | - |"
  return 0
}

json_query_header() {
  printf '{\n'
  printf '  "schema_version": "halo.eval-query.v1",\n'
  printf '  "kind": "eval-query",\n'
  printf '  "action": "%s",\n' "$(json_escape "$ACTION")"
  printf '  "query": {\n'
  printf '    "sink_dir": "%s",\n' "$(json_escape "$SINK_DIR")"
  printf '    "project": "%s",\n' "$(json_escape "$PROJECT_FILTER")"
  printf '    "status": "%s",\n' "$(json_escape "$STATUS_FILTER")"
  printf '    "type": "%s",\n' "$(json_escape "$TYPE_FILTER")"
  printf '    "severity": "%s",\n' "$(json_escape "$SEVERITY_FILTER")"
  printf '    "limit": %s\n' "$LIMIT"
  printf '  },\n'
  printf '  "metrics": {\n'
  printf '    "projects": %s,\n' "$PROJECT_TOTAL"
  printf '    "eval_runs": %s,\n' "$RUN_TOTAL"
  printf '    "runs_pass": %s,\n' "$RUN_PASS"
  printf '    "runs_fail": %s,\n' "$RUN_FAIL"
  printf '    "runs_escalation": %s,\n' "$RUN_ESCALATION"
  printf '    "outcomes": %s,\n' "$OUTCOME_TOTAL"
  printf '    "negative_outcomes": %s,\n' "$OUTCOME_NEGATIVE"
  printf '    "high_critical_outcomes": %s,\n' "$OUTCOME_HIGH_CRITICAL"
  printf '    "success_signals": %s\n' "$OUTCOME_SUCCESS"
  printf '  },\n'
}

render_summary_json() {
  json_query_header
  printf '  "projects": [\n'
  local first=true manifest project slug eval_count outcome_count report_count git_sha published_at
  if [[ "${#MANIFEST_FILES[@]}" -gt 0 ]]; then
    for manifest in "${MANIFEST_FILES[@]}"; do
      project="$(json_get "$manifest" '.project')"
      slug="$(json_get "$manifest" '.project_slug')"
      matches_project "$project" "$slug" || continue
      eval_count="$(json_num "$manifest" '.counts.eval_runs')"
      outcome_count="$(json_num "$manifest" '.counts.outcomes')"
      report_count="$(json_num "$manifest" '.counts.reports')"
      git_sha="$(json_get "$manifest" '.git_sha')"
      published_at="$(json_get "$manifest" '.published_at')"
      [[ "$first" == true ]] || printf ',\n'
      first=false
      printf '    {"project":"%s","project_slug":"%s","eval_runs":%s,"outcomes":%s,"reports":%s,"git_sha":"%s","published_at":"%s"}' \
        "$(json_escape "${project:-unknown}")" "$(json_escape "${slug:-project}")" "$eval_count" "$outcome_count" "$report_count" "$(json_escape "${git_sha:-unknown}")" "$(json_escape "${published_at:-unknown}")"
    done
  fi
  printf '\n  ]\n'
  printf '}\n'
}

render_runs_json() {
  json_query_header
  printf '  "items": [\n'
  local first=true emitted=0 i file project slug status run_id spec git ac_total ac_covered drift review_total review_failed review_cannot_verify retry_count next_action
  if [[ "${#RUN_FILES[@]}" -gt 0 ]]; then
    for ((i = ${#RUN_FILES[@]} - 1; i >= 0; i--)); do
      file="${RUN_FILES[$i]}"
      project="$(project_name_for_file "$file")"
      slug="$(basename "$(project_dir_for_file "$file")")"
      status="$(json_get "$file" '.pipeline.status')"
      matches_project "$project" "$slug" || continue
      [[ -n "$STATUS_FILTER" && "$status" != "$STATUS_FILTER" ]] && continue
      [[ "$emitted" -ge "$LIMIT" ]] && continue
      run_id="$(json_get "$file" '.run_id')"
      spec="$(json_get "$file" '.spec_file')"
      git="$(json_get "$file" '.git_sha')"
      ac_total="$(json_num "$file" '.metrics.ac_total')"
      ac_covered="$(json_num "$file" '.metrics.ac_covered')"
      drift="$(json_num "$file" '.metrics.drift_count')"
      review_total="$(json_num "$file" '.metrics.review_total')"
      review_failed="$(json_num "$file" '.metrics.review_failed')"
      review_cannot_verify="$(json_num "$file" '.metrics.review_cannot_verify')"
      retry_count="$(json_num "$file" '.loop_state.retry_count')"
      next_action="$(json_get "$file" '.loop_state.next_action')"
      [[ "$first" == true ]] || printf ',\n'
      first=false
      printf '    {"project":"%s","run_id":"%s","status":"%s","spec_file":"%s","git_sha":"%s","ac_covered":%s,"ac_total":%s,"drift_count":%s,"review_failed":%s,"review_cannot_verify":%s,"review_total":%s,"retry_count":%s,"next_action":"%s"}' \
        "$(json_escape "$project")" "$(json_escape "${run_id:-unknown}")" "$(json_escape "${status:-unknown}")" "$(json_escape "${spec:-none}")" "$(json_escape "${git:-unknown}")" "$ac_covered" "$ac_total" "$drift" "$review_failed" "$review_cannot_verify" "$review_total" "$retry_count" "$(json_escape "${next_action:-unknown}")"
      emitted=$((emitted + 1))
    done
  fi
  printf '\n  ]\n'
  printf '}\n'
}

render_outcomes_json() {
  json_query_header
  printf '  "items": [\n'
  local first=true emitted=0 i file project slug run_id type severity source refs summary
  if [[ "${#OUTCOME_FILES[@]}" -gt 0 ]]; then
    for ((i = ${#OUTCOME_FILES[@]} - 1; i >= 0; i--)); do
      file="${OUTCOME_FILES[$i]}"
      project="$(project_name_for_file "$file")"
      slug="$(basename "$(project_dir_for_file "$file")")"
      type="$(json_get "$file" '.outcome.type')"
      severity="$(json_get "$file" '.outcome.severity')"
      matches_project "$project" "$slug" || continue
      [[ -n "$TYPE_FILTER" && "$type" != "$TYPE_FILTER" ]] && continue
      [[ -n "$SEVERITY_FILTER" && "$severity" != "$SEVERITY_FILTER" ]] && continue
      [[ "$emitted" -ge "$LIMIT" ]] && continue
      run_id="$(json_get "$file" '.eval_run.run_id')"
      source="$(json_get "$file" '.outcome.source')"
      refs="$(yq -r '(.context_refs // []) | join(", ")' "$file" 2>/dev/null || true)"
      summary="$(json_get "$file" '.outcome.summary')"
      [[ "$first" == true ]] || printf ',\n'
      first=false
      printf '    {"project":"%s","run_id":"%s","type":"%s","severity":"%s","source":"%s","context_refs":"%s","summary":"%s"}' \
        "$(json_escape "$project")" "$(json_escape "${run_id:-unknown}")" "$(json_escape "${type:-unknown}")" "$(json_escape "${severity:-unknown}")" "$(json_escape "${source:-unknown}")" "$(json_escape "$refs")" "$(json_escape "$summary")"
      emitted=$((emitted + 1))
    done
  fi
  printf '\n  ]\n'
  printf '}\n'
}

case "$ACTION:$FORMAT" in
  summary:markdown) render_summary_markdown ;;
  runs:markdown) render_runs_markdown ;;
  outcomes:markdown) render_outcomes_markdown ;;
  summary:json) render_summary_json ;;
  runs:json) render_runs_json ;;
  outcomes:json) render_outcomes_json ;;
  *)
    echo "Usage: eval-query.sh [summary|runs|outcomes] [--sink-dir=<dir>] [--format=markdown|json]"
    exit 1
    ;;
esac

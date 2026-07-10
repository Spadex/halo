#!/usr/bin/env bash
# eval-sink.sh — Publish eval evidence to a local central sink directory.
source "$(dirname "$0")/../_lib.sh"

for arg in "$@"; do
  [[ "$arg" == "--help" || "$arg" == "-h" ]] && cli_help "eval sink" "Publish eval evidence to a local central sink" \
    "eval-sink.sh publish [--sink-dir=<dir>] [--project=<name>] [--eval-dir=<dir>] [--outcomes-dir=<dir>]" \
    "eval-sink.sh status  [--sink-dir=<dir>]"
done

ACTION="${1:-status}"
[[ $# -gt 0 ]] && shift

PROJECT_NAME="$(manifest_get '.project.name')"
PROJECT_NAME="${PROJECT_NAME:-project}"
SINK_DIR="$(manifest_get '.eval.sink.dir')"
SINK_DIR="${SINK_DIR:-halo/state/eval-sink}"
EVAL_DIR="halo/state/eval-runs"
OUTCOME_DIR="halo/state/outcomes"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sink-dir=*) SINK_DIR="${1#--sink-dir=}" ;;
    --project=*) PROJECT_NAME="${1#--project=}" ;;
    --eval-dir=*) EVAL_DIR="${1#--eval-dir=}" ;;
    --outcomes-dir=*) OUTCOME_DIR="${1#--outcomes-dir=}" ;;
    --sink-dir|--project|--eval-dir|--outcomes-dir)
      key="$1"
      shift
      case "$key" in
        --sink-dir) SINK_DIR="${1:-}" ;;
        --project) PROJECT_NAME="${1:-}" ;;
        --eval-dir) EVAL_DIR="${1:-}" ;;
        --outcomes-dir) OUTCOME_DIR="${1:-}" ;;
      esac
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
  shift
done

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

rel_path() {
  local path="$1"
  if [[ "$path" == "$PROJECT_ROOT/"* ]]; then
    printf '%s' "${path#$PROJECT_ROOT/}"
  else
    printf '%s' "$path"
  fi
}

safe_slug() {
  local s="$1"
  s="${s//[^A-Za-z0-9_.-]/-}"
  printf '%s' "$s"
}

json_get_file() {
  local file="$1" expr="$2" value
  value="$(yq -r "$expr // \"\"" "$file" 2>/dev/null || true)"
  [[ "$value" == "null" ]] && value=""
  printf '%s' "$value"
}

abs_path() {
  local path="$1"
  [[ "$path" == /* ]] && printf '%s' "$path" || printf '%s/%s' "$PROJECT_ROOT" "$path"
}

count_files() {
  local dir="$1" pattern="$2"
  if [[ -d "$dir" ]]; then
    find "$dir" -maxdepth 1 -type f -name "$pattern" -print 2>/dev/null | wc -l | tr -d ' '
  else
    printf '0'
  fi
}

copy_matching_files() {
  local src_dir="$1" dest_dir="$2" pattern="$3" copied=0 file
  mkdir -p "$dest_dir"
  if [[ -d "$src_dir" ]]; then
    while IFS= read -r file; do
      cp "$file" "$dest_dir/"
      copied=$((copied + 1))
    done < <(find "$src_dir" -maxdepth 1 -type f -name "$pattern" -print 2>/dev/null | sort)
  fi
  printf '%s' "$copied"
}

write_project_manifest() {
  local out="$1" eval_count="$2" outcome_count="$3" report_count="$4" project_slug="$5"
  local git_sha generated_at
  git_sha="$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
  generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  {
    printf '{\n'
    printf '  "schema_version": "halo.eval-sink-project.v1",\n'
    printf '  "kind": "eval-sink-project",\n'
    printf '  "project": "%s",\n' "$(json_escape "$PROJECT_NAME")"
    printf '  "project_slug": "%s",\n' "$(json_escape "$project_slug")"
    printf '  "source_root": "%s",\n' "$(json_escape "$PROJECT_ROOT")"
    printf '  "git_sha": "%s",\n' "$(json_escape "$git_sha")"
    printf '  "published_at": "%s",\n' "$(json_escape "$generated_at")"
    printf '  "counts": {\n'
    printf '    "eval_runs": %s,\n' "$eval_count"
    printf '    "outcomes": %s,\n' "$outcome_count"
    printf '    "reports": %s\n' "$report_count"
    printf '  }\n'
    printf '}\n'
  } > "$out"
}

render_index() {
  local sink="$1" manifest project count eval_count outcome_count report_count git_sha published_at
  echo "# Halo Central Eval Sink"
  echo ""
  echo "| Project | Eval Runs | Outcomes | Reports | Git | Updated |"
  echo "|---|---:|---:|---:|---|---|"
  count=0
  if [[ -d "$sink/projects" ]]; then
    while IFS= read -r manifest; do
      project="$(json_get_file "$manifest" '.project')"
      eval_count="$(json_get_file "$manifest" '.counts.eval_runs')"
      outcome_count="$(json_get_file "$manifest" '.counts.outcomes')"
      report_count="$(json_get_file "$manifest" '.counts.reports')"
      git_sha="$(json_get_file "$manifest" '.git_sha')"
      published_at="$(json_get_file "$manifest" '.published_at')"
      echo "| $(md_escape "${project:-unknown}") | ${eval_count:-0} | ${outcome_count:-0} | ${report_count:-0} | $(md_escape "${git_sha:-unknown}") | $(md_escape "${published_at:-unknown}") |"
      count=$((count + 1))
    done < <(find "$sink/projects" -mindepth 2 -maxdepth 2 -type f -name 'manifest.json' -print 2>/dev/null | sort)
  fi
  if [[ "$count" -eq 0 ]]; then
    echo "| _none_ | 0 | 0 | 0 | - | - |"
  fi
}

SINK_ABS="$(abs_path "$SINK_DIR")"
EVAL_ABS="$(abs_path "$EVAL_DIR")"
OUTCOME_ABS="$(abs_path "$OUTCOME_DIR")"
PROJECT_SLUG="$(safe_slug "$PROJECT_NAME")"
PROJECT_SINK="$SINK_ABS/projects/$PROJECT_SLUG"

case "$ACTION" in
  publish)
    mkdir -p "$PROJECT_SINK/eval-runs" "$PROJECT_SINK/outcomes" "$PROJECT_SINK/reports"
    EVAL_COPIED="$(copy_matching_files "$EVAL_ABS" "$PROJECT_SINK/eval-runs" '*.json')"
    OUTCOME_COPIED="$(copy_matching_files "$OUTCOME_ABS" "$PROJECT_SINK/outcomes" '*.json')"
    REPORT_COPIED=0
    if [[ -d "$PROJECT_ROOT/halo/state" ]]; then
      REPORT_COPIED="$(copy_matching_files "$PROJECT_ROOT/halo/state" "$PROJECT_SINK/reports" '*.md')"
    fi
    write_project_manifest "$PROJECT_SINK/manifest.json" "$EVAL_COPIED" "$OUTCOME_COPIED" "$REPORT_COPIED" "$PROJECT_SLUG"
    render_index "$SINK_ABS" > "$SINK_ABS/index.md"
    echo "Eval sink published: $(rel_path "$PROJECT_SINK")"
    echo "Index: $(rel_path "$SINK_ABS/index.md")"
    ;;
  status)
    echo "Eval sink: $(rel_path "$SINK_ABS")"
    echo "Project: $PROJECT_NAME"
    echo "Eval runs: $(count_files "$EVAL_ABS" '*.json')"
    echo "Outcomes: $(count_files "$OUTCOME_ABS" '*.json')"
    if [[ -f "$SINK_ABS/index.md" ]]; then
      echo "Index: $(rel_path "$SINK_ABS/index.md")"
    else
      echo "Index: not generated"
    fi
    ;;
  *)
    echo "Usage: eval-sink.sh [publish|status] [--sink-dir=<dir>]"
    exit 1
    ;;
esac

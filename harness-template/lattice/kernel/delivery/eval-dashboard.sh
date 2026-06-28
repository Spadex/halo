#!/usr/bin/env bash
# eval-dashboard.sh — Render a static HTML dashboard from a central eval sink.
source "$(dirname "$0")/../_lib.sh"

for arg in "$@"; do
  [[ "$arg" == "--help" || "$arg" == "-h" ]] && cli_help "eval dashboard" "Render a static HTML dashboard from central eval sink files" \
    "eval-dashboard.sh [--sink-dir=<dir>] [--out=<file>] [--limit=20]" \
    "eval-dashboard.sh --sink-dir=lattice/state/eval-sink --out=lattice/state/eval-sink/dashboard.html"
done

SINK_DIR="$(manifest_get '.eval.sink.dir')"
SINK_DIR="${SINK_DIR:-lattice/state/eval-sink}"
OUT=""
LIMIT=20

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sink-dir=*) SINK_DIR="${1#--sink-dir=}" ;;
    --out=*) OUT="${1#--out=}" ;;
    --out)
      shift
      OUT="${1:-}"
      ;;
    --limit=*) LIMIT="${1#--limit=}" ;;
    -*)
      echo "Unknown option: $1"
      exit 1
      ;;
    *)
      SINK_DIR="$1"
      ;;
  esac
  shift
done

[[ "$SINK_DIR" == /* ]] || SINK_DIR="$PROJECT_ROOT/$SINK_DIR"
OUT="${OUT:-$SINK_DIR/dashboard.html}"
[[ "$OUT" == /* ]] || OUT="$PROJECT_ROOT/$OUT"

if ! [[ "$LIMIT" =~ ^[0-9]+$ ]] || [[ "$LIMIT" -eq 0 ]]; then
  echo "limit must be a positive integer"
  exit 1
fi

html_escape() {
  local s="${1:-}"
  s="${s//&/&amp;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  s="${s//\"/&quot;}"
  s="${s//$'\r'/}"
  s="${s//$'\n'/ }"
  printf '%s' "$s"
}

json_get_file() {
  local file="$1" expr="$2" value
  value="$(yq -r "$expr // \"\"" "$file" 2>/dev/null || true)"
  [[ "$value" == "null" ]] && value=""
  printf '%s' "$value"
}

json_num() {
  local file="$1" expr="$2" value
  value="$(json_get_file "$file" "$expr")"
  if [[ "$value" =~ ^-?[0-9]+$ ]]; then
    printf '%s' "$value"
  else
    printf '0'
  fi
}

rel_from_out() {
  local target="$1" base
  base="$(dirname "$OUT")"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$base" "$target" <<'PY'
import os, sys
print(os.path.relpath(sys.argv[2], sys.argv[1]))
PY
  else
    printf '%s' "$target"
  fi
}

count_project_outcomes() {
  local project_dir="$1" type="$2"
  local count=0 file
  if [[ -d "$project_dir/outcomes" ]]; then
    while IFS= read -r file; do
      if [[ "$(json_get_file "$file" '.outcome.type')" == "$type" ]]; then
        count=$((count + 1))
      fi
    done < <(find "$project_dir/outcomes" -maxdepth 1 -type f -name '*.json' -print 2>/dev/null)
  fi
  printf '%s' "$count"
}

declare -a MANIFESTS=()
if [[ -d "$SINK_DIR/projects" ]]; then
  while IFS= read -r manifest; do
    MANIFESTS+=("$manifest")
  done < <(find "$SINK_DIR/projects" -mindepth 2 -maxdepth 2 -type f -name 'manifest.json' -print 2>/dev/null | sort)
fi

PROJECT_TOTAL="${#MANIFESTS[@]}"
EVAL_TOTAL=0
OUTCOME_TOTAL=0
REPORT_TOTAL=0
NEGATIVE_TOTAL=0
SUCCESS_TOTAL=0

if [[ "$PROJECT_TOTAL" -gt 0 ]]; then
  for manifest in "${MANIFESTS[@]}"; do
    project_dir="$(dirname "$manifest")"
    eval_count="$(json_num "$manifest" '.counts.eval_runs')"
    outcome_count="$(json_num "$manifest" '.counts.outcomes')"
    report_count="$(json_num "$manifest" '.counts.reports')"
    EVAL_TOTAL=$((EVAL_TOTAL + eval_count))
    OUTCOME_TOTAL=$((OUTCOME_TOTAL + outcome_count))
    REPORT_TOTAL=$((REPORT_TOTAL + report_count))
    NEGATIVE_TOTAL=$((NEGATIVE_TOTAL + $(count_project_outcomes "$project_dir" "rework")))
    NEGATIVE_TOTAL=$((NEGATIVE_TOTAL + $(count_project_outcomes "$project_dir" "escaped_defect")))
    NEGATIVE_TOTAL=$((NEGATIVE_TOTAL + $(count_project_outcomes "$project_dir" "incident")))
    SUCCESS_TOTAL=$((SUCCESS_TOTAL + $(count_project_outcomes "$project_dir" "success")))
  done
fi

render_project_rows() {
  local manifest project_dir project slug eval_count outcome_count report_count git_sha published_at report_href
  if [[ "$PROJECT_TOTAL" -eq 0 ]]; then
    echo '<tr><td colspan="7">No projects published yet.</td></tr>'
    return 0
  fi
  for manifest in "${MANIFESTS[@]}"; do
    project_dir="$(dirname "$manifest")"
    project="$(json_get_file "$manifest" '.project')"
    slug="$(json_get_file "$manifest" '.project_slug')"
    eval_count="$(json_num "$manifest" '.counts.eval_runs')"
    outcome_count="$(json_num "$manifest" '.counts.outcomes')"
    report_count="$(json_num "$manifest" '.counts.reports')"
    git_sha="$(json_get_file "$manifest" '.git_sha')"
    published_at="$(json_get_file "$manifest" '.published_at')"
    report_href="$(rel_from_out "$project_dir/reports")"
    printf '<tr>'
    printf '<td><strong>%s</strong><span>%s</span></td>' "$(html_escape "${project:-unknown}")" "$(html_escape "${slug:-project}")"
    printf '<td>%s</td>' "$eval_count"
    printf '<td>%s</td>' "$outcome_count"
    printf '<td>%s</td>' "$report_count"
    printf '<td><code>%s</code></td>' "$(html_escape "${git_sha:-unknown}")"
    printf '<td>%s</td>' "$(html_escape "${published_at:-unknown}")"
    printf '<td><a href="%s">reports</a></td>' "$(html_escape "$report_href")"
    printf '</tr>\n'
  done
}

render_recent_outcomes() {
  local outcome_files=() file project_dir manifest project run_id type severity source summary context_refs row_count i
  if [[ -d "$SINK_DIR/projects" ]]; then
    while IFS= read -r file; do
      outcome_files+=("$file")
    done < <(find "$SINK_DIR/projects" -path '*/outcomes/*.json' -type f -print 2>/dev/null | sort)
  fi
  if [[ "${#outcome_files[@]}" -eq 0 ]]; then
    echo '<tr><td colspan="7">No outcome links recorded yet.</td></tr>'
    return 0
  fi
  row_count=0
  for ((i = ${#outcome_files[@]} - 1; i >= 0 && row_count < LIMIT; i--)); do
    file="${outcome_files[$i]}"
    project_dir="$(dirname "$(dirname "$file")")"
    manifest="$project_dir/manifest.json"
    project="$(json_get_file "$manifest" '.project')"
    run_id="$(json_get_file "$file" '.eval_run.run_id')"
    type="$(json_get_file "$file" '.outcome.type')"
    severity="$(json_get_file "$file" '.outcome.severity')"
    source="$(json_get_file "$file" '.outcome.source')"
    summary="$(json_get_file "$file" '.outcome.summary')"
    context_refs="$(yq -r '(.context_refs // []) | join(", ")' "$file" 2>/dev/null || true)"
    printf '<tr>'
    printf '<td>%s</td>' "$(html_escape "${project:-unknown}")"
    printf '<td><code>%s</code></td>' "$(html_escape "${run_id:-unknown}")"
    printf '<td>%s</td>' "$(html_escape "${type:-unknown}")"
    printf '<td><span class="severity severity-%s">%s</span></td>' "$(html_escape "${severity:-none}")" "$(html_escape "${severity:-none}")"
    printf '<td>%s</td>' "$(html_escape "${source:-unknown}")"
    printf '<td>%s</td>' "$(html_escape "$context_refs")"
    printf '<td>%s</td>' "$(html_escape "$summary")"
    printf '</tr>\n'
    row_count=$((row_count + 1))
  done
}

mkdir -p "$(dirname "$OUT")"
GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

{
  cat <<HTML
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Lattice Eval Dashboard</title>
  <style>
    :root {
      color-scheme: light;
      --bg: #f7f8fa;
      --surface: #ffffff;
      --text: #1f2933;
      --muted: #687586;
      --line: #d7dde5;
      --blue: #2563eb;
      --green: #0f8f6d;
      --amber: #b7791f;
      --red: #c2413d;
      --ink: #101820;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: var(--bg);
      color: var(--text);
      font: 14px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      letter-spacing: 0;
    }
    header {
      background: var(--ink);
      color: #fff;
      padding: 28px 32px;
    }
    header h1 {
      margin: 0;
      font-size: 28px;
      font-weight: 700;
    }
    header p {
      margin: 6px 0 0;
      color: #cbd5e1;
    }
    main {
      max-width: 1180px;
      margin: 0 auto;
      padding: 24px;
    }
    .metrics {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
      gap: 12px;
      margin-bottom: 22px;
    }
    .metric {
      background: var(--surface);
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 14px 16px;
    }
    .metric span {
      color: var(--muted);
      display: block;
      font-size: 12px;
    }
    .metric strong {
      display: block;
      font-size: 24px;
      margin-top: 4px;
    }
    section {
      background: var(--surface);
      border: 1px solid var(--line);
      border-radius: 8px;
      margin: 16px 0;
      overflow: hidden;
    }
    section h2 {
      font-size: 16px;
      margin: 0;
      padding: 14px 16px;
      border-bottom: 1px solid var(--line);
      background: #fbfcfd;
    }
    .table-wrap { overflow-x: auto; }
    table {
      border-collapse: collapse;
      min-width: 860px;
      width: 100%;
    }
    th, td {
      border-bottom: 1px solid var(--line);
      padding: 11px 12px;
      text-align: left;
      vertical-align: top;
    }
    th {
      color: var(--muted);
      font-size: 12px;
      font-weight: 700;
      background: #fbfcfd;
    }
    td span {
      color: var(--muted);
      display: block;
      font-size: 12px;
      margin-top: 2px;
    }
    a { color: var(--blue); text-decoration: none; }
    code {
      background: #eef2f7;
      border-radius: 4px;
      padding: 2px 4px;
      white-space: nowrap;
    }
    .severity {
      border-radius: 999px;
      display: inline-block;
      padding: 2px 8px;
      color: #fff;
      font-size: 12px;
    }
    .severity-none, .severity-low { background: var(--green); }
    .severity-medium { background: var(--amber); }
    .severity-high, .severity-critical { background: var(--red); }
    footer {
      color: var(--muted);
      padding: 12px 0 24px;
    }
  </style>
</head>
<body>
  <header>
    <h1>Lattice Eval Dashboard</h1>
    <p>Central sink snapshot generated at $(html_escape "$GENERATED_AT").</p>
  </header>
  <main>
    <div class="metrics">
      <div class="metric"><span>Projects</span><strong>$PROJECT_TOTAL</strong></div>
      <div class="metric"><span>Eval Runs</span><strong>$EVAL_TOTAL</strong></div>
      <div class="metric"><span>Outcomes</span><strong>$OUTCOME_TOTAL</strong></div>
      <div class="metric"><span>Negative Outcomes</span><strong>$NEGATIVE_TOTAL</strong></div>
      <div class="metric"><span>Success Signals</span><strong>$SUCCESS_TOTAL</strong></div>
      <div class="metric"><span>Reports</span><strong>$REPORT_TOTAL</strong></div>
    </div>
    <section>
      <h2>Projects</h2>
      <div class="table-wrap">
        <table>
          <thead>
            <tr><th>Project</th><th>Eval Runs</th><th>Outcomes</th><th>Reports</th><th>Git</th><th>Updated</th><th>Links</th></tr>
          </thead>
          <tbody>
HTML
  render_project_rows
  cat <<HTML
          </tbody>
        </table>
      </div>
    </section>
    <section>
      <h2>Recent Outcomes</h2>
      <div class="table-wrap">
        <table>
          <thead>
            <tr><th>Project</th><th>Run</th><th>Type</th><th>Severity</th><th>Source</th><th>Context Refs</th><th>Summary</th></tr>
          </thead>
          <tbody>
HTML
  render_recent_outcomes
  cat <<HTML
          </tbody>
        </table>
      </div>
    </section>
    <footer>Data source: $(html_escape "$SINK_DIR")</footer>
  </main>
</body>
</html>
HTML
} > "$OUT"

echo "Eval dashboard: ${OUT#$PROJECT_ROOT/}"

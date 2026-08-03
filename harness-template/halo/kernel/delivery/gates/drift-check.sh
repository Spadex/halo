#!/usr/bin/env bash
# drift-check.sh — Spec-Code drift detection
source "$(dirname "$0")/../../_lib.sh"

for arg in "$@"; do
  [[ "$arg" == "--help" || "$arg" == "-h" ]] && cli_help "delivery gate drift-check" "Detect drift between spec and code" \
    "drift-check.sh [spec-file] [project-root]    Detect DDL/route/error code drift" \
    "drift-check.sh --json-out[=<file>]           Write structured gate JSON" \
    "" \
    "Detects: DDL column drift (GORM) · Route drift (Gin/Echo/Chi/FastAPI/Express) · Error code drift · Seed SQL drift" \
    "" \
    "Dimensions that cannot be compared are reported as NOT verified, never as no drift."
done

WRITE_JSON=false
JSON_OUT=""
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --json-out) WRITE_JSON=true ;;
    --json-out=*) WRITE_JSON=true; JSON_OUT="${arg#--json-out=}" ;;
    --help|-h) ;;
    *) POSITIONAL+=("$arg") ;;
  esac
done

SPEC="${POSITIONAL[0]:-}"
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
PROJECT="${POSITIONAL[1]:-$PROJECT_ROOT}"

[[ -f "$SPEC" ]] || { echo "Spec file not found: $SPEC"; exit 1; }

# PROJECT_LANG, not LANG: LANG is the locale environment variable, and overwriting it with
# a project language leaves every child process (awk, grep, sort) in an invalid locale.
PROJECT_LANG=$(get_language)
DRIFT=0
SKIPPED=0
GATE_FINDINGS=()
SKIPPED_DIMENSIONS=()

# A skipped dimension is not a clean dimension. Every check records whether it actually
# compared anything, so `drift_count: 0` can never be read as "the contract was verified".
CHECKED_DDL=false
CHECKED_ROUTES=false
CHECKED_ERROR_CODES=false
CHECKED_SEED_SQL=false

mark_checked() {
  case "${DRIFT_CATEGORY:-}" in
    ddl)         CHECKED_DDL=true ;;
    routes)      CHECKED_ROUTES=true ;;
    error_codes) CHECKED_ERROR_CODES=true ;;
    seed_sql)    CHECKED_SEED_SQL=true ;;
  esac
}

checks_run() {
  local n=0
  [[ "$CHECKED_DDL" == "true" ]] && n=$((n + 1))
  [[ "$CHECKED_ROUTES" == "true" ]] && n=$((n + 1))
  [[ "$CHECKED_ERROR_CODES" == "true" ]] && n=$((n + 1))
  [[ "$CHECKED_SEED_SQL" == "true" ]] && n=$((n + 1))
  printf '%s' "$n"
}

# Source files to scan, by project language. Override with drift.error_codes.file_glob
# or drift.routes.file_glob when a project does not follow the default extension.
lang_source_globs() {
  case "${1:-}" in
    go)                            printf '%s' '*.go' ;;
    python|py)                     printf '%s' '*.py' ;;
    node|javascript|typescript|ts) printf '%s' '*.ts *.tsx *.js *.jsx *.mjs' ;;
    rust)                          printf '%s' '*.rs' ;;
    java)                          printf '%s' '*.java' ;;
    kotlin)                        printf '%s' '*.kt' ;;
    ruby)                          printf '%s' '*.rb' ;;
    php)                           printf '%s' '*.php' ;;
    csharp|dotnet)                 printf '%s' '*.cs' ;;
    *)                             printf '%s' '' ;;
  esac
}

find_source_files() {
  local root="$1" globs="$2" g first=true
  local name_args=()
  [[ -d "$root" ]] || return 0
  [[ -n "$globs" ]] || return 0
  for g in $globs; do
    if [[ "$first" == "true" ]]; then
      name_args+=(-name "$g")
      first=false
    else
      name_args+=(-o -name "$g")
    fi
  done
  find "$root" \
    \( -path '*/vendor/*' -o -path '*/node_modules/*' -o -path '*/.venv/*' \
       -o -path '*/venv/*' -o -path '*/__pycache__/*' -o -path '*/site-packages/*' \
       -o -path '*/.git/*' -o -path '*/dist/*' -o -path '*/target/*' \) -prune -o \
    -type f \( "${name_args[@]}" \) -print 2>/dev/null || true
}

# Read the whole match set into a variable before testing it. Piping a producer into an
# early-exiting reader lets the reader close the pipe, and the resulting SIGPIPE fails the
# pipeline under the `set -o pipefail` inherited from _lib.sh even when the match succeeded.
grep_files() {
  local pattern_flag="$1" pattern="$2" files="$3"
  [[ -n "$files" ]] || return 1
  local hits
  hits="$(printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 grep -l "$pattern_flag" -- "$pattern" 2>/dev/null || true)"
  [[ -n "$hits" ]]
}

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
  local category="$1" status="$2" message="$3"
  GATE_FINDINGS+=("$(printf '{"category":"%s","status":"%s","message":"%s"}' \
    "$(json_escape "$category")" \
    "$(json_escape "$status")" \
    "$(json_escape "$message")")")
}

drift() { DRIFT=$((DRIFT + 1)); printf "  🔴 %s\n" "$*"; record_finding "${DRIFT_CATEGORY:-general}" "drift" "$*"; }
ok()    { printf "  ✅ %s\n" "$*"; record_finding "${DRIFT_CATEGORY:-general}" "pass" "$*"; }
gate_skip() {
  skip "$*"
  record_finding "${DRIFT_CATEGORY:-general}" "skip" "$*"
  SKIPPED=$((SKIPPED + 1))
  SKIPPED_DIMENSIONS+=("${DRIFT_CATEGORY:-general}")
}

write_gate_json() {
  [[ "$WRITE_JSON" == "true" ]] || return 0
  local status="$1" out="$JSON_OUT"
  [[ -n "$out" ]] || out="$PROJECT_ROOT/halo/state/gates/drift-check.json"
  [[ "$out" == /* ]] || out="$PROJECT_ROOT/$out"
  mkdir -p "$(dirname "$out")"
  {
    printf '{\n'
    printf '  "gate": "drift-check",\n'
    printf '  "status": "%s",\n' "$(json_escape "$status")"
    printf '  "spec_file": "%s",\n' "$(json_escape "${SPEC#$PROJECT_ROOT/}")"
    printf '  "language": "%s",\n' "$(json_escape "$PROJECT_LANG")"
    printf '  "metrics": {\n'
    printf '    "drift_count": %s,\n' "$DRIFT"
    printf '    "checks_run": %s,\n' "$(checks_run)"
    printf '    "checks_skipped": %s,\n' "$SKIPPED"
    printf '    "checked": {\n'
    printf '      "ddl": %s,\n' "$CHECKED_DDL"
    printf '      "routes": %s,\n' "$CHECKED_ROUTES"
    printf '      "error_codes": %s,\n' "$CHECKED_ERROR_CODES"
    printf '      "seed_sql": %s\n' "$CHECKED_SEED_SQL"
    printf '    },\n'
    printf '    "spec_tables": %s,\n' "${SPEC_TABLE_COUNT:-0}"
    printf '    "spec_routes": %s,\n' "${SPEC_ROUTE_COUNT:-0}"
    printf '    "spec_error_codes": %s\n' "${SPEC_CODE_COUNT:-0}"
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

echo "🔍 Drift Check: $(basename "$SPEC") ↔ code [$PROJECT_LANG]"
echo ""

# ══════════════════════════════════════════════════════
# 1. DDL drift (spec CREATE TABLE vs ORM model)
# ══════════════════════════════════════════════════════
echo "── DDL drift detection ──"
DRIFT_CATEGORY="ddl"

SPEC_TABLES=$({ grep -i 'CREATE TABLE' "$SPEC" || true; } | sed 's/.*`\([^`]*\)`.*/\1/' | sort)
SPEC_TABLE_COUNT=$(echo "$SPEC_TABLES" | grep -c . || true)

if [[ "$SPEC_TABLE_COUNT" -eq 0 ]]; then
  gate_skip "No DDL in spec (DDL drift NOT verified)"
else
  ORM=$(manifest_get ".drift.ddl.orm")
  MODEL_TAG=$(manifest_get ".drift.ddl.model_tag")
  MODEL_DIRS=$(manifest_list ".drift.ddl.model_dirs[]")

  case "${ORM:-none}" in
    gorm)
      MODEL_FILES=""
      for dir in $MODEL_DIRS; do
        if [[ -d "$PROJECT/$dir" ]]; then
          found=$(find "$PROJECT/$dir" -name '*.go' -not -name '*_test.go' 2>/dev/null || true)
          MODEL_FILES="$MODEL_FILES $found"
        fi
      done
      if [[ -z "$MODEL_FILES" ]]; then
        MODEL_FILES=$(find "$PROJECT" -name '*.go' -not -path '*/vendor/*' -not -name '*_test.go' -exec grep -l "${MODEL_TAG:-column:}" {} + 2>/dev/null || true)
      fi

      if [[ -z "$MODEL_FILES" ]]; then
        gate_skip "No GORM model files found (DDL drift NOT verified)"
      else
        mark_checked
        ok "Spec DDL tables: $SPEC_TABLE_COUNT"
        while IFS= read -r table; do
          SPEC_COLS=$(awk "/CREATE TABLE \`$table\`/,/\) ENGINE/" "$SPEC" | grep -v -iE '^\s*(PRIMARY|UNIQUE|KEY|INDEX|CONSTRAINT|\))' | grep -oE '`[a-z_]+`' | sed 's/`//g' | grep -v "^$table$" | sort | uniq)
          MODEL_COLS=""
          for mf in $MODEL_FILES; do
            cols=$(grep -oE "${MODEL_TAG}[a-z_]+" "$mf" 2>/dev/null | sed "s/${MODEL_TAG}//" | sort)
            MODEL_COLS="$MODEL_COLS $cols"
          done
          MODEL_COLS=$(echo "$MODEL_COLS" | tr ' ' '\n' | grep -v '^$' | sort | uniq)

          if [[ -z "$MODEL_COLS" ]]; then
            gate_skip "Table '$table': not found in model"
          else
            SPEC_ONLY=$(comm -23 <(echo "$SPEC_COLS") <(echo "$MODEL_COLS") 2>/dev/null || true)
            CODE_ONLY=$(comm -13 <(echo "$SPEC_COLS") <(echo "$MODEL_COLS") 2>/dev/null || true)
            if [[ -n "$SPEC_ONLY" ]]; then drift "Table '$table' — in spec but not code: $(echo "$SPEC_ONLY" | tr '\n' ', ')"; fi
            if [[ -n "$CODE_ONLY" ]]; then drift "Table '$table' — in code but not spec: $(echo "$CODE_ONLY" | tr '\n' ', ')"; fi
            if [[ -z "$SPEC_ONLY" ]] && [[ -z "$CODE_ONLY" ]]; then ok "Table '$table' columns match"; fi
          fi
        done <<< "$SPEC_TABLES"
      fi
      ;;
    sequelize|sqlalchemy|prisma)
      gate_skip "ORM '$ORM' DDL drift detection: not yet implemented (DDL drift NOT verified)"
      ;;
    none|*)
      gate_skip "No ORM configured (DDL drift NOT verified)"
      ;;
  esac
fi

echo ""

# ══════════════════════════════════════════════════════
# 2. Route drift (spec API table vs code route registration)
# ══════════════════════════════════════════════════════
echo "── Route drift detection ──"
DRIFT_CATEGORY="routes"

# Locate the method and path columns by header name. Column position is otherwise an
# undeclared contract: a spec that writes `| 端点 | 方法 | 说明 |` extracts nothing, or
# worse, extracts the description column as the path. Falls back to the historical
# 3rd/4th awk field when no recognisable header row is present.
SPEC_ROUTES=$(awk -F'|' '
  function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
  function clean(s) { gsub(/[`*]/, "", s); return trim(s) }
  function is_method(s) { return toupper(s) ~ /^(GET|POST|PUT|DELETE|PATCH)$/ }
  /^[[:space:]]*\|/ {
    if ($0 ~ /^[[:space:]]*\|[[:space:]]*:?-{2,}/) next
    hm = 0; hp = 0
    for (i = 2; i <= NF; i++) {
      # Match with a regex, not `==`: awk string equality on multibyte cells is unreliable
      # (BSD awk reports every non-empty CJK string as equal to every other one).
      c = clean($i)
      if (c ~ /^([Mm]ethod|METHOD|HTTP ?方法|方法)$/) hm = i
      else if (c ~ /^([Pp]ath|PATH|URL|[Ee]ndpoint|路径|端点)$/) hp = i
    }
    if (hm > 0 && hp > 0) { mi = hm; pi = hp; next }
    if (mi > 0 && pi > 0) { m = clean($mi); p = clean($pi) }
    else { m = clean($3); p = clean($4) }
    if (is_method(m) && p ~ /^\//) print toupper(m) " " p
    next
  }
  { mi = 0; pi = 0 }
' "$SPEC" | sort -u)
SPEC_ROUTE_COUNT=$(echo "$SPEC_ROUTES" | grep -c . || true)

# Normalise path parameters so `/items/{id}`, `/items/:id`, and `/items/<id>` compare equal.
normalize_path() {
  printf '%s' "$1" | sed -E -e 's/\{[^}]*\}/{}/g' -e 's/<[^>]*>/{}/g' -e 's#:[A-Za-z_][A-Za-z0-9_]*#{}#g' -e 's#/+$##'
}

# Build "METHOD /normalised/path" lines from decorator/registration matches of the form
# `@router.get("/x` or `router.get('/x`, expanded by every router prefix in the project.
collect_code_routes() {
  local raw="$1" prefixes="$2" line method path prefix
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    method="$(printf '%s' "$line" | sed -E 's/.*\.([A-Za-z]+)\(.*/\1/' | tr '[:lower:]' '[:upper:]')"
    path="$(printf '%s' "$line" | sed -E 's/.*[("'"'"'`]([^"'"'"'`]*)$/\1/')"
    [[ "$path" == /* ]] || continue
    printf '%s %s\n' "$method" "$(normalize_path "$path")"
    while IFS= read -r prefix; do
      [[ -n "$prefix" ]] || continue
      printf '%s %s\n' "$method" "$(normalize_path "${prefix}${path}")"
    done <<< "$prefixes"
  done <<< "$raw"
}

route_registered() {
  local method="$1" path="$2" endpoint line
  grep -qxF -- "$method $(normalize_path "$path")" <<< "$CODE_ROUTES" && return 0
  # Same leniency as the Go branch: a trailing-segment match still counts as registered,
  # so an unmodelled prefix causes a missed detection rather than a false failure.
  endpoint="$(normalize_path "/$(basename "$path")")"
  while IFS= read -r line; do
    [[ "$line" == "$method "* ]] || continue
    [[ "${line#"$method "}" == *"$endpoint" ]] && return 0
  done <<< "$CODE_ROUTES"
  return 1
}

if [[ "$SPEC_ROUTE_COUNT" -eq 0 ]]; then
  gate_skip "No routes in spec API table (route drift NOT verified)"
else
  FRAMEWORK=$(manifest_get ".drift.routes.framework")
  ROUTE_GLOBS=$(manifest_get ".drift.routes.file_glob")

  case "${FRAMEWORK:-none}" in
    gin|echo|chi)
      ROUTER_FILES=$(find "$PROJECT" -name '*.go' -not -path '*/vendor/*' -exec grep -lE '\.(GET|POST|PUT|DELETE|PATCH)\(' {} + 2>/dev/null || true)

      if [[ -z "$ROUTER_FILES" ]]; then
        gate_skip "No route registration code found (route drift NOT verified)"
      else
        mark_checked
        ok "Spec routes: $SPEC_ROUTE_COUNT"
        while IFS= read -r spec_route; do
          method=$(echo "$spec_route" | awk '{print $1}')
          path=$(echo "$spec_route" | awk '{print $2}')
          endpoint=$(basename "$path")
          if echo "$ROUTER_FILES" | xargs grep -q "$method.*$endpoint" 2>/dev/null; then
            ok "Route: $method $path"
          else
            drift "Spec route not registered in code: $method $path"
          fi
        done <<< "$SPEC_ROUTES"
      fi
      ;;
    fastapi|express)
      if [[ "$FRAMEWORK" == "fastapi" ]]; then
        ROUTE_FILES=$(find_source_files "$PROJECT" "${ROUTE_GLOBS:-*.py}")
        DECORATOR_PAT='@[A-Za-z_][A-Za-z0-9_]*\.(get|post|put|patch|delete)\([[:space:]]*["'"'"'][^"'"'"']*'
        PREFIX_PAT='APIRouter\([^)]*prefix[[:space:]]*=[[:space:]]*["'"'"'][^"'"'"']*'
      else
        ROUTE_FILES=$(find_source_files "$PROJECT" "${ROUTE_GLOBS:-*.ts *.tsx *.js *.jsx *.mjs}")
        DECORATOR_PAT='\b[A-Za-z_][A-Za-z0-9_]*\.(get|post|put|patch|delete)\([[:space:]]*["'"'"'`][^"'"'"'`]*'
        PREFIX_PAT='\.use\([[:space:]]*["'"'"'`]/[^"'"'"'`]*'
      fi

      if [[ -z "$ROUTE_FILES" ]]; then
        gate_skip "No $FRAMEWORK source files found under $PROJECT (route drift NOT verified)"
      else
        RAW_ROUTES="$(printf '%s\n' "$ROUTE_FILES" | tr '\n' '\0' | xargs -0 grep -hoE "$DECORATOR_PAT" 2>/dev/null || true)"
        RAW_PREFIXES="$(printf '%s\n' "$ROUTE_FILES" | tr '\n' '\0' | xargs -0 grep -hoE "$PREFIX_PAT" 2>/dev/null | sed -E 's/.*["'"'"'`]//' | sort -u || true)"
        CODE_ROUTES="$(collect_code_routes "$RAW_ROUTES" "$RAW_PREFIXES" | sort -u)"

        if [[ -z "$CODE_ROUTES" ]]; then
          gate_skip "No $FRAMEWORK route registrations found (route drift NOT verified)"
        else
          mark_checked
          ok "Spec routes: $SPEC_ROUTE_COUNT"
          while IFS= read -r spec_route; do
            method=$(echo "$spec_route" | awk '{print $1}')
            path=$(echo "$spec_route" | awk '{print $2}')
            if route_registered "$method" "$path"; then
              ok "Route: $method $path"
            else
              drift "Spec route not registered in code: $method $path"
            fi
          done <<< "$SPEC_ROUTES"
        fi
      fi
      ;;
    none)
      gate_skip "No framework configured (route drift NOT verified)"
      ;;
    *)
      gate_skip "Framework '$FRAMEWORK' route drift detection: not yet implemented (route drift NOT verified)"
      ;;
  esac
fi

echo ""

# ══════════════════════════════════════════════════════
# 3. Error code drift
# ══════════════════════════════════════════════════════
echo "── Error code drift detection ──"
DRIFT_CATEGORY="error_codes"

# Error codes are read from the first column of the error code table, located by its
# header. Both numeric codes (40001) and upper snake-case enums (REFERENCE_IN_USE) count —
# the default spec template ships `| {ERROR_CODE} | 触发条件 | ... |`, so a numeric-only
# reader finds nothing in a spec written from the framework's own template.
# When no error code table is present, fall back to the historical whole-file numeric scan.
extract_spec_codes() {
  awk -F'|' '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function clean(s) { gsub(/[`*]/, "", s); return trim(s) }
    /^[[:space:]]*\|/ {
      if ($0 ~ /^[[:space:]]*\|[[:space:]]*:?-{2,}/) next
      c = clean($2)
      if (c ~ /^([Ee]rror ?[Cc]odes?|ERROR ?CODES?|错误码|错误代码|业务错误码)$/) { in_table = 1; next }
      if (in_table && c != "" && (c ~ /^[0-9]+$/ || c ~ /^[A-Z][A-Z0-9_]{2,}$/)) print c
      next
    }
    { in_table = 0 }
  ' "$1"
}

SPEC_CODES=$(extract_spec_codes "$SPEC" | { grep -v '^0$' || true; } | sort -u)
if [[ -z "$SPEC_CODES" ]]; then
  SPEC_CODES=$({ grep -E '^\| *[0-9]+ *\|' "$SPEC" || true; } | \
    awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/, "", $2); if ($2 ~ /^[0-9]+$/) print $2}' | \
    { grep -v '^0$' || true; } | sort -n | uniq)
fi
SPEC_CODE_COUNT=$(echo "$SPEC_CODES" | grep -c . || true)

if [[ "$SPEC_CODE_COUNT" -eq 0 ]]; then
  gate_skip "No business error codes in spec (error code drift NOT verified)"
else
  CONST_PAT=$(manifest_get ".drift.error_codes.const_pattern")
  CODE_GLOBS=$(manifest_get ".drift.error_codes.file_glob")
  [[ -n "$CODE_GLOBS" ]] || CODE_GLOBS="$(lang_source_globs "$PROJECT_LANG")"
  CODE_FILES=$(find_source_files "$PROJECT" "$CODE_GLOBS")

  if [[ -z "$CODE_GLOBS" ]]; then
    gate_skip "Error code drift: no source file mapping for language '$PROJECT_LANG' — set drift.error_codes.file_glob (NOT verified)"
  elif [[ -z "$CODE_FILES" ]]; then
    gate_skip "No source files matching '$CODE_GLOBS' under $PROJECT (error code drift NOT verified)"
  else
    # Numeric codes still go through const_pattern; string enums are matched as literals,
    # because their definition syntax differs too much across languages to model as one regex.
    NUMERIC_CONSTS=$(printf '%s\n' "$CODE_FILES" | tr '\n' '\0' | \
      xargs -0 grep -ohE "${CONST_PAT:-(Code|Err)[A-Za-z]+ *= *[0-9]+}" 2>/dev/null | \
      grep -oE '[0-9]+' | sort -n | uniq || true)

    CHECKED_ANY=false
    UNVERIFIED_NUMERIC=false
    while IFS= read -r code; do
      [[ -n "$code" ]] || continue
      if [[ "$code" =~ ^[0-9]+$ ]]; then
        if [[ -z "$NUMERIC_CONSTS" ]]; then
          UNVERIFIED_NUMERIC=true
          continue
        fi
        CHECKED_ANY=true
        if grep -qxF -- "$code" <<< "$NUMERIC_CONSTS"; then
          ok "Error code $code"
        else
          drift "Spec error code $code not defined in code"
        fi
      else
        CHECKED_ANY=true
        if grep_files "-wF" "$code" "$CODE_FILES"; then
          ok "Error code $code"
        else
          drift "Spec error code $code not defined in code"
        fi
      fi
    done <<< "$SPEC_CODES"

    if [[ "$CHECKED_ANY" == "true" ]]; then
      mark_checked
      ok "Spec error codes: $SPEC_CODE_COUNT"
    fi
    if [[ "$UNVERIFIED_NUMERIC" == "true" ]]; then
      gate_skip "No numeric error code constants matched drift.error_codes.const_pattern (numeric codes NOT verified)"
    fi
  fi
fi

echo ""

# ══════════════════════════════════════════════════════
# 4. Seed SQL drift (spec vs fixtures)
# ══════════════════════════════════════════════════════
echo "── Seed SQL drift detection ──"
DRIFT_CATEGORY="seed_sql"

FIXTURE_FILE="$PROJECT_ROOT/halo/fixtures/seed.sql"
if [[ -f "$FIXTURE_FILE" ]]; then
  SPEC_SEED=$(awk '/^```sql$/,/^```$/' "$SPEC" | tail -n +2 | grep -i 'INSERT' || true)
  FILE_SEED=$(grep -i 'INSERT' "$FIXTURE_FILE" || true)

    if [[ -z "$SPEC_SEED" ]]; then
    gate_skip "No Seed SQL in spec (seed drift NOT verified)"
  elif [[ "$SPEC_SEED" == "$FILE_SEED" ]]; then
    mark_checked
    ok "Seed SQL consistent"
  else
    mark_checked
    drift "fixtures/seed.sql differs from spec Seed SQL"
  fi
else
  gate_skip "fixtures/seed.sql not found (seed drift NOT verified)"
fi

# ── Plugin drift detection ──
PLUGIN_COUNT=$(yq '.drift.plugins | length // 0' "$MANIFEST" 2>/dev/null || echo 0)
if [[ "$PLUGIN_COUNT" -gt 0 ]]; then
  echo ""
    echo "── Plugin drift detection ──"
  for i in $(seq 0 $((PLUGIN_COUNT - 1))); do
    DRIFT_CATEGORY="plugin"
    plugin_name=$(yq -r ".drift.plugins[$i].name" "$MANIFEST")
    plugin_run=$(yq -r ".drift.plugins[$i].run" "$MANIFEST")
    [[ -z "$plugin_name" || "$plugin_name" == "null" ]] && continue
    [[ -z "$plugin_run" || "$plugin_run" == "null" ]] && continue

    plugin_run="${plugin_run//\$\{SPEC_FILE\}/$SPEC}"
    plugin_run="${plugin_run//\$\{PROJECT_ROOT\}/$PROJECT_ROOT}"

    printf "  🔌 %s: %s\n" "$plugin_name" "$plugin_run"
    if bash -c "$plugin_run" 2>&1 | sed 's/^/    /'; then
      ok "$plugin_name: no drift"
    else
      drift "$plugin_name: drift detected"
    fi
  done
fi

echo ""
echo "══════════════════════════════════"

RUN_COUNT="$(checks_run)"

if [[ $DRIFT -gt 0 ]]; then
  echo "📊 Drift Check: 🔴 $DRIFT drifts detected in $RUN_COUNT verified dimension(s)"
  echo "❌ FAIL — update spec or fix code to resolve drift"
  write_gate_json "fail"
  exit 1
fi

if [[ $SKIPPED -gt 0 ]]; then
  echo "📊 Drift Check: no drift in $RUN_COUNT verified dimension(s) · $SKIPPED NOT verified"
  printf "   NOT verified: %s\n" "$(printf '%s\n' "${SKIPPED_DIMENSIONS[@]}" | sort -u | paste -sd' ' -)"
  echo "   A skipped dimension was not compared. Do not read this as contract alignment."
else
  echo "📊 Drift Check: no drift in $RUN_COUNT verified dimension(s)"
fi
echo "✅ PASS"
write_gate_json "pass"
exit 0

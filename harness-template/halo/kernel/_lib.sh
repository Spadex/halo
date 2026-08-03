#!/usr/bin/env bash
# _lib.sh — Halo shared library
# Sourced by all kernel scripts; not executed directly.
#
# Provides:
#   - Project path resolution (KERNEL_DIR / PROJECT_ROOT / MANIFEST)
#   - Manifest YAML queries (via yq)
#   - Layer enable/disable detection (layer_enabled)
#   - Unified output formatting (pass/fail/warn/skip)
#   - Command execution (run_cmd)

set -euo pipefail

# ── Locate project root and manifest ──
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_find_project_root() {
  local dir="$_LIB_DIR"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/manifest.yaml" ]]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  echo ""
}

_SH_DIR="$(_find_project_root)"
if [[ -z "$_SH_DIR" ]]; then
  _SH_DIR="$(cd "$_LIB_DIR/.." && pwd)"
fi

PROJECT_ROOT="$(cd "$_SH_DIR/.." && pwd)"
MANIFEST="$_SH_DIR/manifest.yaml"
KERNEL_DIR="$_SH_DIR/kernel"

[[ -f "$MANIFEST" ]] || { echo "manifest.yaml not found: $MANIFEST"; exit 1; }

# ── yq check ──
if ! command -v yq &>/dev/null; then
  echo "Missing required tool: yq"
  echo "  Install: brew install yq  |  apt install yq  |  go install github.com/mikefarah/yq/v4@latest"
  exit 1
fi

# ══════════════════════════════════
# Layer management
# ══════════════════════════════════

layer_enabled() {
  local layer="$1"
  local manifest_val
  manifest_val=$(yq -r ".kernel.layers.${layer} // \"auto\"" "$MANIFEST" 2>/dev/null || echo "auto")

  case "$manifest_val" in
    true)  return 0 ;;
    false) return 1 ;;
    auto|"")
      [[ -d "$KERNEL_DIR/$layer" ]] && return 0 || return 1
      ;;
  esac
}

require_layer() {
  local layer="$1"
  if ! layer_enabled "$layer"; then
    echo "Layer '$layer' is not enabled. Set kernel.layers.$layer: true in manifest.yaml"
    exit 1
  fi
}

# ══════════════════════════════════
# Counters + output helpers
# ══════════════════════════════════

_PASS=0; _FAIL=0; _WARN=0; _SKIP=0

pass() { _PASS=$((_PASS + 1)); printf "  ✅ %s\n" "$*"; }
fail() { _FAIL=$((_FAIL + 1)); printf "  ❌ %s\n" "$*"; }
warn() { _WARN=$((_WARN + 1)); printf "  ⚠️  %s\n" "$*"; }
skip() { _SKIP=$((_SKIP + 1)); printf "  ⏭️  %s\n" "$*"; }

# ══════════════════════════════════
# YAML queries (yq wrapper)
# ══════════════════════════════════

manifest_get() {
  local expr="$1"
  local result
  result=$(yq -r "$expr // \"\"" "$MANIFEST")
  [[ "$result" != "null" ]] && echo "$result" || echo ""
}

manifest_get_cmd() {
  local key="$1"
  [[ "$key" != .* ]] && key=".$key"
  manifest_get "$key"
}

manifest_list() {
  local expr="$1"
  yq -r "$expr // empty" "$MANIFEST" 2>/dev/null || true
}

manifest_select() {
  local array_path="$1" name="$2" field="$3"
  yq -r "${array_path}[] | select(.name == \"${name}\") | .${field} // \"\"" "$MANIFEST" 2>/dev/null || true
}

get_language() {
  manifest_get ".project.language"
}

# ══════════════════════════════════
# Command execution
# ══════════════════════════════════

# Security model: manifest.yaml is trusted project configuration (equivalent to source code).
# run_cmd executes commands in a subprocess for output capture, not for sandboxing.
run_cmd() {
  local cmd="$1"
  bash -c "$cmd"
}

# ══════════════════════════════════
# Spec discovery
# ══════════════════════════════════

if [[ ! -f "$_LIB_DIR/spec-select.sh" ]]; then
  echo "Missing kernel file: $_LIB_DIR/spec-select.sh"
  echo "  Upgrade the project kernel: bash install.sh --upgrade"
  exit 1
fi
# shellcheck source=./spec-select.sh
source "$_LIB_DIR/spec-select.sh"

# Emits "<source>|<detail>|<path>" so callers can record HOW the spec was chosen, not
# just which one. Provenance matters because an auto-discovered spec is a guess: an
# eval run that silently verified the wrong spec is indistinguishable from a real pass
# unless the run records that nobody named the spec.
#   source : explicit | manifest-active | auto
#   return : 0 resolved · 1 nothing to resolve · 2 ambiguous auto-discovery
_resolve_spec() {
  local spec_dir
  spec_dir=$(manifest_get ".specs.dir")
  spec_dir="${spec_dir:-halo/specs}"
  local spec_file="${SPEC_FILE:-}"
  local active_spec
  active_spec=$(manifest_get ".specs.active")

  if [[ -n "$spec_file" ]] && [[ -f "$spec_file" ]]; then
    echo "explicit|caller-supplied|$spec_file"
    return 0
  fi

  if [[ -n "$active_spec" ]]; then
    if [[ -f "$PROJECT_ROOT/$active_spec" ]]; then
      echo "manifest-active|specs.active=$active_spec|$PROJECT_ROOT/$active_spec"
      return 0
    fi
    if [[ -f "$PROJECT_ROOT/$spec_dir/$active_spec/spec.md" ]]; then
      echo "manifest-active|specs.active=$active_spec|$PROJECT_ROOT/$spec_dir/$active_spec/spec.md"
      return 0
    fi
  fi

  local selected rc=0
  selected="$(spec_select "$PROJECT_ROOT/$spec_dir")" || rc=$?
  if [[ "$rc" -eq 0 && -n "$selected" ]]; then
    echo "auto|${SPEC_SELECT_DETAIL}|$selected"
    return 0
  fi
  [[ "$rc" -eq 2 ]] && return 2
  return 1
}

find_spec_with_source() {
  _resolve_spec
}

find_spec() {
  local resolved rc=0
  resolved="$(_resolve_spec)" || rc=$?
  [[ "$rc" -eq 0 ]] || return "$rc"
  resolved="${resolved#*|}"
  printf '%s\n' "${resolved#*|}"
}

# ══════════════════════════════════
# AC declaration source
# ══════════════════════════════════

# The single authoritative source of "which ACs does this spec declare": the first
# cell of each AC table row. Everything else that mentions AC-N — prose, a
# cross-reference to another spec's AC ("see layout-furnish AC-14"), or a reference
# inside another row's cell — is a MENTION, not a declaration, and must never drive
# a gate decision. Emits one AC id per line in file order, unsorted and not deduped;
# callers sort/uniq as their own check needs (spec-lint needs the duplicates kept).
spec_declared_acs() {
  local spec="${1:-}"
  [[ -n "$spec" && -f "$spec" ]] || return 0
  { grep -E '^\| *AC-[0-9]+ *\|' "$spec" || true; } | sed -E 's/^\| *(AC-[0-9]+).*/\1/'
}

# The ACs a piece of plan text actually claims: every AC-N token in it, narrowed to
# the ACs the spec declares. Plan prose legitimately mentions another spec's AC
# ("contrast with upstream-spec AC-14"); treating that as a claim of this spec makes
# gates demand evidence, planning, or coverage for an AC this spec does not own.
# When no AC table is available (no spec.md, or a spec that does not use the table
# shape) there is nothing to narrow against, so fall back to the raw token set
# rather than silently emptying the gate.
narrow_acs_to_declared() {
  local text="$1" spec="${2:-}" declared mentioned
  mentioned="$({ grep -oE 'AC-[0-9]+' <<< "$text" || true; } | sort -u)"
  [[ -n "$mentioned" ]] || return 0
  declared="$(spec_declared_acs "$spec" | sort -u)"
  [[ -n "$declared" ]] || { printf '%s\n' "$mentioned"; return 0; }
  grep -xF -f <(printf '%s\n' "$declared") <<< "$mentioned" || true
}

# ══════════════════════════════════
# CLI help
# ══════════════════════════════════

cli_help() {
  local name="$1" desc="$2"
  shift 2
  echo "halo $name — $desc"
  echo ""
  echo "Usage:"
  for line in "$@"; do
    echo "  $line"
  done
  echo ""
  echo "Exit codes:"
  echo "  0  Success"
  echo "  1  Failure"
  exit 0
}

print_summary() {
  local label="${1:-Summary}"
  echo ""
  echo "══════════════════════════════════"
  echo "📊 $label: ✅ $_PASS  ❌ $_FAIL  ⚠️  $_WARN  ⏭️  $_SKIP"

  if [[ $_FAIL -gt 0 ]]; then
    echo "❌ FAIL"
    return 1
  else
    echo "✅ PASS"
    return 0
  fi
}

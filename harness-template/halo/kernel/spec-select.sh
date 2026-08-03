#!/usr/bin/env bash
# spec-select.sh — Decide which spec is the current work object.
#
# Sourceable (defines spec_select) and executable (prints the selection).
#
# Deliberately independent of _lib.sh and yq: _lib.sh exits when yq or manifest.yaml
# is missing, and prismspec/bin/guide.sh must keep resolving specs in a standalone
# host that has neither. Keep this file dependency-free.
#
# Why not file mtime: mtime is a filesystem accident. git merge / checkout / rebase /
# stash pop rewrite it on every file they check out, so `ls -t` flips the "current
# spec" after any git operation — including the merge that normally precedes final
# verification. The observed result was a structurally complete eval run whose
# spec_file, spec_hash, and AC coverage all belonged to an unrelated spec, with no
# warning printed anywhere. Rank on front matter instead: `status` and `updated_at`
# travel with the file content and survive checkout.

SPEC_SELECT_DETAIL=""

# Same awk shape as the per-script frontmatter_value copies (spec-status.sh:47,
# learn-draft.sh:58, …). Inlined rather than shared so this file stays dependency-free.
spec_select_frontmatter_value() {
  local key="$1" file="$2"
  [[ -f "$file" ]] || return 0
  awk -v key="$key" '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { exit }
    in_fm {
      idx = index($0, ":")
      if (idx == 0) next
      name = substr($0, 1, idx - 1)
      gsub(/^[ \t]+|[ \t]+$/, "", name)
      if (name != key) next
      value = substr($0, idx + 1)
      gsub(/^[ \t]+|[ \t]+$/, "", value)
      gsub(/^["'\''`]+|["'\''`]+$/, "", value)
      print value
      exit
    }
  ' "$file"
}

spec_select_candidates() {
  local root="$1"
  find "$root" -name 'spec.md' -type f -not -path '*/.locks/*' 2>/dev/null | sort
}

# spec_select <specs-root>
#   stdout : the selected spec.md path
#   stderr : the selection basis, plus the candidates it beat
#   return : 0 selected · 1 no candidate · 2 ambiguous (caller must demand an explicit spec)
#   sets   : SPEC_SELECT_DETAIL — machine-ish, single-line basis of the selection
spec_select() {
  local root="${1:-}"
  SPEC_SELECT_DETAIL=""
  [[ -n "$root" && -d "$root" ]] || return 1

  local files
  files="$(spec_select_candidates "$root")"
  [[ -n "$files" ]] || return 1

  local ranked="" file status updated rank has_updated=false
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    status="$(spec_select_frontmatter_value status "$file")"
    updated="$(spec_select_frontmatter_value updated_at "$file")"
    if [[ -n "$updated" ]]; then
      has_updated=true
    else
      # A spec whose front matter carries no updated_at sinks to the bottom. Unmaintained
      # metadata is the weakest claim to being the current work object, not the strongest.
      updated="0000-00-00T00:00:00Z"
    fi
    # `verified` is the terminal status, so any in-flight spec outranks it. When every
    # candidate is verified this key is uniform and updated_at decides on its own.
    if [[ "$status" == "verified" ]]; then rank=1; else rank=0; fi
    ranked+="${rank}|${updated}|${status:-unset}|${file}"$'\n'
  done <<< "$files"

  if [[ "$has_updated" == "false" ]]; then
    # No semantic signal to rank on at all. Fall back to the historical mtime order —
    # strictly no worse than the previous behavior — but say so, because this is the
    # one path that can still be flipped by a git checkout.
    local latest
    latest="$(printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 ls -t 2>/dev/null | head -1)"
    [[ -n "$latest" ]] || return 1
    SPEC_SELECT_DETAIL="mtime-fallback (no spec declares updated_at)"
    printf '⚠️  Spec auto-discovery fell back to file mtime: no spec declares updated_at.\n' >&2
    printf '    Selected %s — a git checkout can change this. Pass the spec explicitly to pin it.\n' "$latest" >&2
    printf '%s\n' "$latest"
    return 0
  fi

  local sorted
  sorted="$(printf '%s' "$ranked" | sed '/^$/d' | sort -t'|' -k1,1n -k2,2r -k4,4)"

  local top top_rank top_updated tied
  top="$(printf '%s\n' "$sorted" | head -1)"
  top_rank="${top%%|*}"
  top_updated="$(printf '%s' "$top" | cut -d'|' -f2)"
  tied="$(printf '%s\n' "$sorted" | awk -F'|' -v r="$top_rank" -v u="$top_updated" '$1 == r && $2 == u { print $4 }')"

  if [[ "$(printf '%s\n' "$tied" | grep -c .)" -gt 1 ]]; then
    # Genuinely undecidable: same lifecycle class, same semantic timestamp. Guessing
    # here is the coin flip this whole file exists to remove, so refuse instead.
    SPEC_SELECT_DETAIL="ambiguous (updated_at=$top_updated)"
    printf '❌ Spec auto-discovery is ambiguous — these specs tie on status and updated_at:\n' >&2
    printf '%s\n' "$tied" | sed 's/^/    /' >&2
    printf '   Pass the spec explicitly (--spec=<path>) or set specs.active in manifest.yaml.\n' >&2
    return 2
  fi

  local selected selected_status
  selected="$(printf '%s' "$top" | cut -d'|' -f4)"
  selected_status="$(printf '%s' "$top" | cut -d'|' -f3)"
  SPEC_SELECT_DETAIL="status=${selected_status} updated_at=${top_updated}"

  printf 'ℹ️  Spec auto-discovery selected %s (%s)\n' "$selected" "$SPEC_SELECT_DETAIL" >&2
  local other
  while IFS= read -r other; do
    [[ -n "$other" ]] || continue
    [[ "$other" == "$top" ]] && continue
    printf '    not selected: %s (status=%s updated_at=%s)\n' \
      "$(printf '%s' "$other" | cut -d'|' -f4)" \
      "$(printf '%s' "$other" | cut -d'|' -f3)" \
      "$(printf '%s' "$other" | cut -d'|' -f2)" >&2
  done <<< "$sorted"

  printf '%s\n' "$selected"
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -uo pipefail
  spec_select "${1:-}"
  exit $?
fi

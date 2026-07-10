#!/usr/bin/env bash
# spec-lock.sh — Multi-agent spec lock management
# Prevents multiple agents from concurrently writing the same spec
# Exit codes: 0=acquire/release success, 1=lock conflict
source "$(dirname "$0")/../../_lib.sh"

for arg in "$@"; do
  [[ "$arg" == "--help" || "$arg" == "-h" ]] && cli_help "delivery gate spec-lock" "Spec concurrent write lock management" \
    "spec-lock.sh acquire <spec-file>    Acquire write lock" \
    "spec-lock.sh release <spec-file>    Release write lock" \
    "spec-lock.sh status  <spec-file>    Check lock status" \
    "spec-lock.sh clean                  Clean expired locks (>1h)"
done

ACTION="${1:?Usage: spec-lock.sh <acquire|release|status|clean> [spec-file]}"
SPEC_FILE="${2:-}"

LOCK_DIR="$PROJECT_ROOT/lattice/specs/.locks"
mkdir -p "$LOCK_DIR"

LOCK_TTL=3600  # 1 hour

_lock_path() {
  local spec="$1"
  local bname
  bname=$(basename "$spec" .md)
  echo "$LOCK_DIR/${bname}.lock"
}

_agent_id() {
  echo "${HOSTNAME:-$(hostname)}:$$:$(date +%s)"
}

case "$ACTION" in
  acquire)
    [[ -z "$SPEC_FILE" ]] && { echo "Spec file required"; exit 1; }
    LOCK_FILE=$(_lock_path "$SPEC_FILE")

    if [[ -f "$LOCK_FILE" ]]; then
      LOCK_TIME=$(head -1 "$LOCK_FILE" | cut -d'|' -f3)
      NOW=$(date +%s)
      if [[ -n "$LOCK_TIME" ]] && [[ $((NOW - LOCK_TIME)) -lt $LOCK_TTL ]]; then
        LOCK_OWNER=$(head -1 "$LOCK_FILE" | cut -d'|' -f1,2)
        echo "🔒 Spec is locked"
        echo "   Owner: $LOCK_OWNER"
        echo "   Locked at: $(date -r "$LOCK_TIME" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -d "@$LOCK_TIME" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$LOCK_TIME")"
        echo "   Auto-expires after: ${LOCK_TTL}s"
        exit 1
      fi
      echo "⚠️  Overriding expired lock"
    fi

    _agent_id > "$LOCK_FILE"
    echo "🔒 Locked: $(basename "$SPEC_FILE")"
    exit 0
    ;;

  release)
    [[ -z "$SPEC_FILE" ]] && { echo "Spec file required"; exit 1; }
    LOCK_FILE=$(_lock_path "$SPEC_FILE")
    if [[ -f "$LOCK_FILE" ]]; then
      rm -f "$LOCK_FILE"
      echo "🔓 Released: $(basename "$SPEC_FILE")"
    else
      echo "⏭️  No lock to release"
    fi
    exit 0
    ;;

  status)
    [[ -z "$SPEC_FILE" ]] && { echo "Spec file required"; exit 1; }
    LOCK_FILE=$(_lock_path "$SPEC_FILE")
    if [[ -f "$LOCK_FILE" ]]; then
      echo "🔒 Locked"
      cat "$LOCK_FILE"
    else
      echo "🔓 Not locked"
    fi
    exit 0
    ;;

  clean)
    echo "🧹 Cleaning expired locks..."
    CLEANED=0
    NOW=$(date +%s)
    for lock in "$LOCK_DIR"/*.lock; do
      [[ -f "$lock" ]] || continue
      LOCK_TIME=$(head -1 "$lock" | cut -d'|' -f3)
      if [[ -n "$LOCK_TIME" ]] && [[ $((NOW - LOCK_TIME)) -ge $LOCK_TTL ]]; then
        rm -f "$lock"
        echo "  🗑️  $(basename "$lock")"
        ((CLEANED++)) || true
      fi
    done
    echo "Done: $CLEANED expired locks cleaned"
    exit 0
    ;;

  *)
    echo "Unknown action: $ACTION"
    echo "Usage: spec-lock.sh <acquire|release|status|clean> [spec-file]"
    exit 1
    ;;
esac

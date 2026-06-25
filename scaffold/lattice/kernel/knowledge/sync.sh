#!/usr/bin/env bash
# sync.sh — Central knowledge base sync
# Pull/push knowledge from/to a remote repository
#
# Usage:
#   sync.sh pull          — Pull knowledge from central repo
#   sync.sh push          — Push local knowledge to central repo
#   sync.sh status        — View sync status
#
# Config: manifest.yaml knowledge.central

source "$(dirname "$0")/../_lib.sh"

KNOWLEDGE_DIR="$PROJECT_ROOT/$(manifest_get '.knowledge.local_dir')"
KNOWLEDGE_DIR="${KNOWLEDGE_DIR:-$PROJECT_ROOT/lattice/knowledge}"
REMOTE_DIR="$KNOWLEDGE_DIR/.remote"

CENTRAL_REPO=$(manifest_get '.knowledge.central.repo')
SYNC_MODE=$(manifest_get '.knowledge.central.mode')
SYNC_MODE="${SYNC_MODE:-read-only}"
CONFLICT_POLICY=$(manifest_get '.knowledge.central.conflict')
CONFLICT_POLICY="${CONFLICT_POLICY:-prefer-local}"

ACTION="${1:-status}"

if [[ -z "$CENTRAL_REPO" ]]; then
  echo "⚠️  Central knowledge repo not configured"
  echo "   Add to manifest.yaml:"
  echo "   knowledge:"
  echo "     central:"
  echo "       repo: https://github.com/your-org/knowledge.git"
  exit 0
fi

case "$ACTION" in
  pull)
    echo "📥 Pulling from central knowledge repo..."
    echo "   Repo: $CENTRAL_REPO"

    if [[ -d "$REMOTE_DIR/.git" ]]; then
      cd "$REMOTE_DIR" && git pull --quiet 2>/dev/null || {
        echo "⚠️  Pull failed, using local cache"
        exit 0
      }
    else
      mkdir -p "$REMOTE_DIR"
      git clone --depth=1 --quiet "$CENTRAL_REPO" "$REMOTE_DIR" 2>/dev/null || {
        echo "⚠️  Clone failed, skipping central knowledge"
        echo "   Check repo URL and permissions: $CENTRAL_REPO"
        exit 0
      }
    fi

    SYNCED=0
    for f in "$REMOTE_DIR"/*.md; do
      [[ -f "$f" ]] || continue
      fname="$(basename "$f")"
      local_file="$KNOWLEDGE_DIR/$fname"

      if [[ -f "$local_file" ]]; then
        case "$CONFLICT_POLICY" in
          prefer-local)  echo "  ⏭️  Keeping local: $fname" ;;
          prefer-remote) cp "$f" "$local_file"; echo "  🔄 Overwritten: $fname" ;;
          fail)          echo "  ❌ Conflict: $fname"; exit 1 ;;
        esac
      else
        cp "$f" "$local_file"
        echo "  ✅ Added: $fname"
        ((SYNCED++))
      fi
    done

    echo ""
    echo "📊 Sync complete: $SYNCED new entries"
    ;;

  push)
    if [[ "$SYNC_MODE" == "read-only" ]]; then
      echo "❌ Central knowledge repo is read-only, push not supported"
      echo "   Set manifest.yaml knowledge.central.mode: read-write"
      exit 1
    fi

    echo "📤 Pushing local knowledge to central repo..."
    if [[ ! -d "$REMOTE_DIR/.git" ]]; then
      echo "❌ Run sync.sh pull first to initialize"
      exit 1
    fi

    cp "$KNOWLEDGE_DIR"/*.md "$REMOTE_DIR/" 2>/dev/null || true
    cd "$REMOTE_DIR" || { echo "❌ Cannot access $REMOTE_DIR"; exit 1; }
    git add -A
    if git diff --cached --quiet; then
      echo "  ⏭️  No changes"
    else
      git commit -m "sync: knowledge from $(manifest_get '.project.name')" --quiet
      git push --quiet || { echo "❌ Push failed"; exit 1; }
      echo "  ✅ Push successful"
    fi
    ;;

  status)
    echo "📚 Knowledge Base Status:"
    echo "  Local dir: $KNOWLEDGE_DIR"
    echo "  Central repo: ${CENTRAL_REPO:-not configured}"
    echo "  Sync mode: $SYNC_MODE"
    echo "  Conflict policy: $CONFLICT_POLICY"
    echo ""

    local_count=$(find "$KNOWLEDGE_DIR" -maxdepth 1 -name "*.md" ! -name "index.md" 2>/dev/null | wc -l | tr -d ' ')
    echo "  Local entries: $local_count"

    if [[ -d "$REMOTE_DIR/.git" ]]; then
      remote_count=$(find "$REMOTE_DIR" -maxdepth 1 -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
      echo "  Remote cache: $remote_count"
    else
      echo "  Remote cache: not initialized (run sync.sh pull)"
    fi
    ;;

  *)
    echo "Usage: sync.sh [pull|push|status]"
    exit 1
    ;;
esac

#!/usr/bin/env bash
# tests/run.sh — Halo 测试统一入口。
# Usage: bash tests/run.sh [unit|regression|e2e|meta|legacy|all]
# 套件目录为空时跳过并提示；任一套件失败则最终非零退出（不吞退出码）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BATS_BIN="$SCRIPT_DIR/vendor/bats-core/bin/bats"
SUITE="${1:-all}"
FAILED=0

if [[ ! -x "$BATS_BIN" ]]; then
  echo "bats not found at tests/vendor/bats-core." >&2
  echo "Run: git submodule update --init" >&2
  exit 1
fi

run_bats_suite() {
  local name="$1"
  local dir="$SCRIPT_DIR/$name"
  local count=0
  if [[ -d "$dir" ]]; then
    # find 输出仅用于计数，不依赖顺序（fail direction: find 报错时 pipefail 会中止
    # 整个 runner → 非零退出 → CI 红，属 fail-closed；count=0 的 skip 分支只在
    # 目录确实为空/不存在时走到，不会把失败伪装成跳过）
    count=$(find "$dir" -name '*.bats' -type f | wc -l | tr -d ' ')
  fi
  if [[ "$count" -eq 0 ]]; then
    echo "── suite ${name}: no cases yet, skipped ──"
    return 0
  fi
  echo "── suite ${name} (${count} files) ──"
  if ! "$BATS_BIN" --recursive "$dir"; then
    FAILED=1
  fi
}

run_legacy() {
  echo "── legacy: smoke-test.sh ──"
  if ! bash "$SCRIPT_DIR/smoke-test.sh"; then
    FAILED=1
  fi
  echo "── legacy: ac-coverage-test.sh ──"
  if ! bash "$SCRIPT_DIR/ac-coverage-test.sh"; then
    FAILED=1
  fi
}

case "$SUITE" in
  unit | regression | e2e | meta)
    run_bats_suite "$SUITE"
    ;;
  legacy)
    run_legacy
    ;;
  all)
    run_bats_suite unit
    run_bats_suite meta
    run_bats_suite regression
    run_bats_suite e2e
    run_legacy
    ;;
  *)
    echo "Unknown suite: $SUITE (expected unit|regression|e2e|meta|legacy|all)" >&2
    exit 2
    ;;
esac

exit "$FAILED"

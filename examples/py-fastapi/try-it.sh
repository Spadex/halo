#!/usr/bin/env bash
# try-it.sh — Run Halo gates on this example project
# Usage: bash examples/py-fastapi/try-it.sh  (from repo root)
#
# This example is the no-regression guard for the FastAPI route parser. It carries the
# registration styles a real FastAPI project uses — an empty decorator path for the
# collection root, a multi-line decorator, and a multi-line APIRouter prefix — so a
# parser that only understands one shape fails here instead of in a target project.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

for tool in yq git; do
  command -v "$tool" &>/dev/null || { echo "Requires $tool"; exit 1; }
done

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

echo "══════════════════════════════════"
echo "Halo — Python FastAPI Example Demo"
echo "Sandbox: $SANDBOX"
echo "══════════════════════════════════"
echo ""

# Set up: copy example + install harness
cp -r "$SCRIPT_DIR"/. "$SANDBOX"/
cd "$SANDBOX"
git init --quiet

# Copy framework pieces used by this standalone demo.
cp -r "$REPO_DIR/harness-template/halo/kernel" "$SANDBOX/halo/kernel"
cp -r "$REPO_DIR/prismspec" "$SANDBOX/prismspec"
chmod +x halo/kernel/*.sh halo/kernel/context/*.sh halo/kernel/context/backends/*.sh halo/kernel/delivery/*.sh halo/kernel/delivery/gates/*.sh prismspec/bin/*.sh 2>/dev/null || true

SPEC="halo/specs/model-set-api/spec.md"

echo "── 1. Spec Lint ──"
bash halo/kernel/delivery/gates/spec-lint.sh "$SPEC"
echo ""

echo "── 2. PrismSpec Lint ──"
bash prismspec/bin/lint.sh "$(dirname "$SPEC")" spec
echo ""

echo "── 3. AC Coverage ──"
bash halo/kernel/delivery/gates/ac-coverage.sh "$SPEC" .
echo ""

echo "── 4. Drift Check ──"
bash halo/kernel/delivery/gates/drift-check.sh "$SPEC" .
echo ""

echo "── 5. Route Parser Guard ──"
# Every spec route must resolve, including the two the parser used to drop: the
# empty-path collection root and the routes behind a multi-line decorator or prefix.
DRIFT_JSON="halo/state/gates/drift-check.json"
bash halo/kernel/delivery/gates/drift-check.sh "$SPEC" . --json-out="$DRIFT_JSON" >/dev/null
yq -e '.metrics.checked.routes == true and .metrics.spec_routes == 6 and .metrics.drift_count == 0' "$DRIFT_JSON" >/dev/null \
  || { echo "❌ route parser regression: see $SANDBOX/$DRIFT_JSON"; yq '.metrics, .findings' "$DRIFT_JSON"; exit 1; }
yq '.metrics.checked, .metrics.spec_routes, .metrics.drift_count' "$DRIFT_JSON"
echo "  ✅ all 6 spec routes resolved (collection root, multi-line decorator, multi-line prefix)"
echo ""

echo "── 6. Context Knowledge Backend ──"
bash halo/kernel/context/backends/knowledge.sh naming
echo ""

echo "── 7. Review Summary Evidence ──"
bash halo/kernel/orchestrator/sdd/review-summary.sh model-set-api branch \
  --spec-compliance=pass \
  --code-quality=pass \
  --test-coverage=pass \
  --risk=pass \
  --evidence="spec-lint, ac-coverage, drift-check"
sed -n '1,24p' halo/specs/model-set-api/review.md
yq '.verdict, .axes' .halo/sdd/model-set-api/branch/review-summary.json
echo ""

echo "── 8. Pipeline Eval JSON ──"
bash halo/kernel/delivery/pipeline.sh --only=ac-coverage --spec="$SPEC" --json-out=halo/state/eval-runs/example.json
yq '.metrics, .gates[0].metrics, .process_evidence.review_summaries[0].verdict, .loop_state' halo/state/eval-runs/example.json
echo ""

echo "── 9. Eval Markdown Summary ──"
bash halo/kernel/delivery/eval-summary.sh halo/state/eval-runs/example.json --out=halo/state/eval-runs/example.md
sed -n '1,48p' halo/state/eval-runs/example.md
echo ""

echo "══════════════════════════════════"
echo "✅ All gates demonstrated"

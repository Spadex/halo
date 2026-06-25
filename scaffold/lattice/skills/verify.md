# Skill: verify — Verification Pipeline

**Triggers**: `/verify`, verify, run pipeline

## Capability

Execute manifest-driven verification pipeline, output evidence-based results.

## CLI

```bash
lattice/kernel/delivery/pipeline.sh
lattice/kernel/delivery/pipeline.sh --skip-spec
lattice/kernel/delivery/pipeline.sh --only=build
lattice/kernel/delivery/pipeline.sh --spec=lattice/specs/foo.md
```

## Behavior

1. Execute `lattice/kernel/delivery/pipeline.sh` (manifest-driven)
2. If harness not found, fallback to language defaults
3. Paste actual terminal output for each step
4. Summarize: ✅ PASS / ❌ FAIL

## Important

- Actual terminal output required, no natural language assertions
- If failures exist, explain cause and suggest fix direction

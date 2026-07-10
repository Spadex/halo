Run Halo Implementation according to the spec execution policy.

Execute `prismspec/skills/prismspec-implementation/SKILL.md`.

## Core behavior

1. Read `halo/specs/<spec-id>/spec.md` and `plan.md`.
2. Generate task briefs with `halo/kernel/orchestrator/sdd/task-brief.sh`.
3. If mode is `plan`, implement from the reviewed plan.
4. If mode is `tdd`, write red tests first, then make them green, then refactor.
5. Generate review packages with `halo/kernel/orchestrator/sdd/review-package.sh`.
6. Do not claim completion before `/verify`.

User input: $ARGUMENTS

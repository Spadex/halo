Run Lattice Planning for an existing spec.

Execute `lattice/skills/plan.md`.

## Core behavior

1. Read `lattice/specs/<spec-id>/spec.md`.
2. Create `lattice/specs/<spec-id>/plan.md`.
3. Ensure every task references Scope or ACs.
4. If `execution_mode: tdd`, include test-first tasks.

User input: $ARGUMENTS

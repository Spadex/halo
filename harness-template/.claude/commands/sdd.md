Run the guided Lattice SDD workflow.

Execute `prismspec/skills/sdd/SKILL.md`.

## Core behavior

1. Run `bash prismspec/bin/guide.sh $ARGUMENTS --json` when present to resolve host mode, spec id, execution mode, and next stage.
2. Resume from existing artifacts when possible.
3. Read the `skill` path returned by the guide, then delegate to stage skills in order:
   `brainstorm -> plan -> implement -> verify -> finish`.
4. After each stage, recompute artifact state and continue when the next action is clear.
5. Stop only on completion, retry exhaustion, or a material human decision.
6. Do not create extra stages, skip verification, or claim completion without evidence.

User input: $ARGUMENTS

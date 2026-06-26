# Skill: implement — Plan/TDD Execution

**Triggers**: `/implement`, implement, execute plan, code from spec, tdd

## Capability

Execute a Lattice plan according to the spec's execution policy:

- `plan`: implement from the reviewed plan with necessary tests.
- `tdd`: write failing tests first, then implementation, then refactor.

Implementation is not a separate workflow. It is one stage with two execution policies.

## Non-goals

- Do not change scope silently.
- Do not relax or delete tests to get green.
- Do not rewrite the spec to match code after the fact.
- Do not claim completion before `/verify` runs.

## Required Context

Before editing code:

1. Read `lattice/specs/<spec-id>/spec.md`.
2. Read `lattice/specs/<spec-id>/plan.md`.
3. Confirm `execution_mode`.
4. Inspect referenced files and tests.

## Workflow: Plan Mode

Use when `execution_mode: plan`.

1. Execute tasks in `plan.md` order.
2. Add tests when behavior changes or the plan requires them.
3. Keep changes scoped to the spec.
4. If the implementation discovers spec drift, stop and update the spec/plan before continuing.
5. Update task checkboxes as tasks complete.

## Workflow: TDD Mode

Use when `execution_mode: tdd`.

1. Write the red tests listed in `plan.md`.
2. Run the focused tests and confirm they fail for the expected reason.
3. Implement the minimal code to make them pass.
4. Run the focused tests again and confirm green.
5. Refactor only after green.
6. Run the broader relevant test suite.

Hard rules:

- No red test, no implementation.
- Tests must trace to `AC-{n}`.
- Do not skip, weaken, rename away, or delete tests to pass.

## Progress Notes

When useful, append brief implementation notes to:

```text
lattice/specs/<spec-id>/plan.md
```

Use concise notes only:

```markdown
- T1 completed: added handler validation for AC-2.
- RED-1 failed as expected before implementation; green after service change.
```

## Exit Criteria

Implementation is ready for verification only when:

- all planned tasks are complete or explicitly deferred;
- focused tests pass;
- `tdd` mode has red/green evidence;
- no known spec drift remains unresolved;
- `/verify` has not yet been replaced by a natural-language completion claim.

User input: $ARGUMENTS

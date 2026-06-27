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
4. Generate a task brief before starting each task:

```bash
bash lattice/kernel/orchestrator/sdd/task-brief.sh <spec-id> <task-id>
```

5. Inspect referenced files and tests.

## Workflow: Plan Mode

Use when `execution_mode: plan`.

1. Execute tasks in `plan.md` order.
2. For each task, read `.lattice/sdd/<spec-id>/<task-id>/brief.md`.
3. Add tests when behavior changes or the plan requires them.
4. Keep changes scoped to the spec and task interfaces.
5. If the implementation discovers spec drift, stop and update the spec/plan before continuing.
6. Generate a review package when the task is complete:

```bash
bash lattice/kernel/orchestrator/sdd/review-package.sh <spec-id> <task-id>
```

7. Update task checkboxes and evidence links as tasks complete.

## Workflow: TDD Mode

Use when `execution_mode: tdd`.

1. Write the red tests listed in `plan.md`.
2. Run the focused tests and confirm they fail for the expected reason.
3. Implement the minimal code to make them pass.
4. Run the focused tests again and confirm green.
5. Refactor only after green.
6. Generate the task review package.
7. Run the broader relevant test suite.

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

## Evidence Files

Use `.lattice/sdd/<spec-id>/<task-id>/` for transient execution evidence:

```text
.lattice/sdd/<spec-id>/<task-id>/
├── brief.md
├── review-package.md
└── implementation-notes.md
```

These files support review and finish. They are not long-term knowledge and should not replace `spec.md`, `plan.md`, tests, or `/verify`.

## Review Contract

If a reviewer/subagent is used, pass the file path to `review-package.md`, not a pasted diff. The reviewer must be read-only and return:

- Spec compliance: `pass`, `fail`, or `cannot-verify`
- Code quality: `pass`, `fail`, or `cannot-verify`

Treat `cannot-verify` as a useful result, not a failure of the reviewer. Add evidence or tests if the gap matters.

## Exit Criteria

Implementation is ready for verification only when:

- all planned tasks are complete or explicitly deferred;
- focused tests pass;
- `tdd` mode has red/green evidence;
- each completed task has a task brief and review package;
- no known spec drift remains unresolved;
- `/verify` has not yet been replaced by a natural-language completion claim.

User input: $ARGUMENTS

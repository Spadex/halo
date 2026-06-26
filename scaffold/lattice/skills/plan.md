# Skill: plan — AC-traced Planning

**Triggers**: `/plan`, planning, write plan, decompose spec

## Capability

Convert a persistent Lattice spec into an execution plan with task-to-acceptance traceability.

The durable output is:

```text
lattice/specs/<spec-id>/plan.md
```

## Non-goals

- Do not implement code in this skill.
- Do not rewrite the spec unless a gap blocks planning.
- Do not create tasks that cannot be reviewed independently.
- Do not hide unrelated refactors inside a task.

## Required Context

Before planning:

1. Read `lattice/specs/<spec-id>/spec.md`.
2. Confirm `status` is `drafted` or later.
3. Read `execution_mode`.
4. Inspect relevant files enough to identify implementation boundaries.

## Workflow

1. Summarize the spec in one sentence.
2. Identify affected modules, files, tests, and contracts.
3. Decompose into tasks that are small enough for review.
4. Reference Scope or `AC-{n}` for every task.
5. If `execution_mode: tdd`, add test-first tasks before implementation tasks.
6. Write `lattice/specs/<spec-id>/plan.md`.
7. Update spec front matter status to `planned` if possible.

## Output Format

```markdown
# Plan: <title>

## Source

- Spec: `lattice/specs/<spec-id>/spec.md`
- Execution mode: plan | tdd

## Implementation Notes

## Tasks

- [ ] T1: <task>
  - Ref: AC-1, AC-2
  - Files:
  - Verification:

- [ ] T2: <task>
  - Ref: Scope
  - Files:
  - Verification:

## Test-first Tasks

<!-- Required when execution_mode is tdd -->

- [ ] RED-1: Add failing test for AC-1
  - Expected failure:
  - Test file:
```

## Exit Criteria

Planning is complete only when:

- every task references Scope or one or more ACs;
- the plan is reviewable without reading unrelated context;
- `tdd` mode includes explicit red-test tasks;
- verification expectations are visible before implementation.

User input: $ARGUMENTS

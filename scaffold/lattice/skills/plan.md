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
2. Extract global constraints that every task must obey: versions, dependencies, naming rules, fixed values, migration constraints, security boundaries, and compatibility limits.
3. Identify affected modules, files, tests, and contracts.
4. Decompose into tasks that are independently reviewable and can complete their own focused test cycle.
5. Reference Scope or `AC-{n}` for every task.
6. For each task, declare interfaces: inputs consumed, outputs produced, touched files/contracts, and verification evidence.
7. Re-check execution mode against the discovered task risk.
   - If the spec says `plan` but the plan reveals bug-fix, money/security/permission/state-machine, concurrency, idempotency, or regression risk, upgrade to `tdd` before implementation.
   - If the spec says `tdd`, do not downgrade to `plan` without explicit user override.
8. If `execution_mode: tdd`, add test-first tasks before implementation tasks.
9. Write `lattice/specs/<spec-id>/plan.md`.
10. Update spec front matter status to `planned` if possible.

## Task Sizing

A task is the right size when:

- one implementer can complete it without reading unrelated modules;
- one reviewer can judge it from the task brief and diff;
- it has clear inputs, outputs, touched files, and verification;
- it can fail independently without invalidating the rest of the plan.

Split tasks that mix unrelated behavior, migrations, API contracts, and cleanup.

## Output Format

```markdown
# Plan: <title>

## Source

- Spec: `lattice/specs/<spec-id>/spec.md`
- Execution mode: plan | tdd

## Implementation Notes

## Global Constraints

- Versions / dependencies:
- Naming / style:
- Security / permissions:
- Data / migration:
- Compatibility:
- Out-of-scope:

## Tasks

- [ ] T1: <task>
  - Ref: AC-1, AC-2
  - Interfaces:
    - Inputs:
    - Outputs:
    - Touched files/contracts:
  - Files:
  - Verification:
  - Evidence:
    - Brief: `.lattice/sdd/<spec-id>/T1/brief.md`
    - Review package: `.lattice/sdd/<spec-id>/T1/review-package.md`

- [ ] T2: <task>
  - Ref: Scope
  - Interfaces:
    - Inputs:
    - Outputs:
    - Touched files/contracts:
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
- every task declares interfaces and verification evidence;
- global constraints capture the few rules all tasks must carry;
- the plan is reviewable without reading unrelated context;
- `tdd` mode includes explicit red-test tasks;
- `plan` mode has been checked for TDD escalation risk;
- verification expectations are visible before implementation.

User input: $ARGUMENTS

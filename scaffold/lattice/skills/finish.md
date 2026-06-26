# Skill: finish — Evidence Closeout

**Triggers**: `/finish`, finish, close out, summarize delivery

## Capability

Close a Lattice change after verification. This stage records delivery status, links evidence, and extracts only durable knowledge.

The durable output is:

```text
lattice/specs/<spec-id>/summary.md
```

Optionally, create a knowledge draft via `/learn` when the change produced reusable rules or lessons.

## Non-goals

- Do not re-summarize the entire spec.
- Do not preserve one-off plan details as long-term knowledge.
- Do not mark finished if required verification failed.
- Do not create knowledge entries from unverified guesses.

## Required Context

Before finishing:

1. Read `lattice/specs/<spec-id>/spec.md`.
2. Read `lattice/specs/<spec-id>/plan.md`.
3. Read verification output from `/verify`.
4. Inspect current git status and relevant commits/diffs.

## Workflow

1. Determine status: `completed`, `partial`, `reverted`, or `escalated`.
2. Link evidence: commands run, gate results, tests, commit hash if available.
3. Summarize shipped changes in a few bullets.
4. Identify durable knowledge candidates.
5. Write `lattice/specs/<spec-id>/summary.md`.
6. If knowledge should be retained, invoke `/learn` or create a clearly marked draft entry.
7. Update spec front matter status to `finished` or `escalated` if possible.

## Output Format

```markdown
# Summary: <title>

## Status

completed | partial | reverted | escalated

## Evidence

- Spec:
- Plan:
- Verify:
- Commit:

## Changes

- ...

## Deferred / Follow-up

- ...

## Knowledge Candidates

- ...
```

## Knowledge Extraction Rule

Extract to knowledge only when the lesson is reusable across future work:

- business invariant;
- incident lesson;
- high-frequency pitfall;
- domain boundary;
- irreversible design decision;
- team convention.

Do not extract:

- temporary implementation detail;
- one-off plan;
- content already expressed precisely by code/tests/schema;
- unverified assumption.

## Exit Criteria

Finishing is complete only when:

- verification evidence is linked;
- final status is explicit;
- reusable knowledge has been extracted or intentionally skipped;
- no required follow-up is hidden in prose.

User input: $ARGUMENTS

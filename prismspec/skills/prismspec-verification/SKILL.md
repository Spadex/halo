---
name: prismspec-verification
description: Runs independent command-backed verification for a PrismSpec run and records durable verify.md evidence. Use when implementation and review are complete, after fixing failures, when Halo pipeline gates should run, or whenever /prismspec routes to verification.
---

# PrismSpec Verification

## Overview

Run actual commands and record evidence. Verification is external proof, not a prose assertion.

This skill aligns with Superpowers `verification-before-completion`: no completion claim without command-backed evidence. PrismSpec adds durable `verify.md` and Halo pipeline/eval gates. Verification is the main PrismSpec workflow endpoint; optional knowledge promotion happens through `/capture`.

<HARD-GATE>
Do not say done, fixed, passing, complete, verified, or equivalent unless the proving command was run in the current verification pass and the result is recorded.
</HARD-GATE>

## Inputs

- `spec.md`
- `plan.md`
- `review.md` when review evidence is required.
- Current code and tests.
- Halo pipeline when installed.
- `prismspec/references/superpowers-alignment.md` when completion discipline is unclear.
- `prismspec/references/definition-of-done.md`

## Workflow

1. Resolve verification command from `prismspec/bin/guide.sh --json`.
2. In Halo-hosted mode, run:

```bash
bash halo/kernel/delivery/pipeline.sh --json-out
```

3. In standalone mode, detect and run the smallest meaningful set:
   - Node: `npm run build`, `npm run lint`, `npm test` when present.
   - Python: `ruff check .`, `pytest` when present.
   - Go: `go test ./...`.
   - Rust: `cargo test`.
4. Record exact commands, exit codes, output summaries, AC completion, skipped checks, residual risks, next actions, and knowledge candidates in `verify.md`.
5. Read the full output and confirm the exit code before making any status claim.
6. If a failure is not immediately explained by the output, switch to `prismspec-debugging` before changing code.
7. Fix retryable failures within the task scope, then rerun affected commands.
8. Escalate non-retryable failures with concrete next steps.
9. In Halo-hosted mode, advance status with `halo/kernel/orchestrator/sdd/spec-status.sh <spec-id> verified --from=implemented` only after verification passes.

## Outputs

- `verify.md` next to `spec.md`.

## Stop Conditions

- Verification requires external service or credentials not available.
- Failure points to ambiguous product behavior.
- Fix would exceed approved scope.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "The tests should pass." | Only actual output is evidence. |
| "Focused tests passed, full verification is unnecessary." | Focused tests prove the slice; verification checks regressions. |
| "This failure is unrelated." | Record it with evidence and rationale, or fix it. |
| "I can summarize without writing verify.md." | Durable evidence is the completion record and future recovery point. |
| "I ran this earlier." | Completion claims need fresh evidence from this verification pass. |

## Red Flags

- Verification output is paraphrased with no command.
- `verify.md` says pass while commands failed.
- TDD evidence is missing for `execution_mode: tdd`.
- Manual checks are claimed without steps or observations.
- Success language appears before the command output has been read.

## Verification

- [ ] `verify.md` exists.
- [ ] Commands and outcomes are recorded.
- [ ] Verification evidence is fresh for this completion claim.
- [ ] AC completion, skipped checks, residual risks, and next actions are recorded.
- [ ] Failures are fixed or escalated.
- [ ] Evidence matches the selected execution mode.
- [ ] Halo spec-status advances to `verified` only after passing evidence exists.

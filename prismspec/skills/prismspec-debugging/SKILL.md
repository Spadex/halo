---
name: prismspec-debugging
description: Investigates PrismSpec bugs, failing tests, build failures, unexpected behavior, or repeated verification failures before fixes are attempted. Use when implementation or verification fails and root cause is not proven.
---

# PrismSpec Debugging

## Overview

Find the root cause before proposing or applying fixes. Debugging is evidence gathering, not guess-and-check.

This skill aligns with Superpowers `systematic-debugging`: reproduce the failure, trace the data or control flow, compare with working examples, test one hypothesis at a time, and only then implement a fix. PrismSpec adds AC traceability and durable evidence in the routed task or verification artifacts.

<HARD-GATE>
Do not change production code, weaken tests, or edit the spec to fit the failure until the root cause is stated with evidence.
</HARD-GATE>

## Inputs

- Failing command, test, build, lint, pipeline, review finding, or user-reported bug.
- `spec.md`, `plan.md`, task evidence, `verify.md`, and review evidence when available.
- Recent diffs, related tests, logs, configs, schemas, and comparable working code.
- `prismspec/references/tdd-evidence-checklist.md` when the issue requires a regression test.

## Workflow

1. Record the exact failure: command, exit code, failing test or symptom, and relevant output.
2. Reproduce it consistently. If it is flaky, collect at least one more signal before hypothesizing.
3. Check recent changes and the AC or task that should cover the behavior.
4. Trace from the observed symptom back to the source of the bad value, state, config, or control path.
5. Compare against a working example in the same codebase or against the referenced contract.
6. State one hypothesis: "Root cause is X because evidence Y shows Z."
7. Test the hypothesis with the smallest diagnostic change, focused command, log, or one-off probe.
8. If the hypothesis fails, discard it and form a new one; do not stack unrelated changes.
9. Before the fix, add or identify a failing test when the bug is behaviorally testable.
10. Implement one fix that addresses the root cause, then rerun the focused command and relevant regression command.
11. Record the root cause, fix, commands, and residual risk in task evidence or `verify.md`.
12. If three different fixes fail, stop and ask whether the underlying architecture or spec should change.

## Outputs

- Root cause statement with evidence.
- Focused reproduction command or steps.
- Failing test or explicit no-test rationale.
- Fix scoped to the proven root cause.
- Updated task evidence or `verify.md` with commands, results, and residual risk.

## Stop Conditions

- The failure cannot be reproduced and no reliable diagnostic signal exists.
- Fixing the root cause requires product, architecture, data, credential, or permission decisions.
- Three fix attempts fail or reveal a deeper architectural problem.
- The required fix exceeds the approved spec scope.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "This looks obvious." | Symptoms are not root causes. Reproduce and trace first. |
| "I will just try one quick fix." | Guessing creates new bugs and hides evidence. |
| "The test is wrong." | Prove the expected behavior from the spec or contract before changing the test. |
| "Multiple small fixes are faster." | Multiple variables make the result uninterpretable. |
| "Manual verification is enough." | Behavioral bugs need repeatable proof or a written no-test rationale. |

## Red Flags

- Proposed fix appears before a root cause statement.
- Test expectations are changed before the spec or contract is checked.
- Logs or probes are added but never removed or explained.
- More than one unrelated change is made before rerunning the failing command.
- The same command fails after several different fixes.
- Failure is labeled unrelated without evidence.

## Verification

- [ ] Failure was reproduced or the inability to reproduce is documented.
- [ ] Root cause is stated with specific evidence.
- [ ] Fix maps to an AC, task, contract, or explicit follow-up.
- [ ] Focused failing command passes after the fix.
- [ ] Relevant regression command passes or blocker is explicit.
- [ ] Task evidence or `verify.md` records command output and residual risk.

## Halo Agent Rules

> Halo injects repo-local AI Coding constraints through `CLAUDE.md` `@import`.
> PrismSpec owns the Spec Coding workflow; Halo adds project context, verification gates, evidence, loop, and learn.

### Operating Rule

Route from current artifacts, not conversation memory:

```bash
bash prismspec/bin/guide.sh --json
```

Use the returned `stage`, `mode`, `skill`, `spec_dir`, `run_dir`, and `verify_command` as the source of truth.

### Routing

| Trigger | Route | Output |
|---------|-------|--------|
| Requirement without spec | Specification | `halo/specs/<spec-id>/spec.md` with Context Basis |
| `/prismspec` | PrismSpec controller | Next stage from `guide.sh --json` |
| `/clarify` | Grilling mode inside Specification | `status: clarifying` spec draft with engineering boundaries and open questions |
| `/spec` | Specification skill | context basis and spec |
| `/plan` | Planning skill | AC-traced `plan.md` |
| `/implement` | Implementation skill | code, tests, task evidence |
| `/review` | Review skill | `review.md` |
| `/verify` | Verification skill | `verify.md`, eval JSON when available |
| `/capture` | Knowledge capture skill | knowledge draft or promoted project knowledge |

### Source Of Truth

| Surface | Path |
|---------|------|
| Project contract | `halo/manifest.yaml` |
| Project context map | `halo/context/README.md` |
| External context map | `halo/context/external.md` |
| Durable project knowledge | `halo/context/knowledge/` |
| Spec artifacts | `halo/specs/<spec-id>/` |
| Task evidence | `.halo/sdd/<spec-id>/<task-id>/` |
| Eval runs and loop state | `halo/state/` |
| PrismSpec skills | `prismspec/skills/*/SKILL.md` |

Current code, tests, schemas, contracts, and command output override stale notes.

### Specification

- Use `prismspec-grilling` when engineering boundaries, artifact contracts, workflow state, compatibility, or verification are unclear. Ask one material question at a time and provide a recommended answer.
- `status: clarifying` is allowed only for an unfinished Clarify draft. Formal specs must advance to `status: drafted` before planning.
- Write `spec.md` with a Context Basis section.
- Read `halo/context/README.md` first when present.
- Load only context that changes scope, AC, risk, interface, compatibility, or verification.
- Optional curated knowledge search: `bash halo/kernel/context/backends/knowledge.sh <keywords>`.
- Do not paste large knowledge files into the spec; record selected facts, constraints, conflicts, exclusions, and gaps in `spec.md` Context Basis.
- Record `execution_mode`, reason, and source: `model-selected`, `project-default`, or `user-override`.
- Use stable `AC-{n}` identifiers.

Run when available:

```bash
bash halo/kernel/orchestrator/sdd/spec-state-lint.sh <spec-id>
```

### Planning

- Write `halo/specs/<spec-id>/plan.md`.
- Every behavior task must reference at least one AC.
- Every task must name scope, touched files/contracts, verification command, evidence path, and done conditions.
- Use thin vertical slices when possible.
- Upgrade `plan -> tdd` when planning reveals bug-fix, permission, security, money, state-machine, migration, concurrency, idempotency, or regression risk.
- Do not silently downgrade `tdd -> plan`.

Run when available:

```bash
bash halo/kernel/orchestrator/sdd/plan-lint.sh <spec-id>
bash halo/kernel/orchestrator/sdd/spec-status.sh <spec-id> planned --from=drafted
```

### Implementation

- Resolve the next task from artifacts:

```bash
bash halo/kernel/orchestrator/sdd/task-next.sh <spec-id> --json
```

- Implement one planned slice at a time.
- In Plan Mode, add tests for behavior changes or write an explicit no-test rationale.
- In TDD Mode, write the red test first, make it fail for the expected reason, then implement green and refactor.
- Generate task brief and review package when helpers exist.
- Mark tasks complete only through evidence-gated helper:

```bash
bash halo/kernel/orchestrator/sdd/task-complete.sh <spec-id> <task-id> --json
```

- Do not mix unrelated refactors.
- If implementation needs scope not in the spec, update the spec first.

Before treating implementation as complete:

```bash
bash halo/kernel/orchestrator/sdd/task-evidence-lint.sh <spec-id>
bash halo/kernel/orchestrator/sdd/spec-status.sh <spec-id> implemented --from=planned
```

### Review

Review is read-only evidence checking before final verification.

- Read `spec.md`, `plan.md`, task evidence, review packages, and changed files.
- Use one skeptical reviewer that returns `pass`, `fail`, or `cannot_verify` across spec compliance, code quality, test coverage, and risk.
- Treat missing evidence as `cannot_verify`.
- Do not tell the reviewer what to ignore.

Record review evidence when available:

```bash
bash halo/kernel/orchestrator/sdd/review-summary.sh <spec-id> branch \
  --spec-compliance=pass|fail|cannot_verify \
  --code-quality=pass|fail|cannot_verify \
  --test-coverage=pass|fail|cannot_verify \
  --risk=pass|fail|cannot_verify
```

The canonical review artifact is `halo/specs/<spec-id>/review.md`. The helper also writes `.halo/sdd/<spec-id>/branch/review.md` for run-scoped review evidence and `.halo/sdd/<spec-id>/branch/review-summary.json` as machine-readable pipeline input.

### Verification

Verification is command-backed proof, not a prose assertion.

Default Halo-hosted verification:

```bash
bash halo/kernel/delivery/pipeline.sh --json-out
```

Rules:

- No completion claim without command output or recorded evidence.
- Fix retryable failures within spec scope and rerun relevant commands.
- Escalate when the fix requires product, architecture, credential, data, or permission decisions.
- Record exact commands and outcomes in `verify.md`.

When verification passes:

```bash
bash halo/kernel/orchestrator/sdd/spec-status.sh <spec-id> verified --from=implemented
```

### Knowledge Capture

Promote only durable, reusable, non-secret lessons.

- Prefer `halo/kernel/context/summary-learn-draft.sh <spec-id>` when `verify.md` contains Knowledge Candidates.
- Store drafts under `halo/context/drafts/`.
- Promote to `halo/context/knowledge/` only after checking duplicates and conflicts.
- When governance is required, record reviewer evidence:

```bash
bash halo/kernel/context/knowledge-review.sh approve halo/context/drafts/<draft>.md --reviewer=<name> --reason=<reason> --conflicts-checked
bash halo/kernel/context/learn-draft.sh promote halo/context/drafts/<draft>.md --require-review --to=halo/context/knowledge/pitfalls.md
```

### Review Contract

- Review is read-only.
- Valid verdicts: `pass`, `fail`, `cannot_verify`.
- Check spec compliance, code quality, test coverage, and risk.
- Do not treat missing evidence as pass.

### Artifact Layout

```text
halo/
├── manifest.yaml
├── context/
│   ├── README.md
│   ├── external.md
│   ├── knowledge/
│   └── drafts/
├── specs/
│   └── <spec-id>/
│       ├── spec.md
│       ├── plan.md
│       ├── review.md
│       └── verify.md
└── state/
    ├── eval-runs/
    ├── loops/
    ├── outcomes/
    ├── learn-promotions/
    └── knowledge-reviews/

prismspec/
├── skillpack.yaml
├── skills/
├── templates/
├── references/
└── bin/

.halo/sdd/<spec-id>/<task-id>/
├── brief.md
├── review-package.md
├── review.md
├── review-summary.json
└── tdd-evidence.json

.halo/sdd/<spec-id>/branch/
├── review.md
└── review-summary.json
```

<p align="center">
  <h1 align="center">Lattice</h1>
  <p align="center">
    <strong>Repo-local AI Coding control plane for teams</strong>
  </p>
  <p align="center">
    <a href="README.md">中文文档</a> ·
    <a href="docs/wiki/">Design Wiki</a> ·
    <a href="docs/adapters/">Agent Adapters</a> ·
    <a href="examples/go-gin-gorm/">Runnable Example</a> ·
    <a href="CHANGELOG.md">Changelog</a>
  </p>
</p>

---

## What Is Lattice

Lattice is a repo-local AI Coding control plane for teams. It turns the requirement understanding, project context, execution policy, verification gates, and delivery evidence that usually stay inside individual AI coding sessions into reusable engineering contracts inside the code repository, so individual productivity compounds into team productivity.

| Capability Layer | Purpose |
|------------------|---------|
| Specification & Planning | Turns requirement understanding into executable specs, acceptance criteria, and task plans so AI coding starts with clear boundaries. |
| Context Engineering | Keeps project knowledge, historical lessons, external constraints, and team rules in the repository so individual judgment becomes reusable team context. |
| Delivery Verification | Uses build, lint, test, AC coverage, drift checks, and compliance gates to verify that code, specs, and project constraints stay aligned before delivery. |
| Evidence Intelligence | Aggregates command output, gate results, eval runs, history, and outcomes so completion status, quality risk, and improvement direction are traceable. |

In short: **Lattice turns repeated individual AI Coding gains into reusable, reviewable, and verifiable team engineering capability.**

## What Problem It Solves

Individual AI Coding can be fast, but team adoption often breaks down when:

- requirements, assumptions, and critical context stay inside chat;
- code changes lack reviewable specs, plans, and review evidence;
- "done" depends on a summary instead of fresh command output;
- project rules, lessons, and verification practices do not become shared assets.

Lattice turns those implicit individual workflows into versioned, reviewable, and verifiable engineering assets inside the repository.

## What You Get

A Lattice-guided AI Coding task leaves a clear delivery chain in the repo:

| Artifact | Purpose |
|----------|---------|
| `spec.md` | Requirement, Context Basis, scope, ACs, risks, and verification plan. |
| `plan.md` | AC-traced tasks, file boundaries, and verification commands. |
| `review.md` | Read-only review verdicts, findings, and risk dispositions. |
| `verify.md` | Commands, exit codes, results, residual risks, and knowledge candidates. |
| `lattice/state/eval-runs/*.json` | Structured delivery evidence for queries, summaries, CI, and dashboards. |

## Quick Start

### Install Into A Target Project

```bash
# Run inside your application repository
cd /path/to/your-project
bash <(curl -fsSL https://raw.githubusercontent.com/zdolphin07-dotcom/lattice/main/install.sh) --init

# Or clone locally first, then install into the current repository
git clone https://github.com/zdolphin07-dotcom/lattice.git /tmp/lattice
/tmp/lattice/install.sh "$PWD" --init
```

Prerequisites: Bash 4+, `yq` 4.x, and `git`.

Installation adds `lattice/`, `prismspec/`, and agent entry files. On upgrade, framework code under `kernel/` and PrismSpec can be refreshed; project-owned assets such as `lattice/manifest.yaml`, `lattice/context/`, and `lattice/specs/` should not be overwritten.

### Run The Example

```bash
git clone https://github.com/zdolphin07-dotcom/lattice.git
cd lattice
bash examples/go-gin-gorm/try-it.sh
```

The example demonstrates directory specs, embedded Context Basis in `spec.md`, spec lint, AC coverage, drift checks, eval JSON, and the context knowledge backend.

## Core Workflow

```text
Intent -> Clarify -> Spec -> Build -> Review -> Verify
```

`/prismspec` is the controller, not an extra phase. It routes from existing artifacts:

```bash
bash prismspec/bin/guide.sh --json
```

PrismSpec is not documentation ceremony. It moves the important AI coding decisions out of chat and into a resumable contract chain and evidence chain. The user-facing product blocks are backed by Agent Skills-compatible skill folders, command gates, and evidence:

| Block | Goal | Primary Artifacts |
|---|---|---|
| Clarify | Resolve intent, context basis, assumptions, conflicts, and blocking questions. | `spec.md#Context Basis` |
| Spec | Capture scope, non-goals, ACs, risks, mode, and verification plan. | `spec.md` |
| Build | Plan and implement AC-traced slices with Plan/TDD/debugging evidence. | `plan.md`, task evidence, TDD/debug evidence |
| Review | Independently inspect implementation evidence, diff, and quality risk. | `review.md`, review package |
| Verify | Prove completion with fresh commands or the Lattice pipeline. | `verify.md`, eval run JSON |

`/capture` is an optional post-run command. It promotes only durable, reusable, non-secret lessons from `verify.md` or review evidence.

Plan Mode and TDD Mode are implementation policies inside the same workflow:

| Mode | Use When | Evidence |
|------|----------|----------|
| `plan` | Docs, config, low-risk features, simple refactors, or changes already well covered by tests. | `plan.md`, relevant tests or no-test rationale, verification commands. |
| `tdd` | Bug fixes, permissions, security, state machines, concurrency, idempotency, migrations, or regressions. | Red test, green test, AC-to-test trace, and related verification. |

Projects can set the default mode in `lattice/manifest.yaml`. Users can override per spec. Risk discovered later may upgrade `plan -> tdd`; downgrading `tdd -> plan` requires explicit user override.

## Installed Layout

```text
your-project/
├── CLAUDE.md
├── lattice/
│   ├── manifest.yaml
│   ├── config/
│   ├── kernel/
│   │   ├── orchestrator/
│   │   ├── context/
│   │   └── delivery/
│   ├── context/
│   │   ├── README.md
│   │   ├── external.md
│   │   ├── knowledge/
│   │   └── drafts/
│   ├── state/
│   │   ├── eval-runs/
│   │   ├── loops/
│   │   ├── outcomes/
│   │   ├── learn-promotions/
│   │   └── knowledge-reviews/
│   └── specs/
│       └── <spec-id>/
│           ├── spec.md
│           ├── plan.md
│           ├── review.md
│           └── verify.md
└── prismspec/
    ├── skillpack.yaml
    ├── skills/
    ├── templates/
    ├── references/
    └── bin/
```

`kernel/` is upgradeable framework code. `manifest.yaml`, `context/`, and `specs/` are project-owned assets and should not be overwritten during upgrades.

## Components

The capability layers above are the user-facing view; the component model below is the repository implementation view.

| Component | Responsibility | Key Paths |
|-----------|----------------|-----------|
| PrismSpec | Standalone Spec Coding skill pack. | `prismspec/skills/`, `prismspec/bin/`, `prismspec/templates/` |
| Orchestrator | Agent control plane for stage routing, status transitions, task selection, and evidence gating. | `lattice/kernel/orchestrator/` |
| Context | Context map, project knowledge, external references, and optional retrieval backend. | `lattice/context/`, `lattice/kernel/context/` |
| Verification | Reproducible pipeline and gates. | `lattice/kernel/delivery/` |
| Evidence / Eval | Gate output, structured eval runs, Markdown summary/history, central sink, dashboard, queries, and outcomes. | `lattice/state/eval-runs/*.json`, `*.md`, `lattice/state/outcomes/` |

## Common Commands

| Scenario | Command |
|----------|---------|
| Check installation health | `bash lattice/kernel/doctor.sh` |
| Check PrismSpec standalone health | `bash prismspec/bin/doctor.sh` |
| Create an initial spec directory | `bash prismspec/bin/new.sh checkout-flow --template=service --mode=plan` |
| Route the next PrismSpec step | `bash prismspec/bin/guide.sh --json` |
| Lint the PrismSpec skill pack | `bash prismspec/bin/lint.sh prismspec skillpack` |
| Lint spec / plan / evidence | `bash prismspec/bin/lint.sh lattice/specs/<spec-id>` |
| Run the full verification pipeline | `bash lattice/kernel/delivery/pipeline.sh --json-out` |
| Run one gate | `bash lattice/kernel/delivery/pipeline.sh --only=spec-lint` |
| Resolve next task | `bash lattice/kernel/orchestrator/sdd/task-next.sh <spec-id> --json` |
| Complete a task with evidence | `bash lattice/kernel/orchestrator/sdd/task-complete.sh <spec-id> T1 --json` |
| Check task evidence | `bash lattice/kernel/orchestrator/sdd/task-evidence-lint.sh <spec-id>` |
| Advance spec status | `bash lattice/kernel/orchestrator/sdd/spec-status.sh <spec-id> planned --from=drafted` |
| Write review verdict | `bash lattice/kernel/orchestrator/sdd/review-summary.sh <spec-id> branch --spec-compliance=pass --code-quality=pass --test-coverage=pass --risk=pass` |
| Create knowledge draft from candidates | `bash lattice/kernel/context/summary-learn-draft.sh <spec-id>` |
| Render eval summary | `bash lattice/kernel/delivery/eval-summary.sh lattice/state/eval-runs/<run-id>.json` |
| Aggregate eval history | `bash lattice/kernel/delivery/eval-history.sh --out=lattice/state/eval-runs/history.md` |
| Publish central eval sink | `bash lattice/kernel/delivery/eval-sink.sh publish --sink-dir=lattice/state/eval-sink` |
| Render static dashboard | `bash lattice/kernel/delivery/eval-dashboard.sh --sink-dir=lattice/state/eval-sink --out=lattice/state/eval-sink/dashboard.html` |
| Query central sink | `bash lattice/kernel/delivery/eval-query.sh summary --sink-dir=lattice/state/eval-sink` |
| Approve knowledge draft | `bash lattice/kernel/context/knowledge-review.sh approve lattice/context/drafts/<draft>.md --reviewer=<name> --reason=<reason> --conflicts-checked` |
| Promote knowledge draft | `bash lattice/kernel/context/learn-draft.sh promote lattice/context/drafts/<draft>.md --require-review --to=lattice/context/knowledge/pitfalls.md` |

See the [Design Wiki](docs/wiki/) and script `--help` output for the full command contracts.

## Current Status

Lattice currently provides a minimum trusted loop for repo-local AI Coding:

| Verified Capability | Evidence |
|---------------------|----------|
| Install and init | `install.sh --init`, `lattice/kernel/doctor.sh`, smoke test. |
| PrismSpec workflow | `new.sh`, `guide.sh --json`, `lint.sh prismspec skillpack`, templates, and Plan/TDD policy. |
| Delivery verification | Lattice pipeline, spec lint, AC coverage, drift check, and compliance gates. |
| Evidence loop | `eval-runs/*.json`, Markdown summary/history, loop state, and outcome link/report. |
| Runnable example | `examples/go-gin-gorm/try-it.sh` demonstrates spec, AC coverage, drift check, and eval summary. |

Still evolving:

- dashboard trends and cross-project attribution;
- stronger semantic conflict governance;
- more drift parsers for Node, Python, and other stacks;
- plugin manifest/schema/versioning;
- multi-agent owner / lease model.

## Docs

| Document | Purpose |
|----------|---------|
| [Design Wiki](docs/wiki/) | System design, SDD, Context, Eval, Loop, Roadmap |
| [Workflow Blocks](docs/wiki/workflow-blocks.md) | Clarify / Spec / Build / Review / Verify contracts |
| [PrismSpec README](prismspec/README.md) | Standalone Spec Coding skill pack |
| [Agent adapters](docs/adapters/) | Claude Code, Cursor, Aider, Superpowers, Agent Skills, and generic agents |
| [Runnable example](examples/go-gin-gorm/) | End-to-end Go/Gin/GORM sample |
| [Contributing](CONTRIBUTING.md) | Development, testing, and contribution guide |

## Design Principles

- Spec is a contract, not a long document.
- Current code, tests, schema, and command output remain the source of truth.
- Context starts with a map, then the Agent discovers, selects, and compresses relevant facts.
- Verification must be backed by external commands and evidence.
- PrismSpec can be used independently; Lattice adds project-level context, verification, evidence, loop, and learn.
- Extensions integrate through files, YAML, and command contracts.

## License

MIT

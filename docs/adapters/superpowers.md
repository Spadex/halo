# Superpowers Adapter — Lattice Integration Guide

> This document describes how Lattice maps its AI Coding workflow to the [Superpowers](https://github.com/obra/superpowers) workflow engine.
> Lattice does not depend on Superpowers. Superpowers is an optional execution adapter.

## Phase Mapping

Lattice keeps its own durable artifacts (`spec.md`, `plan.md`, verification evidence, summary) and maps its stages to Superpowers skills when Superpowers is present:

| Lattice Stage | Superpowers Skill | Lattice Artifact / Constraint |
|---------------|-------------------|-------------------------------|
| **Brainstorming** | `brainstorming` | Write persistent `lattice/specs/<id>/spec.md`; load knowledge; select execution policy |
| **Planning** | `writing-plans` | Write `lattice/specs/<id>/plan.md`; every task references Scope or ACs |
| **Implementation: plan** | `executing-plans` | Execute reviewed plan with necessary tests |
| **Implementation: tdd** | `test-driven-development` | Red test first; tests trace to ACs |
| **Verification** | `verification-before-completion` | Run `lattice/kernel/delivery/pipeline.sh` |
| **Finishing** | `finishing-a-development-branch` | Write `summary.md`; extract durable knowledge only |

## How It Works

Lattice injects rules via `@import` in the project's `CLAUDE.md`:

```markdown
@import lattice/kernel/orchestrator/rules.md
```

When `rules.md` and a Superpowers skill definition conflict, `CLAUDE.md` content takes priority. Lattice rules override Superpowers defaults without modifying Superpowers source code.

The most important distinction:

- Superpowers owns workflow discipline.
- Lattice owns durable artifacts, execution policy, knowledge injection, and verification evidence.

## Why Not Modify Superpowers Directly

1. **Version independence**: Superpowers upgrades don't break Lattice artifacts or gates
2. **Portability**: Switching to another engine keeps the same `spec.md` / `plan.md` / `verify` contract
3. **Separation of concerns**: Superpowers manages workflow discipline; Lattice manages contracts and evidence
4. **Zero invasion**: Teams can adopt Lattice without replacing or forking Superpowers

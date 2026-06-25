# Superpowers Adapter — Lattice Integration Guide

> This document describes how Lattice integrates with the [Superpowers](https://github.com/obra/superpowers) workflow engine.
> For other engines, the same principles apply — Lattice injects constraints at phase boundaries, not inside the engine.

## Phase Mapping

Lattice uses generic phase names. Map them to Superpowers skills:

| Lattice Phase | Superpowers Skill | Override Scope |
|-------------------|-------------------|----------------|
| **design** | `brainstorming` | Spec path, format, knowledge injection |
| **approve** | HARD-GATE (built-in) | Unchanged |
| **plan** | `writing-plans` | AC traceability in tasks |
| **implement** | `test-driven-development` | Test naming conventions |
| **verify** | `verification-before-completion` | Pipeline execution |
| **deliver** | `finishing-a-development-branch` | Full coverage check |

## How It Works

Lattice injects rules via `@import` in the project's `CLAUDE.md`:

```markdown
@import lattice/kernel/orchestrator/rules.md
```

When `rules.md` and a Superpowers skill definition conflict, `CLAUDE.md` content takes priority. Lattice rules override Superpowers defaults without modifying Superpowers source code.

## Why Not Modify Superpowers Directly

1. **Version independence**: Superpowers upgrades don't break Lattice constraints
2. **Portability**: Switching to another engine only requires adjusting rules.md
3. **Separation of concerns**: Superpowers manages workflow order, Lattice manages quality standards
4. **Zero invasion**: Teams can adopt Lattice independently without affecting other team members' Superpowers experience

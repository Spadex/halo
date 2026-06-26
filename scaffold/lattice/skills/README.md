# Lattice Skills — Agent Capability Interface

Skills are discoverable, invokable capability declarations for the AI agent. Lattice keeps the AI Coding workflow intentionally small: Brainstorming, Planning, Implementation, Verification, Finishing, plus init and learn.

## Built-in Skills

| Skill | File | Trigger | Dependency Layer |
|-------|------|---------|-----------------|
| init | `init.md` | `/init`, initialize Lattice | Orchestrator + Delivery |
| brainstorm | `brainstorm.md` | `/brainstorm`, clarify, draft spec | Orchestrator + Knowledge |
| plan | `plan.md` | `/plan`, write plan | Orchestrator |
| implement | `implement.md` | `/implement`, execute plan, tdd | Orchestrator + Delivery |
| verify | `verify.md` | `/verify`, verify, run pipeline | Delivery |
| finish | `finish.md` | `/finish`, close out | Orchestrator + Knowledge |
| learn | `learn.md` | `/learn`, capture, remember | Knowledge |

Other capabilities (knowledge loading, spec templates, AC tracing, drift detection) are injected via `lattice/kernel/orchestrator/rules.md` and enforced by delivery gates.

## Relationship with `.claude/commands/`

`.claude/commands/` provides Claude Code slash command entry points that reference `lattice/skills/*.md`.

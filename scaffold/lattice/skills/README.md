# Lattice Skills — Agent Capability Interface

Skills are discoverable, invokable capability declarations for the AI agent. Three explicit skills are available: init, verify, learn.

## Built-in Skills

| Skill | File | Trigger | Dependency Layer |
|-------|------|---------|-----------------|
| init | `init.md` | `/init`, initialize Lattice | Orchestrator + Delivery |
| verify | `verify.md` | `/verify`, verify, run pipeline | Delivery |
| learn | `learn.md` | `/learn`, capture, remember | Knowledge |

Other capabilities (knowledge loading, spec templates, AC tracing, drift detection) are injected via `lattice/kernel/orchestrator/rules.md` and do not need separate skills.

## Relationship with `.claude/commands/`

`.claude/commands/` provides Claude Code slash command entry points that reference `lattice/skills/*.md`.

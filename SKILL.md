---
name: lattice
version: 1.0.0
description: >
  Lattice — repo-local AI Coding harness for teams.
  Use it to initialize a project harness, route PrismSpec SDD work, provide project context,
  run delivery gates, and record command-backed evidence.
  Triggers: "lattice init", "initialize harness", "sdd", "verify", "run pipeline", "learn".
---

# Lattice Skill

Lattice installs a project-level harness into a target repository. It does not replace the coding agent; it gives the agent stable project contracts for context, spec, verification, and evidence.

## Entry Points

| User Intent | Action |
|-------------|--------|
| initialize Lattice / `lattice init` | Run `bash .lattice/framework/init.sh` in the target project |
| SDD / guided workflow | Run `bash prismspec/bin/guide.sh --json`, then follow the routed PrismSpec skill |
| brainstorm / draft spec | Write `lattice/specs/<spec-id>/context.md` and `spec.md` |
| plan | Write AC-traced `plan.md` |
| implement / tdd | Execute `plan` or `tdd` according to `spec.md` |
| verify / run pipeline | Run `bash lattice/kernel/delivery/pipeline.sh` |
| finish | Write `verify.md` / `summary.md` and capture residual risk |
| learn | Follow `prismspec/skills/learn/SKILL.md` |

## Contracts

- PrismSpec is the only SDD workflow source: `prismspec/skills/*/SKILL.md`.
- Default spec layout: `lattice/specs/<spec-id>/context.md` + `spec.md`.
- Templates live under `prismspec/templates/`.
- Lattice-specific skills under `lattice/skills/` should stay minimal; do not duplicate PrismSpec.
- User-owned assets are not overwritten on upgrade: `lattice/manifest.yaml`, `lattice/context/`, `lattice/specs/`.

## Verification

```bash
bash prismspec/bin/guide.sh --json
bash prismspec/bin/lint.sh lattice/specs/<spec-id>
bash lattice/kernel/delivery/pipeline.sh
```

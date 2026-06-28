# Lattice Skills

Lattice keeps only Lattice-specific skills here.

| Skill | File | Purpose |
|-------|------|---------|
| init | `init.md` | Initialize Lattice in a target project |

SDD / Spec Coding skills are not duplicated under `lattice/skills/`.
Use PrismSpec as the single workflow source of truth:

```text
prismspec/skills/sdd/SKILL.md
prismspec/skills/brainstorm/SKILL.md
prismspec/skills/plan/SKILL.md
prismspec/skills/implement/SKILL.md
prismspec/skills/verify/SKILL.md
prismspec/skills/finish/SKILL.md
prismspec/skills/learn/SKILL.md
```

Lattice-hosted behavior is detected by `prismspec/bin/guide.sh` when `lattice/manifest.yaml` exists. In that mode, PrismSpec writes artifacts under `lattice/specs/`, uses `.lattice/sdd/` for transient evidence, and verifies through `lattice/kernel/delivery/pipeline.sh`.

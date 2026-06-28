# /init — Lattice Project Initialization

## Trigger

User says "initialize Lattice", "/init", or project root has no `lattice/manifest.yaml`.

## Flow

1. Detect the project language, framework, ORM, database, and CI profile.
2. Copy the Lattice kernel, context template, PrismSpec module, and slash commands.
3. Generate `lattice/manifest.yaml` when it does not already exist.
4. Configure `CLAUDE.md` with `@import lattice/kernel/orchestrator/rules.md`.
5. Create project-owned directories: `lattice/specs/`, `lattice/context/`, `lattice/state/`.
6. Run `bash lattice/kernel/delivery/bootstrap.sh check`.

## Output

- `lattice/manifest.yaml` — project declaration
- `CLAUDE.md` — Claude Code import entry
- `lattice/context/README.md` — project context map
- `lattice/specs/` — directory spec artifacts

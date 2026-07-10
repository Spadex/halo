# /init — Halo Project Initialization

## Trigger

User says "initialize Halo", "/init", or project root has no `halo/manifest.yaml`.

## Flow

1. Detect the project language, framework, ORM, database, and CI profile.
2. Copy the Halo kernel, context template, PrismSpec module, and slash commands.
3. Generate `halo/manifest.yaml` when it does not already exist.
4. Configure `CLAUDE.md` with `@import halo/kernel/orchestrator/rules.md`.
5. Create project-owned directories: `halo/specs/`, `halo/context/`, `halo/state/`.
6. Run `bash halo/kernel/delivery/bootstrap.sh check`.

## Output

- `halo/manifest.yaml` — project-owned contract
- `CLAUDE.md` — Claude Code import entry
- `halo/context/README.md` — project context map
- `halo/specs/` — directory spec artifacts

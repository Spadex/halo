# Engine & Agent Adapters

Halo is agent-agnostic. It injects behavioral constraints at phase boundaries via `rules.md` and provides CLI tools that any agent can invoke. The integration mechanism varies by agent:

| Agent / Engine | Integration Method | File |
|---------------|-------------------|------|
| **Claude Code** | `CLAUDE.md` `@import` + `.claude/commands/` | Built-in (default) |
| **Cursor** | `.cursorrules` `@file` directive | [cursor.md](cursor.md) |
| **Aider** | `--read` flag / `.aider.conf.yml` | [aider.md](aider.md) |
| **Superpowers** | Workflow engine phase mapping | [superpowers.md](superpowers.md) |
| **Agent Skills** | Skill packaging, metadata, progressive disclosure, evals | [agent-skills.md](agent-skills.md) |

## How It Works

Halo has two integration surfaces:

1. **Rules injection** — `rules.md` is a plain Markdown file describing agent behavior per phase. Any agent that supports system prompt customization can import it.
2. **CLI tools** — All gates (`pipeline.sh`, `spec-lint.sh`, etc.) are standalone bash scripts. Any agent that can run shell commands can use them.

## Writing a New Adapter

To integrate Halo with a new agent or workflow engine:

1. Find how your agent loads custom instructions (system prompt, rules file, config)
2. Point it to `halo/kernel/orchestrator/rules.md`
3. Document how to invoke CLI tools (`/run`, shell access, MCP, etc.)
4. Add a `<agent-name>.md` file to this directory

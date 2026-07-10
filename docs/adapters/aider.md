# Aider Adapter

Halo works with [Aider](https://aider.chat) via its conventions file.

## Setup

1. Install Halo into your project:

```bash
bash install.sh /path/to/your-project --init
```

2. Create `.aider.conf.yml` and add Halo rules as a read-only file:

```yaml
read:
  - halo/kernel/orchestrator/rules.md
```

Or pass it on the command line:

```bash
aider --read halo/kernel/orchestrator/rules.md
```

3. Aider will include Halo rules in its system prompt context.

## Usage

Aider can execute shell commands via `/run`:

```
/run bash halo/kernel/delivery/pipeline.sh
/run bash halo/kernel/context/backends/knowledge.sh <keywords>
/run bash halo/kernel/delivery/gates/spec-lint.sh halo/specs/my-spec/spec.md
```

## Limitations

- No automatic skill triggers — use `/run` for all Halo commands
- Aider's `/run` output is included in context, so pipeline output is visible to the model
- Context knowledge backend results may consume significant context — use targeted keywords

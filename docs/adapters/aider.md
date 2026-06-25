# Aider Adapter

Lattice works with [Aider](https://aider.chat) via its conventions file.

## Setup

1. Install Lattice into your project:

```bash
bash install.sh /path/to/your-project --init
```

2. Create `.aider.conf.yml` and add Lattice rules as a read-only file:

```yaml
read:
  - lattice/kernel/orchestrator/rules.md
```

Or pass it on the command line:

```bash
aider --read lattice/kernel/orchestrator/rules.md
```

3. Aider will include Lattice rules in its system prompt context.

## Usage

Aider can execute shell commands via `/run`:

```
/run bash lattice/kernel/delivery/pipeline.sh
/run bash lattice/kernel/knowledge/loader.sh <keywords>
/run bash lattice/kernel/delivery/gates/spec-lint.sh lattice/specs/my-spec.md
```

## Limitations

- No automatic skill triggers — use `/run` for all Lattice commands
- Aider's `/run` output is included in context, so pipeline output is visible to the model
- Knowledge loader results may consume significant context — use targeted keywords

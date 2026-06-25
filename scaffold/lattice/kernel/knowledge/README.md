# Layer 2: Knowledge — Knowledge Base Engine

Pluggable knowledge layer supporting local knowledge management and central repo sync.

## CLI

```bash
# Load knowledge by keyword
lattice/kernel/knowledge/loader.sh grab balance concurrency

# List all knowledge entries
lattice/kernel/knowledge/loader.sh --list

# Output all knowledge content
lattice/kernel/knowledge/loader.sh --all

# Central knowledge repo sync
lattice/kernel/knowledge/sync.sh pull     # Pull
lattice/kernel/knowledge/sync.sh push     # Push
lattice/kernel/knowledge/sync.sh status   # Status
```

## Knowledge File Format

```markdown
# <One-line title>

**Keywords**: <comma-separated keywords>
**Core rule**: <one-line core conclusion>
**Source**: <date + source>
**Context**: <supplementary explanation>
```

## Index Format (index.md)

```
- `slug` | Keywords: k1, k2 | One-line description
```

## Central Knowledge Repo Config

```yaml
# manifest.yaml
knowledge:
  local_dir: lattice/knowledge
  central:
    repo: https://github.com/your-org/shared-knowledge.git
    mode: read-only         # read-only | read-write
    conflict: prefer-local  # prefer-local | prefer-remote | fail
```

## Enable/Disable

```yaml
# manifest.yaml
kernel:
  layers:
    knowledge: true   # false to skip knowledge loading
```

When disabled, the design phase skips knowledge loading and proceeds directly to brainstorming.

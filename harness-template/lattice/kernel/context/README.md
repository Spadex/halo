# Layer 2: Context

The context layer prepares reliable project context for AI coding. It links durable project knowledge, optional central knowledge, source records, and per-spec context basis files.

## CLI

```bash
# Load context knowledge by keyword
lattice/kernel/context/loader.sh auth rate-limit idempotency

# List project and central context indexes
lattice/kernel/context/loader.sh --list

# Output all context knowledge entries
lattice/kernel/context/loader.sh --all

# Sync central context knowledge
lattice/kernel/context/sync.sh pull
lattice/kernel/context/sync.sh push
lattice/kernel/context/sync.sh status
```

## Directory Contract

```text
lattice/context/
  sources.yaml                 # External and central context source registry
  knowledge/
    project/                   # Project-owned durable knowledge
      index.md
      synonyms.txt
    central/                   # Cached central knowledge
    drafts/                    # Candidate learnings before review
lattice/specs/<spec-id>/
  context.md                   # Per-spec context basis
```

`context.md` is the delivery artifact for one feature iteration. It should cite which project knowledge, central knowledge, code facts, contracts, and open questions were used to produce the spec.

## Knowledge Entry Format

```markdown
---
id: auth-idempotency
type: rule
scope: project
status: accepted
tags: [auth, idempotency]
source: "decision log, 2026-06-28"
---

# Auth Idempotency

## Rule
One stable business action must map to one idempotency key.

## Applies When
- Creating or retrying auth-sensitive write operations.

## Evidence
- Link to source code, decision, incident, or spec.
```

## Manifest

```yaml
kernel:
  layers:
    context: true

context:
  root: lattice/context
  sources_file: lattice/context/sources.yaml
  knowledge:
    project_dir: lattice/context/knowledge/project
    central_dir: lattice/context/knowledge/central
    drafts_dir: lattice/context/knowledge/drafts
  central:
    repo: https://github.com/your-org/context-knowledge.git
    mode: read-only
    conflict: project-wins
```

Project knowledge wins over central knowledge when the two conflict.

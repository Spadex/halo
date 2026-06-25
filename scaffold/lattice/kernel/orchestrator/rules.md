## Lattice — Agent Behavior Rules

> Lattice injects project-level constraints into your AI coding agent via `CLAUDE.md` `@import`.
> These rules enhance the agent's default workflow with knowledge injection and delivery verification.

---

### Routing

| Trigger | Path | When to use |
|---------|------|-------------|
| Describe a requirement (default) | **Standard workflow** | New features, cross-module, data/auth/stability concerns |
| `/init` | **Init Skill** | Set up harness, generate `lattice/manifest.yaml`, inject `CLAUDE.md` |
| `/verify` | **Verify Skill** | Run manifest-driven verification pipeline |
| `/learn` | **Learn Skill** | Capture knowledge into the knowledge base |

---

### Phase Rules

> The following rules apply to each phase of development. If your workflow engine provides
> phases with different names, map them accordingly (see docs/adapters/ for engine-specific mappings).

#### Phase: Design — Spec format and knowledge injection

- **Spec path**: `lattice/specs/{requirement}-{slug}.md`
- **Template**: `lattice/kernel/orchestrator/templates/spec-template.md`
- **Dual-audience principle**: diagrams for humans, DDL/AC/API examples for AI execution
- **AC numbering**: globally unique `AC-{nn}`, traced through spec -> test -> coverage

Before drafting the spec:
1. Read `lattice/manifest.yaml`
2. Run `bash lattice/kernel/knowledge/loader.sh <requirement keywords>`
3. Use matched knowledge entries as design input; if context is insufficient, ask the user first — do not guess

#### Phase: Plan — AC traceability

- Plan path: `lattice/plans/{requirement}-{slug}.md`
- Each task must reference its associated AC number
- If spec drift is discovered during coding, update the spec first, then continue implementation

#### Phase: Implement — Test naming conventions

- Unit tests: `TestAC{nn}_{description}` (Go) / `test_ac{nn}_{description}` (Python) / `describe('AC-{nn}: ...')` (Node)
- Integration tests: `TestIntegration_{scenario}`
- Smoke tests: `TestSmoke_{API}`

#### Phase: Verify — Delivery pipeline

Before declaring completion, run:

```bash
bash lattice/kernel/delivery/pipeline.sh
```

Rules:
- No completion claims without verification evidence
- On failure: fix -> re-run loop, default max 3 retries
- After retry budget exhausted: escalation, await human intervention

#### Phase: Deliver — Full coverage check

Before merge/PR, confirm:
- `ac-coverage`: every AC has a corresponding test
- `drift-check`: DDL / routes / error codes match spec
- `compliance`: knowledge references and clarification traces are auditable
- For multi-agent concurrent spec edits, use `spec-lock.sh`

---

### Available Skills

| Skill | Trigger | Capability |
|-------|---------|------------|
| `init` | `/init`, initialize Lattice | Generate manifest, copy scaffold, inject CLAUDE.md |
| `verify` | `/verify`, verify, run pipeline | Execute `lattice/kernel/delivery/pipeline.sh` |
| `learn` | `/learn`, capture, remember | Write to `lattice/knowledge/` and update index |

### Artifact Layout

```text
lattice/
├── manifest.yaml
├── kernel/
│   ├── _lib.sh
│   ├── orchestrator/
│   │   ├── rules.md
│   │   ├── flow.yaml
│   │   └── templates/
│   ├── knowledge/
│   └── delivery/
├── knowledge/
├── requirements/
├── specs/
├── plans/
├── state/
└── skills/
```

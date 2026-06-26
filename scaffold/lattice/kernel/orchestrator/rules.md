## Lattice — Agent Behavior Rules

> Lattice injects project-level constraints into your AI coding agent via `CLAUDE.md` `@import`.
> These rules enhance the agent's default workflow with knowledge injection and delivery verification.

---

### Routing

| Trigger | Path | When to use |
|---------|------|-------------|
| Describe a requirement (default) | **Brainstorming** | Clarify intent, load knowledge, write persistent spec |
| `/init` | **Init Skill** | Set up harness, generate `lattice/manifest.yaml`, inject `CLAUDE.md` |
| `/brainstorm` | **Brainstorm Skill** | Produce `lattice/specs/<id>/spec.md` |
| `/plan` | **Plan Skill** | Produce `lattice/specs/<id>/plan.md` |
| `/implement` | **Implement Skill** | Execute plan or tdd policy from the spec |
| `/verify` | **Verify Skill** | Run manifest-driven verification pipeline |
| `/finish` | **Finish Skill** | Close delivery, link evidence, extract durable knowledge |
| `/learn` | **Learn Skill** | Capture knowledge into the knowledge base |

---

### Phase Rules

> The following rules apply to each phase of development. If your workflow engine provides
> phases with different names, map them accordingly (see docs/adapters/ for engine-specific mappings).

#### Phase: Brainstorming — Spec format and knowledge injection

- **Spec path**: `lattice/specs/{spec-id}/spec.md`
- **Template**: `lattice/kernel/orchestrator/templates/spec-template.md`
- **Dual-audience principle**: diagrams for humans, DDL/AC/API examples for AI execution
- **AC numbering**: globally unique `AC-{nn}`, traced through spec -> test -> coverage
- **Execution policy**: choose `plan` or `tdd`; do not create separate workflows

Before drafting the spec:
1. Read `lattice/manifest.yaml`
2. Run `bash lattice/kernel/knowledge/loader.sh <requirement keywords>`
3. Use matched knowledge entries as design input; if context is insufficient, ask the user first — do not guess

#### Phase: Planning — AC traceability

- Plan path: `lattice/specs/{spec-id}/plan.md`
- Each task must reference its associated AC number
- If `execution_mode: tdd`, include test-first tasks
- If spec drift is discovered during coding, update the spec first, then continue implementation

#### Phase: Implementation — Plan/TDD policy

- Unit tests: `TestAC{nn}_{description}` (Go) / `test_ac{nn}_{description}` (Python) / `describe('AC-{nn}: ...')` (Node)
- Integration tests: `TestIntegration_{scenario}`
- Smoke tests: `TestSmoke_{API}`
- Plan mode: execute `plan.md`, add necessary tests for behavior changes
- TDD mode: write red tests first, implement green, then refactor; no red test, no implementation

#### Phase: Verification — Delivery pipeline

Before declaring completion, run:

```bash
bash lattice/kernel/delivery/pipeline.sh
```

Rules:
- No completion claims without verification evidence
- On failure: fix -> re-run loop, default max 3 retries
- After retry budget exhausted: escalation, await human intervention

#### Phase: Finishing — Evidence closeout

Before merge/PR, confirm:
- `ac-coverage`: every AC has a corresponding test
- `drift-check`: DDL / routes / error codes match spec
- `compliance`: knowledge references and clarification traces are auditable
- For multi-agent concurrent spec edits, use `spec-lock.sh`
- Write `lattice/specs/{spec-id}/summary.md`
- Extract only durable knowledge via `/learn`; do not preserve one-off implementation details

---

### Available Skills

| Skill | Trigger | Capability |
|-------|---------|------------|
| `init` | `/init`, initialize Lattice | Generate manifest, copy scaffold, inject CLAUDE.md |
| `brainstorm` | `/brainstorm`, draft spec | Clarify intent, load knowledge, write persistent spec |
| `plan` | `/plan`, write plan | Decompose spec into AC-traced tasks |
| `implement` | `/implement`, tdd | Execute plan or tdd policy |
| `verify` | `/verify`, verify, run pipeline | Execute `lattice/kernel/delivery/pipeline.sh` |
| `finish` | `/finish`, close out | Write summary and extract durable knowledge |
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

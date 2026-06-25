# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0] — 2026-06-23

### Added

- **Engine-agnostic architecture**: Generic phase names (design → plan → implement → verify → deliver) replace engine-specific coupling. Workflow engine integration via adapter docs.
- **Configurable spec-lint**: `specs.required_sections[]` and `specs.risk_categories[]` in manifest.yaml — override defaults without touching kernel code.
- **Three-layer architecture**: Orchestrator (rules injection), Knowledge (context retrieval), Delivery (gate pipeline) — each independently pluggable.
- **5 delivery gates**: spec-lint, ac-coverage, drift-check, compliance, spec-lock.
- **AC tracing**: Acceptance Criteria numbering from spec through test naming to coverage verification.
- **Knowledge layer**: Keyword-based retrieval with synonym support, central repo sync.
- **Multi-language support**: Go (Gin/GORM), Node (Express/Prisma), Python (FastAPI/SQLAlchemy), Rust detection.
- **Agent skills**: `/init` (project setup), `/verify` (pipeline execution), `/learn` (knowledge capture).
- **Escalation protocol**: Exit code 2 triggers human intervention after retry exhaustion.
- **Adapter documentation**: Engine-specific integration guides under `docs/adapters/`.

### Fixed

- `_find_project_root()` now walks up directories instead of using hardcoded relative path.
- `run_cmd()` removed non-functional security check; documented trust model.
- `init.sh` fixed `local` keyword used outside function scope.
- `drift-check.sh` replaced `eval` with `bash -c` for plugin execution.

### Changed

- All CLI output in English (previously Chinese).
- All internal variables renamed from `ASD_*` / `_ASD_*` prefix to `SH_*` / `_SH_*`.
- Spec template sections use English headers by default.
- Install paths changed from `.asd/` to `.specharness/`.

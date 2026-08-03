# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- `prismspec/skillpack.yaml` as the machine-readable PrismSpec skill pack contract.
- `halo/kernel/doctor.sh` to verify installed Halo/PrismSpec project health.
- `pipeline.sh --json-out[=<file>]` to write structured eval run evidence under `halo/state/eval-runs/`.
- `--json-out[=<file>]` for AC coverage, drift check, and compliance gates, embedded into pipeline eval runs.
- `eval-summary.sh` to render eval run JSON into Markdown for local review and CI Step Summary.
- `eval-history.sh` to aggregate eval run JSON files into a Markdown trend report.
- `eval-sink.sh` to publish eval runs, outcome links, and Markdown reports to a local central eval sink with per-project manifests and an index.
- `eval-dashboard.sh` to render a static HTML dashboard from the central eval sink.
- `eval-query.sh` to query central eval sink summaries, runs, and outcomes as Markdown or JSON.
- `outcome-link.sh` to link post-run review findings, rework, escaped defects, incidents, or success signals back to eval runs under `halo/state/outcomes/`.
- `outcome-report.sh` to render outcome attribution signals, context references, severity distribution, and runs needing review.
- Loop state JSON under `halo/state/loops/`, embedded into eval runs and summarized in eval reports.
- Failure category and default action fields in loop state, eval summaries, and escalation learn drafts.
- Configurable failure categories via `halo/config/failure-categories.yaml`.
- `failure-category-lint.sh` and doctor integration for failure category config validation.
- Escalation knowledge drafts under `halo/context/drafts/` when retry budget is exhausted.
- `learn-draft.sh` to promote or discard confirmed knowledge drafts with archived source drafts and audit events under `halo/state/learn-promotions/`.
- `knowledge-review.sh` to record approve/reject reviewer decisions under `halo/state/knowledge-reviews/`; `learn-draft.sh promote --require-review` can require approved review evidence with conflict checks.
- `summary-learn-draft.sh` to convert Knowledge Candidates into reviewable knowledge drafts.
- `knowledge-lint.sh` to flag missing metadata, missing sources, placeholders, conflict markers, expired entries, and duplicate headings in project knowledge.
- `pr-comment.sh` to create or update a stable GitHub PR comment from the eval Markdown summary.
- `install.sh --dry-run` and `install.sh --version` for safer install diagnostics.
- `tests/release-check.sh` as the maintainer release readiness command.
- `SECURITY.md`, `SUPPORT.md`, GitHub issue templates, and a pull request template for public project operations.
- `spec-state-lint.sh` to validate spec front matter and status-to-artifact readiness.
- `spec-status.sh` to advance spec lifecycle status with guarded transitions, stale-state protection, and JSON transition events.
- `spec-history.sh` to aggregate spec transition events into a Markdown lifecycle report.
- `plan-lint.sh` to validate AC-traced implementation plans before task execution starts.
- `task-next.sh` to resolve the next incomplete plan task as text or JSON for implementation recovery.
- `task-complete.sh` to mark individual plan tasks complete only after required task evidence exists.
- `task-evidence-lint.sh` to require brief, review package, and TDD evidence for completed implementation tasks.
- `summary-draft.sh` to generate `summary.md` completion drafts from spec, plan, verification, task evidence, and optional eval JSON.
- `review-summary.sh` and `tdd-evidence.sh` to capture process evidence as structured JSON.
- GitHub Actions eval artifact workflow template installed by `init.sh --ci=github`.
- **PrismSpec** standalone spec-coding skill pack with guided `/prismspec`, canonical `SKILL.md` files, templates, references, and workflow scripts.
- Chinese-first project entrypoint via the root `README.md`; English documentation moved to `README.en.md`.
- CI validation for PrismSpec skill frontmatter and PrismSpec shell scripts.
- Root `AGENTS.md` to make the repository easier for coding agents to navigate.
- `examples/py-fastapi/`, a runnable Python/FastAPI example that doubles as the route parser
  regression guard, run by `tests/release-check.sh`. Its routers carry the registration shapes
  real FastAPI projects use — empty-path collection root, `"/"` form, multi-line decorator,
  multi-line router prefix — and `try-it.sh` asserts every spec route resolves, so a parser
  that understands only one shape fails there instead of in a target project.

### Changed

- README and wiki now describe pipeline/gate eval JSON, central eval sink, loop state, outcome links/reports, configurable failure categories, failure category lint, escalation knowledge drafts, knowledge draft promotion/discard, knowledge governance lint, review/TDD process evidence, Markdown summaries/history, GitHub Actions artifacts, Step Summary, and PR comments as implemented.
- Default architecture and glossary knowledge templates now include `Source` columns for promotion governance.
- Default project knowledge templates now include `owner`, `verified_at`, and `applies_to` front matter.
- PrismSpec now treats `spec.md#Context Basis` as the default per-spec context contract instead of a separate `context.md` artifact.
- Plan lint now enforces a stricter task schema with AC coverage, mode/scope, evidence paths, done conditions, stable task order, and TDD red-test ordering.

### Fixed

- `drift-check.sh` no longer drops FastAPI/Express route registrations it cannot read on a
  single line with a non-empty path. `APIRouter(prefix="/model-sets")` + `@router.get("")`
  is how FastAPI registers a collection root — the decorator path is empty and the prefix
  carries the whole URL — and the `path must start with /` guard dropped the registration
  before prefix expansion, so a route that exists in code was reported as drift. Decorators
  and `APIRouter(...)` calls spanning several lines were invisible for the same reason:
  grep matches one line at a time. Both are now read, and the guard fails open. The
  predicate came from the spec side, where dropping a row means one fewer comparison; on
  the code side it removes the evidence a route exists and manufactures a failure.
  `AGENTS.md` gains a `## Gate Rules` section so the direction is not re-inverted.
- Spec auto-discovery no longer ranks candidates by file mtime. `git merge`, `checkout`, `rebase`,
  and `stash pop` rewrite mtime on every file they check out, so `ls -t` flipped the "current spec"
  after any git operation — including the merge that normally precedes final verification. The
  whole toolchain (`pipeline.sh` and four gates via `find_spec`, plus `prismspec/bin/guide.sh`)
  then verified an unrelated spec and wrote a structurally complete eval run whose `spec_file`,
  `spec_hash`, and AC coverage all belonged to that other spec, with nothing printed anywhere.
  New `halo/kernel/spec-select.sh` ranks on front matter instead: in-flight specs outrank
  `verified` ones, then the newest `updated_at` wins. It announces the selection and the
  candidates it beat, refuses to guess on an exact tie, and falls back to mtime only when no spec
  declares `updated_at` — saying so when it does.
- `pipeline.sh` prints the resolved spec with how it was chosen, and eval run JSON gains
  `spec_source` (`explicit` / `manifest-active` / `auto`) and `spec_source_detail`;
  `guide.sh --json` gains `spec_source`. An auto-discovered spec is a guess, and a run that
  verified the wrong spec is otherwise indistinguishable from a real pass.
- `learn-draft.sh promote` now writes into table-shaped knowledge files as table rows. The shipped
  default target `halo/context/knowledge/pitfalls.md` is a `| Pitfall | Trigger | Guidance | Source |`
  table followed by `## Do Not Repeat`, so appending a `## Promoted Learn Draft` section to EOF put
  the lesson outside the table it was meant to extend — and `knowledge-lint.sh` could not see it,
  because the file already carries a `Source` column at file level. Promotion metadata is no longer
  copied into the knowledge file; it already lives in the audit event under
  `halo/state/learn-promotions/`. Section-shaped targets keep the previous append behavior.
- `drift-check.sh` no longer reports an unchecked dimension as a clean one. Gate JSON gains
  `metrics.checks_run`, `metrics.checks_skipped`, and `metrics.checked.{ddl,routes,error_codes,seed_sql}`,
  and the verdict line names the dimensions that were NOT verified.
- `drift-check.sh` error code drift now reads upper snake-case codes (`REFERENCE_IN_USE`) from the
  error code table, not only numeric ones, and scans source files by project language instead of
  hardcoded `*.go`. The default spec template ships `| {ERROR_CODE} | … |`, so the numeric-only
  reader silently skipped every spec written from the framework's own template.
- `drift-check.sh` locates the route table method/path columns by header name instead of fixed
  column position, and implements route drift detection for FastAPI and Express — both of which
  `init.sh` already detects and writes into the manifest.
- `drift-check.sh`, `ac-coverage.sh`, and `pipeline.sh` no longer assign the project language to
  `LANG`, which is the locale environment variable and left every child process in an invalid locale.
- `review-package.sh` now covers committed work via `--base=<ref>` (default: merge base with the
  repository's default branch), staged changes, and untracked file content. A project that commits
  per task — the SDD discipline the framework itself prescribes — previously got an empty package.
- `compliance.sh` source trace recognises the Chinese source categories used by the default spec
  template, which previously produced a permanent warning on every spec written from that template.
- `plan-lint.sh` placeholder detection no longer fires on REST path parameters (`{set_id}`),
  f-strings, or a line containing both `<` and `>` as comparisons, and now does detect the Chinese
  template placeholders (`{条件}`) that the previous ASCII-only pattern could not match.
- `knowledge.sh` splits a quoted multi-word argument (`knowledge.sh "vite IPv6"`) on whitespace
  instead of matching it as one literal substring. Agent-facing docs spell this argument
  `<keywords>`, so a single quoted string is what callers actually pass, and it previously
  matched only when every word sat adjacent on the same line.
- `knowledge.sh` reads each knowledge file directly instead of piping its content into `grep -q`.
  The early exit of `grep -q` raised SIGPIPE, and under the `set -o pipefail` inherited from
  `_lib.sh` that turned a real match inside a file larger than the pipe buffer into a reported
  miss — the same failure mode fixed earlier in `task-complete.sh`.
- `knowledge.sh` matches keywords literally (`grep -F`), so a `.` in a keyword no longer
  wildcard-matches and an unbalanced `[` no longer makes grep error out into silence.
- PrismSpec guide now requires actual verification evidence and no longer treats review packages as verification output.
- Public contribution docs now use Halo naming and current paths.
- CI now runs the Go/Gin/GORM example and release readiness check in addition to smoke tests.

## [1.0.0] — 2026-06-23

### Added

- **Engine-agnostic architecture**: Generic phase names (design → plan → implement → verify → deliver) replace engine-specific coupling. Workflow engine integration via adapter docs.
- **Configurable spec-lint**: `specs.required_sections[]` and `specs.risk_categories[]` in manifest.yaml — override defaults without touching kernel code.
- **Three-layer architecture**: Orchestrator (rules injection), Knowledge (context retrieval), Delivery (gate pipeline) — each independently pluggable.
- **5 delivery gates**: spec-lint, ac-coverage, drift-check, compliance, spec-lock.
- **AC tracing**: Acceptance Criteria numbering from spec through test naming to coverage verification.
- **Knowledge layer**: Keyword-based retrieval with synonym support, central repo sync.
- **Multi-language support**: Go (Gin/GORM), Node (Express/Prisma), Python (FastAPI/SQLAlchemy), Rust detection.
- **Agent skills**: project setup, verification, and knowledge capture.
- **Escalation protocol**: Exit code 2 triggers human intervention after retry exhaustion.
- **Adapter documentation**: Engine-specific integration guides under `docs/adapters/`.

### Fixed

- `_find_project_root()` now walks up directories instead of using hardcoded relative path.
- `run_cmd()` removed non-functional security check; documented trust model.
- `init.sh` fixed `local` keyword used outside function scope.
- `drift-check.sh` replaced `eval` with `bash -c` for plugin execution.

### Changed

- All CLI output in English (previously Chinese).
- Internal delivery variables standardized on the `SH_*` / `_SH_*` prefix.
- Spec template sections use English headers by default.
- Install paths standardized for the Halo harness-template layout.

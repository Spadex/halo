# Project Context Map

## Project Snapshot

- Project purpose: small Python/FastAPI example that exercises the Halo gates against the
  route registration styles real FastAPI projects use.
- Core domain objects: model set, model set member.
- Main modules: FastAPI routers, business error codes, AC-traced tests.
- High-risk flows: route drift between the spec API table and `APIRouter` registrations.

## Where To Find Context

| Need | Read |
|------|------|
| Architecture and module boundaries | `knowledge/architecture.md` |
| Rules and contracts | `knowledge/rules.md` |
| Historical pitfalls | `knowledge/pitfalls.md` |
| Naming conventions | `knowledge/glossary.md` |
| External references | `external.md` |

## Loading Policy

- Start from the sample spec and current code.
- Use project knowledge only when it affects AC coverage, drift checks, or naming decisions.
- Do not copy full files into specs; cite the relevant source and decision impact.

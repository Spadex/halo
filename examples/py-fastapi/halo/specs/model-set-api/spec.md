---
id: model-set-api
title: Model Set API
status: drafted
template: service
execution_mode: plan
mode_source: model-selected
approval: inferred
owner: halo-example
created_at: 2026-08-03T00:00:00Z
updated_at: 2026-08-03T00:00:00Z
---

# Spec: Model Set API

## Intent

Build a small CRUD API for model sets and demonstrate how Halo validates spec structure, AC-to-test traceability, route drift, and error code drift against a FastAPI project that uses the framework's ordinary registration styles.

## Scope

### In

- List, create, read, rename, and delete a model set.
- List model set members.
- Verify route, error code, and AC traceability through Halo gates.

### Out

- Authentication and authorization.
- Real database integration setup.
- Pagination, soft delete, and audit events.

## Context Basis

| Source | Constraint / Fact | Impact |
|--------|-------------------|--------|
| code / tests | `app/routers` already registers routes through `APIRouter` prefixes, and tests carry AC numbers. | Use Plan Mode and verify with existing gates. |
| `halo/context/knowledge/pitfalls.md` | A collection root is registered as `@router.get("")`, and a router prefix may span several lines. | The API table lists full URLs; drift-check must resolve prefix plus decorator path. |
| open questions / conflicts | None. | No blocking decision required. |

## Acceptance Criteria

| # | Given | When | Then | Verification |
|---|-------|------|------|--------------|
| AC-1 | API server is running | GET `/api/model-sets` | Returns 200 with the model set collection | `test_ac1_list_model_sets` |
| AC-2 | API server is running | POST `/api/model-sets` with a valid body | Returns 201 with the created model set | `test_ac2_create_model_set` |
| AC-3 | No model set exists for the requested id | GET `/api/model-sets/{set_id}` | Returns 404 with `MODEL_SET_NOT_FOUND` | `test_ac3_get_model_set_not_found` |
| AC-4 | A model set exists | DELETE `/api/model-sets/{set_id}` | Returns 204 and the model set is no longer retrievable | `test_ac4_delete_model_set` |

## Contract Surface

### API Design

| API | Method | Path | Description | Auth |
|-----|--------|------|-------------|------|
| API-1 | GET | /api/model-sets | List model sets | No |
| API-2 | POST | /api/model-sets | Create model set | No |
| API-3 | GET | /api/model-sets/{set_id} | Get model set by id | No |
| API-4 | PUT | /api/model-sets/{set_id} | Rename model set | No |
| API-5 | DELETE | /api/model-sets/{set_id} | Delete model set | No |
| API-6 | GET | /api/model-set-members | List model set members | No |

### Error Codes

| 错误码 | 触发条件 | HTTP |
|--------|----------|------|
| MODEL_SET_NOT_FOUND | `set_id` does not exist | 404 |
| MODEL_SET_NAME_CONFLICT | The name is already taken | 409 |
| MODEL_SET_IN_USE | The model set is referenced by a running job | 409 |

### Data Model

```sql
CREATE TABLE `model_sets` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL,
  `description` varchar(500) NOT NULL DEFAULT '',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

## Design Decisions

| # | Decision | Rationale | Alternatives | Reversible? |
|---|----------|-----------|--------------|-------------|
| D-1 | Put the resource in the `APIRouter` prefix and register the collection root as `@router.get("")`. | Standard FastAPI style; keeps the collection URL free of a trailing slash. | Repeat the resource in every decorator path | yes |
| D-2 | Use string error code constants rather than numeric codes. | Readable in logs and stable across services. | Numeric codes | yes |

## Risks And Invariants

| Risk / Invariant | Mitigation | Verification |
|------------------|------------|--------------|
| Route/spec drift | Keep API rows and `APIRouter` registrations aligned. | `drift-check.sh` |
| Error code drift | Every code in the spec table exists in `app/errors.py`. | `drift-check.sh` |
| AC/test drift | Test names must include stable AC ids. | `ac-coverage.sh` |
| SQLAlchemy DDL is not compared | The gate reports the DDL dimension as NOT verified instead of clean. | `drift-check.sh` verdict line |

## Execution Policy

- Mode: `plan`
- Reason: This is a low-risk example with existing AC-named tests and no high-risk state transitions.
- Source: `model-selected`
- Escalation: `plan -> tdd` allowed if a regression or high-risk invariant is introduced; `tdd -> plan` requires explicit user override.

## Verification Plan

| Gate / Test | Required? | Evidence |
|-------------|-----------|----------|
| spec-lint | yes | Directory layout, Context Basis, required sections |
| prismspec-lint | yes | PrismSpec spec contract |
| AC coverage | yes | AC-1 through AC-4 map to tests |
| drift check | yes | Route and error code alignment; DDL reported as NOT verified |
| unit test | yes | `pytest -q` |

## Open Questions

- [x] None for the example.

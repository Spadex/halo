# {Title}

---

## Part I — Background & Goals

### 1.1 Background & Goals

{One sentence: what to build and why}

### 1.2 Naming Conventions

| Layer | Style | Example |
|-------|-------|---------|
| API JSON fields | camelCase | `bizId`, `userId` |
| Go struct fields | PascalCase, acronyms uppercased | `BizID`, `UserID` |
| DB columns | snake_case | `biz_id`, `user_id` |
| Go json tags | camelCase | `json:"bizId"` |
| Go gorm tags | column:snake_case | `gorm:"column:biz_id"` |
| Error code constants | Err + PascalCase | `ErrNotFound` |
| URL paths | kebab-case + resource name | `/api/v1/{service}/{resource}` |

---

## Part II — Technical Design

### 2.1 Technical Design

**Tech stack:** {language / framework / ORM / cache}

### 2.1.1 Architecture Diagram

```mermaid
graph TB
    %% Architecture: show layers, module dependencies, external services
```

### 2.1.2 Core Sequence Diagram

> Number steps ①②③…, use alt blocks for exceptions, annotate transaction boundaries and lock key formats.
> Financial operations must follow: create order → mutate state → update status.

```mermaid
sequenceDiagram
    %% Core flow sequence diagram
```

### 2.1.3 Runtime Environment

| Category | Item | Description |
|----------|------|-------------|
| Dependencies | {lib} | {purpose} |
| Infrastructure | {MySQL/Redis/...} | {connection info} |

### 2.2 API Design

#### 2.2.1 Unified Response Format

```json
{
  "code": 0,
  "message": "success",
  "data": {}
}
```

| Field | Type | Description |
|-------|------|-------------|
| code | int | 0=success, non-zero=error code |
| message | string | Human-readable message |
| data | object | Business data, omitted on error |

#### 2.2.2 Error Codes

| code | HTTP Status | Meaning | Trigger |
|------|-------------|---------|---------|
| 0 | 200 | Success | — |
| 400 | 400 | Bad request | Missing required fields |
| 500 | 500 | Internal error | Database/cache failure |

<!-- Add business-specific error codes as needed -->

#### 2.2.3 API Endpoint Details

> Common prefix `/api/v1/{service}`, no JSON `//` comments.

| API | Method | Path | Description | Auth |
|-----|--------|------|-------------|------|

<!--
Per API format:
**API-{n}** `{METHOD} {path}` — Header: `X-User-ID: xxx` (if auth required)

Request (for write endpoints):
```json
{ formatted }
```

| Field | Required | Description | (field table for key write endpoints)

Response:
```json
{ formatted }
```
-->

### 2.3 Data Model

> ER diagram shows relationships and cardinality only — field details are in the DDL (single source of truth).

```mermaid
erDiagram
    %% Table relationships
```

#### 2.3.1 DDL

```sql
-- Complete CREATE TABLE with indexes, COMMENTs, charset utf8mb4
```

#### 2.3.2 Index Design

| Table | Index | Purpose | Covers |
|-------|-------|---------|--------|
| | | | {API number or sequence diagram step} |

### 2.4 Design Alternatives

> Keep only decisions with real trade-offs. Obvious choices get a one-liner.

<!--
Example:
**Tech stack**: Go + Gin (high concurrency, single binary), MySQL + GORM (straightforward).

#### 2.4.1 {Decision with trade-offs}

| Dimension | Option A | Option B | Option C |
|-----------|----------|----------|----------|
| {dimension} | | | |
| **Decision** | ✅ Selected — {rationale} | ❌ | ❌ |
-->

---

## Part III — Quality Assurance

### 3.1 Acceptance Criteria

> Given-When-Then + table-driven, grouped by scenario.
> AC numbers are globally unique, cross-referenced with sequence diagram steps.

#### {Scenario group: happy path}

Given {preconditions}

| # | When | Then | Ref step |
|---|------|------|----------|
| AC-1 | | | |

#### {Scenario group: validation}

Given {preconditions}

| # | Condition | Then | code |
|---|-----------|------|------|
| AC-n | | | |

#### {Scenario group: failure compensation}

Given {preconditions}

| # | Failure point | Then (state) | Then (funds/side effects) |
|---|--------------|--------------|--------------------------|
| AC-n | | | |

#### Queries

| # | When | Then |
|---|------|------|
| AC-n | | |

#### Engineering Quality & NFR

| # | Verification command / condition | Expected |
|---|----------------------------------|----------|
| AC-n | `go build ./...` | Zero errors |
| AC-n | `go vet ./...` | Zero warnings |
| AC-n | `go test ./...` | All PASS |

### 3.2 Risk Review

> AI auto-populates the "Design basis" column from the spec. Reviewer verifies: ① each item assessed ② references accurate.

| Category | Review Item | Status | Design Basis |
|----------|-------------|--------|-------------|
| **Financial Safety** | Transaction log | | |
| | Idempotency | | |
| | Audit trail | | |
| | Refund/reversal | | |
| | Reconciliation | | |
| | ROI | | |
| | Budget | | |
| | Probability monitoring | | |
| | Opening/closing balance | | |
| **Technical Risk** | Rate limiting | | |
| | API caching | | |
| | Cron job dependencies | | |
| | Slow SQL / full table scan | | |
| | Message queue failure | | |
| | Risk control integration | | |
| **Data Risk** | Tenant data isolation | | |
| | High-risk DML | | |
| | Character encoding | | |
| | Cross-period idempotency | | |
| | Concurrency consistency | | |
| **Release Process** | Acceptance verified | | |
| | Canary capable | | |
| | Rollback capable | | |
| **Other** | Multi-tenancy design | | |

### 3.3 Test Strategy

- **Unit tests**: {coverage scope}
- **Integration tests**: {coverage scope, AC numbers}
- **Concurrency tests**: {coverage scope, AC numbers}

---

## Part IV — Release

### 4.1 Release Checklist

| # | Action | Owner | Notes |
|---|--------|-------|-------|

**Seed SQL:**

```sql
-- Complete INSERT statements
```

### 4.2 Rollout & Rollback

> Early stage: one paragraph is fine. Expand to canary table + rollback plan when real traffic exists.

---

## Decision Log

> AI collects all decisions requiring human confirmation during the design phase.
> Confirmed items marked ✅. Unconfirmed items use "default decision" for coding; adjustable later.

| # | Decision | Impact | Default | Status |
|---|----------|--------|---------|--------|
| D-1 | | | | Pending |

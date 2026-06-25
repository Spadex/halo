# Go + Gin + GORM Example

A minimal runnable example demonstrating Lattice with a Go API project.

## What's Included

```
examples/go-gin-gorm/
├── manifest.yaml                      # Lattice project config
├── go.mod                             # Go module (mock, not buildable)
├── lattice/
│   ├── specs/
│   │   └── create-item-api.md         # Sample spec with AC-1 through AC-4
│   └── knowledge/
│       ├── index.md                   # Knowledge index
│       └── naming-rules.md            # Sample knowledge entry
├── internal/
│   ├── model/item.go                  # GORM model (matches spec DDL)
│   └── handler/item.go               # Gin route registration
└── tests/
    └── item_test.go                   # Tests named TestAC1_ through TestAC4_
```

## Try It

```bash
# From the repo root:
cd examples/go-gin-gorm

# Run individual gates:
bash ../../scaffold/lattice/kernel/delivery/gates/spec-lint.sh lattice/specs/create-item-api.md
bash ../../scaffold/lattice/kernel/delivery/gates/ac-coverage.sh lattice/specs/create-item-api.md .
bash ../../scaffold/lattice/kernel/delivery/gates/drift-check.sh lattice/specs/create-item-api.md .
bash ../../scaffold/lattice/kernel/knowledge/loader.sh naming
```

## What You'll See

- **spec-lint**: Validates that the spec has all required sections, sequential AC numbers, risk review
- **ac-coverage**: Maps AC-1 through AC-4 to `TestAC1_CreateItem`, `TestAC2_GetItem`, etc. — 100% coverage
- **drift-check**: Compares spec DDL columns against GORM model tags — no drift
- **knowledge loader**: Searches "naming" → returns `naming-rules.md`

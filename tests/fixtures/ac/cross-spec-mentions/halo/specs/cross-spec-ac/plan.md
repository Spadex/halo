# Plan: Cross Spec AC

## Source

- Spec: `halo/specs/cross-spec-ac/spec.md`
- Execution mode: tdd

## Global Constraints

- Versions / dependencies: use existing Go module.
- Out-of-scope: upstream-spec AC-14, already covered by the upstream spec.

## Tasks

- [ ] RED-1: Add failing tests for AC-1, AC-2 and AC-3
  - Ref: AC-1, AC-2, AC-3
  - Expected failure: handler implements none of the three paths yet
  - Discriminating power: contrast the list shape against upstream-spec AC-14
  - Test file: `internal/handler/item_test.go`
  - Verification: `go test ./internal/handler -run TestXsAC`
  - Done when:
    - [ ] All expected failures are captured in task evidence.

- [ ] T1: Add the three handler behaviors
  - Ref: AC-1, AC-2, AC-3
  - Mode: tdd
  - Scope: Implement the smallest paths needed for AC-1 through AC-3.
  - Files: `internal/handler/item.go`
  - Verification: `TestXsAC`
  - Evidence:
    - Brief: `.halo/sdd/cross-spec-ac/T1/brief.md`
    - Review package: `.halo/sdd/cross-spec-ac/T1/review-package.md`
  - Done when:
    - [ ] AC-1 through AC-3 pass focused verification and evidence exists.

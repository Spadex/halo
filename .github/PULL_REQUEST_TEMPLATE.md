## Summary

- 

## Validation

- [ ] `bash -n init.sh install.sh tests/*.sh $(find harness-template prismspec/bin -name '*.sh')`
- [ ] `shellcheck --severity=warning init.sh install.sh tests/*.sh $(find harness-template prismspec/bin -name '*.sh')`
- [ ] `bash tests/smoke-test.sh`
- [ ] `bash examples/go-gin-gorm/try-it.sh`
- [ ] `bash prismspec/bin/lint.sh prismspec skillpack`
- [ ] `git diff --check`
- [ ] `bash tests/release-check.sh`

## Release Impact

- [ ] Public docs updated where behavior changed
- [ ] Chinese README and English README stay aligned
- [ ] Install/upgrade behavior preserves project-owned files
- [ ] No secrets, tokens, private data, or machine-local paths added

## Notes

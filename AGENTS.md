# Lattice Agent Guide

## Role

This repository is the source repository for Lattice, a Chinese-first AI Coding framework. It is not a target project that already uses Lattice.

## Priorities

- Keep the public product experience Chinese-first while preserving English docs for international readers.
- Treat `prismspec/skills/*/SKILL.md` as the canonical PrismSpec skill source.
- Treat flat files under `prismspec/skills/*.md` and `scaffold/lattice/skills/*.md` as compatibility entry points.
- Preserve the install boundary: `scaffold/` is copied into target projects; project-owned data must not be overwritten on upgrade.

## Common Checks

```bash
bash -n init.sh install.sh tests/smoke-test.sh $(find scaffold prismspec/bin -name '*.sh')
shellcheck --severity=warning init.sh install.sh tests/smoke-test.sh $(find scaffold prismspec/bin -name '*.sh')
bash tests/smoke-test.sh
```

## Documentation Rules

- Root `README.md` is the Chinese default entry.
- `README.en.md` is the English entry.
- Keep wiki pages concise and design-oriented.
- Do not leave old project names, obsolete paths, or one-off implementation notes in public docs.

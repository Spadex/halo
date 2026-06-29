# Security Policy

## Supported Versions

Lattice is currently in an early preview stage. Security fixes are applied to the default branch first and should be consumed by upgrading from the latest public release or commit.

| Version | Supported |
|---------|-----------|
| latest preview | Yes |
| older commits | Best effort |

## Reporting A Vulnerability

Please do not disclose security issues in public issues before maintainers have had a chance to investigate.

Report suspected vulnerabilities with:

- a short description of the issue;
- affected files, commands, or generated artifacts;
- reproduction steps;
- impact assessment;
- whether credentials, private code, or user data may be exposed.

If no private disclosure channel is available yet, open a minimal public issue that states "security report requested" without exploit details. The project should establish a private contact before a stable commercial release.

## Security Boundaries

Lattice is a repo-local engineering harness:

- It does not intentionally upload source code, specs, context, or eval evidence.
- It writes artifacts into the target repository, including `lattice/`, `prismspec/`, and optional `.claude/` command files.
- It executes project-configured commands from `lattice/manifest.yaml`; treat those commands as trusted project code.
- It does not sandbox build, lint, test, or custom gate commands.
- It should not be used to store secrets in `spec.md`, `plan.md`, `review.md`, `verify.md`, context knowledge, or eval JSON.

## Release Readiness

Before promoting a release to stable, maintainers should verify:

- the public install URL is accessible without local credentials;
- release artifacts are versioned and reproducible;
- generated artifacts do not include credentials;
- installation, doctor, smoke test, and runnable examples pass from a fresh clone.

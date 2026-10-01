# Security Policy

## Scope

Claude Remainder reads local Claude Code OAuth credential material to request quota usage data.

## Supported versions

The latest `main` branch is supported.

## Report a vulnerability

Please open a private security advisory in GitHub, or contact maintainers directly if listed in the repository profile.

When reporting, include:

- Affected version/commit
- Reproduction steps
- Impact description
- Suggested mitigation (if known)

## Sensitive data handling expectations

- Never include full tokens, refresh tokens, or keychain dumps in reports.
- Redact account identifiers when possible.
- If you suspect keychain ACL weakness, include only metadata and command traces.

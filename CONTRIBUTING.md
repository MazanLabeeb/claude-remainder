# Contributing

Thanks for your interest in contributing to Claude Remainder.

## Setup

1. Clone the repository.
2. Run `swift test` and `swift build`.
3. Build a local app with `./scripts/build-app.sh release`.

## Development guidelines

- Keep runtime dependencies at zero.
- Prefer native macOS APIs (AppKit/Foundation/Security).
- Do not introduce telemetry or external data collectors.
- Keep idle resource usage minimal.

## Pull request checklist

- [ ] Tests pass (`swift test`)
- [ ] App builds (`swift build`)
- [ ] No credentials or secrets logged
- [ ] README/docs updated when behavior changes

## Reporting issues

Please include:

- macOS version
- Claude Code version
- Repro steps
- Relevant logs (without tokens or secrets)

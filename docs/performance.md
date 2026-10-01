# Performance Notes

Claude Remainder is designed to stay idle most of the time.

## Measurement method

1. Build release app: `./scripts/build-app.sh release`
2. Launch app and let it idle for 5 minutes with auto refresh disabled.
3. Open `Resource Usage…` to confirm in-app metrics.
4. Cross-check with macOS Activity Monitor.
5. Trigger `Refresh All` and observe short CPU/network burst.

## Baseline targets

These are practical targets for review and regressions.

- Idle CPU (manual mode): near 0%
- Idle memory footprint: typically under 40 MB
- Background timers when manual mode is selected: none
- Resource sampler overhead: active only while Resource Usage window is open
- Refresh behavior: bounded concurrency (1-4), backoff after repeated failures

## What to watch for in PRs

- Added polling loops or short-interval timers
- Unbounded concurrent network requests
- Growing snapshot cache or duplicate writes
- UI redraw churn without new data

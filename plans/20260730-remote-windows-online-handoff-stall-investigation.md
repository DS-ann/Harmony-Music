# Investigate Windows online handoff stalls

## Goal

Determine why a song selected on Android can leave Windows permanently loading
when Android has a local copy but Windows must resolve and play an online
source.

## Steps

1. Add deterministic emulator integration coverage where Android selects a
   local-file item, Windows resolves the same id to an online source, and the
   first Windows load is deliberately stalled.
2. Send a second Android selection through the normal controller and cloud
   command path. Verify the newer selection supersedes the stalled one instead
   of leaving Windows in loading state.
3. Add a regression case for a delayed-but-successful Windows online source,
   including the expected loading UI and transition to ready.
4. After server access is supplied, correlate client handoff diagnostics with
   cloud session commands, resolver metadata requests, audio-source requests,
   and any ingestion work for the affected song ids.
5. If the server confirms a client-side stale-load race, implement cancellation
   and bounded failure handling for the obsolete playback generation, then
   extend the regression assertions.

## Boundaries

- Tests use simulated ids and sources only.
- Run on the Android emulator; never use the physical phone.
- Do not expose URLs, tokens, cookies, or server credentials in diagnostics.

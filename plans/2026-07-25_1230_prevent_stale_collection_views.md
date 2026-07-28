# Prevent stale collection views

## Summary

Keep the playlist fix and apply the same listener pattern to Album screens as preventive hardening. No other confirmed stale-state paths were found.

## Key changes

- Keep `playlistController.songList` in the playlist screen’s merged rebuild listener.
- Add `albumController.songList` to the Album screen’s corresponding merged listener.
- Do not alter repository, removal, download, queue, or library mutation behavior.

## Test plan

- Retain the playlist removal regression test.
- Add a matching listener-wiring regression test for the Album screen.
- Run focused playlist/album tests and targeted analysis.

## Assumptions

- Album hardening is intentionally preventive: it protects future direct `songList` mutations without changing today’s behavior.
- The audit scope is Flutter observable collections and their immediate rendering surfaces; no backend sync behavior changes are included.

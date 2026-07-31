# Test remote Home-selection queue replacement for offline and online tracks

## Summary

Add three deterministic integration tests for Android controlling Windows. Each
begins with an existing phone-to-Windows handoff, then simulates selecting a
new Home song on the phone and verifies Windows replaces playback with that
song and its queue.

## Test setup

- Reuse the fake cloud/socket bridge, a real source `PlayerController`, and a
  headless Windows `CloudPlaybackReceiver`.
- Simulate the Home/watch response for the selected replacement song as
  `[selected, next, next]`.
- Resolve the shared IDs on Windows as an all-local `file://` queue, an
  all-online `https://` queue, and a mixed local/online queue.
- Record the media item supplied to Windows's audio handler so each case proves
  the expected source type reached the target.

## Scenarios

1. Hand off initial queue `[A, B]` from Android to Windows and confirm Windows
   is playing `A`.
2. Simulate the phone selecting Home song `C`; its generated queue is
   `[C, D, E]`.
3. Verify Windows immediately switches to `C`, enters loading at `0:00` while
   its source is delayed, then starts without a pause/play workaround.
4. Verify the final Windows queue and durable cloud session are exactly
   `[C, D, E]`; no initial `[A, B]` items remain.
5. Send Next from the phone and confirm Windows plays `D` using the expected
   offline/online source for the scenario.

## Boundaries

- Tracks and source URLs are simulated; no real files, music backend, cloud
  infrastructure, or physical device is used.
- The real source controller selection path, queue update, handoff command,
  cloud receiver, metadata-resolution boundary, and target audio-command path
  are exercised.
- Production behavior changes only if the tests expose a real replacement-path
  regression.

# Fix Windows handoff supersession during online loading

## Goal

Allow a newer explicit Android-to-Windows handoff to replace an unresolved
Windows online playback start, without reintroducing duplicate replay from
session snapshots.

## Implementation

1. Track the identity of the currently starting target playback request:
   its session id, selected song, ordered queue, and selected index.
2. When an incoming start request has the same identity, join the existing
   future so duplicate socket/REST delivery and session refreshes do not restart
   playback.
3. When an explicit handoff has a different identity, invalidate the old
   playback generation and begin the new request immediately. The old async
   metadata/audio load becomes stale and cannot update the target when it
   settles.
4. Clear the tracked start identity only when the matching start future ends.
5. Preserve existing queue, loading, and error behavior otherwise.

## Tests

- Keep the delayed Windows-online source test for an Android-local selection.
- Make the stalled-first-load then newer-Android-tap regression pass.
- Add coverage that identical start requests continue to join rather than
  creating a second playback start.
- Run the focused and full remote integration suite on the Android emulator,
  plus Flutter analysis.

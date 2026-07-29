# Keep cloud playback metadata and loading position consistent

## Summary

Make the audio target authoritative for the current song's presentation so both
devices show the same title, artist, album, artwork, duration, playback state,
and position.

## Implementation

- Keep cloud queues compact and ID-only.
- Require live target progress frames to carry a compact current-song metadata
  block containing the song ID, title, artist, album, artwork URI, and duration.
- Apply metadata only when its song ID matches the current progress song ID and
  the controller's current or pending song, preventing stale cross-song updates.
- Replace the matching controller queue item with the target's resolved metadata
  so the full player, mini-player, artwork, and duration agree on both devices.
- Hold the progress bar at the intended loading position:
  - New song selections and Previous start at zero.
  - Handoffs retain the transferred position.
  - Same-song restarts and seeks retain the requested position.
- Keep the timer fixed at that position until the target reports playback ready.
- Preserve the complete queue when selecting a song during remote control so the
  target does not collapse to a one-item queue and Previous remains available.
- Both dev builds will move to the new frame contract together; no legacy frame
  compatibility path is required.

## Verification

- Test matching and mismatching metadata blocks.
- Test target metadata replacement in the controller queue.
- Test loading at zero and at a non-zero handoff position.
- Test remote standalone selections retain the full queue.
- Run focused cloud/player tests and `flutter analyze --no-pub`.

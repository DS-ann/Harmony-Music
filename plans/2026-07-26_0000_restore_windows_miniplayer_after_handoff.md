# Restore the Windows mini-player after device handoff

## Summary

Ensure an incoming handoff initializes the visible player shell before
resolving or starting audio, so Windows shows the selected song's mini-player
immediately.

## Implementation Changes

- Add a `PlayerController` entry point for incoming cloud songs that:
  - Installs the resolving placeholder.
  - Initializes the collapsed player height through the existing panel helper
    without auto-opening the full player.
  - Restores mini-player visibility and opacity when the panel is collapsed.
  - Leaves an already-open full player unchanged.
- Call this entry point from `CloudPlaybackReceiver` before awaiting metadata
  resolution.
- Add `loading` to `LocalPlaybackCommands.progressFrame()`, which is the frame
  source actually used by the receiver.
- Delegate or share progress-frame construction between local and forwarding
  command facades so their payloads cannot diverge again.
- Preserve the current Android optimistic selection, stale-frame protection,
  and shimmer behavior.

## Interface Changes

- Replace the target's direct
  `setCurrentSongResolving(...pendingSong:)` call with the new incoming-song
  preparation method.
- Keep the existing optional `loading` field in cloud progress frames; no
  server or persisted-session schema change is required.

## Test Plan

- Verify an incoming handoff initializes a non-zero wide-screen mini-player
  height before metadata resolution.
- Verify collapsed visibility and opacity are restored on Windows, while an
  open full player is not forcibly collapsed.
- Verify receiver progress frames report loading during metadata resolution,
  buffering, and source loading.
- Run `flutter analyze --no-pub` and the complete `flutter test --no-pub` suite.
- Manually verify Android to Windows handoff: audio starts and the Windows
  mini-player appears immediately with shimmer, then resolved metadata.

## Assumptions

- The missing UI is the collapsed Windows mini-player after selecting the
  laptop in "Play on device."
- Incoming handoffs should reveal the mini-player but should not automatically
  open the full player on Windows.

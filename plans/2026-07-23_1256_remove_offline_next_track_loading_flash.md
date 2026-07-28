# Remove the Offline Next-Track Loading Flash

## Summary

The flicker does not occur on `main`. The current branch changed
`_emitSourceStartedSnapshot()` from `ready` to `loading`, even though
`_player.load()` has already completed. For offline files, the subsequent real
`ready` event arrives milliseconds later, producing the visible spinner flash.

## Implementation Changes

- Restore `_emitSourceStartedSnapshot()` to publish
  `AudioProcessingState.ready`, matching `main`.
- Continue showing loading while source lookup and `_player.load()` are
  genuinely pending through the existing playback-event stream.
- Keep the pending-source transition guard and restored-session fix unchanged.
- Do not introduce a minimum spinner duration or debounce; cached/offline
  tracks should transition directly to playing when already ready.

## Test Plan

- Restore the regression assertion that a successfully loaded source emits
  `ready`, not `loading`.
- Run focused audio-handler and player-controller tests.
- On Android, repeatedly press Next through downloaded songs and verify no
  spinner flashes before playback.
- Verify network songs still show loading while resolving/buffering.
- Verify Windows source switching, restored paused sessions, and playback
  errors remain correct.

## Assumptions

- Completion of `_player.load()` is the authoritative ready boundary on every
  supported backend.
- The Windows audio-output fix does not require overwriting that completed
  state with a synthetic loading snapshot.

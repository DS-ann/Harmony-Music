# Fix cross-device song loading feedback on Android

## Summary

Make song changes feel immediate during remote playback: both the controlling
Android device and the playback target will switch to the selected song's
loading presentation immediately, show shimmer and loading controls throughout
resolution/buffering, and ignore stale updates from the previous song.

## Implementation Changes

- Add a pending remote-song transition to `PlayerController`, keyed by song
  ID/generation:
  - Optimistically select the tapped song, reset progress, and enter loading
    before sending the remote command.
  - Ignore delayed progress/session frames for the previous song.
  - Allow rapid selections to supersede older pending transitions.
  - Clear loading only when a matching settled frame arrives; on command
    failure, restore the last confirmed mirrored state.
- On the target device, publish the incoming song as a resolving placeholder
  before metadata lookup so its player changes immediately instead of showing
  the previous song.
- Extend cloud progress frames with a non-sensitive `loading` flag derived from
  resolving, loading, and buffering state. Keep compatibility with peers that
  do not yet send the field.
- Make `setCurrentSongResolving(false)` derive the button state from both
  processing and playing state, ensuring a timed-out-but-still-buffering source
  remains visibly loading.
- Use one loading predicate—metadata placeholder or active song resolution—for
  the full player and mini-player title/artist shimmer. Keep the existing
  play-button spinner and album-art loading overlay synchronized with it.
- Apply the optimistic transition to standalone song taps and playlist/index
  selections only while remote control is active; local playback behavior
  remains unchanged.

## Interface Changes

- Cloud `progress` frames gain an optional boolean `loading`.
- `PlayerController` gains explicit begin/confirm/fail helpers for pending cloud
  song transitions; these remain internal UI coordination APIs and do not alter
  persisted session data.

## Test Plan

- Verify a remote song tap immediately updates the controller's selected song,
  resets progress, and shows shimmer/loading.
- Verify the target shows the incoming placeholder and loading state before
  metadata/audio resolution completes.
- Verify stale frames and snapshots from the previous song cannot revert either
  UI.
- Verify matching `loading: true` frames retain loading and matching settled
  frames clear it.
- Verify rapid consecutive song selections retain only the newest transition.
- Verify command failure restores the last confirmed mirrored state and does
  not leave a permanent shimmer.
- Verify timeout/buffering paths keep loading visible until the audio handler
  reports readiness or error.
- Run focused cloud/player widget tests, `flutter analyze`, and the relevant
  `flutter test` suite.
- Manually test Android-to-Android transfers in both directions, including slow
  network resolution and repeated random song selections.

## Assumptions

- "Both devices" means the device issuing the remote selection and the device
  producing audio.
- Shimmer applies to the mini-player and full-player song metadata while the
  play button and album art retain their existing loading indicators.
- Existing uncommitted repository work will be preserved.

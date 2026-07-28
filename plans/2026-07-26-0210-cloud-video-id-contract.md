# Make the cloud playback video-ID contract explicit

## Summary

Cloud playback must identify playable YouTube videos, never generic song,
playlist, album, or browse entities. `MediaItem.id` currently contains the
video ID for playable songs, but its generic name and lack of validation make
the contract easy to violate.

## Implementation

- Add a shared playback video-ID validator for the 11-character YouTube ID
  format.
- Require cloud session queue items to be playable and to contain valid video
  IDs.
- Validate externally supplied cloud queue IDs and the current video ID before
  constructing a session payload.
- Use explicit `queueVideoIds` and `currentVideoId` terminology inside the
  command service.
- Preserve the server's existing `queueIds` and `currentSongId` JSON keys; their
  values are formally defined as video IDs.
- Add tests proving valid video IDs pass and album, playlist, browse, empty, and
  malformed identifiers are rejected.

## Verification

- Run focused cloud session, playback-role, and loading-feedback tests.
- Run `flutter analyze --no-pub`.

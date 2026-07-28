# Refresh the active playlist after song removal

## Summary

The playlist screen rebuilds from its controller and downloader, but not from `songList`. Removal mutates `songList` directly, so the view can remain stale unless another controller notification happens coincidentally.

## Key changes

- Update the playlist screen’s rebuild listener to include `playlistController.songList`.
- Keep the existing removal paths unchanged: local, Piped, downloaded, cached, favorites, and multi-select removal will all refresh through the same observable list notification.
- Preserve existing thumbnail and persistence behavior; this change only makes the visible playlist state react immediately to successful list mutations.

## Test plan

- Add a focused widget/state regression test that removes an item from the active playlist list and verifies the screen reflects the reduced item count and no longer renders that song.
- Run the focused Flutter test and the existing playlist-related test suite.

## Assumptions

- “Remove a song” covers both the song action sheet/slidable action and batch removal while the affected playlist screen is open.
- Cloud playlists remain out of scope because their current UI does not expose this local removal path.

# Account-scoped library: Songs filtering, clean account switch, visible sign-out

## Context

The Songs tab is `getAllLibrarySongs()` — `SongsCache` + `SongDownloads`
([hive_library_repository.dart:74](lib/data/repositories/hive_library_repository.dart:74)) — with no
account dimension at all. Both boxes are device-local, so the tab means "every audio file this
device holds": deliberate downloads and anything incidentally cached while streaming, belonging to
nobody. Liked songs live in `LIBFAV`, which *is* account-synced, but nothing connects the two.

There is also no account identity stored locally — no `accountId`, no `userSub` anywhere in `lib` —
and `logout()` clears only the Auth0 session. So a second account inherits the first account's
synced library, and the sync bookkeeping (`cloudCheckpoint`, `cloudSyncState` fingerprints) is
silently reinterpreted as the new account's. The next fingerprint reset — which a
`cloudSyncSchemaVersion` bump performs deliberately — would upload the previous account's library
into the new one.

Finally, an expired session is invisible: `tryRestoreSession()` returns null, sync starts failing,
and nothing tells the user.

## The keystone: a stored account subject

One new pref — the Auth0 subject of the account this device's library belongs to — resolves all
three problems, and every rule below reads from it.

| Stored subject | Session | Meaning |
|---|---|---|
| absent | none | never signed in — Songs shows everything |
| absent | restored by `init()` | **upgrade**: seed the subject quietly, same account |
| absent | new interactive `login()` | first sign-in — ask merge or replace |
| present | matches | normal |
| present | different subject signs in | **account switch** — wipe |
| present | none, sync enabled | **silently signed out** — tell the user |

The upgrade row matters: your current install has been signed in for days with no subject stored.
Without it, everyone gets a spurious "merge or replace" dialog on first launch of the new build.
Seeding on a *restored* session and prompting only on an *interactive* login is what separates them.

## Songs filtering

Three inputs decide the list:

| | Never signed in | Signed in, or signed out with a last account |
|---|---|---|
| Downloads | all | liked only |
| Cached | only with "include cached" | liked only, and only with "include cached" |

Both toggles ("show downloads not in your library", "include cached songs") compose with the liked
filter rather than special-casing it. Signing out does **not** change what Songs shows: the last
account's likes are still on the device, so the view stays put and the toggles still reveal
everything.

**"In your library" means `LIBFAV` and nothing else.** A downloaded song sitting in a playlist or a
saved album but never liked stays hidden from Songs — it still plays normally from that playlist.
One rule, one cheap lookup, and no per-build scan across every playlist and album song box.

When the filter leaves the list empty, the empty state explains that Songs shows downloads in your
library and offers a button that flips "show downloads not in your library" — otherwise a user with
downloads and no likes sees a blank tab and concludes their music is gone. On a device that has
never been signed in the toggle would do nothing, so hide it there.

- `LibraryRepository` gains a filtered read so the liked lookup happens once against `LIBFAV`
  instead of per song. Keep `getAllLibrarySongs()` for its other callers.
- `LibrarySongsController`
  ([library_controller.dart:37](lib/ui/screens/Library/library_controller.dart:37)) holds the toggle
  values, reads them from `SettingsRepository` on init, and re-reads the list when either changes.
  It already has `_settingsRepository`.
- Toggles render in `SortWidget` ([sort_widget.dart:196](lib/ui/widgets/sort_widget.dart:196)),
  already the Songs toolbar and already carrying feature flags like `isSearchFeatureRequired`. Add
  an opt-in filter control the same way so no other screen using `SortWidget` changes; follow
  `_customIconButton` for styling.
- New `PrefKeys` (`songsShowUnlikedDownloads`, `songsIncludeCached`, plus the subject and the dialog
  suppression below) with `SettingsRepository` accessors mirroring `getVolume`/`setVolume`.
  **Add every one to `_excludedPreferenceKeys`** in
  [cloud_sync_repository.dart](lib/data/repositories/cloud_sync_repository.dart) — they are
  device-scoped, and syncing them would apply one device's view to a different set of files.

## Download dialog

Only the explicit download button needs it —
[song_download_btn.dart:173](lib/ui/widgets/song_download_btn.dart:173). The two auto-download paths
([player_controller.dart:2184](lib/ui/player/player_controller.dart:2184),
[song_info_bottom_sheet.dart:648](lib/ui/widgets/song_info_bottom_sheet.dart:648)) fire *because*
the song was just liked, so they are already consistent and must stay silent — a modal in front of a
background action would be a bug.

Shown when a last account exists, the song is not liked, and the user has not dismissed it:
explain that downloads appear in Songs only when they are in the account's library, and offer
**Like and download** / **Download only**, with a "don't ask again" checkbox. Reuse
`CommonDialog`/`showDialog` as the settings dialogs do.

## First sign-in with an existing local library

On an interactive `login()` with no stored subject **and** a non-empty local library, ask once:

- **Merge** — keep this device's library and add it to the account (upload local, download remote).
  This is the "device I have been using offline" case.
- **Replace** — discard the device's synced library and take the account's. It clears the same boxes
  the account switch does and **keeps downloaded audio and cache**, so anything the account likes
  that is already on disk plays offline straight away.

With an empty local library, skip the dialog and merge silently; there is nothing to lose. Merge is
the no-op path — it is exactly what happens today when nothing is wiped.

## Account switch

In `AuthController` ([auth_providers.dart](lib/app/providers/auth_providers.dart)), before starting
sync, compare the stored subject with the one just signed in. Different → wipe, then sync fresh.

- The wipe clears the account-owned boxes — `LIBFAV`, `LIBRP`, `LibraryPlaylists`, `LibraryAlbums`,
  `LibraryArtists`, `LibrarySearches`, `blacklistedPlaylist`, `searchQuery`, and every per-playlist
  and per-album song box — plus `CloudSyncState`, `CloudSyncOutbox`, and `cloudCheckpoint`. Reuse
  `StorageAdminRepository.clearBoxes` and `PlaylistRepository.deletePlaylistSongBox`; enumerate the
  song boxes with the same `_songContainerBoxes()` logic the sync scan uses.
- **Downloaded audio and cache stay.** They are device-local; the filter handles visibility, and
  switching back restores the old view without re-downloading gigabytes.
- **Do not wipe `AppPrefs` wholesale** — it holds `cloudDeviceId` and the device-scoped sync
  bookkeeping. The new account's settings arrive per key through normal sync.
- **Keep `cloudDeviceId`.** Devices are scoped per account server-side, so the same id under a new
  account is a new row starting at sequence 0, and the client's own counter keeps rising — which the
  server already tolerates.
- **Reset `cloudCheckpoint` to 0**, or the new account's history is filtered out: `changes` is
  `revision > checkpoint`, and `cloud_revision_seq` is global across accounts, so the previous
  account's checkpoint sits arbitrarily far ahead of the new account's revisions. This is the same
  shape of dead end as the `sync_paused` bug.
- Offline edits made under the previous account go with the wipe. They belong to that account, and
  anything never synced is genuinely lost — which is why the sign-out notice below matters.
- **Logout wipes nothing**, so signing back into the same account keeps working offline.

## Making a silent sign-out visible

Detection: a stored subject, sync enabled, and no restorable session. Surface it two ways so
dismissing one does not hide the state:

- A dismissible banner on Library/Home: sync is paused, sign back in.
- A badge on the account row in Settings that persists until resolved.

Library edits stay **enabled** while signed out and queue in the outbox, so signing back into the
same account uploads them. `AuthController` already exposes `isAuthenticated` and `needsCloudOptIn`
for the settings UI to read; this adds one more piece of state alongside them.

## Verification

```bash
flutter analyze --no-pub
```

then `flutter test`, both via the `harmony-flutter-dart` MCP tools with `timeout_ms: 600000`.

Unit tests, following the Hive-backed pattern in
[test/cloud_sync_domains_test.dart](test/cloud_sync_domains_test.dart):

- never signed in lists all downloads; with a last account lists only liked ones
- signing out does not change the list
- "show all downloads" restores the unliked ones; cached stay out until their toggle is on and are
  still liked-filtered
- a downloaded song that is only in a playlist or saved album, never liked, stays hidden
- a restored session with no stored subject seeds it and prompts nothing (the upgrade path)
- an account switch clears the synced boxes, checkpoint and outbox while `SongDownloads`,
  `SongsCache` and `cloudDeviceId` survive
- the same subject signing in again wipes nothing

**End to end (user-run):** on the phone, confirm Songs shows only liked downloads and that signing
out leaves it unchanged; toggle each filter. Download an unliked song and confirm the dialog appears
once and not again after dismissing. Sign into a different account and confirm the library empties
while the audio files remain and nothing from the first account reaches the second. Let a session
expire (or revoke it) and confirm the banner and settings badge appear.

## Rollout order

1. The stored subject, including the upgrade seeding — everything else reads from it.
2. Songs filtering and toggles.
3. The download dialog.
4. First-sign-in merge/replace, then the account-switch wipe.
5. The sign-out banner and badge.

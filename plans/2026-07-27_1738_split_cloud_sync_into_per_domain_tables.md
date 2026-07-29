# Split Cloud sync storage into per-domain tables

## Context

Everything an account syncs — settings, favourites, playlists, songs, search history — lands in
two generic tables that differ only by an opaque string:

- `cloud_sync_events` — the append-only log. Serves sync (`changes` = rows with
  `revision > checkpoint`) and orders checkpoints.
- `cloud_snapshots` — current state per entity, last-write-wins. Written by `MergeSnapshotAsync`,
  deleted on account delete, and **never read by anything**.

In both, `entity_type` is the hardcoded literal `'hive-entry'` and the only thing distinguishing a
theme colour from a liked song is an `entity_id` prefix like `AppPrefs:ImxpYnJhcnlGaXJzdFRhYiI=`.
The database is unreadable without decoding base64 by hand, song metadata is duplicated across
five boxes, and there is no way to answer "what are my favourites" in SQL.

This replaces that with per-domain tables holding real columns, and takes downloads out of sync
entirely so they stay device-local.

## Decisions

- **Split both** the event log and the state tables per domain.
- **Real typed columns**, not jsonb blobs, for state.
- **One shared `cloud_songs` table** plus thin membership tables, instead of a copy of each song's
  metadata in every domain that references it.
- **Wipe and re-sync** rather than backfilling.
- **Downloads are device-local.** Also device-local, per follow-up: liked-not-downloaded, last
  playback session, import staging, lyrics cache.

## What syncs, and what no longer does

Synced (10 domains):

| Domain | Hive box | Key |
|---|---|---|
| `settings` | `AppPrefs` | pref key |
| `favourites` | `LIBFAV` | videoId |
| `recentlyPlayed` | `LIBRP` | int entry key |
| `playlists` | `LibraryPlaylists` | playlistId |
| `playlistSongs` | `<playlistId>` (one box each) | int entry key |
| `albums` | `LibraryAlbums` | browseId |
| `artists` | `LibraryArtists` | browseId |
| `savedSearches` | `LibrarySearches` | int entry key |
| `searchHistory` | `searchQuery` | int entry key |
| `blacklistedPlaylists` | `blacklistedPlaylist` | playlistId |

**Removed from sync** (`_staticBoxes` in [cloud_sync_repository.dart:20](lib/data/repositories/cloud_sync_repository.dart:20)):
`SongDownloads`, `LIBFAV_NOT_DOWNLOADED`, `prevSessionData`, `LIBIMPORT_DUPLICATES`,
`LIBIMPORT_REVIEW`, `lyrics`. This alone drops the bulk of the traffic — Windows' outbox is
currently 1,333 events of which **948 are `SongDownloads`**.

Removing `SongDownloads` also fixes the bug where songs downloaded on Windows showed as
"downloaded" on the phone with no file behind them.

## Revision strategy — the one non-obvious piece

Splitting the log per domain normally forces per-domain checkpoints, a wire-format change, and a
rebuild on every device before any device can sync. Avoid all of that with a **single Postgres
sequence shared by every event table**:

```sql
CREATE SEQUENCE cloud_revision_seq;
-- every cloud_events_* table:
revision bigint NOT NULL DEFAULT nextval('cloud_revision_seq')
```

Revisions stay globally monotonic across domains, so `checkpoint` remains one number and
`SyncRequest`/`SyncResponse` keep their current shape. The read path becomes a `UNION ALL` over the
domain event tables filtered on `account_id` and `revision > checkpoint`, ordered by `revision`,
limited to `MaxEventsPerSync`. Each table carries the same `(account_id, revision)` index, so this
stays cheap.

## Server — `C:\MyRepositories\Harmony-Cloud`

### Event tables

Ten tables (`cloud_events_settings`, `cloud_events_favourites`, …), all the same shape as today's
`cloud_sync_events`: `revision`, `account_id`, `event_id`, `device_id`, `device_sequence`,
`hlc_physical_ms`, `hlc_logical`, `entity_id`, `operation`, `payload jsonb`, `received_at`.
Payload stays jsonb — the log is an immutable record of what a device sent, and it is what serves
`changes`, so the client's `applyRemote` contract is unchanged.

Map one `SyncEventEntity` CLR type onto all ten via EF **shared-type entity types** rather than ten
near-identical classes:

```csharp
modelBuilder.SharedTypeEntity<SyncEventEntity>("SettingsEvent").ToTable("cloud_events_settings");
// accessed as db.Set<SyncEventEntity>("SettingsEvent")
```

### State tables

`cloud_songs(account_id, video_id, title, artists jsonb, album jsonb, duration_s, artwork_url,
year, date_ms, track_details jsonb, hlc_*, revision)` — PK `(account_id, video_id)`. Every domain
carrying song metadata upserts here under LWW; membership tables hold only the reference:

- `cloud_favourites(account_id, video_id, …)`
- `cloud_recently_played(account_id, entry_key, video_id, …)`
- `cloud_playlist_songs(account_id, playlist_id, entry_key, video_id, …)`

Non-song domains get their own typed tables: `cloud_settings(account_id, key, value jsonb)`,
`cloud_playlists(account_id, playlist_id, title, description, thumbnail_url, item_count,
is_piped, is_cloud)`, `cloud_albums`, `cloud_artists`, `cloud_saved_searches`,
`cloud_search_history`, `cloud_blacklisted_playlists`.

Every state table carries the LWW/bookkeeping columns already proven in `SnapshotEntity`:
`hlc_physical_ms`, `hlc_logical`, `hlc_device_id`, `tombstone`, `revision`.

### `SyncService` ([SyncService.cs](C:/MyRepositories/Harmony-Cloud/src/Harmony.Cloud.Api/Sync/SyncService.cs))

- Route each incoming event to its domain from `EntityType` (see client change below), replacing
  the single `db.SyncEvents.Add`.
- Replace `MergeSnapshotAsync` with a per-domain mapper: same `Compare` HLC precedence as today,
  but writing typed columns, and upserting `cloud_songs` for song-bearing domains.
- Keep `SyncPayloadPolicy.Normalize` on the payload before storing.
- **Unknown domains must be accepted and dropped, never rejected.** A device on an older build will
  keep sending `SongDownloads`/`lyrics` events until it is rebuilt; a 400 would wedge its sync
  permanently, exactly like the `sync_paused` bug did earlier today. Count them as accepted so the
  device's outbox drains, and write nothing.
- `AccountEndpoints` delete must clear all new tables.

### Migration

One EF migration that drops `cloud_sync_events` and `cloud_snapshots`, creates the sequence, the
ten event tables and the state tables. This is the "wipe" half of wipe-and-re-sync.

## Client — `C:\MyRepositories\Harmony-Music`

[cloud_sync_repository.dart](lib/data/repositories/cloud_sync_repository.dart):

- Cut `_staticBoxes` to the ten synced boxes.
- Add a box → domain map and set `entityType` to the domain when building each event in
  `_enqueue`, replacing the hardcoded `'hive-entry'` in
  [cloud_sync_event.dart](lib/services/cloud/cloud_sync_event.dart). `entityId` keeps its
  `Box:base64(key)` form — `applyRemote` still needs it to write back into Hive.
- Add `PrefKeys.cloudSyncSchemaVersion` and a matching constant. On sync start, if the stored value
  differs, clear the `CloudSyncState` fingerprints and the outbox and reset `cloudCheckpoint` to 0,
  then store the new version. This forces the one full re-upload that pairs with the server wipe.

Downloads becoming device-local needs two follow-through changes, or the phone keeps its 948
inherited path-less download rows forever:

- One-time purge of `SongDownloads` entries whose `url` is missing or points at no existing file.
- `isDownloaded` / `containsDownload` in
  [hive_library_repository.dart:104](lib/data/repositories/hive_library_repository.dart:104) and
  [hive_download_repository.dart:12](lib/data/repositories/hive_download_repository.dart:12)
  currently test key presence only. Make them require a usable local path, reusing the
  support-dir/permission logic already in `_downloadedStreamInfoForSong`
  ([audio_handler.dart:1302](lib/services/audio_handler.dart:1302)) rather than writing a new check.
  This also unblocks re-downloading, which `downloader.dart:206` currently skips for such rows.

## Verification

**Cloud:**

```bash
dotnet test Harmony.Cloud.slnx
```

The integration suite boots the real API against a throwaway Postgres via Testcontainers and runs
migrations ([CloudApiFixture.cs](C:/MyRepositories/Harmony-Cloud/tests/Harmony.Cloud.IntegrationTests/CloudApiFixture.cs)),
so the new migration and routing are covered end to end. Add cases for: an event of each domain
landing in its own table; a song referenced by both a favourite and a playlist producing exactly
one `cloud_songs` row; an unknown domain being accepted and dropped rather than 400'd; and
`UNION`-ordered `changes` still coming back in strict `revision` order across tables.
Rewrite `SyncPayloadPolicyTests` only if the payload contract changes (it should not).

**App** (via `harmony-flutter-dart` MCP, `timeout_ms: 600000`):

```bash
flutter analyze --no-pub
```

then `flutter test`. Add coverage for the box → domain mapping and for the schema-version reset
clearing fingerprints, checkpoint and outbox exactly once.

**End to end (user-run):** deploy Cloud, rebuild both apps, then confirm in SQL that settings land
in `cloud_settings` and songs in `cloud_songs`/`cloud_favourites`; that a song liked on the phone
appears on Windows; that a song downloaded on Windows does **not** show as downloaded on the phone;
and that `cloud_events_*` totals no longer include download or lyrics traffic.

## Rollout order

1. Deploy the Cloud schema first — it accepts-and-drops the domains old clients still send, so
   existing builds keep syncing what remains valid instead of breaking.
2. Rebuild and install both apps. The schema-version bump triggers one full re-upload per device.
3. Verify the tables, then spot-check the two-device behaviours above.

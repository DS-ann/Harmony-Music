# Full-metadata cloud sync + removal of the audio backup, repair and retry features

## Context

Cloud sync currently degrades the library on its way through the wire. The client strips local
paths and secrets (correct), but `SyncPayloadPolicy.RedactSongMetadata` in Harmony-Cloud then
strips `title`, `artists`, `album`, `duration` and `thumbnail` from **every object carrying a
`videoId`** — which is every song JSON, since `MediaItemBuilder.toJson` writes `"videoId"`. Those
redacted payloads are echoed back in the same sync response and `applyRemote` writes them over the
local rich entry, so a synced device ends up with id-only songs and letterboxed `hqdefault`
artwork. `LibraryMetadataRepairService` exists purely to clean up after this.

A `.hmb` local backup has no such problem: it copies the Hive files verbatim. The goal is to make
cloud sync carry the same descriptive metadata a local backup does, while still keeping
device-specific paths and secrets out of the cloud.

At the same time, three features are being retired:

- **Cloud audio backup** — the Resolver now ingests audio itself through its delegated downloader
  fleet, and (per the accepted Resolver plans `2026-07-26_0118_metadata_only_backfill` and
  `2026-07-26_1200_store_metadata_on_tracks`) fills track metadata server-side. Client-side uploads
  of downloaded files are redundant.
- **Repair library metadata** — unnecessary once sync stops degrading metadata.
- **Retry failed downloads** — removed entirely, including the failure-tracking store.

And *Export/Import clone package* becomes visible only under developer settings.

**No backfill/migration is needed:** the user confirmed nothing is in the cloud yet — this is still
a development feature with no real users.

## Decisions

- Cloud keeps: `title`, `artists`, `album`, `duration`/`length`, real artwork URLs, `date`, `year`,
  `trackDetails`. Cloud never receives: local file paths, stream/media URLs, tokens/secrets — the
  client's existing `_excludedPayloadKeys` already covers these and stays as-is.
- Harmony-Cloud is in scope (the redaction is server-side, there is no client-only fix), including
  removal of its audio broker endpoint. Harmony-Resolver is **not** modified.

---

## Part 1 — Harmony-Cloud: stop redacting song metadata

`C:\MyRepositories\Harmony-Cloud`

**`src/Harmony.Cloud.Api/Domain/SyncPayloadPolicy.cs`**
- Replace `SongMetadataProperties` with a much smaller stream/media URL deny-list:
  `streamUrl`, `audioUrl`, `mediaUrl`, `url`, `filePath`, `localPath`, `downloadPath` — defense in
  depth behind the client's own stripping. Keep `artwork`/`artworkUrl`/`thumbnail`/`thumbnails`.
- Drop the id-only collapse in `Normalize` for `entityType` `song`/`track` (the app only ever sends
  `hive-entry`, and the collapse contradicts the new policy). Keep the `IsVideoId` validation so a
  malformed `videoId` is still rejected with `invalid_video_id`.
- Rename `RedactSongMetadata`/`RedactObject` to reflect what they now do (strip URL-bearing fields),
  and update the class doc comment — "Prevents Cloud from becoming a duplicate song catalog" is no
  longer the policy.

**`src/Harmony.Cloud.Api/Persistence/CloudSchemaMigrator.cs`**
- Delete `RedactExistingSongMetadataAsync` / `ReplaceWithNormalizedPayload` and their call in
  `MigrateAsync`. This pass re-normalizes every event and snapshot on every startup; with the new
  policy it is pure dead weight, and nothing stored needs rewriting.

**`src/Harmony.Cloud.Api/Endpoints/AudioEndpoints.cs`, `src/Harmony.Cloud.Api/Audio/ResolverBackupClient.cs`**
- Delete both files, plus `builder.Services.AddHttpClient<ResolverBackupClient>()` and
  `cloud.MapAudioEndpoints()` in `Program.cs`, and the now-unused `using Harmony.Cloud.Api.Audio;`.
- Check `CloudOptions` for settings that become unused (`ResolverBaseUrl`, backup capacity knobs)
  and drop only those with no remaining reader.

**`tests/Harmony.Cloud.UnitTests/SyncPayloadPolicyTests.cs`**
- Rewrite the three cases: song metadata now **survives** normalization; embedded playlist items
  keep `title`/`artist`/`durationMs`; stream/media URL fields are still stripped; an invalid
  `videoId` inside a payload still throws `invalid_video_id`.
- Grep the integration tests for `/audio/next` and remove any coverage of the deleted endpoint.

> Note (not in scope): Harmony-Resolver's `internal/v1/backup-grants` + `v1/backup-uploads/{id}`
> subsystem (`BackupUploadEndpoints.cs`, `BackupCandidates` table) loses its only caller and becomes
> unreachable from clients. Ripping it out means an EF migration and is best done separately.

## Part 2 — Harmony-Music: client-side sync payload

**`lib/data/repositories/cloud_sync_repository.dart`**
- Remove the artwork-reconstruction block in `_sanitize` (the `hasArtwork` / `hqdefault.jpg` fallback,
  ~lines 217–231). Real artwork URLs now survive the round trip, and `MediaItemBuilder.fromJson`
  already synthesizes the same fallback at read time when artwork is genuinely absent — synthesizing
  it into the payload is what put letterboxed covers into the library in the first place.
- Leave `_excludedPayloadKeys` and the artwork-context `url` exception exactly as they are.
- Remove `audioBackupEnabled` / `setAudioBackupEnabled`.

## Part 3 — Harmony-Music: remove the cloud audio backup channel

- **Delete** `lib/services/cloud/cloud_audio_backup_service.dart`.
- `lib/services/cloud/cloud_sync_coordinator.dart` — drop the `_audioBackup` ctor arg and field,
  `audioBackupEnabled`, `setAudioBackupEnabled`, `backupAudioNow`, and the trailing
  `if (audioBackupEnabled) unawaited(_audioBackup.run());` in `_synchronizeCore`.
- `lib/services/cloud/harmony_cloud_client.dart` — delete `nextAudio` and `uploadAudio`; drop the
  now-unused `dart:io` import.
- `lib/app/providers/auth_providers.dart` — remove the `CloudAudioBackupService(...)` construction
  (~line 59), `cloudBackupRunning`, `cloudBackupProgress`, `cloudAudioBackupEnabled`,
  `setCloudAudioBackupEnabled`, `backupCloudAudioNow`.
- `lib/services/constant.dart` — remove `PrefKeys.cloudAudioBackupEnabled`.
- `lib/ui/screens/Settings/settings_screen.dart` — remove the "Downloaded-audio backup" toggle and
  the "Back up downloaded songs now" tile (~lines 254–302), the `_runCloudAudioBackup` helper
  (~line 1653) and its second call site (~line 1683), and the `cloud_audio_backup_service.dart` import.
- **l10n** — delete `downloadedAudioBackup`, `downloadedAudioBackupDescription`, `cloudBackupNow`,
  `cloudBackupInProgress`, `cloudBackupProgress` (+ its `@` metadata) from `lib/l10n/app_en.arb` and
  `lib/l10n/app_hr.arb`, then regenerate `lib/l10n/app_localizations*.dart`
  (`flutter gen-l10n`; these files are committed). `test/localization_sync_test.dart` enforces
  en/hr key parity.
- **pubspec** — `battery_plus` and `connectivity_plus` have no other importer; remove both deps and
  run `flutter pub get`. Re-grep before deleting to confirm.
- `test/large_restore_and_ui_fixes_test.dart` — delete the assertions on
  `CloudAudioBackupResult.*` / `class CloudAudioBackupProgress` /
  `CloudAudioBackupProgress? cloudBackupProgress` (lines ~12–15, 39, 42).

## Part 4 — Harmony-Music: remove "Repair library metadata"

- **Delete** `lib/services/library_metadata_repair_service.dart`,
  `lib/data/repositories/hive_library_repair_repository.dart`, and
  `test/library_metadata_repair_test.dart`.
- `lib/app/providers/repository_providers.dart` — remove `libraryRepairRepositoryProvider` (~line 71).
- `lib/app/providers/service_providers.dart` — remove `libraryMetadataRepairServiceProvider` (~line 81).
- `lib/ui/screens/Settings/settings_screen.dart` — remove the "Repair library metadata" tile
  (~line 303–318), the `_runLibraryRepair` helper (~lines 42–110) and the service import.

## Part 5 — Harmony-Music: remove the failed-download retry mechanism entirely

- **Delete** `lib/domain/repositories/download_retry_repository.dart`,
  `lib/data/repositories/hive_download_retry_repository.dart`, and
  `test/download_retry_store_test.dart`.
- `lib/services/downloader.dart` — drop the `_retryRepository` ctor param/field,
  `failedDownloadCount`, `retryFailedDownloads()` (~line 248), `_rememberFailedDownload` /
  `_removeFailedDownload` (~lines 525–535) and their three call sites (lines ~288, ~352, ~615).
  Where a failure was remembered, keep the existing logging so failures remain diagnosable.
- `lib/app/providers/repository_providers.dart` — remove `downloadRetryRepositoryProvider` (~line 43);
  `lib/app/providers/service_providers.dart` — drop the arg at ~line 59.
- `lib/services/constant.dart` — remove `BoxNames.downloadFailures`; then remove its
  `Hive.openBox` in `lib/main.dart` (~line 232) and every list entry in
  `lib/data/repositories/hive_storage_admin_repository.dart` (`backupBoxNames`, `reopenCoreBoxes`,
  and the clear/scan lists at ~lines 14, 70). Existing `DownloadFailures.hive` files stay on disk,
  unopened and harmless.
- `lib/ui/screens/Settings/settings_screen.dart` — remove the "Retry failed downloads" tile
  (~lines 1182–1202). If `downloader` is then unused in `build`, drop the `ref.watch`.
- **l10n** — remove `retryFailedDownloads`, `retryFailedDownloadsDescription` and the
  `@retryFailedDownloadsDescription` placeholder block from both ARBs; regenerate. Keep the generic
  `retry` string (used elsewhere).
- `test/downloader_metadata_test.dart:54` — delete the
  `contains('Future<void> retryFailedDownloads()')` assertion.

## Part 6 — Clone package behind developer settings

`lib/ui/screens/Settings/settings_screen.dart` (~lines 1332–1360): extend both guards from
`if (RuntimePlatform.isAndroid)` to
`if (RuntimePlatform.isAndroid && settingsController.developerSettingsEnabled.value)`, and gate the
preceding `Divider()` the same way so no stray separator remains. `developerSettingsEnabled` is the
same `ObservableValue` the Resolver-backend section already gates on (~line 318), so no new state is
needed. Leave `exportDeveloperClonePackage` / `importDeveloperClonePackage` in the controller
untouched.

---

## Verification

**Harmony-Music** (use the `harmony-flutter-dart` MCP tools, always with `timeout_ms: 600000`):

1. `dart({args: ["format", "lib", "test"]})`
2. `flutter({args: ["pub", "get"]})` after the pubspec edit
3. `flutter({args: ["gen-l10n"]})` after the ARB edits
4. `flutter({args: ["analyze", "--no-pub"]})` — must be clean; unused imports/fields are the main
   risk in a removal-heavy change
5. `flutter({args: ["test"]})` — `localization_sync_test`, `downloader_metadata_test` and
   `large_restore_and_ui_fixes_test` are the ones this change touches

**Harmony-Cloud:**

```bash
dotnet test Harmony.Cloud.slnx
```

**End-to-end (user-run, per the standing rule — I do not launch the app):** with a locally running
Cloud API, log in on one build, enable cloud sync, let it sync a few songs, and confirm on the
second device that titles, artists, albums, durations and real (square) artwork arrive intact rather
than as id-only placeholders. Then check Settings shows no "Downloaded-audio backup", no "Back up
downloaded songs now", no "Repair library metadata", no "Retry failed downloads", and that
Export/Import clone package appears only once developer settings are on.

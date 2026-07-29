# Library Metadata Repair + Parser Root Fix

## Problem

Cloud sync propagated two metadata defects across every signed-in device and
overwrote good local copies (because `applyRemote` writes synced payloads
verbatim into Hive):

1. **Type token in artists** — `parseSongRuns` (`lib/services/nav_parser.dart`)
   adds the leading subtitle run as an artist. For search card-shelf / unfiltered
   search results whose subtitle is `"Song • Artist • …"`, the type word
   (`"Song"`/`"Video"`) becomes `artists[0]` → `"Song, Lil Baby"`. Pre-existing
   bug (nav_parser is not part of the cloud branch); sync made it visible and
   sticky.
2. **Letterboxed thumbnails** — `CloudSyncRepository._sanitize` injects
   `i.ytimg.com/vi/<id>/hqdefault.jpg` for any song that reaches sync without an
   artwork field. `hqdefault` is letterboxed for music-video sources. Only the
   subset of songs that lacked real artwork are affected.

Search forces `hl='en'`, so the leaked token is always an English type word.
Re-fetching a song via `getSongWithId` (watch-playlist path) returns clean
artists and real square thumbnails.

## Fixes

### 1. Parser root fix (prevent recurrence)
In `parseSongRuns`, skip a leading run (index 0, no `navigationEndpoint`) whose
text is a known English result-type label (`song, video, album, single, ep,
playlist, artist, station`). Guarded so it only drops a genuine type token, never
a real artist. Unit-tested.

### 2. Repair migration (heal existing data)
New `LibraryMetadataRepairService`:
- Recursively walks the song-bearing Hive boxes (`libFav`,
  `libFavNotDownloaded`, `libRP`, `songDownloads`, `prevSessionData`,
  `homeScreenData`, and every library playlist box), mutating song Maps in place.
- **Artist strip (local, instant):** remove `artists[0]` when it is an id-less
  known English type label. Re-put changed box values. Counts fixed songs.
- **Thumbnail re-fetch (network, best-effort, throttled):** collect song Maps
  whose stored thumbnail is the injected `hqdefault.jpg`; re-resolve each unique
  videoId via the music service, patch `thumbnails` with the real URL. Failures
  leave the existing fallback untouched. Bounded + sequential to avoid hammering.
- After repair, trigger a cloud sync so the cleaned payloads re-upload and
  converge every device.

### 3. Settings trigger
A "Repair library metadata" action in Settings that runs the service with a
progress indicator and reports how many songs were fixed. User-initiated (not
automatic) because the thumbnail phase does network work over the whole library.

## Testing
- `flutter analyze` on all touched files.
- Unit test: `parseSongRuns` drops the leading `"Song"`/`"Video"` token but keeps
  a real leading artist (id-less artist that is not a type label).
- Unit test: repair walk strips the token from a nested song Map and leaves clean
  songs unchanged.

## Notes
- Non-destructive: artist strip is a pure local transform; thumbnail phase only
  replaces the known-bad `hqdefault` fallback.
- `_sanitize`'s hqdefault injection stays (reasonable last resort); after repair,
  real artwork exists so it no longer triggers for those songs.

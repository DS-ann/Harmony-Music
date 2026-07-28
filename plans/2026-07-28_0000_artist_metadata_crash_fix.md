# Retain only the artist-metadata crash fix

## Summary

The full earlier feature is no longer needed. Recent Resolver work now fetches rich YouTube Music
metadata, preserves artist/album IDs and square artwork, backfills old Resolver records, and purges
thin app cache entries once.

Do not add another artwork-selection system, app-side YouTube Music lookup, or metadata-quality
race. If letterboxed artwork persists after deployment, investigate Resolver rollout/backfill state
rather than player layout.

The logged exception remains possible: `MediaItemBuilder` still stores raw artist strings in
`extras`, while `SongInfoBottomSheet` calls `containsKey` on every entry.

## Implementation Changes

- Normalize `MediaItemBuilder` artist metadata into `{name, id?}` maps before storing it in
  `extras`.
- Preserve valid artist IDs and names; convert legacy strings to id-less maps and discard malformed
  entries.
- Defensively type-check artist entries in both `SongInfoBottomSheet` consumers so directly
  constructed or legacy `MediaItem` values cannot crash.
- Show artist navigation only when a non-empty artist ID exists.
- Leave artwork rendering, thumbnail selection, Resolver preference, cache purge, and cloud
  contracts unchanged.

## Interfaces

- No public API or persistence migration.
- Continue accepting both legacy string artists and the new Resolver map format.

## Test Plan

- Test mixed string/map/malformed artist normalization.
- Test that opening song information with legacy string artists does not throw.
- Test that artist navigation remains available for map entries with IDs and is omitted for id-less
  entries.
- Run the focused tests and `flutter analyze --no-pub`; Flutter could not be run during the review
  because it was not available on the shell `PATH`.

## Assumptions

- The rich Resolver deployment and its metadata backfill will be rolled out as implemented.
- Video artwork remains the intentional fallback when YouTube Music has no release cover.

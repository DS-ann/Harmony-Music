# Decouple device control, data sync, and audio backup

## Accepted outcome

Signing in registers the current Harmony installation with the authenticated
Harmony Cloud account independently of library synchronization or downloaded
audio backup. The account can therefore discover its Windows and Android
devices as soon as both have signed in.

## Changes

- Keep the existing `cloudSyncEnabled` preference as the data-sync preference.
  It controls synchronization of sanitized Hive-backed user data only:
  library entries, liked songs, playlists, albums, artists, searches, lyrics,
  queue/session data, and safe preferences.
- Add a separate persisted `cloudAudioBackupEnabled` preference for downloaded
  audio. Audio upload remains opt-in, Wi-Fi/battery gated, one file at a time,
  and is sent directly to Resolver storage using Cloud-issued short-lived
  grants. Cloud itself does not store the audio bytes.
- On authenticated startup and login, register and refresh the current device
  with Harmony Cloud regardless of either backup preference. Device records
  remain account-scoped and contain only a generated device id, automatic
  platform/name, and app version; they never contain raw Auth0 subjects,
  credentials, paths, media URLs, or playback payloads.
- Start the existing command receiver whenever an authenticated app is
  running. It polls the authenticated command endpoint independently of data
  synchronization so foreground Windows/Android clients can acknowledge
  handoffs. Keep the existing Android FCM registration independent of data
  synchronization as the background-reachability path.
- Split Settings wording and controls into device control, data sync, and
  downloaded-audio backup. Preserve the existing Cloud data opt-in prompt as
  the decision for data synchronization, not device registration.

## Verification

- Generate localization code after updating English and Croatian strings.
- Run focused Cloud/controller tests and `flutter analyze` where practical.
- Manual check: sign in on Windows and Android with data sync and audio backup
  disabled; both installations appear in the device picker. Enable data sync
  and confirm likes/playlists synchronize. Enable downloaded-audio backup and
  confirm only then does Resolver receive audio upload requests.

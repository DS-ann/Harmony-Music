# Windows + Android Cloud Release and Cross-Device Playback

## Summary

Deliver one production milestone with reliable GitHub rolling and stable releases for Windows and Android, a validated Harmony Cloud backup/sync foundation, and Spotify-style account-based playback handoff plus persistent remote control.

Harmony Cloud remains the backend. Appwrite is not introduced. Android uses FCM only to wake a signed-in background Harmony installation; commands and playback data remain in Harmony Cloud.

## Key Changes

- Replace the separate release workflows with one release pipeline:
  - Every `main` push builds signed Android APK and signed Windows installer, then updates one `main-latest` prerelease containing both platform assets.
  - Every `vX.Y.Z` tag builds and publishes both matching assets in one stable GitHub release.
  - Derive version/channel/build metadata consistently from `pubspec.yaml` and CI run number; make Windows installer metadata follow the release version instead of its current hard-coded legacy version.
  - Configure Auth0, Resolver, Cloud, issue-report, Android signing, and Windows code-signing inputs in CI; verify signatures and installable artifacts before publishing.
  - Make in-app update checks select the current platform’s asset and channel.
  - Fix Windows Auth0 availability so a signed-in Windows installation can use Cloud, sync, and device control.

- Complete and productionize Harmony Cloud backup/sync:
  - Validate the existing authenticated device registration, durable outbox, checkpoint synchronization, conflict merge, pause, account deletion, and audio-backup contracts against deployed Harmony Cloud.
  - Keep cloud data portable and sanitized: no credentials, tokens, local paths, stream URLs, visitor IDs, or cached media metadata.
  - Ensure first sync merges local and remote data without destructive replacement; restore/download behavior remains platform-safe.
  - Keep audio backup policy and failure handling: Wi-Fi/battery gating, one-at-a-time uploads, resumable retry behavior, actionable authentication/network/service errors, and no user-visible secrets.

- Add an account-based device-control protocol to Harmony Cloud:
  - Extend device records with platform, automatic display name, app version, FCM registration/token metadata, heartbeat/presence state, and last-seen timestamps.
  - Add authenticated SignalR real-time connections for active Harmony clients; persist short-lived, idempotent command envelopes in PostgreSQL so FCM-woken Android clients can fetch and acknowledge them.
  - Add device-list, presence, FCM-token registration, command submission, command acknowledgment, and playback-state endpoints/hub messages.
  - Use opaque FCM data messages containing only a command ID. Harmony Cloud resolves the authenticated account/device relationship and never puts playback payloads, Auth0 tokens, or media URLs in FCM.
  - Treat commands as unavailable rather than queued when the target cannot acknowledge within the defined delivery timeout. A failed handoff leaves playback on the source device.

- Add Harmony Music cross-device playback:
  - Add a Devices button to both mini and full player. Its sheet lists signed-in account devices using automatic platform/device names and states: current, online, background-reachable, or unavailable.
  - Selecting a device performs a handoff: serialize only portable playback state—logical queue identifiers, current index, position, play state, speed, shuffle/repeat, and supported volume state—then start the target and pause the source only after target acknowledgment.
  - Once handed off, keep the sender as a remote controller: play/pause, seek, previous/next, queue changes, playback mode, and supported volume changes are sent to the target; target playback state updates the sender UI.
  - The target replaces any existing playback immediately, as selected. Local-only paths, downloaded-file references, and temporary resolver URLs are never transferred; the receiving device resolves playable media itself.
  - Keep account-based device control separate from local Listen Together sessions. Existing Bluetooth/Wi-Fi party behavior remains unchanged.

- Add Android background delivery:
  - Register and rotate the FCM token while the user is signed in and Cloud is enabled; remove/invalidate it on logout, account deletion, and failed delivery.
  - Receive high-priority opaque wake-up messages in Android native/Flutter background handling, reconnect to Harmony Cloud, fetch/acknowledge the command, and start or update the existing media-playback foreground service.
  - Show only the standard ongoing media notification when remote playback starts; no separate alert.
  - Define availability honestly: FCM enables a normally backgrounded Android app to wake, but a force-stopped, revoked, offline, or OS-restricted app is unavailable. Windows is reachable while its process remains running, including minimized-to-tray.

## Test Plan

- Automated Harmony Music tests for Cloud sanitization, sync/outbox replay, first-merge behavior, device listing, presence transitions, handoff serialization, target acknowledgment/timeout, remote command ordering/idempotency, source-pause-after-ack, and localized device-picker states.
- Automated Harmony Cloud tests for account isolation, JWT authorization, device/token lifecycle, SignalR authorization, command persistence/expiry, FCM payload redaction, delivery acknowledgement, and account deletion.
- CI tests build and sign Android and Windows rolling/stable artifacts, verify correct asset names/version metadata, and exercise update-asset selection per platform.
- Physical Android/Windows matrix:
  - Same account, both foreground: handoff and continuous remote control.
  - Windows minimized to tray: Android controls Windows playback.
  - Android backgrounded: Windows handoff wakes Android, starts playback, and displays the media notification.
  - Target offline, force-stopped, or acknowledgement timeout: sender reports unavailable and source playback continues.
  - Different accounts cannot discover or control each other.
  - Cloud backup/sync persists across Android and Windows without transferring paths, secrets, or invalid media references.
- Run `flutter analyze`, full `flutter test`, Android release build/install smoke test, Windows release installer install/launch smoke test, Harmony Cloud unit/integration tests, and deployed production health/command smoke tests.

## Assumptions

- GitHub Releases is the distribution channel for both platforms: rolling `main-latest` assets and versioned stable assets.
- Harmony Cloud continues to use the shared Auth0 audience and existing Platform deployment path.
- FCM is an Android-only wake-up dependency, not the Cloud data store or command authority.
- No additional Cloud/FCM consent text is added; existing Cloud enablement gates device-control registration.
- An accepted version of this plan will be saved as a timestamped file under `plans/` before implementation begins.

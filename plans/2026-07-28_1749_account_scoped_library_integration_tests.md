# End-to-end integration tests for account-scoped library

## Context

The account-scoped library work (stored subject, Songs filtering, the unliked-download dialog,
account switch, sign-out visibility) is covered only at the unit level today —
`songs_tab_filter_test.dart` and `account_switch_test.dart` call repository/coordinator methods
directly against real Hive boxes. Nothing exercises the actual widgets: no dialog has been shown,
no toggle has been tapped, `AuthController.login()`/`init()` have never run, and the merge/replace
and session-expiry paths — the two pieces flagged as unverified — have no coverage at all.

Two things stand in the way of testing this for real, both established patterns in this codebase
already:

1. **`AuthController` depends on the concrete `Auth0Service`**, not an interface. Every other
   external boundary (`MusicServiceContract`, `AppPlatformContract`, `UpdateServiceContract`,
   `FilePickerContract` in [app_contracts.dart](lib/services/app_contracts.dart)) is behind a
   contract precisely so `integration_test/support/fakes.dart` can stand in for it. Auth is the one
   exception, and it's exactly the boundary this feature lives behind.
2. **`HarmonyCloudClient` already takes an injectable `Dio`** — `HarmonyCloudClient({Dio? dio, ...})`
   ([harmony_cloud_client.dart:92](lib/services/cloud/harmony_cloud_client.dart:92)) — so network
   calls can be faked with a custom `Dio` adapter without touching the coordinator itself. No new
   seam needed there.

This plan closes the first gap with a small, behavior-preserving refactor, then adds integration
tests that drive the real `SettingsScreen`, `Library` screen and download button through
`tester.tap`/`pumpAndSettle`, exactly as [app_smoke_test.dart](integration_test/app_smoke_test.dart)
already does for the rest of the app.

## Part 1 — `AuthServiceContract` (testability only, no behavior change)

- New `abstract class AuthServiceContract` in
  [app_contracts.dart](lib/services/app_contracts.dart), mirroring the existing contracts' shape:
  `isConfigured`, `isSupportedPlatform`, `isAvailable`, `Future<UserProfile?> tryRestoreSession()`,
  `Future<UserProfile> login()`, `Future<void> logout()`.
- `Auth0Service` gets `implements AuthServiceContract` added to its class declaration
  ([auth0_service.dart:16](lib/services/auth0_service.dart:16)) — no method bodies change.
- `AuthController` ([auth_providers.dart](lib/app/providers/auth_providers.dart)) takes
  `AuthServiceContract _service` instead of `Auth0Service`.
- `auth0ServiceProvider` stays returning `Auth0Service` for production; `authControllerProvider`
  reads it through the same provider, so nothing about the app's real wiring changes — this is
  purely a declared-type narrowing that Dart accepts because `Auth0Service` already satisfies it.

## Part 2 — Fakes

In [integration_test/support/fakes.dart](integration_test/support/fakes.dart), following the file's
existing style:

- **`FakeAuthService implements AuthServiceContract`.** Configurable: a `UserProfile?` to return
  from `tryRestoreSession()`/`login()` (settable mid-test to simulate a *different* account
  signing in, or a lapsed session by returning null), call counts, and `isAvailable = true`.
  `UserProfile` is a plain auth0_flutter data class — constructible directly, no mocking framework
  needed.
- **`fakeCloudDio()`** — a `Dio` whose `HttpClientAdapter` answers `POST v1/devices/register` with
  204, `POST v1/sync` with `{"checkpoint": 0, "acceptedEventIds": [], "changes": []}`, and
  `POST v1/sync/pause` with 204, matching by request path. Good enough for every scenario below,
  since what's under test is the *local* wipe/merge/filter behavior, not server responses — those
  are already covered by the Cloud test suite. Built once, reused via a
  `cloudSyncCoordinatorProvider` override:
  `CloudSyncCoordinator(CloudSyncRepository(...), HarmonyCloudClient(dio: fakeCloudDio(), accessToken: () async => 'fake-token'))`.

## Part 3 — Test files

All under `integration_test/`, following `app_smoke_test.dart`'s boot sequence
(`app.initHive()` → `ProviderContainer` with overrides → `setAppInitPrefs` → `registerAppServices`
→ `pumpWidget`). Each file seeds Hive boxes directly before pumping, the same way the unit tests do,
so a scenario starts from a known state without needing five minutes of UI navigation to get there.

### `account_songs_filter_test.dart`
1. No account, mixed liked/unliked downloads seeded → Songs lists all of them; the "show unliked"
   filter option is absent from the menu.
2. `FakeAuthService` returns a profile, subject stored, only one download liked → Songs lists only
   that one.
3. Tapping the filter icon then the "show downloads not in your library" switch reveals the rest;
   toggling off hides them again.
4. Toggling "include cached songs" reveals a liked cached entry; a cached-but-unliked entry stays
   out until both switches are on.
5. All downloads unliked → the empty state's explanatory text renders, and tapping
   "Show all downloads" flips the toggle and the list populates.

### `unliked_download_dialog_test.dart`
6. Signed in, tapping download on an unliked song → dialog appears with its title/message and both
   buttons.
7. "Like and download" → song ends up in `LIBFAV` and the download starts.
8. "Download only" → download starts, `LIBFAV` untouched.
9. Checking "don't ask again" then choosing either button → downloading a second unliked song
   shows no dialog.
10. Dismissing the dialog (tap the barrier) → no download starts, and the "don't ask again" pref is
    still false (only an actual answer records it, per
    [unliked_download_dialog.dart](lib/ui/widgets/unliked_download_dialog.dart)'s existing
    `dismiss && choice != null` guard).
11. Downloading an already-liked song, or downloading with no account → no dialog, download starts
    immediately.

### `account_switch_test.dart` (integration_test — distinct from the existing unit test of the same
name in `test/`)
12. Fresh `FakeAuthService`, no local library seeded, `login()` invoked via the Settings sign-in
    button → no merge/replace dialog; the subject is stored.
13. Local library seeded (a liked song, a playlist) before `login()` → the merge/replace dialog
    appears.
14. Choosing "Add to my account" → `LIBFAV`/playlist boxes untouched.
15. Choosing "Use my account's library" → those boxes are cleared, but a downloaded file's box
    entry survives (asserted the same way `account_switch_test.dart`'s unit test does).
16. `init()` restoring a session with no stored subject (the upgrade path) → subject gets seeded,
    no dialog appears at all — this is the regression the seeding logic exists to prevent.
17. `FakeAuthService.login()` returning a *different* subject than the one stored → no dialog
    (switches are silent, per the plan), synced boxes clear, checkpoint resets to 0.
18. Same subject signing in again → nothing cleared.

### `session_expiry_test.dart`
19. Stored subject present, `FakeAuthService.tryRestoreSession()` returns null, sync enabled →
    `SessionExpiredBanner` renders on the Library screen and the Settings account row shows the
    error icon and message.
20. Dismissing the banner hides it; the Settings badge still shows on navigating there.
21. A successful `login()` afterward clears both.
22. Toggling a favorite while `needsReauthentication` is true still writes to `LIBFAV` — edits are
    never blocked.

### `account_lifecycle_smoke_test.dart`
23. One longer scenario chaining several of the above end to end: no account → download two songs
    → sign in first time with that library present → merge → like one of them → Songs now filters
    to it → simulate session loss → banner appears → sign in as a *different* subject → library
    empties and Songs reflects it → both original audio files still resolve via
    `DownloadRepository` (not deleted). This is the one closest to what manual testing would click
    through, and its job is to catch any interaction between the pieces that the narrower tests,
    run in isolation, wouldn't.

## Verification

```bash
flutter analyze --no-pub
flutter test
flutter test integration_test
```

All three via the `harmony-flutter-dart` MCP tools with `timeout_ms: 600000`. The existing
`test/songs_tab_filter_test.dart` and `test/account_switch_test.dart` keep covering the pure data
logic; the new `integration_test/` files are what actually prove the screens, dialogs and toggles
behave — the thing this conversation started by pointing out was missing.

Not proposing CI wiring for `integration_test` in this plan — per the existing README, that suite is
deliberately opt-in until its device/emulator workflow is trusted, and this batch shouldn't decide
that on its own. Run manually with the command above; whether to promote it to required CI is a
separate call once these are green a few times.

# Integration tests

These tests run the real Flutter UI with fake app service boundaries for
network, platform, file picker, downloader, update, auth, and audio behavior.

## Running

Run the whole suite through the single entrypoint, on a device or emulator:

```sh
flutter test integration_test/all_tests.dart -d <device-id>
```

Use `all_tests.dart` rather than `flutter test integration_test/`: the latter
treats every file as its own run and rebuilds and reinstalls the APK for each
one, which costs several times more than the tests themselves (~3 minutes
versus ~5½ for the same coverage). Running one file directly is still the right
way to iterate on a single scenario — one build is only a win across the set.

Because the whole suite shares one process, state that is genuinely global
outlives an individual test. `bootTestApp` gives each test its own Hive
directory and provider container, but `AudioService`'s handler and the
controller registries are process-wide; that is why the harness registers one
audio handler and resets it between boots instead of building a new one.

## The harness

`support/harness.dart` boots the real `MyApp` against an isolated temp Hive
directory with the external boundaries faked, and pre-answers the first-run
prompts (release channel, battery optimisation, cloud opt-in, update popup)
that would otherwise open a modal over whatever a test is doing. Prefer it over
writing a bespoke boot sequence — every fake it wires up exists because
something in the real startup path reached for a real device, network, or
Firebase.

Two things to know when writing tests here:

- **`pumpAndSettle` hangs whenever a progress indicator is on screen.** It
  waits for frame scheduling to stop, and an animating spinner never stops. The
  Settings account row shows one for as long as `AuthController.isBusy` is
  true — which includes the entire time a sign-in dialog sits unanswered. Pump
  a fixed number of frames instead.
- **Leave no dialog open and no async work in flight at the end of a test.**
  Both bleed into the next test in the shared process.

## CI

Intentionally not part of required PR checks yet. Keep PR CI on `flutter test`
until the emulator/device workflow is stable enough to trust.

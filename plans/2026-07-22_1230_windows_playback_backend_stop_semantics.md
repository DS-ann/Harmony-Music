# Windows Playback Backend and Stop Semantics Fix

## Summary

Fix Windows audio output by registering the MediaKit-backed `just_audio` platform before Harmony creates its audio handler. This should create the Harmony session in Windows Volume Mixer and make the existing in-app volume slider effective.

Normal Stop commands will behave as Pause and retain the current position. Explicit lifecycle shutdown—Android’s enabled “stop playback when swiped away” setting—will remain a true stop.

## Implementation Changes

- In `main()` register `JustAudioMediaKit` on Windows/Linux before `initAudioService(...)`; retain the existing title/protocol configuration.
- Keep the existing `AudioHandler.stop()` behavior for actual teardown, source replacement, and Android task-removal handling.
- Change `PlaybackCommandService.stop()` to delegate to `pause()` so user-facing or remote Stop commands preserve position.
- Add regression coverage that verifies MediaKit registration precedes audio-handler initialization and that normal Stop maps to pause without changing the lifecycle stop path.

## Test Plan

- Run `flutter analyze` and focused playback tests.
- On Windows: launch Harmony, play a track, verify a visible “Harmony music” Volume Mixer session, change Harmony’s mixer volume and in-app volume, and confirm audible output changes.
- Verify Pause/normal Stop resumes at the saved position; enable Android swipe-away stop and confirm that path still ends playback.

## Assumptions

- The current silent Windows playback is caused by the missing `JustAudioMediaKit.registerWith()` call; diagnostics show decoding/position advancement with valid volume but no Windows mixer session.
- No new player UI control is needed because normal playback already exposes Pause.

# Account-Bound Shared Playback Session

## Summary

Replace the current one-shot handoff with a persistent, account-bound playback session. Multiple signed-in devices are controllers, but exactly one selected device produces audio. All controllers mirror the target’s playback state and may issue commands. The session persists until explicit disconnect or logout.

## Implementation Changes

- Add a Cloud playback-session model containing account/device membership, target, portable queue state, playback state, sequence ordering, acknowledgements, target switching, disconnect, and restoration.
- Use SignalR for near-real-time delivery with authenticated polling/FCM fallback.
- Keep device control separate from Listen Together and ordinary metadata backup; never transfer files, local paths, resolver URLs, or secrets.
- Resolve target playback from local downloads first, then Resolver by stable song ID and sanitized metadata; preserve unavailable queue items.
- Make both devices controllers while only the selected target produces audio. Route playback, queue, mode, speed, and volume commands through the ordered shared session and mirror target state.
- Support atomic target switching, “This device” local return, immediate song replacement, automatic restoration, explicit disconnect, and paused failure recovery at the latest acknowledged position.
- Show all account devices with target highlighting and honest availability. Use opaque FCM wakeups for Android background targets.

## Test Plan

- Test Cloud account isolation, session lifecycle, ordered commands, acknowledgements, expiry, switching, restoration, and logout.
- Test Flutter role transitions, mirrored state, queue edits, Resolver fallback, unavailable items, switching, failure recovery, and reopen restoration.
- Validate Android/Windows foreground, tray/background, FCM wakeup, offline, force-stop, target switching, and different-account isolation.
- Verify ordinary Cloud sync transfers metadata only and does not copy audio files.

## Assumptions

- Both devices observe and control one session; only the selected target emits audio.
- Either controller may issue commands; Cloud serializes them.
- Latest acknowledged target position is authoritative.
- Failed sessions end paused rather than auto-resuming audio.
- Existing Listen Together remains separate.

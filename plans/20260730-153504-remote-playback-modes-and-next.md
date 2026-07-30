# Synchronize remote player modes and fix remote next

## Summary

Make the active cloud playback session authoritative for shuffle, repeat, and queue-loop. Fix remote Next so Windows loads the exact requested song through the normal cloud-loading path instead of relying on its potentially incomplete local queue.

## Implementation changes

- Apply explicit `shuffle`, `repeat`, and `queueLoop` values during handoff, reconnect, and target switching. Missing fields from older clients leave current settings unchanged.
- Persist the session modes on both devices. When sync ends, the adopted local player keeps those modes.
- Include live mode values in progress frames and durable session updates so changes made on either Windows or Android appear on the other device.
- Prevent feedback loops: received mode state updates UI/settings without sending another remote command.
- Extend remote `next` commands with the desired song ID.
- On the controller, immediately select the next mirrored queue item and show it at `0:00` with loading controls.
- On the target, validate the requested ID against the authoritative shared queue and start it through the full cloud source-loading path. Retain a fallback for older clients that send `next` without an ID.
- Keep the timer frozen and play/pause controls loading while the target resolves or buffers; clear loading automatically once playback genuinely advances—no pause/play workaround.
- Add mode and next-transition state to existing playback diagnostics.

## Integration and regression tests

- Add a deterministic two-device fake cloud/socket bridge; no live server or two physical devices required.
- Test Android-source handoff where Android modes are disabled and Windows previously saved them enabled; both must become disabled.
- Test toggling shuffle/repeat/queue-loop from either device and verify target audio state, mirrored UI, durable session state, and saved preferences agree.
- Test reconnecting during a session restores the current modes without restarting playback.
- Test remote Next with a delayed Windows source:
  - both surfaces immediately show the next song;
  - timer remains `0:00`;
  - play/pause shows loading;
  - a misleading buffering position does not advance the timer;
  - completing the source automatically changes to playing without another command.
- Test remote automatic advancement and previous-track behavior against the same bridge.
- Test end-of-queue behavior with queue-loop both enabled and disabled.
- Test compatibility with old session snapshots missing mode fields and old `next` commands missing the desired song ID.
- Run focused unit tests, the new remote integration suite on Windows, Android when the connected device is available, and Flutter analysis.

## Assumptions

- The active session’s modes persist on both participating devices after synchronization ends.
- The shared queue’s transmitted order is authoritative; enabling shuffle during handoff must not shuffle that order a second time.
- Automated tests use one visible app plus a headless peer because Flutter’s audio-service integration cannot mount two full app instances in one test process.

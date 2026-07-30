# Prevent clock-skew drift in remote playback progress

## Summary

Make the controlling device anchor remote progress to when it receives each
frame, rather than deriving network delay from the sending device's wall clock.

## Changes

- Keep `publishedAtMs` in progress frames for compatibility and diagnostics.
- Do not add `controller wall clock - target wall clock` to the displayed
  position; Windows and Android clocks are independent and can differ by a
  visible amount.
- Re-anchor the controller progress ticker at frame receipt, then continue
  extrapolating until the next frame corrects it.

## Regression coverage

- Update `RemoteProgressAnchor` unit tests for target clocks both ahead of and
  behind the controller.
- Update the controller integration test to prove a skewed target timestamp
  does not advance the visible timer.
- Verify remote Next continues to reject stale previous-song frames and only
  clears loading on the matching ready frame.

## Verification

- Run focused unit tests for remote progress anchoring.
- Run the focused controller-side integration tests on the Android emulator.
- Run Flutter analysis where practical.

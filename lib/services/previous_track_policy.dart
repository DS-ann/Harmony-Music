/// The established Previous-button behavior: restart the current song after
/// this point; at or before it, select the previous queue item.
const previousTrackRestartThreshold = Duration(seconds: 5);

bool shouldRestartCurrentTrack(Duration position) =>
    position > previousTrackRestartThreshold;

/// The controller decides Previous-button semantics once, using the position
/// visible to the user. A remote target must execute that intent directly
/// instead of evaluating its independently sampled position again.
enum PreviousTrackIntent { restartCurrent, selectPrevious }

PreviousTrackIntent previousTrackIntentFor(Duration position) =>
    shouldRestartCurrentTrack(position)
    ? PreviousTrackIntent.restartCurrent
    : PreviousTrackIntent.selectPrevious;

PreviousTrackIntent? previousTrackIntentFromWire(Object? value) {
  for (final intent in PreviousTrackIntent.values) {
    if (intent.name == value) return intent;
  }
  return null;
}

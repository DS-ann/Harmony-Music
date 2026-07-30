/// A progress sample from the audio target, plus the arithmetic to project it
/// forward.
///
/// A controller device receives position samples every couple of seconds. Drawn
/// as-is the progress bar visibly steps; projecting between samples makes it
/// sweep. Kept separate from `PlayerController` so the maths is testable without
/// a Flutter binding.
class RemoteProgressAnchor {
  const RemoteProgressAnchor({
    required this.position,
    required this.anchoredAt,
    required this.speed,
  });

  static final zero = RemoteProgressAnchor(
    position: Duration.zero,
    anchoredAt: DateTime.fromMillisecondsSinceEpoch(0),
    speed: 1,
  );

  final Duration position;
  final DateTime anchoredAt;
  final double speed;

  factory RemoteProgressAnchor.fromSample({
    required int positionMs,
    required double speed,
    required int? publishedAtMs,
    required DateTime now,
  }) {
    // `publishedAtMs` belongs to the *other* device's wall clock. Android and
    // Windows commonly differ by hundreds of milliseconds or more, which used
    // to be mistaken for network delay and made the controlling device visibly
    // ahead/behind. A received frame is authoritative at receipt time; the
    // next frame corrects the small, real transport delay.
    return RemoteProgressAnchor(
      position: Duration(milliseconds: positionMs < 0 ? 0 : positionMs),
      anchoredAt: now,
      // A zero or negative rate would freeze or rewind the bar.
      speed: speed <= 0 ? 1.0 : speed,
    );
  }

  /// How long extrapolation may continue without a fresh sample.
  ///
  /// Samples arrive every couple of seconds. If they stop — the target went
  /// away, the socket dropped — projecting onward is a lie that sweeps the bar
  /// to the end of the track and pins it there. Better to hold the last known
  /// position than to invent progress that is not happening.
  static const maximumProjection = Duration(seconds: 8);

  bool isStale(DateTime now) => now.difference(anchoredAt) > maximumProjection;

  /// Where playback should be at [now], never before the sampled position and
  /// never extrapolated beyond [maximumProjection].
  Duration project(DateTime now) {
    var elapsed = now.difference(anchoredAt);
    if (elapsed <= Duration.zero) return position;
    if (elapsed > maximumProjection) elapsed = maximumProjection;
    return position +
        Duration(microseconds: (elapsed.inMicroseconds * speed).round());
  }
}

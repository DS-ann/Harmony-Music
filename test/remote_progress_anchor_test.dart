import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/ui/player/remote_progress_anchor.dart';

void main() {
  final now = DateTime.utc(2026, 7, 25, 12, 0, 0);

  group('RemoteProgressAnchor', () {
    test('projects forward at real time between samples', () {
      final anchor = RemoteProgressAnchor.fromSample(
        positionMs: 10000,
        speed: 1,
        publishedAtMs: now.millisecondsSinceEpoch,
        now: now,
      );

      expect(
        anchor.project(now.add(const Duration(seconds: 3))),
        const Duration(milliseconds: 13000),
      );
    });

    test('scales projection by playback speed', () {
      final anchor = RemoteProgressAnchor.fromSample(
        positionMs: 0,
        speed: 2,
        publishedAtMs: now.millisecondsSinceEpoch,
        now: now,
      );

      expect(
        anchor.project(now.add(const Duration(seconds: 5))),
        const Duration(seconds: 10),
      );
    });

    test('does not treat a behind peer clock as delivery latency', () {
      // The target clock is 400ms behind. That must not make the controller
      // jump forward: this number cannot distinguish clock skew from latency.
      final anchor = RemoteProgressAnchor.fromSample(
        positionMs: 10000,
        speed: 1,
        publishedAtMs: now.millisecondsSinceEpoch - 400,
        now: now,
      );

      expect(anchor.project(now), const Duration(milliseconds: 10000));
    });

    test('anchors at receipt time for either direction of clock skew', () {
      for (final skew in const [Duration(seconds: -2), Duration(seconds: 2)]) {
        final anchor = RemoteProgressAnchor.fromSample(
          positionMs: 10000,
          speed: 1,
          publishedAtMs: now.add(skew).millisecondsSinceEpoch,
          now: now,
        );

        expect(anchor.project(now), const Duration(milliseconds: 10000));
      }
    });

    test('treats a non-positive speed as normal rate rather than freezing', () {
      final anchor = RemoteProgressAnchor.fromSample(
        positionMs: 0,
        speed: 0,
        publishedAtMs: now.millisecondsSinceEpoch,
        now: now,
      );

      expect(
        anchor.project(now.add(const Duration(seconds: 4))),
        const Duration(seconds: 4),
      );
    });

    test('clamps a negative reported position to zero', () {
      final anchor = RemoteProgressAnchor.fromSample(
        positionMs: -500,
        speed: 1,
        publishedAtMs: now.millisecondsSinceEpoch,
        now: now,
      );

      expect(anchor.project(now), Duration.zero);
    });

    test('stops extrapolating once samples dry up', () {
      // A dead socket used to let the bar sweep to the end of the track and pin
      // there, which reads as "playing" when nothing is playing.
      final anchor = RemoteProgressAnchor.fromSample(
        positionMs: 10000,
        speed: 1,
        publishedAtMs: now.millisecondsSinceEpoch,
        now: now,
      );
      final long = now.add(const Duration(minutes: 5));

      expect(anchor.isStale(long), isTrue);
      expect(
        anchor.project(long),
        const Duration(milliseconds: 10000) +
            RemoteProgressAnchor.maximumProjection,
      );
    });

    test('is not stale while samples are arriving normally', () {
      final anchor = RemoteProgressAnchor.fromSample(
        positionMs: 0,
        speed: 1,
        publishedAtMs: now.millisecondsSinceEpoch,
        now: now,
      );

      expect(anchor.isStale(now.add(const Duration(seconds: 4))), isFalse);
    });

    test('a paused sample projected at its own anchor does not move', () {
      final anchor = RemoteProgressAnchor.fromSample(
        positionMs: 7000,
        speed: 1,
        publishedAtMs: null,
        now: now,
      );

      expect(anchor.project(now), const Duration(milliseconds: 7000));
    });
  });
}

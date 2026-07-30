import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/domain/repositories/settings_repository.dart';
import 'package:harmonymusic/services/playback_command_service.dart';
import 'package:harmonymusic/services/playback_video_id.dart';

/// Keys the Cloud's `PlaybackPayload.IsPortable` deny-list rejects. It matches on
/// substrings of key names, so any of these anywhere in the document fails the
/// whole request with a flat 400.
const _forbiddenKeyFragments = ['url', 'path', 'token', 'credential'];

void main() {
  late PlaybackCommandService commands;
  late _FakeAudioHandler handler;

  setUp(() {
    handler = _FakeAudioHandler();
    commands = PlaybackCommandService(
      audioHandler: handler,
      settingsRepository: _FakeSettings(),
    );
  });

  List<MediaItem> queueOf(int count) => List.generate(
    count,
    (index) => MediaItem(
      id: index.toString().padLeft(11, '0'),
      title: 'Song $index',
      artist: 'Artist $index',
      duration: const Duration(seconds: 200),
      artUri: Uri.parse('https://i.ytimg.com/vi/x/hqdefault.jpg'),
    ),
  );

  group('session state v2', () {
    test('carries explicit playback modes, including false values', () {
      final state = commands.sessionState(queue: queueOf(2), index: 0);

      expect(state['shuffle'], isFalse);
      expect(state['repeat'], isFalse);
      expect(state['queueLoop'], isFalse);
    });

    test('carries ordered ids and nothing else about each song', () {
      final state = commands.sessionState(queue: queueOf(3), index: 1);

      expect(state['schemaVersion'], 2);
      expect(state['queueIds'], ['00000000000', '00000000001', '00000000002']);
      expect(state['index'], 1);
      expect(state['currentSongId'], '00000000001');
      // No per-song metadata: that is the whole point of the id-only payload.
      expect(state.containsKey('queue'), isFalse);
    });

    test('contains no key the cloud deny-list would reject', () {
      // Artwork urls previously travelled in this payload; reintroducing one
      // would silently 400 every handoff.
      final state = commands.sessionState(queue: queueOf(2), index: 0);

      for (final key in state.keys) {
        for (final fragment in _forbiddenKeyFragments) {
          expect(
            key.toLowerCase().contains(fragment),
            isFalse,
            reason: '"$key" contains "$fragment" and would be rejected',
          );
        }
      }
    });

    test('a large queue stays small on the wire', () {
      final state = commands.sessionState(queue: queueOf(900), index: 0);

      final ids = state['queueIds'] as List;
      expect(ids.length, 900);
      // ~11 bytes per id: a 900-song queue is kilobytes, not megabytes.
      expect(ids.join(',').length, lessThan(20 * 1024));
    });

    test('the queue revision increases so a stale write can be rejected', () {
      final first = commands.sessionState(queue: queueOf(1), index: 0);
      final second = commands.sessionState(queue: queueOf(1), index: 0);

      expect(
        second['queueRevision'] as int,
        greaterThan(first['queueRevision'] as int),
      );
    });

    test('adopting a peer revision keeps later local writes ahead of it', () {
      commands.observeQueueRevision(500);

      final state = commands.sessionState(queue: queueOf(1), index: 0);

      expect(state['queueRevision'] as int, greaterThan(500));
    });

    test('an out-of-range index is clamped rather than sent as-is', () {
      // The cloud rejects an index outside the queue, so never construct one.
      final state = commands.sessionState(queue: queueOf(3), index: 99);

      expect(state['index'], 2);
      expect(state['currentSongId'], '00000000002');
    });

    test('an empty queue produces a safe index', () {
      final state = commands.sessionState(queue: const [], index: 4);

      expect(state['queueIds'], isEmpty);
      expect(state['index'], 0);
      expect(state.containsKey('currentSongId'), isFalse);
    });

    test('accepts only playable YouTube video ids', () {
      expect(isValidPlaybackVideoId('7Kp5a89LBu8'), isTrue);
      expect(
        () => commands.sessionState(
          queue: const [
            MediaItem(
              id: '7Kp5a89LBu8',
              title: 'Album entity',
              playable: false,
            ),
          ],
          index: 0,
        ),
        throwsFormatException,
      );

      for (final invalidId in [
        '',
        'PL_PLAYLIST_ID',
        'MPREb_BROWSE_ID',
        'too-short',
      ]) {
        expect(
          () => commands.sessionState(
            queue: [MediaItem(id: invalidId, title: 'Invalid')],
            index: 0,
          ),
          throwsFormatException,
          reason: '$invalidId is not a playback video id',
        );
      }
    });

    test('validates externally supplied cloud video ids', () {
      expect(
        () => commands.sessionState(
          queue: queueOf(1),
          index: 0,
          queueVideoIds: const ['PL_NOT_A_VIDEO'],
        ),
        throwsFormatException,
      );
      expect(
        () => commands.sessionState(
          queue: queueOf(1),
          index: 0,
          currentVideoId: 'MPRE_NOT_A_VIDEO',
        ),
        throwsFormatException,
      );
    });
  });

  group('progress frame', () {
    test('carries duration and a publish timestamp for extrapolation', () {
      final frame = commands.progressFrame();

      expect(frame['type'], 'progress');
      expect(frame.containsKey('positionMs'), isTrue);
      expect(frame.containsKey('playing'), isTrue);
      expect(frame.containsKey('speed'), isTrue);
      expect(frame['publishedAtMs'], isA<int>());
    });

    test('reports loading and buffering to remote controllers', () {
      expect(commands.progressFrame()['loading'], isFalse);

      handler.playbackState.add(
        PlaybackState(processingState: AudioProcessingState.loading),
      );
      expect(commands.progressFrame()['loading'], isTrue);

      handler.playbackState.add(
        PlaybackState(processingState: AudioProcessingState.buffering),
      );
      expect(commands.progressFrame()['loading'], isTrue);
    });

    test('reports live playback modes to remote controllers', () {
      handler.playbackState.add(
        PlaybackState(
          shuffleMode: AudioServiceShuffleMode.all,
          repeatMode: AudioServiceRepeatMode.one,
        ),
      );

      expect(commands.progressFrame(), containsPair('shuffle', true));
      expect(commands.progressFrame(), containsPair('repeat', true));
      expect(commands.progressFrame(), containsPair('queueLoop', false));
    });
  });
}

class _FakeSettings implements SettingsRepository {
  @override
  bool getShuffleModeEnabled() => false;

  @override
  bool getLoopModeEnabled() => false;

  @override
  bool getQueueLoopModeEnabled() => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked.');
}

class _FakeAudioHandler extends BaseAudioHandler {}

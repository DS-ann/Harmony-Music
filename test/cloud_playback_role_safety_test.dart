import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/domain/repositories/settings_repository.dart';
import 'package:harmonymusic/services/playback_command_service.dart';

/// The handoff regression: a device that is controlling a peer and then becomes
/// the audio target must drive its *own* player. Routing that through
/// [PlaybackCommandService] sends it back out to the peer instead, because every
/// method there forks on whether remote control is active.
void main() {
  late _RecordingAudioHandler handler;
  late PlaybackCommandService commands;

  setUp(() {
    handler = _RecordingAudioHandler();
    commands = PlaybackCommandService(
      audioHandler: handler,
      settingsRepository: _FakeSettings(),
    );
  });

  group('local command path', () {
    test('drives the local handler even while controlling a peer', () async {
      commands.startRemoteControl('peer-device');

      await commands.local.play();
      await commands.local.updateQueue([_song('aaaaaaaaaaa')]);
      await commands.local.playByIndex(0, position: 1000);

      expect(handler.calls, contains('play'));
      expect(handler.calls, contains('updateQueue:1'));
      expect(handler.calls, contains('playByIndex:0'));
    });

    test(
      'the forwarding service does NOT touch the handler in that state',
      () async {
        // Guards the distinction the receiver depends on: same operation, one path
        // goes out to the network, the other stays here.
        commands.startRemoteControl('peer-device');

        await commands.playByIndex(3);

        expect(handler.calls, isEmpty);
      },
    );

    test(
      'stopping remote control returns the service to the local handler',
      () async {
        commands.startRemoteControl('peer-device');
        commands.stopRemoteControl();

        await commands.updateQueue([_song('aaaaaaaaaaa')]);

        expect(handler.calls, contains('updateQueue:1'));
      },
    );

    test('local song selections are exposed before the handler action', () async {
      await commands.updateQueue([_song('aaaaaaaaaaa')]);
      final selections = <String?>[];
      final subscription = commands.localSongSelections.listen(selections.add);

      await commands.playByIndex(0);
      await commands.setSourceAndPlay(_song('bbbbbbbbbbb'));

      // The fake handler records updateQueue without mirroring the queue value,
      // so playByIndex cannot name its item here. The takeover signal itself is
      // what the receiver needs; direct source selection carries its exact id.
      expect(selections, [null, 'bbbbbbbbbbb']);
      await subscription.cancel();
    });

    test('forwarded selections are not reported as local takeovers', () async {
      commands.startRemoteControl('peer-device');
      final selections = <String?>[];
      final subscription = commands.localSongSelections.listen(selections.add);

      await commands.playByIndex(0);
      await commands.setSourceAndPlay(_song('bbbbbbbbbbb'));

      expect(selections, isEmpty);
      await subscription.cancel();
    });

    test('a queue replacement while synced stays remote control', () async {
      // Picking music on a mirrored UI plays it on the target, like any cast
      // UX. Leaving sync is an explicit act (own device row in the sheet), so
      // the forwarding service must NOT quietly fall back to the local player.
      commands.startRemoteControl('peer-device');

      await commands.updateQueue([_song('aaaaaaaaaaa')]);
      await commands.setSourceAndPlay(_song('bbbbbbbbbbb'));

      expect(handler.calls, isEmpty);
      expect(commands.isRemoteControlActive, isTrue);
    });

    test('local progress frames describe this device, not the peer', () {
      commands.startRemoteControl('peer-device');
      handler.mediaItem.add(
        MediaItem(
          id: 'aaaaaaaaaaa',
          title: 'Canonical title',
          artist: 'Canonical artist',
          album: 'Canonical album',
          duration: const Duration(seconds: 123),
          artUri: Uri.parse('https://example.com/art.jpg'),
        ),
      );

      final frame = commands.local.progressFrame();
      final metadata = frame['songMetadata'] as Map<String, Object?>;

      expect(frame['type'], 'progress');
      expect(frame['publishedAtMs'], isA<int>());
      expect(metadata['id'], 'aaaaaaaaaaa');
      expect(metadata['title'], 'Canonical title');
      expect(metadata['artist'], 'Canonical artist');
      expect(metadata['album'], 'Canonical album');
      expect(metadata['durationMs'], 123000);
      expect(metadata['artworkUri'], 'https://example.com/art.jpg');
    });

    test('both progress facades report local buffering as loading', () {
      handler.playbackState.add(
        PlaybackState(processingState: AudioProcessingState.buffering),
      );

      expect(commands.local.progressFrame()['loading'], isTrue);
      expect(commands.progressFrame()['loading'], isTrue);
    });
  });
}

MediaItem _song(String id) => MediaItem(id: id, title: 'Song $id', artist: 'A');

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

/// Records what actually reached this device's audio engine.
class _RecordingAudioHandler extends BaseAudioHandler {
  final List<String> calls = [];

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> updateQueue(List<MediaItem> queue) async =>
      calls.add('updateQueue:${queue.length}');

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    calls.add(name == 'playByIndex' ? 'playByIndex:${extras?['index']}' : name);
    return null;
  }
}

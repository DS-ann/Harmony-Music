import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/domain/repositories/settings_repository.dart';
import 'package:harmonymusic/services/cloud/cloud_playback_gateway.dart';
import 'package:harmonymusic/services/cloud/cloud_playback_receiver.dart';
import 'package:harmonymusic/services/cloud/harmony_cloud_client.dart';
import 'package:harmonymusic/services/cloud/playback_socket_client.dart';
import 'package:harmonymusic/services/metadata/playback_metadata_resolver.dart';
import 'package:harmonymusic/services/playback_command_service.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late _PlaybackBridge bridge;
  late _MemorySettings androidSettings;
  late _MemorySettings windowsSettings;
  late _RemoteAudioHandler androidAudio;
  late _RemoteAudioHandler windowsAudio;
  late PlaybackCommandService androidCommands;
  late PlaybackCommandService windowsCommands;
  late CloudPlaybackReceiver windowsReceiver;

  setUp(() async {
    bridge = _PlaybackBridge();
    androidSettings = _MemorySettings();
    windowsSettings = _MemorySettings(
      shuffle: true,
      repeat: true,
      queueLoop: true,
    );
    androidAudio = _RemoteAudioHandler();
    windowsAudio = _RemoteAudioHandler(
      shuffle: true,
      repeat: true,
      queueLoop: true,
    );
    androidCommands = PlaybackCommandService(
      audioHandler: androidAudio,
      settingsRepository: androidSettings,
      cloudSync: bridge.gateway('android'),
    );
    windowsCommands = PlaybackCommandService(
      audioHandler: windowsAudio,
      settingsRepository: windowsSettings,
      cloudSync: bridge.gateway('windows'),
    );
    windowsReceiver = CloudPlaybackReceiver(
      bridge.gateway('windows'),
      _FixtureMetadata(),
      windowsCommands,
      bridge.socket('windows'),
    );
    await windowsReceiver.start();
  });

  tearDown(() {
    windowsReceiver.dispose();
  });

  Future<void> startAndroidSession() async {
    final sessionId = await androidCommands.startSharedSession(
      targetDeviceId: 'windows',
      queue: _songs,
      index: 0,
      positionMs: 0,
      playing: true,
    );
    expect(sessionId, isNotNull);
    await _waitUntil(
      () =>
          windowsAudio.mediaItem.value?.id == _songs.first.id &&
          windowsAudio.playbackState.value.processingState ==
              AudioProcessingState.ready,
      reason: 'the Windows target should finish the initial handoff',
    );
  }

  testWidgets(
    'handoff replaces target modes and reconnect does not restart playback',
    (_) async {
      await startAndroidSession();

      expect(windowsSettings.shuffle, isFalse);
      expect(windowsSettings.repeat, isFalse);
      expect(windowsSettings.queueLoop, isFalse);
      expect(
        windowsAudio.playbackState.value.shuffleMode,
        AudioServiceShuffleMode.none,
      );
      expect(
        windowsAudio.playbackState.value.repeatMode,
        AudioServiceRepeatMode.none,
      );
      expect(windowsAudio.queueLoop, isFalse);

      final startsBeforeReconnect = windowsAudio.playedSongIds.length;
      await windowsReceiver.refreshSession();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(windowsAudio.playedSongIds.length, startsBeforeReconnect);
    },
  );

  testWidgets(
    'remote next selects the exact cloud song and leaves loading by itself',
    (_) async {
      await startAndroidSession();
      windowsAudio.completeLoadsAutomatically = false;

      await androidCommands.next(desiredVideoId: _songs[1].id);
      await _waitUntil(
        () =>
            windowsAudio.mediaItem.value?.id == _songs[1].id &&
            windowsAudio.playbackState.value.processingState ==
                AudioProcessingState.loading,
        reason: 'Windows should enter loading for the requested second song',
      );

      windowsAudio.reportBuffering(const Duration(milliseconds: 500));
      await Future<void>.delayed(
        CloudPlaybackReceiver.progressInterval +
            const Duration(milliseconds: 100),
      );
      final loading = bridge.lastProgressFrom('windows');
      expect(loading?['currentSongId'], _songs[1].id);
      expect(loading?['loading'], isTrue);
      expect(loading?['positionMs'], 0);

      windowsAudio.completePendingLoad();
      await _waitUntil(
        () {
          final frame = bridge.lastProgressFrom('windows');
          return windowsAudio.playbackState.value.processingState ==
                  AudioProcessingState.ready &&
              frame?['currentSongId'] == _songs[1].id &&
              frame?['loading'] == false;
        },
        reason: 'the target should leave loading without a pause/play command',
      );
      expect(windowsAudio.pauseCallCount, 0);
      expect(windowsAudio.playCallCount, greaterThan(0));
      expect(
        windowsReceiver.diagnostics()['lastRequestedNextSongId'],
        _songs[1].id,
      );
    },
  );

  testWidgets('legacy next uses the authoritative cloud queue', (_) async {
    await startAndroidSession();

    await androidCommands.next();
    await _waitUntil(
      () => windowsAudio.mediaItem.value?.id == _songs[1].id,
      reason: 'a next command without a song id should still advance',
    );

    expect(windowsAudio.skipToNextCallCount, 0);
    expect(windowsAudio.playedSongIds.last, _songs[1].id);
  });

  testWidgets('older handoffs without mode fields keep the target modes', (
    _,
  ) async {
    await bridge
        .gateway('android')
        .sendSessionCommand(
          targetDeviceId: 'windows',
          type: 'handoff',
          payload: {
            'queueIds': _songs.map((song) => song.id).toList(),
            'index': 0,
            'currentSongId': _songs.first.id,
            'positionMs': 0,
            'playing': true,
          },
        );
    await _waitUntil(
      () => windowsAudio.mediaItem.value?.id == _songs.first.id,
      reason: 'the legacy handoff should still start playback',
    );

    expect(windowsSettings.shuffle, isTrue);
    expect(windowsSettings.repeat, isTrue);
    expect(windowsSettings.queueLoop, isTrue);
  });

  testWidgets('legacy next stops at the end unless queue-loop wraps it', (
    _,
  ) async {
    await startAndroidSession();
    await androidCommands.next(desiredVideoId: _songs[1].id);
    await _waitUntil(
      () => windowsAudio.mediaItem.value?.id == _songs[1].id,
      reason: 'the target should reach the final queue item',
    );

    final startsAtEnd = windowsAudio.playedSongIds.length;
    await androidCommands.next();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(windowsAudio.mediaItem.value?.id, _songs[1].id);
    expect(windowsAudio.playedSongIds.length, startsAtEnd);

    await androidCommands.setQueueLoopMode(true);
    await _waitUntil(
      () => windowsSettings.queueLoop,
      reason: 'queue-loop should reach the target',
    );
    await androidCommands.next();
    await _waitUntil(
      () => windowsAudio.mediaItem.value?.id == _songs.first.id,
      reason: 'queue-loop should wrap legacy next to the first item',
    );
  });

  testWidgets(
    'target auto-advance publishes the new song and remote previous returns',
    (_) async {
      await startAndroidSession();
      await _waitUntil(
        () => windowsAudio.queue.value.length == _songs.length,
        reason: 'the target should finish widening the shared queue',
      );

      await windowsAudio.advanceAutomatically();
      await _waitUntil(
        () =>
            bridge.lastProgressFrom('windows')?['currentSongId'] ==
            _songs[1].id,
        timeout:
            CloudPlaybackReceiver.progressInterval + const Duration(seconds: 1),
        reason: 'automatic target advancement should reach controllers',
      );

      await bridge
          .gateway('android')
          .sendSessionCommand(
            targetDeviceId: 'windows',
            type: 'previous',
            payload: {
              'intent': 'selectPrevious',
              'desiredVideoId': _songs.first.id,
            },
          );
      await _waitUntil(
        () => windowsAudio.mediaItem.value?.id == _songs.first.id,
        reason: 'remote previous should return to the exact preceding song',
      );
    },
  );

  testWidgets(
    'mode commands persist on both devices and publish durable session state',
    (_) async {
      await startAndroidSession();

      await androidCommands.toggleShuffle(enabled: false);
      await androidCommands.toggleLoop(enabled: false);
      await androidCommands.setQueueLoopMode(true);
      await _waitUntil(
        () =>
            windowsSettings.shuffle &&
            windowsSettings.repeat &&
            windowsSettings.queueLoop,
        reason: 'the Windows target should apply all controller mode commands',
      );
      await _waitUntil(
        () {
          final state = bridge.sessionState;
          return state?['shuffle'] == true &&
              state?['repeat'] == true &&
              state?['queueLoop'] == true;
        },
        timeout: const Duration(seconds: 2),
        reason: 'the target should persist the modes in the shared session',
      );

      expect(androidSettings.shuffle, isTrue);
      expect(androidSettings.repeat, isTrue);
      expect(androidSettings.queueLoop, isTrue);
      expect(bridge.lastProgressFrom('windows'), containsPair('shuffle', true));
      expect(bridge.lastProgressFrom('windows'), containsPair('repeat', true));
      expect(
        bridge.lastProgressFrom('windows'),
        containsPair('queueLoop', true),
      );
    },
  );
}

const _songs = [
  MediaItem(
    id: 'aaaaaaaaaaa',
    title: 'Remote Song One',
    artist: 'Fixture Artist',
    duration: Duration(minutes: 3),
  ),
  MediaItem(
    id: 'bbbbbbbbbbb',
    title: 'Remote Song Two',
    artist: 'Fixture Artist',
    duration: Duration(minutes: 4),
  ),
];

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
  required String reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue, reason: reason);
}

class _FixtureMetadata implements PlaybackMetadataResolver {
  @override
  Future<MediaItem?> resolve(String videoId) async {
    for (final song in _songs) {
      if (song.id == videoId) return song;
    }
    return null;
  }

  @override
  Future<Map<String, MediaItem>> resolveBatch(List<String> videoIds) async {
    return {
      for (final song in _songs)
        if (videoIds.contains(song.id)) song.id: song,
    };
  }
}

class _PlaybackBridge {
  final Map<String, _BridgeSocket> _sockets = {};
  final List<Map<String, dynamic>> progressFrames = [];
  Map<String, dynamic>? sessionState;
  String? targetDeviceId;
  var _commandSequence = 0;

  CloudPlaybackGateway gateway(String deviceId) =>
      _BridgeGateway(this, deviceId);

  PlaybackSocketTransport socket(String deviceId) {
    return _sockets.putIfAbsent(deviceId, () => _BridgeSocket(this, deviceId));
  }

  Map<String, dynamic>? lastProgressFrom(String deviceId) {
    for (final frame in progressFrames.reversed) {
      if (frame['_sourceDeviceId'] == deviceId) return frame;
    }
    return null;
  }

  void _sendCommand(
    String sourceDeviceId,
    String targetDeviceId,
    String type,
    Map<String, Object?> payload,
  ) {
    _sockets[targetDeviceId]?.addFrame({
      'type': 'command',
      'commandId': 'command-${++_commandSequence}',
      'sourceDeviceId': sourceDeviceId,
      'targetDeviceId': targetDeviceId,
      'commandType': type,
      'payload': Map<String, Object?>.from(payload),
    });
  }

  void _fromSocket(String sourceDeviceId, Map<String, Object?> frame) {
    if (frame['type'] != 'progress') return;
    final recorded = <String, dynamic>{
      ...frame,
      '_sourceDeviceId': sourceDeviceId,
    };
    progressFrames.add(recorded);
    for (final entry in _sockets.entries) {
      if (entry.key != sourceDeviceId) entry.value.addFrame(recorded);
    }
  }
}

class _BridgeGateway implements CloudPlaybackGateway {
  _BridgeGateway(this.bridge, this.deviceId);

  final _PlaybackBridge bridge;

  @override
  final String deviceId;

  @override
  Future<void> acknowledgePlaybackCommand({
    required String commandId,
    required bool applied,
  }) async {}

  @override
  Future<void> endPlaybackSession() async {
    bridge.sessionState = null;
    bridge.targetDeviceId = null;
  }

  @override
  Future<List<CloudPlaybackCommand>> pendingPlaybackCommands() async =>
      const [];

  @override
  Future<CloudPlaybackSession?> playbackSession() async {
    final state = bridge.sessionState;
    final target = bridge.targetDeviceId;
    if (state == null || target == null) return null;
    return CloudPlaybackSession(
      sessionId: 'session-1',
      targetDeviceId: target,
      sequence: 1,
      state: Map<String, dynamic>.from(state),
      currentSongId: state['currentSongId']?.toString(),
      positionMs: (state['positionMs'] as num?)?.toInt() ?? 0,
      playing: state['playing'] == true,
    );
  }

  @override
  Future<void> sendSessionCommand({
    required String targetDeviceId,
    required String type,
    required Map<String, Object?> payload,
  }) async {
    bridge._sendCommand(deviceId, targetDeviceId, type, payload);
  }

  @override
  Future<String> startPlaybackSession({
    required String targetDeviceId,
    required Map<String, Object?> state,
  }) async {
    bridge.targetDeviceId = targetDeviceId;
    bridge.sessionState = Map<String, dynamic>.from(state);
    bridge._sendCommand(deviceId, targetDeviceId, 'handoff', state);
    return 'session-1';
  }

  @override
  Future<void> switchPlaybackTarget({
    required String targetDeviceId,
    required Map<String, Object?> state,
  }) async {
    bridge.targetDeviceId = targetDeviceId;
    bridge.sessionState = Map<String, dynamic>.from(state);
    bridge._sendCommand(deviceId, targetDeviceId, 'handoff', state);
  }

  @override
  Future<void> updatePlaybackSessionState(Map<String, Object?> state) async {
    bridge.sessionState = Map<String, dynamic>.from(state);
  }
}

class _BridgeSocket implements PlaybackSocketTransport {
  _BridgeSocket(this.bridge, this.deviceId);

  final _PlaybackBridge bridge;
  final String deviceId;
  final _frames = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final _statuses = StreamController<PlaybackSocketStatus>.broadcast(
    sync: true,
  );

  @override
  PlaybackSocketStatus currentStatus = PlaybackSocketStatus.disconnected;

  @override
  Stream<Map<String, dynamic>> get frames => _frames.stream;

  @override
  Stream<PlaybackSocketStatus> get status => _statuses.stream;

  void addFrame(Map<String, dynamic> frame) => _frames.add(frame);

  @override
  Future<void> connect(String _) async {
    currentStatus = PlaybackSocketStatus.connected;
    _statuses.add(currentStatus);
  }

  @override
  void send(Map<String, Object?> frame) => bridge._fromSocket(deviceId, frame);

  @override
  Future<void> dispose() async {
    currentStatus = PlaybackSocketStatus.disconnected;
    await _frames.close();
    await _statuses.close();
  }
}

class _RemoteAudioHandler extends BaseAudioHandler {
  _RemoteAudioHandler({
    bool shuffle = false,
    bool repeat = false,
    this.queueLoop = false,
  }) {
    playbackState.add(
      PlaybackState(
        processingState: AudioProcessingState.idle,
        playing: false,
        shuffleMode: shuffle
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        repeatMode: repeat
            ? AudioServiceRepeatMode.one
            : AudioServiceRepeatMode.none,
      ),
    );
  }

  bool completeLoadsAutomatically = true;
  bool queueLoop;
  int playCallCount = 0;
  int pauseCallCount = 0;
  int skipToNextCallCount = 0;
  final List<String> playedSongIds = [];
  Completer<void>? _pendingLoad;

  @override
  Future<void> updateQueue(List<MediaItem> items) async {
    final currentId = mediaItem.value?.id;
    queue.add(List<MediaItem>.from(items));
    final index = items.indexWhere((item) => item.id == currentId);
    if (index >= 0) {
      playbackState.add(playbackState.value.copyWith(queueIndex: index));
    }
  }

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    if (name == 'playByIndex') {
      final index = extras?['index'] as int? ?? 0;
      if (index < 0 || index >= queue.value.length) return null;
      final song = queue.value[index];
      playedSongIds.add(song.id);
      mediaItem.add(song);
      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.loading,
          playing: true,
          queueIndex: index,
          updatePosition: Duration.zero,
          bufferedPosition: Duration.zero,
        ),
      );
      if (!completeLoadsAutomatically) {
        _pendingLoad = Completer<void>();
        await _pendingLoad!.future;
      }
      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.ready,
          playing: true,
          updatePosition: Duration.zero,
        ),
      );
    } else if (name == 'toggleQueueLoopMode') {
      queueLoop = extras?['enable'] == true;
    } else if (name == 'setShuffleModePreservingQueue') {
      final enabled = extras?['enabled'] == true;
      playbackState.add(
        playbackState.value.copyWith(
          shuffleMode: enabled
              ? AudioServiceShuffleMode.all
              : AudioServiceShuffleMode.none,
        ),
      );
    }
    return null;
  }

  @override
  Future<void> play() async {
    playCallCount++;
    playbackState.add(
      playbackState.value.copyWith(
        playing: true,
        processingState: AudioProcessingState.ready,
      ),
    );
  }

  @override
  Future<void> pause() async {
    pauseCallCount++;
    playbackState.add(playbackState.value.copyWith(playing: false));
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
  }

  @override
  Future<void> skipToNext() async {
    skipToNextCallCount++;
  }

  void reportBuffering(Duration position) {
    playbackState.add(
      playbackState.value.copyWith(
        processingState: AudioProcessingState.buffering,
        playing: true,
        updatePosition: position,
      ),
    );
  }

  void completePendingLoad() {
    final pending = _pendingLoad;
    if (pending == null || pending.isCompleted) return;
    pending.complete();
    _pendingLoad = null;
  }

  Future<void> advanceAutomatically() async {
    final currentIndex = queue.value.indexWhere(
      (item) => item.id == mediaItem.value?.id,
    );
    if (currentIndex < 0 || currentIndex + 1 >= queue.value.length) return;
    await customAction('playByIndex', {'index': currentIndex + 1});
  }
}

class _MemorySettings implements SettingsRepository {
  _MemorySettings({
    this.shuffle = false,
    this.repeat = false,
    this.queueLoop = false,
  });

  bool shuffle;
  bool repeat;
  bool queueLoop;

  @override
  bool getShuffleModeEnabled() => shuffle;

  @override
  bool getLoopModeEnabled() => repeat;

  @override
  bool getQueueLoopModeEnabled() => queueLoop;

  @override
  Future<void> setShuffleModeEnabled(bool value) async => shuffle = value;

  @override
  Future<void> setLoopModeEnabled(bool value) async => repeat = value;

  @override
  Future<void> setQueueLoopModeEnabled(bool value) async => queueLoop = value;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked.');
}

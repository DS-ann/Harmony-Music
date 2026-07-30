import 'package:audio_service/audio_service.dart';

import '../domain/repositories/settings_repository.dart';
import 'cloud/playback_modes.dart';

/// Playback operations that always act on **this** device's audio engine.
///
/// [PlaybackCommandService] deliberately forks every operation: when this device
/// is controlling another, `play()` sends a command over the network instead of
/// touching the local player. That is right for user input, and catastrophic for
/// a command that *arrived* from the network — applying it through the forking
/// service can bounce it straight back out to the peer.
///
/// So the cloud receiver holds one of these instead. A command from the cloud is
/// by definition something to perform here, and this type makes that structural
/// rather than a rule someone has to remember.
class LocalPlaybackCommands {
  LocalPlaybackCommands({
    required AudioHandler audioHandler,
    required SettingsRepository settingsRepository,
  }) : _audioHandler = audioHandler,
       _settingsRepository = settingsRepository;

  final AudioHandler _audioHandler;
  final SettingsRepository _settingsRepository;

  bool get isPlaying => _audioHandler.playbackState.value.playing;

  MediaItem? get currentSong => _audioHandler.mediaItem.value;

  List<MediaItem> get queue => _audioHandler.queue.value;

  Stream<List<MediaItem>> get queueStream => _audioHandler.queue;

  Stream<MediaItem?> get mediaItemStream => _audioHandler.mediaItem;

  Stream<PlaybackState> get playbackStateStream => _audioHandler.playbackState;

  CloudPlaybackModes get playbackModes {
    final state = _audioHandler.playbackState.value;
    return CloudPlaybackModes(
      shuffle: state.shuffleMode != AudioServiceShuffleMode.none,
      repeat: state.repeatMode != AudioServiceRepeatMode.none,
      queueLoop: _settingsRepository.getQueueLoopModeEnabled(),
    );
  }

  Future<void> play() => _audioHandler.play();

  Future<void> pause() => _audioHandler.pause();

  Future<void> seek(Duration position) => _audioHandler.seek(position);

  Future<void> next() => _audioHandler.skipToNext();

  Future<void> previous() => _audioHandler.skipToPrevious();

  Future<void> playPause({required bool isPlaying}) =>
      isPlaying ? _audioHandler.pause() : _audioHandler.play();

  Future<void> updateQueue(List<MediaItem> queue) =>
      _audioHandler.updateQueue(queue);

  Future<void> clearQueue() => _audioHandler.customAction('clearQueue');

  /// [restoreSession] prepares and seeks the source without resuming, which is
  /// what adopting a song from somewhere else needs — the alternative is a
  /// burst of audio before the immediately following pause lands.
  Future<void> playByIndex(
    int index, {
    int? position,
    bool generateNewUrl = false,
    bool restoreSession = false,
  }) => _audioHandler.customAction('playByIndex', {
    'index': index,
    if (position != null) 'position': position,
    if (generateNewUrl) 'newUrl': true,
    if (restoreSession) 'restoreSession': true,
  });

  Future<void> setVolume(int value) =>
      _audioHandler.customAction('setVolume', {'value': value});

  Future<void> setShuffle(
    bool enabled, {
    bool preserveQueueOrder = false,
  }) async {
    if (preserveQueueOrder) {
      await _audioHandler.customAction('setShuffleModePreservingQueue', {
        'enabled': enabled,
      });
    } else {
      await _audioHandler.setShuffleMode(
        enabled ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
      );
    }
    await _settingsRepository.setShuffleModeEnabled(enabled);
  }

  Future<void> setLoop(bool enabled) async {
    await _audioHandler.setRepeatMode(
      enabled ? AudioServiceRepeatMode.one : AudioServiceRepeatMode.none,
    );
    await _settingsRepository.setLoopModeEnabled(enabled);
  }

  Future<void> setQueueLoopMode(bool enabled) async {
    await _audioHandler.customAction('toggleQueueLoopMode', {
      'enable': enabled,
    });
    await _settingsRepository.setQueueLoopModeEnabled(enabled);
  }

  Future<void> persistPlaybackModes(CloudPlaybackModes modes) async {
    final writes = <Future<void>>[];
    if (modes.shuffle case final enabled?) {
      writes.add(_settingsRepository.setShuffleModeEnabled(enabled));
    }
    if (modes.repeat case final enabled?) {
      writes.add(_settingsRepository.setLoopModeEnabled(enabled));
    }
    if (modes.queueLoop case final enabled?) {
      writes.add(_settingsRepository.setQueueLoopModeEnabled(enabled));
    }
    await Future.wait(writes);
  }

  /// Live progress for publication to the account session. Carries `durationMs`
  /// and `publishedAtMs` so a controller can extrapolate between samples.
  Map<String, Object?> progressFrame() {
    final item = _audioHandler.mediaItem.value;
    final state = _audioHandler.playbackState.value;
    final artworkUri = item?.artUri;
    final portableArtwork =
        artworkUri != null &&
            (artworkUri.scheme == 'https' || artworkUri.scheme == 'http')
        ? artworkUri.toString()
        : null;
    final loading =
        state.processingState == AudioProcessingState.loading ||
        state.processingState == AudioProcessingState.buffering;
    return {
      'type': 'progress',
      if (item != null) 'currentSongId': item.id,
      if (item != null)
        'songMetadata': {
          'id': item.id,
          'title': item.title,
          'artist': item.artist,
          'album': item.album,
          'durationMs': item.duration?.inMilliseconds,
          'artworkUri': portableArtwork,
        },
      'positionMs': state.updatePosition.inMilliseconds,
      if (item?.duration != null) 'durationMs': item!.duration!.inMilliseconds,
      'playing': state.playing,
      'loading': loading,
      'speed': state.speed,
      ...playbackModes.toMap(),
      'publishedAtMs': DateTime.now().millisecondsSinceEpoch,
    };
  }
}

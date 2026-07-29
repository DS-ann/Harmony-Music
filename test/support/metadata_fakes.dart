import 'package:audio_service/audio_service.dart';
import 'package:harmonymusic/domain/repositories/download_repository.dart';
import 'package:harmonymusic/domain/repositories/settings_repository.dart';
import 'package:harmonymusic/domain/repositories/song_cache_repository.dart';
import 'package:harmonymusic/services/app_contracts.dart';
import 'package:harmonymusic/services/resolver/resolver_client.dart';

/// These fakes implement only what `SongMetadataService` touches. Everything
/// else throws, so an accidental new dependency shows up as a loud failure
/// rather than a silent default.

class FakeMusicService implements MusicServiceContract {
  final Map<String, MediaItem> metadata = {};
  final List<String> resolveCalls = [];
  Duration delay = Duration.zero;

  @override
  Future<MediaItem?> resolveSongMetadata(String songId) async {
    resolveCalls.add(songId);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return metadata[songId];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked.');
}

class FakeSongCache implements SongCacheRepository {
  final Map<String, MediaItem> songs = {};

  @override
  Future<MediaItem?> getCachedSong(String songId) async => songs[songId];

  @override
  Future<void> saveCachedSong(MediaItem song) async => songs[song.id] = song;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked.');
}

class FakeDownloads implements DownloadRepository {
  final Map<String, Map<String, dynamic>> songs = {};

  @override
  Future<bool> containsDownload(String songId) async =>
      songs.containsKey(songId);

  @override
  Future<dynamic> getDownloadJson(String songId) async => songs[songId];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked.');
}

class FakeSettings implements SettingsRepository {
  FakeSettings({this.resolverEnabled = true});

  final bool resolverEnabled;

  @override
  bool getResolverEnabled() => resolverEnabled;

  @override
  String? getResolverDebugOverride() => 'https://resolver.test/resolver';

  @override
  String? getResolverProductionOverride() => 'https://resolver.test/resolver';

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked.');
}

class FakeResolverClient extends ResolverClient {
  FakeResolverClient() : super();

  /// Keyed by videoId; values mirror the `v1/tracks/metadata:batch` shape.
  final Map<String, Map<String, dynamic>> tracks = {};
  final List<List<String>> batchCalls = [];
  bool throwOnBatch = false;

  @override
  Future<Map<String, Map<String, dynamic>>> metadataBatch(
    Uri baseUrl,
    List<String> videoIds,
  ) async {
    batchCalls.add(List<String>.from(videoIds));
    if (throwOnBatch) throw Exception('resolver unavailable');
    return {
      for (final videoId in videoIds)
        if (tracks[videoId] case final track?) videoId: track,
    };
  }
}

import 'dart:async';

import 'package:audio_service/audio_service.dart';

import '../../domain/repositories/download_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../domain/repositories/song_cache_repository.dart';
import '../../models/media_Item_builder.dart';
import '../../utils/helper.dart';
import '../app_contracts.dart';
import '../constant.dart';
import '../resolver/resolver_client.dart';
import '../resolver/resolver_configuration.dart';

/// Turns bare video ids into displayable [MediaItem]s as fast as the situation
/// allows.
///
/// Cloud playback sessions carry ordered ids and nothing else, so every device
/// resolves its own metadata. The old path went straight to
/// `MusicService.getSongWithId`, which costs 2-4 sequential round trips per song
/// and ignored the fact that the app usually already knows the answer.
///
/// Order of preference:
///   1. Hive caches (`SongsCache`, then downloads) — no network at all
///   2. the Resolver's batch metadata endpoint raced against YouTube's `player`
///      endpoint, first usable answer wins
///
/// The Resolver is shared across all users so it is usually the faster leg, but
/// its coverage starts empty and fills lazily; racing rather than chaining means
/// a Resolver miss never adds latency.
class SongMetadataService {
  SongMetadataService({
    required MusicServiceContract music,
    required SongCacheRepository songCache,
    required DownloadRepository downloads,
    required ResolverClient resolverClient,
    required SettingsRepository settings,
  }) : _music = music,
       _songCache = songCache,
       _downloads = downloads,
       _resolverClient = resolverClient,
       _settings = settings;

  final MusicServiceContract _music;
  final SongCacheRepository _songCache;
  final DownloadRepository _downloads;
  final ResolverClient _resolverClient;
  final SettingsRepository _settings;

  /// In-flight resolutions keyed by id, so a queue that renders the same song in
  /// several places resolves it once.
  final Map<String, Future<MediaItem?>> _inFlight = {};

  Future<MediaItem?> resolve(String videoId) {
    final existing = _inFlight[videoId];
    if (existing != null) return existing;
    final operation = _resolve(videoId);
    _inFlight[videoId] = operation;
    return operation.whenComplete(() => _inFlight.remove(videoId));
  }

  /// Resolves many ids, preferring one batched Resolver call over N single
  /// lookups. Ids the batch cannot answer fall back to [resolve] individually.
  /// Returns only what resolved — callers keep their placeholders for the rest.
  Future<Map<String, MediaItem>> resolveBatch(List<String> videoIds) async {
    final resolved = <String, MediaItem>{};
    final unresolved = <String>[];
    for (final videoId in videoIds.toSet()) {
      final cached = await _fromCaches(videoId);
      if (cached != null) {
        resolved[videoId] = cached;
      } else {
        unresolved.add(videoId);
      }
    }
    if (unresolved.isEmpty) return resolved;

    for (final chunk in _chunk(unresolved, ResolverClient.metadataBatchLimit)) {
      final fromResolver = await _resolverBatch(chunk);
      for (final entry in fromResolver.entries) {
        resolved[entry.key] = entry.value;
        unawaited(_songCache.saveCachedSong(entry.value));
      }
    }

    // Anything the Resolver could not answer still needs YouTube — and only
    // YouTube: the batch above already reported these ids as missing, so racing
    // the Resolver again would issue one pointless request per song. Bounded
    // concurrency keeps a long queue from opening hundreds of sockets at once.
    final remaining = unresolved
        .where((id) => !resolved.containsKey(id))
        .toList();
    for (final window in _chunk(remaining, _youtubeConcurrency)) {
      final items = await Future.wait(window.map(_youtubeOnly));
      for (var index = 0; index < window.length; index++) {
        final item = items[index];
        if (item != null) resolved[window[index]] = item;
      }
    }
    return resolved;
  }

  Future<MediaItem?> _youtubeOnly(String videoId) async {
    try {
      final item = await _music.resolveSongMetadata(videoId);
      if (item != null) unawaited(_songCache.saveCachedSong(item));
      return item;
    } catch (_) {
      return null;
    }
  }

  /// How many YouTube `player` calls may be in flight at once during a backfill.
  static const _youtubeConcurrency = 4;

  Future<MediaItem?> _resolve(String videoId) async {
    final cached = await _fromCaches(videoId);
    if (cached != null) return cached;

    final resolved = await _raceResolvers(videoId);
    if (resolved != null) unawaited(_songCache.saveCachedSong(resolved));
    return resolved;
  }

  Future<MediaItem?> _fromCaches(String videoId) async {
    final cached = await _songCache.getCachedSong(videoId);
    if (cached != null && cached.title.trim().isNotEmpty) return cached;
    if (await _downloads.containsDownload(videoId)) {
      final json = await _downloads.getDownloadJson(videoId);
      if (json is Map) {
        return MediaItemBuilder.fromJson(Map<String, dynamic>.from(json));
      }
    }
    return null;
  }

  /// Runs both online sources concurrently and takes the first usable answer,
  /// mirroring the audio-URL race in [AudioHandler].
  Future<MediaItem?> _raceResolvers(String videoId) async {
    final completer = Completer<MediaItem?>();
    var pending = 2;

    void settle(MediaItem? item) {
      pending--;
      if (completer.isCompleted) return;
      if (item != null) {
        completer.complete(item);
      } else if (pending == 0) {
        completer.complete(null);
      }
    }

    unawaited(
      _resolverSingle(videoId).then(settle, onError: (_) => settle(null)),
    );
    unawaited(
      _music
          .resolveSongMetadata(videoId)
          .then(settle, onError: (_) => settle(null)),
    );
    // The completer only settles once a leg answers, so a leg that never
    // answers holds it — and its caller — open indefinitely. The audio target
    // blocks on this before it can start a handed-off song, which turns one
    // stalled request into a permanent spinner and a placeholder title on the
    // receiving device. Report "unknown" instead and let the caller move on.
    return completer.future.timeout(_resolveBudget, onTimeout: () => null);
  }

  /// Ceiling on one resolution, whatever the clients underneath decide to do.
  /// Comfortably longer than either leg's own timeouts, so this only fires when
  /// something below has genuinely stopped answering.
  static const _resolveBudget = Duration(seconds: 15);

  Future<MediaItem?> _resolverSingle(String videoId) async {
    final batch = await _resolverBatch([videoId]);
    return batch[videoId];
  }

  Future<Map<String, MediaItem>> _resolverBatch(List<String> videoIds) async {
    final baseUrl = _resolverBaseUrl();
    if (baseUrl == null || videoIds.isEmpty) return const {};
    final Map<String, Map<String, dynamic>> response;
    try {
      response = await _resolverClient.metadataBatch(baseUrl, videoIds);
    } catch (_) {
      // The Resolver is an optimisation, never a requirement.
      return const {};
    }
    // Parse per track. Folding this into the request's try meant one unexpected
    // field shape threw and discarded the whole chunk — up to
    // [ResolverClient.metadataBatchLimit] songs reported as "the Resolver does
    // not know these", silently, forever. Every one of them then fell through
    // to the slower YouTube leg for no reason.
    final resolved = <String, MediaItem>{};
    for (final entry in response.entries) {
      try {
        resolved[entry.key] = _fromResolver(entry.key, entry.value);
      } catch (error) {
        // Silence here hid a real contract break for weeks: the Resolver sent
        // `album` as a bare string, parsing threw on `album['id']`, and every
        // track that actually had an album was dropped — which looked exactly
        // like the Resolver not knowing them.
        printWarning(
          'Resolver metadata for ${entry.key} could not be parsed: $error',
          tag: LogTags.musicService,
        );
        continue;
      }
    }
    return resolved;
  }

  /// Reloaded per call so a settings change (or a discovered LAN endpoint) takes
  /// effect without rebuilding this service.
  Uri? _resolverBaseUrl() {
    final configuration = ResolverConfiguration.load(_settings);
    return configuration.enabled ? configuration.baseUrl : null;
  }

  MediaItem _fromResolver(String videoId, Map<String, dynamic> track) {
    // Resolver now returns the same Harmony-shaped song JSON as the local source.
    return MediaItemBuilder.fromJson({
      ...track,
      'videoId': track['videoId'] ?? videoId,
    });
  }

  static Iterable<List<T>> _chunk<T>(List<T> items, int size) sync* {
    for (var start = 0; start < items.length; start += size) {
      yield items.sublist(start, (start + size).clamp(0, items.length));
    }
  }
}

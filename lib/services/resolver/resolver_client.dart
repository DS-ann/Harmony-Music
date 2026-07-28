import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class ResolverHealth {
  const ResolverHealth({required this.ready, required this.dependencies});
  final bool ready;
  final Map<String, String> dependencies;
}

class ResolverClient {
  ResolverClient({Dio? dio, Future<String?> Function()? accessToken})
    : _dio = dio ?? Dio(),
      _accessToken = accessToken;

  final Dio _dio;
  final Future<String?> Function()? _accessToken;

  Future<ResolverHealth> check(Uri baseUrl) async {
    final response = await _dio.getUri<Map<String, dynamic>>(
      baseUrl.resolve('/health/ready'),
      options: Options(
        receiveTimeout: const Duration(seconds: 5),
        sendTimeout: const Duration(seconds: 5),
      ),
    );
    final data = response.data ?? const <String, dynamic>{};
    final rawDependencies = data['dependencies'];
    return ResolverHealth(
      ready: response.statusCode == 200 && data['status'] == 'ready',
      dependencies: rawDependencies is Map
          ? rawDependencies.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const {},
    );
  }

  Future<Options> authorizedOptions(
    Uri baseUrl, {
    Map<String, String>? headers,
  }) async {
    final token = baseUrl.scheme == 'https' || !kReleaseMode
        ? await _accessToken?.call()
        : null;
    return Options(
      headers: {
        ...?headers,
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    );
  }

  /// Batch display metadata for a queue. Ids the Resolver has never seen come
  /// back with status `missing` — the caller is expected to fall back to its own
  /// resolution path rather than treat that as an error.
  Future<Map<String, Map<String, dynamic>>> metadataBatch(
    Uri baseUrl,
    List<String> videoIds,
  ) async {
    if (videoIds.isEmpty) return const {};
    final options = await authorizedOptions(
      baseUrl,
      headers: const {'Content-Type': 'application/json'},
    );
    final response = await _dio.postUri<Map<String, dynamic>>(
      baseUrl.resolve('v1/tracks/metadata:batch'),
      data: {
        'videoIds': videoIds.take(metadataBatchLimit).toList(growable: false),
      },
      options: Options(
        headers: options.headers,
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );
    final tracks = response.data?['tracks'];
    if (tracks is! List) return const {};
    final resolved = <String, Map<String, dynamic>>{};
    for (final track in tracks.whereType<Map>()) {
      if (track['status'] != 'ready') continue;
      final videoId = track['videoId']?.toString();
      if (videoId == null || videoId.isEmpty) continue;
      resolved[videoId] = Map<String, dynamic>.from(track);
    }
    return resolved;
  }

  /// Mirrors the server-side cap on `v1/tracks/metadata:batch`.
  static const metadataBatchLimit = 100;

  /// Asks Resolver to make the track available for future playback without
  /// delaying the app's existing local downloader when the service is busy.
  Future<void> prefetch(Uri baseUrl, List<String> videoIds) async {
    if (videoIds.isEmpty) return;
    final options = await authorizedOptions(
      baseUrl,
      headers: const {'Content-Type': 'application/json'},
    );
    await _dio.postUri<void>(
      baseUrl.resolve('v1/prefetch'),
      data: {'videoIds': videoIds.take(3).toList(growable: false)},
      options: options,
    );
  }
}

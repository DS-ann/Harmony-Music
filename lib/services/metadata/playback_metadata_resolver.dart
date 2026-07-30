import 'package:audio_service/audio_service.dart';

/// Metadata boundary used by cross-device playback.
abstract interface class PlaybackMetadataResolver {
  Future<MediaItem?> resolve(String videoId);

  Future<Map<String, MediaItem>> resolveBatch(List<String> videoIds);
}

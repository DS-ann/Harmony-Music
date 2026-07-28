import 'package:audio_service/audio_service.dart';

final RegExp _youtubeVideoIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

bool isValidPlaybackVideoId(String value) =>
    _youtubeVideoIdPattern.hasMatch(value);

String requirePlaybackVideoId(MediaItem item) {
  if (item.playable != true) {
    throw FormatException(
      'Cloud playback requires a playable video item: ${item.id}',
    );
  }
  return requirePlaybackVideoIdValue(item.id);
}

String requirePlaybackVideoIdValue(String value) {
  if (!isValidPlaybackVideoId(value)) {
    throw FormatException('Invalid YouTube playback video ID: $value');
  }
  return value;
}

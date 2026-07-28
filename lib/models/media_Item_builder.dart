// ignore_for_file: file_names

import 'package:audio_service/audio_service.dart';
import '../models/thumbnail.dart';

class MediaItemBuilder {
  static MediaItem fromJson(dynamic json, {String? url}) {
    final artists = _normalizeArtists(json['artists']);
    final artistName = artists
        ?.map((artist) => artist['name'] as String)
        .join(', ');

    Map? album;
    if (json['album'] != null) {
      if (json['album']['id'] != null) {
        album = json['album'];
      }
    }

    final thumbnails = json['thumbnails'];
    final thumbnailUrl =
        thumbnails is List && thumbnails.isNotEmpty && thumbnails.first is Map
        ? thumbnails.first['url']?.toString()
        : null;
    final videoId = json['videoId']?.toString() ?? '';
    final fallbackThumbnail = videoId.isEmpty
        ? null
        : 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';

    return MediaItem(
      // Album/playlist responses can contain unavailable rows with a null
      // videoId or title. MediaItem requires non-null Strings, so a raw null
      // here throws "Null is not a subtype of String" and aborts the entire
      // album fetch. Fall back to safe values so the rest of the list loads.
      id: videoId,
      title: json["title"]?.toString() ?? '',
      duration: json['duration'] != null
          ? Duration(seconds: json['duration'])
          : toDuration(json['length']),
      album: album != null ? album['name'] : null,
      artist: artistName,
      // Cloud sync deliberately strips stream and remote URL fields. Artwork
      // is optional, so an URL-free portable item must remain usable instead
      // of making the entire library unreadable.
      artUri: thumbnailUrl == null || thumbnailUrl.isEmpty
          ? (fallbackThumbnail == null ? null : Uri.parse(fallbackThumbnail))
          : Uri.tryParse(Thumbnail(thumbnailUrl).high),
      extras: {
        'url': json['url'] ?? url,
        'length': json['length'],
        'album': album,
        'artists': artists,
        'date': json['date'],
        'trackDetails': json['trackDetails'],
        'year': json['year'],
      },
    );
  }

  /// Canonicalizes every supported source shape before it reaches widgets.
  ///
  /// Rich metadata uses `{name, id}` maps, while legacy Resolver and synced
  /// rows can contain plain artist strings. Keeping those strings in `extras`
  /// made artist-link widgets call map methods on a String. Invalid entries are
  /// dropped; a non-empty String id is the only navigable artist identity.
  static List<Map<String, dynamic>>? _normalizeArtists(dynamic value) {
    if (value == null) return null;
    final entries = value is List ? value : [value];
    final normalized = <Map<String, dynamic>>[];
    for (final entry in entries) {
      final dynamic rawName = entry is Map ? entry['name'] : entry;
      if (rawName is! String || rawName.trim().isEmpty) continue;
      final artist = <String, dynamic>{'name': rawName.trim()};
      final dynamic rawId = entry is Map ? entry['id'] : null;
      if (rawId is String && rawId.trim().isNotEmpty) {
        artist['id'] = rawId.trim();
      }
      normalized.add(artist);
    }
    return normalized;
  }

  /// Marks an item whose metadata has not been resolved yet.
  static const resolvingExtra = 'isResolving';

  /// A stand-in for a song we only know the id of.
  ///
  /// Cloud sessions carry ordered ids, so the queue must be renderable before
  /// any metadata arrives. Deliberately non-empty title and non-null artist:
  /// `PlayerController.isDisplayableSong` hides the mini player on an empty
  /// title, and several widgets dereference `artist!`.
  static MediaItem placeholder(String videoId) => MediaItem(
    id: videoId,
    title: ' ',
    artist: '',
    playable: true,
    artUri: videoId.isEmpty
        ? null
        : Uri.parse('https://i.ytimg.com/vi/$videoId/hqdefault.jpg'),
    extras: {resolvingExtra: true},
  );

  static bool isResolving(MediaItem item) =>
      item.extras?[resolvingExtra] == true;

  static Duration? toDuration(String? time) {
    if (time == null) {
      return null;
    }

    int sec = 0;
    final splitted = time.split(":");
    if (splitted.length == 3) {
      sec +=
          int.parse(splitted[0]) * 3600 +
          int.parse(splitted[1]) * 60 +
          int.parse(splitted[2]);
    } else if (splitted.length == 2) {
      sec += int.parse(splitted[0]) * 60 + int.parse(splitted[1]);
    } else if (splitted.length == 1) {
      sec += int.parse(splitted[0]);
    }
    return Duration(seconds: sec);
  }

  static String displayDuration(MediaItem mediaItem) {
    final length = mediaItem.extras?['length'];
    if (length is String && length.trim().isNotEmpty) {
      return length.trim();
    }

    final duration = mediaItem.duration;
    if (duration == null) return "";

    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString()}:${seconds.toString().padLeft(2, '0')}';
  }

  static Map<String, dynamic> toJson(MediaItem mediaItem) => {
    "videoId": mediaItem.id,
    "title": mediaItem.title,
    'album': mediaItem.extras!['album'],
    'artists': mediaItem.extras!['artists'],
    'length': mediaItem.extras!['length'],
    'duration': mediaItem.duration?.inSeconds,
    'date': mediaItem.extras!['date'],
    'thumbnails': [
      {'url': mediaItem.artUri.toString()},
    ],
    'url': mediaItem.extras!['url'],
    'trackDetails': mediaItem.extras?['trackDetails'],
    'year': mediaItem.extras?['year'],
  };
}

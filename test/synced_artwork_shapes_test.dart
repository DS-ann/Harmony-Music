import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/artist.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/models/thumbnail.dart';

void main() {
  // Regression: cloud syncs from builds whose payload sanitizer stripped every
  // `url` (including artwork ones) wrote `thumbnails: [{}]` into the library
  // boxes. Reading `json['thumbnails'][0]['url']` on such a row yields null,
  // and the parsers then called `.isEmpty` on it or fed it into a non-null
  // String field — crashing the sync scan and the library screens on any device
  // that received those rows.
  const strippedByOlderSync = <String, dynamic>{
    'thumbnails': [<String, dynamic>{}],
  };

  group('thumbnailUrlFromJson', () {
    test('returns null for every unusable shape instead of throwing', () {
      for (final json in <dynamic>[
        null,
        'not a map',
        <String, dynamic>{},
        {'thumbnails': null},
        {'thumbnails': <dynamic>[]},
        {'thumbnails': 'not a list'},
        {
          'thumbnails': ['not a map'],
        },
        strippedByOlderSync,
        {
          'thumbnails': [
            {'url': null},
          ],
        },
        {
          'thumbnails': [
            {'url': ''},
          ],
        },
      ]) {
        expect(thumbnailUrlFromJson(json), isNull, reason: '$json');
      }
    });

    test('returns the URL when one is present', () {
      expect(
        thumbnailUrlFromJson({
          'thumbnails': [
            {'url': 'https://example.com/art.jpg'},
          ],
        }),
        'https://example.com/art.jpg',
      );
    });
  });

  group('Playlist.fromJson', () {
    test('falls back to the placeholder for artwork stripped by sync', () {
      final playlist = Playlist.fromJson({
        'title': 'Imported Spotify playlist export',
        'playlistId': 'PL123',
        ...strippedByOlderSync,
      });

      expect(playlist.thumbnailUrl, contains('playlist_placeholder'));
    });

    test('keeps a real artwork URL', () {
      final playlist = Playlist.fromJson({
        'title': 'Road trip',
        'playlistId': 'PL456',
        'thumbnails': [
          {'url': 'https://lh3.googleusercontent.com/cover'},
        ],
      });

      expect(playlist.thumbnailUrl, contains('lh3.googleusercontent.com'));
    });
  });

  group('Artist.fromJson', () {
    test('does not throw for artwork stripped by sync', () {
      final artist = Artist.fromJson({
        'artist': 'Some Artist',
        'browseId': 'UC123',
        'radioId': null,
        'subscribers': null,
        ...strippedByOlderSync,
      });

      expect(artist.name, 'Some Artist');
      expect(artist.thumbnailUrl, isEmpty);
    });
  });
}

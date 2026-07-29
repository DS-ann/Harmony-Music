import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/album.dart';

void main() {
  group('Album.fromJson', () {
    test('falls back to a safe placeholder artist for an empty list', () {
      // Regression: parseSongRuns can strip a leading type token ("Album")
      // with no real artist behind it, leaving artists: [] rather than null.
      // ContentListItem indexes artists[0] unconditionally, so an empty (but
      // non-null) list must not be passed through as-is.
      final album = Album.fromJson({
        'title': 'Some Album',
        'browseId': 'MPRE123',
        'artists': <Map<String, dynamic>>[],
        'thumbnails': [
          {'url': 'https://example.com/art.jpg'},
        ],
      });

      expect(album.artists, isNotEmpty);
    });

    test('does not throw when title, browseId, and thumbnails are null', () {
      expect(
        () => Album.fromJson({
          'title': null,
          'browseId': null,
          'artists': null,
          'thumbnails': null,
        }),
        returnsNormally,
      );
    });

    test('does not throw when thumbnails is an empty list', () {
      expect(
        () => Album.fromJson({
          'title': 'Some Album',
          'browseId': 'MPRE123',
          'artists': [
            {'name': 'Real Artist'},
          ],
          'thumbnails': <Map<String, dynamic>>[],
        }),
        returnsNormally,
      );
    });

    test('keeps a real artist and year intact', () {
      final album = Album.fromJson({
        'title': 'Some Album',
        'browseId': 'MPRE123',
        'artists': [
          {'name': 'Real Artist'},
        ],
        'year': '2023',
        'thumbnails': [
          {'url': 'https://example.com/art.jpg'},
        ],
      });

      expect(album.artists!.first['name'], 'Real Artist');
      expect(album.year, '2023');
    });
  });
}

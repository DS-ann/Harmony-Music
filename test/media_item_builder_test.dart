import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/models/media_Item_builder.dart';

void main() {
  test('accepts portable synced media without URL fields', () {
    final item = MediaItemBuilder.fromJson({
      'videoId': 'portable-song',
      'title': 'Portable song',
      'artists': [
        {'name': 'Harmony'},
      ],
      'duration': 120,
    });

    expect(item.id, 'portable-song');
    expect(item.artUri?.host, 'i.ytimg.com');
    expect(item.extras?['url'], isNull);
  });

  group('artist metadata normalization', () {
    test('normalizes mixed legacy and rich artist entries', () {
      final item = MediaItemBuilder.fromJson({
        'videoId': 'artist-test',
        'title': 'Mixed artists',
        'artists': [
          ' Legacy Artist ',
          {'name': ' Rich Artist ', 'id': ' UC_rich '},
          {'name': 'Id-less Artist', 'id': ''},
          {'id': 'UC_missing_name'},
          '',
          42,
          null,
        ],
      });

      expect(item.artist, 'Legacy Artist, Rich Artist, Id-less Artist');
      expect(item.extras?['artists'], [
        {'name': 'Legacy Artist'},
        {'name': 'Rich Artist', 'id': 'UC_rich'},
        {'name': 'Id-less Artist'},
      ]);
    });

    test('accepts one legacy artist string', () {
      final item = MediaItemBuilder.fromJson({
        'videoId': 'legacy-test',
        'title': 'Legacy artist',
        'artists': 'Cunami Flo',
      });

      expect(item.artist, 'Cunami Flo');
      expect(item.extras?['artists'], [
        {'name': 'Cunami Flo'},
      ]);
    });
  });
}

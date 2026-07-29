import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/data/repositories/hive_song_cache_repository.dart';
import 'package:harmonymusic/models/media_Item_builder.dart';
import 'package:harmonymusic/services/constant.dart';
import 'package:hive/hive.dart';

// Regression: metadata resolved while the Resolver only knew a song's video
// shape — channel as artist, letterboxed thumbnail, no album — was written to
// SongsCache, which is consulted before any network source. That pinned the
// thin view in place and no later, richer lookup could replace it.
void main() {
  group('a Resolver-shaped song keeps its album identity', () {
    test('an album with an id survives fromJson', () {
      // "Go to album" is gated on extras['album']['id'] existing.
      final song = MediaItemBuilder.fromJson({
        'videoId': 'abcdefghijk',
        'title': 'Za Tobom Lud',
        'artists': [
          {'name': 'Relja', 'id': 'UC_relja'},
        ],
        'album': {'name': 'Kamikaza', 'id': 'MPREb_kamikaza'},
        'thumbnails': [
          {'url': 'https://lh3.googleusercontent.com/cover'},
        ],
      });

      expect(song.extras!['album'], isA<Map>());
      expect(song.extras!['album']['id'], 'MPREb_kamikaza');
      expect(song.artUri.toString(), contains('lh3.googleusercontent.com'));
    });

    test(
      'an album without an id is dropped, as the album menu requires one',
      () {
        final song = MediaItemBuilder.fromJson({
          'videoId': 'abcdefghijk',
          'title': 'Za Tobom Lud',
          'album': {'name': 'Kamikaza'},
        });

        expect(song.extras!['album'], isNull);
      },
    );
  });

  group('purging thin cached songs', () {
    late Directory hiveDir;
    late HiveSongCacheRepository repository;

    setUp(() async {
      hiveDir = await Directory.systemTemp.createTemp('song_cache_test_');
      Hive.init(hiveDir.path);
      await Hive.openBox(BoxNames.songsCache);
      await Hive.openBox(BoxNames.songsUrlCache);
      repository = HiveSongCacheRepository();
    });

    tearDown(() async {
      await Hive.close();
      await hiveDir.delete(recursive: true);
    });

    test('drops entries with no album id and keeps rich ones', () async {
      final box = Hive.box(BoxNames.songsCache);
      await box.put('rich', {
        'videoId': 'rich',
        'title': 'Rich',
        'album': {'name': 'Kamikaza', 'id': 'MPREb_kamikaza'},
      });
      await box.put('no-album', {'videoId': 'no-album', 'title': 'Thin'});
      await box.put('album-without-id', {
        'videoId': 'album-without-id',
        'title': 'Thin',
        'album': {'name': 'Kamikaza'},
      });
      await box.put('empty-id', {
        'videoId': 'empty-id',
        'title': 'Thin',
        'album': {'name': 'Kamikaza', 'id': ''},
      });

      final removed = await repository.purgeSongsWithoutAlbumId();

      expect(removed, 3);
      expect(box.containsKey('rich'), isTrue);
      expect(box.containsKey('no-album'), isFalse);
      expect(box.containsKey('album-without-id'), isFalse);
      expect(box.containsKey('empty-id'), isFalse);
    });

    test('a malformed entry is dropped rather than throwing', () async {
      final box = Hive.box(BoxNames.songsCache);
      await box.put('junk', 'not a map');

      expect(await repository.purgeSongsWithoutAlbumId(), 1);
      expect(box.isEmpty, isTrue);
    });
  });
}

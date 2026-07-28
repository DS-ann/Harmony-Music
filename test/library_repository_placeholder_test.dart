import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/data/repositories/hive_library_repository.dart';
import 'package:harmonymusic/data/repositories/hive_song_cache_repository.dart';
import 'package:harmonymusic/models/media_Item_builder.dart';
import 'package:harmonymusic/services/constant.dart';
import 'package:hive/hive.dart';

// Regression: a cloud playback session shows a resolving placeholder
// (title ' ', artist null) before real metadata arrives. Favouriting or
// playing that placeholder used to persist it verbatim into LIBFAV/LIBRP,
// then propagate it via cloud sync as a blank/"null" favourite on every
// other device, because MediaItemBuilder.toJson does not carry the
// `isResolving` marker across the JSON round trip.
void main() {
  late Directory hiveDir;
  late HiveLibraryRepository repository;

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('library_repo_test_');
    Hive.init(hiveDir.path);
    await Hive.openBox(BoxNames.libFav);
    await Hive.openBox(BoxNames.libRP);
    await Hive.openBox(BoxNames.songsCache);
    await Hive.openBox(BoxNames.songDownloads);
    repository = HiveLibraryRepository();
  });

  tearDown(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  test('setFavorite ignores an unresolved placeholder', () async {
    final placeholder = MediaItemBuilder.placeholder('song-1');

    await repository.setFavorite(placeholder, true);

    expect(await repository.isFavorite('song-1'), isFalse);
    expect(await repository.getFavoriteSongs(), isEmpty);
  });

  test('addRecentlyPlayedSong ignores an unresolved placeholder', () async {
    final placeholder = MediaItemBuilder.placeholder('song-1');

    await repository.addRecentlyPlayedSong(placeholder);

    expect(await repository.getRecentlyPlayedSongs(), isEmpty);
  });

  test('setFavorite persists a song with real metadata', () async {
    final song = MediaItem(
      id: 'song-2',
      title: 'Real Song',
      artist: 'Artist',
      extras: const {},
    );

    await repository.setFavorite(song, true);

    final favorites = await repository.getFavoriteSongs();
    expect(favorites, hasLength(1));
    expect(favorites.first.title, 'Real Song');
  });

  test(
    'getFavoriteSongs repairs a placeholder already on disk from the song cache',
    () async {
      final favBox = await Hive.openBox(BoxNames.libFav);
      await favBox.put(
        'song-3',
        MediaItemBuilder.toJson(MediaItemBuilder.placeholder('song-3')),
      );
      await HiveSongCacheRepository().saveCachedSong(
        MediaItem(
          id: 'song-3',
          title: '100K',
          artist: 'Some Artist',
          extras: const {},
        ),
      );

      final favorites = await repository.getFavoriteSongs();

      expect(favorites, hasLength(1));
      expect(favorites.first.title, '100K');
      // The repair must also persist, so a later cloud sync uploads the
      // corrected title instead of re-queuing the blank one.
      final stored = favBox.get('song-3') as Map;
      expect(stored['title'], '100K');
    },
  );

  test('getFavoriteSongs leaves an unrepairable placeholder as-is', () async {
    final favBox = await Hive.openBox(BoxNames.libFav);
    await favBox.put(
      'song-4',
      MediaItemBuilder.toJson(MediaItemBuilder.placeholder('song-4')),
    );

    final favorites = await repository.getFavoriteSongs();

    expect(favorites, hasLength(1));
    expect(favorites.first.title.trim(), isEmpty);
  });
}

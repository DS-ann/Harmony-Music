import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/data/repositories/hive_library_repository.dart';
import 'package:harmonymusic/data/repositories/hive_settings_repository.dart';
import 'package:harmonymusic/services/constant.dart';
import 'package:hive/hive.dart';

// The Songs tab used to list every audio file the device held — downloads and
// anything incidentally cached while streaming — which belonged to no account
// and did not change when accounts did.
void main() {
  late Directory hiveDir;
  late HiveLibraryRepository library;

  setUp(() async {
    hiveDir = await Directory.systemTemp.createTemp('songs_filter_test_');
    Hive.init(hiveDir.path);
    for (final box in const [
      BoxNames.songDownloads,
      BoxNames.songsCache,
      BoxNames.libFav,
      BoxNames.appPrefs,
    ]) {
      await Hive.openBox(box);
    }
    library = HiveLibraryRepository();

    await Hive.box(BoxNames.songDownloads).put('liked-download', {
      'videoId': 'liked-download',
      'title': 'Liked download',
      'url': '/music/liked.m4a',
    });
    await Hive.box(BoxNames.songDownloads).put('plain-download', {
      'videoId': 'plain-download',
      'title': 'Plain download',
      'url': '/music/plain.m4a',
    });
    await Hive.box(
      BoxNames.songsCache,
    ).put('liked-cached', {'videoId': 'liked-cached', 'title': 'Liked cached'});
    await Hive.box(BoxNames.libFav).put('liked-download', {
      'videoId': 'liked-download',
      'title': 'Liked download',
    });
    await Hive.box(
      BoxNames.libFav,
    ).put('liked-cached', {'videoId': 'liked-cached', 'title': 'Liked cached'});
  });

  tearDown(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  Future<List<String>> ids({
    required bool likedOnly,
    required bool includeCached,
  }) async => (await library.getSongsTabList(
    likedOnly: likedOnly,
    includeCached: includeCached,
  )).map((song) => song.id).toList();

  test('with no account every download is listed', () async {
    expect(
      await ids(likedOnly: false, includeCached: false),
      containsAll(['liked-download', 'plain-download']),
    );
  });

  test('with an account only liked downloads are listed', () async {
    expect(await ids(likedOnly: true, includeCached: false), [
      'liked-download',
    ]);
  });

  test('cached songs stay out until they are asked for', () async {
    expect(
      await ids(likedOnly: true, includeCached: false),
      isNot(contains('liked-cached')),
    );
    expect(
      await ids(likedOnly: true, includeCached: true),
      containsAll(['liked-download', 'liked-cached']),
    );
  });

  test('included cached songs are still filtered by likes', () async {
    await Hive.box(
      BoxNames.songsCache,
    ).put('plain-cached', {'videoId': 'plain-cached', 'title': 'Plain cached'});

    expect(
      await ids(likedOnly: true, includeCached: true),
      isNot(contains('plain-cached')),
    );
    expect(
      await ids(likedOnly: false, includeCached: true),
      contains('plain-cached'),
    );
  });

  test('a download only in a playlist, never liked, stays hidden', () async {
    // "In your library" is LIBFAV and nothing else — playlist membership does
    // not count, which is what keeps the check to a single box read.
    final playlist = await Hive.openBox('PL_local_1');
    await playlist.add({'videoId': 'plain-download', 'title': 'Plain'});

    expect(
      await ids(likedOnly: true, includeCached: false),
      isNot(contains('plain-download')),
    );
  });

  group('device-scoped preferences', () {
    test('filters and the account subject default to off/absent', () {
      final settings = HiveSettingsRepository();

      expect(settings.getCloudAccountSubject(), isNull);
      expect(settings.getSongsShowUnlikedDownloads(), isFalse);
      expect(settings.getSongsIncludeCached(), isFalse);
      expect(settings.getUnlikedDownloadNoticeDismissed(), isFalse);
    });

    test('an empty stored subject reads as no account', () async {
      final settings = HiveSettingsRepository();
      await settings.setCloudAccountSubject('');

      expect(settings.getCloudAccountSubject(), isNull);

      await settings.setCloudAccountSubject('auth0|abc');
      expect(settings.getCloudAccountSubject(), 'auth0|abc');
    });
  });
}

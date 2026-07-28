import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/constant.dart';
import 'package:hive/hive.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

/// The Songs tab used to list every audio file the device held — downloads
/// and anything incidentally cached while streaming — belonging to no
/// account and unaffected by signing in. These drive the real Library screen
/// (not just `getSongsTabList` in isolation) to prove the toggle, the account
/// scoping and the empty state actually render and respond to taps.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Real files, not just Hive records: `startHouseKeeping` (run from
  // `LibrarySongsController.init()` on every boot) deletes any download whose
  // `url` names a file that doesn't exist on disk, so a seeded record backed
  // by a make-believe path is silently purged before the first frame the test
  // inspects — the app is right to do that outside tests, but it means these
  // helpers must back every seeded row with a file that's actually there.
  late Directory audioDir;

  setUpAll(() async {
    audioDir = await Directory.systemTemp.createTemp('harmony_it_audio_');
  });

  tearDownAll(() async {
    if (await audioDir.exists()) await audioDir.delete(recursive: true);
    final cachedSongsDir = Directory(
      '${(await getTemporaryDirectory()).path}/cachedSongs',
    );
    if (await cachedSongsDir.exists()) {
      await cachedSongsDir.delete(recursive: true);
    }
  });

  Future<String> realAudioFile(String name) async {
    final file = File('${audioDir.path}/$name.m4a');
    await file.writeAsBytes(const [0]);
    return file.path;
  }

  Future<void> seedDownloads({required bool likeOne}) async {
    final downloads = await Hive.openBox(BoxNames.songDownloads);
    await downloads.put('liked-song', {
      'videoId': 'liked-song',
      'title': 'Liked Song',
      'url': await realAudioFile('liked-song'),
    });
    await downloads.put('plain-song', {
      'videoId': 'plain-song',
      'title': 'Plain Song',
      'url': await realAudioFile('plain-song'),
    });
    if (likeOne) {
      final favourites = await Hive.openBox(BoxNames.libFav);
      await favourites.put('liked-song', {
        'videoId': 'liked-song',
        'title': 'Liked Song',
      });
    }
  }

  // `LibrarySongsController.init()` treats the SongsCache box as a mirror of
  // `<tmp>/cachedSongs/<id>.mp3` on disk and deletes any record without a
  // matching file there (its own from-scratch scan, separate from the
  // downloads house-keeping above) — so a cached-song seed needs one too.
  Future<void> markCachedOnDisk(String id) async {
    final cacheDir = (await getTemporaryDirectory()).path;
    final dir = Directory('$cacheDir/cachedSongs');
    await dir.create(recursive: true);
    await File('${dir.path}/$id.mp3').writeAsBytes(const [0]);
  }

  Future<void> seedCachedSongs({required bool likeOne}) async {
    final cache = await Hive.openBox(BoxNames.songsCache);
    await cache.put('liked-cached-song', {
      'videoId': 'liked-cached-song',
      'title': 'Liked Cached Song',
      'url': await realAudioFile('liked-cached-song'),
    });
    await markCachedOnDisk('liked-cached-song');
    await cache.put('plain-cached-song', {
      'videoId': 'plain-cached-song',
      'title': 'Plain Cached Song',
      'url': await realAudioFile('plain-cached-song'),
    });
    await markCachedOnDisk('plain-cached-song');
    if (likeOne) {
      final favourites = await Hive.openBox(BoxNames.libFav);
      await favourites.put('liked-cached-song', {
        'videoId': 'liked-cached-song',
        'title': 'Liked Cached Song',
      });
    }
  }

  /// The Library tab's Songs sub-tab is the first of five and shown by
  /// default, so reaching it only needs the bottom nav's Library icon.
  Future<void> openLibrary(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.library_music));
    await tester.pumpAndSettle();
  }

  testWidgets('with no account, Songs lists every download', (tester) async {
    await bootTestApp(tester, seedHive: () => seedDownloads(likeOne: false));
    await openLibrary(tester);

    expect(find.text('Liked Song'), findsWidgets);
    expect(find.text('Plain Song'), findsWidgets);
  });

  testWidgets('signed in, Songs lists only the liked download', (
    tester,
  ) async {
    final auth = FakeAuthService()
      ..restorableSession = testUserProfile(sub: 'auth0|user-1');

    await bootTestApp(
      tester,
      authService: auth,
      seedHive: () => seedDownloads(likeOne: true),
    );
    await openLibrary(tester);

    expect(find.text('Liked Song'), findsWidgets);
    expect(find.text('Plain Song'), findsNothing);
  });

  testWidgets('the "show downloads not in your library" filter reveals '
      'and re-hides the unliked download', (tester) async {
    final auth = FakeAuthService()
      ..restorableSession = testUserProfile(sub: 'auth0|user-1');
    await bootTestApp(
      tester,
      authService: auth,
      seedHive: () => seedDownloads(likeOne: true),
    );
    await openLibrary(tester);
    expect(find.text('Plain Song'), findsNothing);

    await tester.tap(find.byIcon(Icons.filter_alt_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show downloads not in your library'));
    await tester.pumpAndSettle();

    expect(find.text('Plain Song'), findsWidgets);

    // Close the menu, then flip it back off from the now-highlighted icon.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.filter_alt));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show downloads not in your library'));
    await tester.pumpAndSettle();

    expect(find.text('Plain Song'), findsNothing);
  });

  testWidgets(
    'the "include cached songs" filter reveals only the liked cached entry '
    'until "show downloads not in your library" is also on',
    (tester) async {
      final auth = FakeAuthService()
        ..restorableSession = testUserProfile(sub: 'auth0|user-1');
      await bootTestApp(
        tester,
        authService: auth,
        seedHive: () async {
          await seedDownloads(likeOne: true);
          await seedCachedSongs(likeOne: true);
        },
      );
      await openLibrary(tester);
      expect(find.text('Liked Cached Song'), findsNothing);
      expect(find.text('Plain Cached Song'), findsNothing);

      await tester.tap(find.byIcon(Icons.filter_alt_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Include cached songs'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Liked-only still applies: the cached-but-unliked entry stays hidden.
      expect(find.text('Liked Cached Song'), findsWidgets);
      expect(find.text('Plain Cached Song'), findsNothing);

      await tester.tap(find.byIcon(Icons.filter_alt));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show downloads not in your library'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.text('Plain Cached Song'), findsWidgets);
    },
  );

  testWidgets(
    'a fully-filtered Songs tab explains why and offers the way out',
    (tester) async {
      final auth = FakeAuthService()
        ..restorableSession = testUserProfile(sub: 'auth0|user-1');
      await bootTestApp(
        tester,
        authService: auth,
        // Nothing liked at all, so the liked-only filter hides everything.
        seedHive: () => seedDownloads(likeOne: false),
      );
      await openLibrary(tester);

      expect(
        find.textContaining('Songs shows downloads that are in your'),
        findsOneWidget,
      );

      await tester.tap(find.text('Show all downloads'));
      await tester.pumpAndSettle();

      expect(find.text('Liked Song'), findsWidgets);
      expect(find.text('Plain Song'), findsWidgets);
    },
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/app/providers/repository_providers.dart';
import 'package:harmonymusic/services/constant.dart';
import 'package:hive/hive.dart';
import 'package:integration_test/integration_test.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

/// The Songs tab hides anything not liked once an account is attached, so a
/// bare "download" tap can look like it did nothing. These drive the real
/// `SongInfoBottomSheet` + `SongDownloadButton` + `maybeAskAboutUnlikedDownload`
/// dialog to prove the explanation actually shows, both answers do what they
/// say, "don't ask again" sticks, and the cases with nothing to explain (no
/// account, already liked) stay silent.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> longPressSong(WidgetTester tester, String title) async {
    await tester.longPress(find.text(title));
    await tester.pumpAndSettle();
  }

  Future<void> tapDownloadButton(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.download));
    await tester.pumpAndSettle();
  }

  /// The dialog's own barrier tap only pops the dialog's route — the
  /// `SongInfoBottomSheet` underneath it is a separate route and stays open,
  /// so a second song's tile behind it either misses the tap entirely or
  /// (once the sheet's own ListTile duplicates the title) makes the finder
  /// ambiguous. One more barrier tap, well clear of the sheet's own content
  /// near the bottom of the screen, closes it.
  Future<void> closeBottomSheet(WidgetTester tester) async {
    await tester.tapAt(const Offset(200, 60));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'signed in, downloading an unliked song shows the explanatory dialog',
    (tester) async {
      final auth = FakeAuthService()
        ..restorableSession = testUserProfile(sub: 'auth0|user-1');
      await bootTestApp(tester, authService: auth);

      await longPressSong(tester, 'Fixture Song');
      await tapDownloadButton(tester);

      expect(find.text('This song is not in your library'), findsOneWidget);
      expect(
        find.textContaining('Songs shows downloads that are in your'),
        findsOneWidget,
      );
      expect(find.text('Like and download'), findsOneWidget);
      expect(find.text('Download only'), findsOneWidget);
    },
  );

  testWidgets('"Like and download" likes the song and starts the download', (
    tester,
  ) async {
    final auth = FakeAuthService()
      ..restorableSession = testUserProfile(sub: 'auth0|user-1');
    final handle = await bootTestApp(tester, authService: auth);

    await longPressSong(tester, 'Fixture Song');
    await tapDownloadButton(tester);
    await tester.tap(find.text('Like and download'));
    await tester.pumpAndSettle();

    final favourites = await Hive.openBox(BoxNames.libFav);
    expect(favourites.containsKey('song-1'), isTrue);
    expect(
      handle.downloader.downloadedSongs.map((s) => s.id),
      contains('song-1'),
    );
  });

  testWidgets('"Download only" starts the download and leaves LIBFAV alone', (
    tester,
  ) async {
    final auth = FakeAuthService()
      ..restorableSession = testUserProfile(sub: 'auth0|user-1');
    final handle = await bootTestApp(tester, authService: auth);

    await longPressSong(tester, 'Fixture Song');
    await tapDownloadButton(tester);
    await tester.tap(find.text('Download only'));
    await tester.pumpAndSettle();

    final favourites = await Hive.openBox(BoxNames.libFav);
    expect(favourites.containsKey('song-1'), isFalse);
    expect(
      handle.downloader.downloadedSongs.map((s) => s.id),
      contains('song-1'),
    );
  });

  testWidgets(
    '"don\'t ask again" suppresses the dialog for the next unliked download',
    (tester) async {
      final auth = FakeAuthService()
        ..restorableSession = testUserProfile(sub: 'auth0|user-1');
      final handle = await bootTestApp(tester, authService: auth);

      await longPressSong(tester, 'Fixture Song');
      await tapDownloadButton(tester);
      await tester.tap(find.text("Don't ask again"));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download only'));
      await tester.pumpAndSettle();
      await closeBottomSheet(tester);

      await longPressSong(tester, 'Fixture Song Two');
      await tapDownloadButton(tester);

      expect(find.text('This song is not in your library'), findsNothing);
      expect(
        handle.downloader.downloadedSongs.map((s) => s.id),
        containsAll(<String>['song-1', 'song-2']),
      );
    },
  );

  testWidgets(
    'dismissing the dialog starts no download and leaves the notice enabled',
    (tester) async {
      final auth = FakeAuthService()
        ..restorableSession = testUserProfile(sub: 'auth0|user-1');
      final handle = await bootTestApp(tester, authService: auth);

      await longPressSong(tester, 'Fixture Song');
      await tapDownloadButton(tester);
      // Tap the modal barrier, well away from the dialog card itself.
      await tester.tapAt(const Offset(200, 60));
      await tester.pumpAndSettle();

      expect(handle.downloader.downloadedSongs, isEmpty);
      // Read the persisted flag directly rather than re-driving the UI to
      // prove the dialog would reappear: closing the sheet and re-issuing a
      // longPress on the same tile in one test proved unreliable in practice
      // (the second longPress silently failed to reopen it, independent of
      // barrier-tap coordinates), and the settings flag is exactly what
      // `maybeAskAboutUnlikedDownload` itself checks before deciding to show.
      expect(
        handle.container
            .read(settingsRepositoryProvider)
            .getUnlikedDownloadNoticeDismissed(),
        isFalse,
      );
    },
  );

  testWidgets(
    'downloading an already-liked song starts immediately, no dialog',
    (tester) async {
      final auth = FakeAuthService()
        ..restorableSession = testUserProfile(sub: 'auth0|user-1');
      final handle = await bootTestApp(
        tester,
        authService: auth,
        seedHive: () async {
          final favourites = await Hive.openBox(BoxNames.libFav);
          await favourites.put('song-1', {
            'videoId': 'song-1',
            'title': 'Fixture Song',
          });
        },
      );

      await longPressSong(tester, 'Fixture Song');
      await tapDownloadButton(tester);

      expect(find.text('This song is not in your library'), findsNothing);
      expect(
        handle.downloader.downloadedSongs.map((s) => s.id),
        contains('song-1'),
      );
    },
  );

  testWidgets('with no account, downloading starts immediately, no dialog', (
    tester,
  ) async {
    final handle = await bootTestApp(tester);

    await longPressSong(tester, 'Fixture Song');
    await tapDownloadButton(tester);

    expect(find.text('This song is not in your library'), findsNothing);
    expect(
      handle.downloader.downloadedSongs.map((s) => s.id),
      contains('song-1'),
    );
  });
}

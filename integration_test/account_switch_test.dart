import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/app/providers/repository_providers.dart';
import 'package:harmonymusic/models/playlist.dart';
import 'package:harmonymusic/services/constant.dart';
import 'package:hive/hive.dart';
import 'package:integration_test/integration_test.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

/// Distinct from the unit-level `test/account_switch_test.dart`, which drives
/// `CloudSyncCoordinator.forgetAccountLibrary()` directly against Hive. These
/// drive the real Settings screen's sign-in button and the merge/replace
/// dialog it shows, so the actual `AuthController.login()`/`onFirstSignInWith
/// LocalLibrary` wiring — never exercised end to end before — gets covered.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// The sign-in button lives inside the Settings screen's "Account"
  /// expansion tile, collapsed by default — reaching it needs an extra tap.
  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
  }

  /// Pumps a fixed number of frames instead of settling.
  ///
  /// `pumpAndSettle` waits for frame scheduling to stop, and it never does
  /// while `AuthController.isBusy` is true: the Settings account row swaps its
  /// button for a `CircularProgressIndicator`, whose animation schedules a
  /// frame forever. `login()` stays busy for as long as the merge/replace
  /// dialog is unanswered, so every step from the login tap until that dialog
  /// is dismissed has a spinner on screen behind it and must pump explicitly.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tapLoginButton(WidgetTester tester) async {
    await tester.tap(find.text('Login / Register'));
    await pumpFrames(tester);
  }

  Future<void> seedLocalLibrary() async {
    final favourites = await Hive.openBox(BoxNames.libFav);
    await favourites.put('local-song', {
      'videoId': 'local-song',
      'title': 'Local Song',
    });
    final playlists = await Hive.openBox(BoxNames.libraryPlaylists);
    await playlists.put(
      'local-playlist',
      Playlist(
        title: 'Local Playlist',
        playlistId: 'local-playlist',
        thumbnailUrl: Playlist.thumbPlaceholderUrl,
      ).toJson(),
    );
  }

  testWidgets(
    'first sign-in with no local library skips the merge/replace dialog',
    (tester) async {
      final auth = FakeAuthService()
        ..nextLogin = testUserProfile(sub: 'auth0|user-1');
      final handle = await bootTestApp(tester, authService: auth);

      await openSettings(tester);
      await tapLoginButton(tester);

      expect(find.text('Music already on this device'), findsNothing);
      expect(auth.lastChooseAccount, isFalse);
      expect(
        handle.container
            .read(settingsRepositoryProvider)
            .getCloudAccountSubject(),
        'auth0|user-1',
      );
    },
  );

  testWidgets('Use another account requests a fresh provider account chooser', (
    tester,
  ) async {
    final auth = FakeAuthService()
      ..nextLogin = testUserProfile(sub: 'auth0|user-2');
    await bootTestApp(tester, authService: auth);

    await openSettings(tester);
    await tester.tap(find.text('Use another account'));
    await pumpFrames(tester);

    expect(auth.loginCallCount, 1);
    expect(auth.lastChooseAccount, isTrue);
    expect(find.text('Music already on this device'), findsNothing);
  });

  testWidgets(
    'first sign-in with a local library shows the merge/replace dialog',
    (tester) async {
      final auth = FakeAuthService()
        ..nextLogin = testUserProfile(sub: 'auth0|user-1');
      final handle = await bootTestApp(
        tester,
        authService: auth,
        seedHive: seedLocalLibrary,
      );

      await openSettings(tester);
      await tapLoginButton(tester);

      expect(find.text('Music already on this device'), findsOneWidget);
      expect(find.text('Add to my account'), findsOneWidget);
      expect(find.text("Use my account's library"), findsOneWidget);
      // The dialog is still up, so login() hasn't resolved and the
      // subject isn't stored yet — the answer decides what happens next.
      expect(
        handle.container
            .read(settingsRepositoryProvider)
            .getCloudAccountSubject(),
        isNull,
      );

      // Answer it: left open, AuthController.login() never resolves (nothing
      // else pops this route), which hangs the test at teardown forever
      // rather than failing it.
      await tester.tap(find.text('Add to my account'));
      await pumpFrames(tester);
    },
  );

  testWidgets('choosing "Add to my account" merges, keeping the local library', (
    tester,
  ) async {
    final auth = FakeAuthService()
      ..nextLogin = testUserProfile(sub: 'auth0|user-1');
    await bootTestApp(tester, authService: auth, seedHive: seedLocalLibrary);

    await openSettings(tester);
    await tapLoginButton(tester);
    await tester.tap(find.text('Add to my account'));
    await pumpFrames(tester);

    final favourites = await Hive.openBox(BoxNames.libFav);
    final playlists = await Hive.openBox(BoxNames.libraryPlaylists);
    expect(favourites.containsKey('local-song'), isTrue);
    expect(playlists.containsKey('local-playlist'), isTrue);
  });

  testWidgets(
    'choosing "Use my account\'s library" replaces the local library, '
    'keeping downloaded files',
    (tester) async {
      final auth = FakeAuthService()
        ..nextLogin = testUserProfile(sub: 'auth0|user-1');
      await bootTestApp(
        tester,
        authService: auth,
        seedHive: () async {
          await seedLocalLibrary();
          final downloads = await Hive.openBox(BoxNames.songDownloads);
          await downloads.put('downloaded-song', {
            'videoId': 'downloaded-song',
            'title': 'Downloaded Song',
          });
        },
      );

      await openSettings(tester);
      await tapLoginButton(tester);
      await tester.tap(find.text("Use my account's library"));
      await pumpFrames(tester);

      final favourites = await Hive.openBox(BoxNames.libFav);
      final playlists = await Hive.openBox(BoxNames.libraryPlaylists);
      final downloads = await Hive.openBox(BoxNames.songDownloads);
      expect(favourites.containsKey('local-song'), isFalse);
      expect(playlists.containsKey('local-playlist'), isFalse);
      expect(downloads.containsKey('downloaded-song'), isTrue);
    },
  );

  testWidgets(
    'restoring a session with no stored subject seeds it silently '
    '(the pre-account-scoping upgrade path)',
    (tester) async {
      final auth = FakeAuthService()
        ..restorableSession = testUserProfile(sub: 'auth0|user-1');
      final handle = await bootTestApp(tester, authService: auth);

      expect(find.text('Music already on this device'), findsNothing);
      expect(
        handle.container
            .read(settingsRepositoryProvider)
            .getCloudAccountSubject(),
        'auth0|user-1',
      );
    },
  );

  testWidgets(
    'signing in as a different account wipes silently, no dialog',
    (tester) async {
      final auth = FakeAuthService()
        ..restorableSession = testUserProfile(sub: 'auth0|old-user');
      final handle = await bootTestApp(
        tester,
        authService: auth,
        seedHive: seedLocalLibrary,
      );
      // Restored as the old account: the seeded library belongs to it.
      expect(
        handle.container
            .read(settingsRepositoryProvider)
            .getCloudAccountSubject(),
        'auth0|old-user',
      );

      await openSettings(tester);
      await tester.tap(find.text('Logout'));
      await pumpFrames(tester);

      auth.nextLogin = testUserProfile(sub: 'auth0|new-user');
      await tapLoginButton(tester);

      expect(find.text('Music already on this device'), findsNothing);
      final favourites = await Hive.openBox(BoxNames.libFav);
      final playlists = await Hive.openBox(BoxNames.libraryPlaylists);
      expect(favourites.containsKey('local-song'), isFalse);
      expect(playlists.containsKey('local-playlist'), isFalse);
      expect(
        handle.container
            .read(settingsRepositoryProvider)
            .getCloudAccountSubject(),
        'auth0|new-user',
      );
    },
  );

  testWidgets('signing in again as the same account clears nothing', (
    tester,
  ) async {
    final auth = FakeAuthService()
      ..restorableSession = testUserProfile(sub: 'auth0|user-1');
    final handle = await bootTestApp(
      tester,
      authService: auth,
      seedHive: seedLocalLibrary,
    );

    await openSettings(tester);
    await tester.tap(find.text('Logout'));
    await pumpFrames(tester);

    auth.nextLogin = testUserProfile(sub: 'auth0|user-1');
    await tapLoginButton(tester);

    expect(find.text('Music already on this device'), findsNothing);
    final favourites = await Hive.openBox(BoxNames.libFav);
    final playlists = await Hive.openBox(BoxNames.libraryPlaylists);
    expect(favourites.containsKey('local-song'), isTrue);
    expect(playlists.containsKey('local-playlist'), isTrue);
    expect(
      handle.container
          .read(settingsRepositoryProvider)
          .getCloudAccountSubject(),
      'auth0|user-1',
    );
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/app/providers/auth_providers.dart';
import 'package:harmonymusic/app/providers/repository_providers.dart';
import 'package:harmonymusic/services/constant.dart';
import 'package:hive/hive.dart';
import 'package:integration_test/integration_test.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

/// One chained run through the whole account-scoping story, in the order a
/// person would actually hit it: an account-less device with downloads, a
/// first sign-in that merges them, liking one, the session lapsing, then a
/// different account taking the device over.
///
/// The narrower files each prove one step in isolation; this one exists to
/// catch the interactions between them — state left behind by an earlier step
/// that only bites the next one.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory audioDir;

  setUpAll(() async {
    audioDir = await Directory.systemTemp.createTemp('harmony_it_lifecycle_');
  });

  tearDownAll(() async {
    if (await audioDir.exists()) await audioDir.delete(recursive: true);
  });

  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('an account-less library survives a merge, then a takeover', (
    tester,
  ) async {
    // Backed by real files: house-keeping drops download rows whose `url`
    // names nothing on disk (see account_songs_filter_test.dart).
    final firstAudio = File('${audioDir.path}/first.m4a');
    final secondAudio = File('${audioDir.path}/second.m4a');
    await firstAudio.writeAsBytes(const [0]);
    await secondAudio.writeAsBytes(const [0]);

    final auth = FakeAuthService();
    final handle = await bootTestApp(
      tester,
      authService: auth,
      // Step 1: an account-less device that has been used offline for a while.
      seedHive: () async {
        final downloads = await Hive.openBox(BoxNames.songDownloads);
        await downloads.put('first-song', {
          'videoId': 'first-song',
          'title': 'First Song',
          'url': firstAudio.path,
        });
        await downloads.put('second-song', {
          'videoId': 'second-song',
          'title': 'Second Song',
          'url': secondAudio.path,
        });
        final favourites = await Hive.openBox(BoxNames.libFav);
        await favourites.put('first-song', {
          'videoId': 'first-song',
          'title': 'First Song',
        });
      },
      cloudSyncEnabled: true,
    );
    final settings = handle.container.read(settingsRepositoryProvider);

    // With no account there is nothing to scope to: Songs lists both.
    await tester.tap(find.byIcon(Icons.library_music));
    await tester.pumpAndSettle();
    expect(find.text('First Song'), findsWidgets);
    expect(find.text('Second Song'), findsWidgets);

    // Step 2: first sign-in, with that library present — merge it.
    auth.nextLogin = testUserProfile(sub: 'auth0|first-user');
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Login / Register'));
    await pumpFrames(tester);

    expect(find.text('Music already on this device'), findsOneWidget);
    await tester.tap(find.text('Add to my account'));
    await pumpFrames(tester);
    expect(settings.getCloudAccountSubject(), 'auth0|first-user');

    // Merged, so the liked song stays and Songs now scopes to it — the
    // unliked download is still on the device, just not in the library.
    await tester.tap(find.byIcon(Icons.library_music));
    await tester.pumpAndSettle();
    expect(find.text('First Song'), findsWidgets);
    expect(find.text('Second Song'), findsNothing);

    // Step 3: the session lapses. The banner is the only thing that says so.
    final authController = handle.container.read(authControllerProvider);
    await auth.logout();
    authController.userProfile = null;
    authController.sessionExpired = true;
    authController.notifyListeners();
    await tester.pumpAndSettle();

    expect(find.textContaining('You have been signed out'), findsOneWidget);
    // The library is still the first account's, and still editable.
    expect(find.text('First Song'), findsWidgets);

    // Step 4: someone else signs in on this device. A different subject is a
    // takeover, not a merge: no dialog, the synced library goes.
    auth.nextLogin = testUserProfile(sub: 'auth0|second-user');
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Login / Register'));
    await pumpFrames(tester);

    expect(find.text('Music already on this device'), findsNothing);
    expect(settings.getCloudAccountSubject(), 'auth0|second-user');

    final favourites = await Hive.openBox(BoxNames.libFav);
    expect(favourites.containsKey('first-song'), isFalse);

    // The audio itself is never the account's to delete: both files are still
    // on disk, and their download records with them, so the new owner can
    // like them back into their own library without re-downloading.
    expect(await firstAudio.exists(), isTrue);
    expect(await secondAudio.exists(), isTrue);
    final downloads = await Hive.openBox(BoxNames.songDownloads);
    expect(downloads.containsKey('first-song'), isTrue);
    expect(downloads.containsKey('second-song'), isTrue);

    // And Songs reflects the empty library rather than showing the previous
    // account's music to its replacement.
    await tester.tap(find.byIcon(Icons.library_music));
    await tester.pumpAndSettle();
    expect(find.text('First Song'), findsNothing);
    expect(find.text('Second Song'), findsNothing);
  });
}

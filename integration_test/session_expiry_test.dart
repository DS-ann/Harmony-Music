import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/constant.dart';
import 'package:harmonymusic/ui/widgets/song_info_bottom_sheet.dart';
import 'package:hive/hive.dart';
import 'package:integration_test/integration_test.dart';

import 'support/fakes.dart';
import 'support/harness.dart';

/// A lapsed session used to be invisible: `tryRestoreSession` returned null,
/// the account row looked exactly like "never signed in", and sync silently
/// stopped reaching the account while edits piled up locally. These drive the
/// real Library banner and Settings account row to prove the state is now
/// actually surfaced, dismissible, cleared by signing back in — and that it
/// never blocks editing the library in the meantime.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// A device that was signed in as [subject] but can no longer restore it:
  /// the stored subject is what tells `AuthController.init()` this is an
  /// expired session rather than a first run.
  Future<void> seedLapsedSession(String subject) async {
    final prefs = await Hive.openBox(BoxNames.appPrefs);
    await prefs.put(PrefKeys.cloudAccountSubject, subject);
  }

  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> openLibrary(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.library_music));
    await tester.pumpAndSettle();
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a lapsed session shows the Library banner and the Settings account error',
    (tester) async {
      // restorableSession stays null: the stored subject is all that is left.
      await bootTestApp(
        tester,
        seedHive: () => seedLapsedSession('auth0|user-1'),
        cloudSyncEnabled: true,
      );

      await openLibrary(tester);
      expect(
        find.textContaining('You have been signed out'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);

      await openSettings(tester);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(
        find.textContaining('You have been signed out'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'dismissing the banner hides it but keeps the Settings account error',
    (tester) async {
      await bootTestApp(
        tester,
        seedHive: () => seedLapsedSession('auth0|user-1'),
        cloudSyncEnabled: true,
      );

      await openLibrary(tester);
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);

      // The badge is what persists until the session is actually restored.
      await openSettings(tester);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    },
  );

  testWidgets('tapping the banner opens Settings with Account expanded', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await bootTestApp(
      tester,
      authService: auth,
      seedHive: () => seedLapsedSession('auth0|user-1'),
      cloudSyncEnabled: true,
    );

    await openLibrary(tester);
    // The message itself, not the dismiss button beside it.
    await tester.tap(find.textContaining('You have been signed out'));
    await tester.pumpAndSettle();

    // Landed on Settings with the section already open, so the way to fix it
    // is right there rather than behind another tap.
    expect(find.text('Login / Register'), findsOneWidget);

    auth.nextLogin = testUserProfile(sub: 'auth0|user-1');
    await tester.tap(find.text('Login / Register'));
    await pumpFrames(tester);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('signing back in clears the banner and the account error', (
    tester,
  ) async {
    final auth = FakeAuthService();
    await bootTestApp(
      tester,
      authService: auth,
      seedHive: () => seedLapsedSession('auth0|user-1'),
      cloudSyncEnabled: true,
    );

    await openSettings(tester);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);

    auth.nextLogin = testUserProfile(sub: 'auth0|user-1');
    await tester.tap(find.text('Login / Register'));
    await pumpFrames(tester);

    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(find.textContaining('You have been signed out'), findsNothing);

    await openLibrary(tester);
    expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);
  });

  testWidgets('the library stays editable while the session is lapsed', (
    tester,
  ) async {
    await bootTestApp(
      tester,
      seedHive: () => seedLapsedSession('auth0|user-1'),
      cloudSyncEnabled: true,
    );

    // A stalled sync must never become a read-only library: the edit is made
    // locally now and pushed whenever the account is reachable again.
    await tester.longPress(find.text('Fixture Song'));
    await tester.pumpAndSettle();
    // Scoped to the sheet: the player behind it has its own favourite button.
    await tester.tap(
      find.descendant(
        of: find.byType(SongInfoBottomSheet),
        matching: find.byIcon(Icons.favorite_border),
      ),
    );
    await tester.pumpAndSettle();

    final favourites = await Hive.openBox(BoxNames.libFav);
    expect(favourites.containsKey('song-1'), isTrue);
  });
}

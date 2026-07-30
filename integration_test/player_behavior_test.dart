import 'package:audio_service/audio_service.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_lyric/flutter_lyric.dart';
import 'package:harmonymusic/app/providers/controller_providers.dart';
import 'package:harmonymusic/app/providers/repository_providers.dart';
import 'package:harmonymusic/app/providers/service_providers.dart';
import 'package:harmonymusic/l10n/l10n.dart';
import 'package:harmonymusic/services/cloud/playback_modes.dart';
import 'package:harmonymusic/services/constant.dart';
import 'package:harmonymusic/ui/player/components/album_art_lyrics.dart';
import 'package:harmonymusic/ui/player/components/lyrics_switch.dart';
import 'package:harmonymusic/ui/player/components/lyrics_widget.dart';
import 'package:harmonymusic/ui/player/components/mini_player.dart';
import 'package:harmonymusic/ui/player/components/player_control.dart';
import 'package:harmonymusic/ui/player/player_controller.dart';
import 'package:harmonymusic/ui/widgets/loader.dart';
import 'package:harmonymusic/ui/widgets/image_widget.dart';
import 'package:hive/hive.dart';
import 'package:integration_test/integration_test.dart';
import 'package:toggle_switch/toggle_switch.dart';

import 'support/harness.dart';
import 'support/fakes.dart';

/// Drives the real home, mini-player, full-player, and queue UI against the
/// shared fake audio boundary. These scenarios cover user-visible player
/// behavior without relying on YouTube, Resolver, or a physical audio device.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    String? reason,
  }) async {
    for (var attempt = 0; attempt < 30; attempt++) {
      if (condition()) return;
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(condition(), isTrue, reason: reason);
  }

  Future<TestAppHandle> startFixturePlayback(
    WidgetTester tester, {
    bool completeSourceLoad = true,
    FakeLyricsRepository? lyricsRepository,
  }) async {
    final handle = await bootTestApp(
      tester,
      lyricsRepository: lyricsRepository,
    );
    handle.audioHandler.completeSourceLoadsAutomatically = completeSourceLoad;
    final song = find.text('Fixture Song').hitTestable();
    expect(song, findsWidgets);

    await tester.tap(song.first);
    await pumpUntil(
      tester,
      () =>
          handle.audioHandler.queue.value.length == 2 &&
          handle.audioHandler.mediaItem.value?.id == 'song-1',
      reason: 'the selected song and its watch queue should reach the handler',
    );
    await tester.pump(const Duration(milliseconds: 300));
    return handle;
  }

  Future<void> openFullPlayer(WidgetTester tester) async {
    final miniTitle = find
        .descendant(
          of: find.byType(MiniPlayer),
          matching: find.text('Fixture Song'),
        )
        .hitTestable();
    expect(miniTitle, findsOneWidget);
    await tester.tap(miniTitle);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AlbumArtNLyrics).hitTestable(), findsOneWidget);
  }

  Future<void> openQueue(WidgetTester tester) async {
    final queueHandle = find.byIcon(Icons.keyboard_arrow_up).hitTestable();
    expect(queueHandle, findsOneWidget);
    await tester.tap(queueHandle);
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.byKey(const Key('queue-row-song-1-0')).hitTestable(),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('queue-row-song-2-1')).hitTestable(),
      findsOneWidget,
    );
  }

  Finder fullPlayerIcon(IconData icon) => find
      .descendant(
        of: find.byType(PlayerControlWidget),
        matching: find.byIcon(icon),
      )
      .hitTestable();

  Finder loadingIndicatorWithin(Finder parent) =>
      find.descendant(of: parent, matching: find.byType(LoadingIndicator));

  Finder fullPlayerArtwork() => find
      .descendant(
        of: find.byType(AlbumArtNLyrics),
        matching: find.byType(ImageWidget),
      )
      .hitTestable();

  Future<void> selectPlainLyrics(WidgetTester tester) async {
    final toggle = find.byType(ToggleSwitch).hitTestable();
    expect(toggle, findsOneWidget);
    final bounds = tester.getRect(toggle);
    await tester.tapAt(
      Offset(bounds.left + bounds.width * 0.75, bounds.center.dy),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets(
    'selecting a song starts playback and opens and closes the full player',
    (tester) async {
      final handle = await startFixturePlayback(tester);
      final controller = handle.container.read(playerControllerProvider);

      expect(handle.audioHandler.customActionNames, contains('setSourceNPlay'));
      expect(handle.audioHandler.playbackState.value.playing, isTrue);
      expect(controller.currentSong.value?.id, 'song-1');
      expect(controller.currentQueue.map((song) => song.id), [
        'song-1',
        'song-2',
      ]);
      expect(
        find
            .descendant(
              of: find.byType(MiniPlayer),
              matching: find.text('Fixture Song'),
            )
            .hitTestable(),
        findsOneWidget,
      );

      await openFullPlayer(tester);
      expect(fullPlayerIcon(Icons.skip_previous), findsOneWidget);
      expect(fullPlayerIcon(Icons.skip_next), findsOneWidget);

      await tester.tap(find.byIcon(Icons.keyboard_arrow_down).hitTestable());
      await tester.pump(const Duration(milliseconds: 700));
      expect(controller.playerPanelController.isPanelClosed, isTrue);
    },
  );

  testWidgets('play and pause controls update the active audio session', (
    tester,
  ) async {
    final handle = await startFixturePlayback(tester);
    await openFullPlayer(tester);

    final playButton = find.byKey(const Key('playButton')).hitTestable();
    await tester.tap(playButton);
    await tester.pump(const Duration(milliseconds: 400));
    expect(handle.audioHandler.pauseCallCount, 1);
    expect(handle.audioHandler.playbackState.value.playing, isFalse);

    await tester.tap(playButton);
    await tester.pump(const Duration(milliseconds: 400));
    expect(handle.audioHandler.playCallCount, 1);
    expect(handle.audioHandler.playbackState.value.playing, isTrue);
  });

  testWidgets('next and previous move through the queue in both directions', (
    tester,
  ) async {
    final handle = await startFixturePlayback(tester);
    final controller = handle.container.read(playerControllerProvider);
    await openFullPlayer(tester);

    await tester.tap(fullPlayerIcon(Icons.skip_next));
    await pumpUntil(
      tester,
      () => controller.currentSong.value?.id == 'song-2',
      reason: 'next should select the second queue item',
    );
    expect(handle.audioHandler.nextCallCount, 1);
    expect(find.text('Fixture Song Two'), findsWidgets);

    await tester.tap(fullPlayerIcon(Icons.skip_previous));
    await pumpUntil(
      tester,
      () => controller.currentSong.value?.id == 'song-1',
      reason: 'previous should return to the first queue item',
    );
    expect(handle.audioHandler.previousCallCount, 1);
  });

  testWidgets('remote mode snapshots update the mirrored UI and preferences', (
    tester,
  ) async {
    final handle = await startFixturePlayback(tester);
    final controller = handle.container.read(playerControllerProvider);
    final settings = handle.container.read(settingsRepositoryProvider);

    controller.applyRemotePlaybackModes(
      const CloudPlaybackModes(shuffle: true, repeat: true, queueLoop: true),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.isShuffleModeEnabled.value, isTrue);
    expect(controller.isLoopModeEnabled.value, isTrue);
    expect(controller.isQueueLoopModeEnabled.value, isTrue);
    expect(settings.getShuffleModeEnabled(), isTrue);
    expect(settings.getLoopModeEnabled(), isTrue);
    expect(settings.getQueueLoopModeEnabled(), isTrue);

    controller.applyRemotePlaybackModes(
      const CloudPlaybackModes(shuffle: false, repeat: false, queueLoop: false),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.isShuffleModeEnabled.value, isFalse);
    expect(controller.isLoopModeEnabled.value, isFalse);
    expect(controller.isQueueLoopModeEnabled.value, isFalse);
    expect(settings.getShuffleModeEnabled(), isFalse);
    expect(settings.getLoopModeEnabled(), isFalse);
    expect(settings.getQueueLoopModeEnabled(), isFalse);
  });

  testWidgets(
    'remote next immediately shows the exact incoming song at zero and loading',
    (tester) async {
      final handle = await startFixturePlayback(tester);
      final controller = handle.container.read(playerControllerProvider);
      final commands = handle.container.read(playbackCommandServiceProvider);

      commands.startRemoteControl('windows-target');
      controller.applyRemoteQueue(
        List<MediaItem>.from(controller.currentQueue),
        index: 0,
        positionMs: 42000,
        durationMs: const Duration(minutes: 3).inMilliseconds,
        playing: true,
      );
      await tester.pump(const Duration(milliseconds: 100));

      // This is the controller-side half of a user pressing Next. The command
      // transport itself is covered by remote_playback_test; here we exercise
      // the optimistic surface that must stay coherent until target frames
      // arrive over the socket.
      final transition = controller.beginRemoteSongTransition(
        List<MediaItem>.from(controller.currentQueue),
        1,
      );
      expect(transition, isNotNull);
      await tester.pump();

      expect(controller.currentSong.value?.id, 'song-2');
      expect(controller.progressBarStatus.value.current, Duration.zero);
      expect(controller.buttonState.value, PlayButtonState.loading);

      // The target can still have an in-flight progress frame for the old
      // song. It must not undo the controller's optimistic next transition.
      controller.applyRemoteProgress({
        'currentSongId': 'song-1',
        'positionMs': 45000,
        'durationMs': const Duration(minutes: 3).inMilliseconds,
        'playing': true,
        'loading': false,
        'publishedAtMs': DateTime.now().millisecondsSinceEpoch,
      });
      await tester.pump();
      expect(controller.currentSong.value?.id, 'song-2');
      expect(controller.progressBarStatus.value.current, Duration.zero);
      expect(controller.buttonState.value, PlayButtonState.loading);

      // The matching target frame confirms the transition. A loading frame
      // remains frozen; a ready frame alone clears the controller's spinner.
      controller.applyRemoteProgress({
        'currentSongId': 'song-2',
        'positionMs': 0,
        'durationMs': const Duration(minutes: 3).inMilliseconds,
        'playing': true,
        'loading': true,
        'publishedAtMs': DateTime.now().millisecondsSinceEpoch,
      });
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.progressBarStatus.value.current, Duration.zero);
      expect(controller.buttonState.value, PlayButtonState.loading);

      controller.applyRemoteProgress({
        'currentSongId': 'song-2',
        'positionMs': 0,
        'durationMs': const Duration(minutes: 3).inMilliseconds,
        'playing': true,
        'loading': false,
        'publishedAtMs': DateTime.now().millisecondsSinceEpoch,
      });
      await tester.pump();
      expect(controller.buttonState.value, PlayButtonState.playing);

      // Stop the controller ticker before the widget test disposes the tree.
      controller.applyRemoteProgress({
        'currentSongId': 'song-2',
        'positionMs': 0,
        'durationMs': const Duration(minutes: 3).inMilliseconds,
        'playing': false,
        'loading': false,
        'publishedAtMs': DateTime.now().millisecondsSinceEpoch,
      });
      await tester.pump();
    },
  );

  testWidgets(
    'controller follows, corrects, pauses, and freezes remote progress frames',
    (tester) async {
      final handle = await startFixturePlayback(tester);
      final controller = handle.container.read(playerControllerProvider);

      // The target clock is one second behind the controller. Its wall-clock
      // timestamp must not be treated as transport latency: doing so is what
      // made a phone visibly ahead of Windows in a real remote session.
      controller.applyRemoteProgress({
        'currentSongId': 'song-1',
        'positionMs': 10000,
        'durationMs': const Duration(minutes: 3).inMilliseconds,
        'playing': true,
        'loading': false,
        'speed': 1.0,
        'publishedAtMs': DateTime.now()
            .subtract(const Duration(seconds: 1))
            .millisecondsSinceEpoch,
      });
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await tester.pump();
      final projectedMs =
          controller.progressBarStatus.value.current.inMilliseconds;
      expect(
        projectedMs,
        inInclusiveRange(10000, 10450),
        reason:
            'the controller should follow from frame receipt, not peer clock skew',
      );

      // A newer sample is authoritative and must re-anchor the visible timer
      // rather than accumulating drift from the controller's own clock.
      controller.applyRemoteProgress({
        'currentSongId': 'song-1',
        'positionMs': 18000,
        'durationMs': const Duration(minutes: 3).inMilliseconds,
        'playing': true,
        'loading': false,
        'speed': 1.0,
        // A target clock ahead by two seconds must be equally harmless.
        'publishedAtMs': DateTime.now()
            .add(const Duration(seconds: 2))
            .millisecondsSinceEpoch,
      });
      await tester.pump();
      expect(
        controller.progressBarStatus.value.current.inMilliseconds,
        inInclusiveRange(18000, 18250),
        reason: 'a fresh target frame should correct the controller position',
      );

      // Pause and loading frames own the timer: neither is allowed to continue
      // extrapolating locally while the remote audio device is stopped/loading.
      controller.applyRemoteProgress({
        'currentSongId': 'song-1',
        'positionMs': 18300,
        'durationMs': const Duration(minutes: 3).inMilliseconds,
        'playing': false,
        'loading': false,
        'publishedAtMs': DateTime.now().millisecondsSinceEpoch,
      });
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await tester.pump();
      expect(controller.progressBarStatus.value.current.inMilliseconds, 18300);
      expect(controller.buttonState.value, PlayButtonState.paused);

      controller.applyRemoteProgress({
        'currentSongId': 'song-2',
        'positionMs': 0,
        'durationMs': const Duration(minutes: 4).inMilliseconds,
        'playing': true,
        'loading': true,
        'publishedAtMs': DateTime.now().millisecondsSinceEpoch,
      });
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await tester.pump();
      expect(controller.currentSong.value?.id, 'song-2');
      expect(controller.progressBarStatus.value.current, Duration.zero);
      expect(controller.buttonState.value, PlayButtonState.loading);
    },
  );

  Future<void> expectIncomingTrackWaitsAtZero(
    WidgetTester tester,
    TestAppHandle handle,
  ) async {
    final controller = handle.container.read(playerControllerProvider);
    await pumpUntil(
      tester,
      () => controller.currentSong.value?.id == 'song-2',
      reason: 'the incoming queue item should become the visible song',
    );

    // Android can briefly report ready at zero before the incoming network
    // source falls back to buffering. That transient ready event is not proof
    // that audible playback started and must not release the timer/loading UI.
    handle.audioHandler.reportCurrentLoadBuffering(
      reportedPosition: Duration.zero,
    );
    await tester.pump(const Duration(milliseconds: 100));
    handle.audioHandler.completeCurrentLoad();
    await tester.pump(const Duration(milliseconds: 100));
    handle.audioHandler.reportCurrentLoadBuffering();
    await tester.pump(const Duration(milliseconds: 100));

    final progressFinder = find.descendant(
      of: find.byType(PlayerControlWidget),
      matching: find.byType(ProgressBar),
    );
    expect(
      (
        controllerPosition: controller.progressBarStatus.value.current,
        visiblePosition: tester.widget<ProgressBar>(progressFinder).progress,
        buttonState: controller.buttonState.value,
        visibleLoadingIndicators: loadingIndicatorWithin(
          find.byType(PlayerControlWidget),
        ).evaluate().length,
      ),
      (
        controllerPosition: Duration.zero,
        visiblePosition: Duration.zero,
        buttonState: PlayButtonState.loading,
        visibleLoadingIndicators: 1,
      ),
      reason:
          'the incoming timer must stay at 0:00 and its play/pause control '
          'must show loading immediately, without the later-rebuffer grace',
    );

    await tester.pump(const Duration(seconds: 2));
    expect(
      controller.progressBarStatus.value.current,
      Duration.zero,
      reason: 'buffering time must not be counted as elapsed playback',
    );
    expect(tester.widget<ProgressBar>(progressFinder).progress, Duration.zero);
    expect(controller.buttonState.value, PlayButtonState.loading);
  }

  testWidgets(
    'manually skipped online song stays at zero and loading until ready',
    (tester) async {
      final handle = await startFixturePlayback(tester);
      final controller = handle.container.read(playerControllerProvider);
      await openFullPlayer(tester);

      handle.audioHandler.completeSourceLoadsAutomatically = false;
      await tester.tap(fullPlayerIcon(Icons.skip_next));
      await expectIncomingTrackWaitsAtZero(tester, handle);

      handle.audioHandler.completeCurrentLoad();
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.buttonState.value, PlayButtonState.playing);
      expect(
        loadingIndicatorWithin(find.byType(PlayerControlWidget)),
        findsNothing,
      );
    },
  );

  testWidgets(
    'automatically advanced online song stays at zero and loading until ready',
    (tester) async {
      final handle = await startFixturePlayback(tester);
      final controller = handle.container.read(playerControllerProvider);
      await openFullPlayer(tester);

      handle.audioHandler.completeSourceLoadsAutomatically = false;
      await handle.audioHandler.finishCurrentTrackAndAdvance();
      await expectIncomingTrackWaitsAtZero(tester, handle);

      handle.audioHandler.completeCurrentLoad();
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.buttonState.value, PlayButtonState.playing);
      expect(
        loadingIndicatorWithin(find.byType(PlayerControlWidget)),
        findsNothing,
      );
    },
  );

  testWidgets('the progress control sends the requested seek position', (
    tester,
  ) async {
    final handle = await startFixturePlayback(tester);
    await openFullPlayer(tester);

    final progressFinder = find.descendant(
      of: find.byType(PlayerControlWidget),
      matching: find.byType(ProgressBar),
    );
    expect(progressFinder, findsOneWidget);
    final progressBar = tester.widget<ProgressBar>(progressFinder);
    progressBar.onSeek!(const Duration(minutes: 1, seconds: 17));
    await tester.pump(const Duration(milliseconds: 300));

    expect(handle.audioHandler.seekPositions, [
      const Duration(minutes: 1, seconds: 17),
    ]);
    expect(
      handle.audioHandler.playbackState.value.updatePosition,
      const Duration(minutes: 1, seconds: 17),
    );
  });

  testWidgets(
    'seeking beyond loaded online audio freezes time and shows loading',
    (tester) async {
      final handle = await startFixturePlayback(tester);
      final controller = handle.container.read(playerControllerProvider);
      await openFullPlayer(tester);
      handle.audioHandler.bufferSeeks = true;

      final progressFinder = find.descendant(
        of: find.byType(PlayerControlWidget),
        matching: find.byType(ProgressBar),
      );
      final progressBar = tester.widget<ProgressBar>(progressFinder);
      const requestedPosition = Duration(minutes: 2, seconds: 5);
      progressBar.onSeek!(requestedPosition);
      await pumpUntil(
        tester,
        () => controller.progressBarStatus.value.current == requestedPosition,
        reason: 'the seek position should reach the visible progress bar',
      );
      // Buffering has a deliberate 350 ms grace period to avoid flashing the
      // spinner for tiny decoder stalls.
      await tester.pump(const Duration(milliseconds: 500));

      expect(controller.buttonState.value, PlayButtonState.loading);
      expect(
        loadingIndicatorWithin(find.byType(PlayerControlWidget)),
        findsOneWidget,
      );
      expect(
        loadingIndicatorWithin(find.byType(AlbumArtNLyrics)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(AlbumArtNLyrics),
          matching: find.byKey(const Key('online-song-artwork-shimmer')),
        ),
        findsNothing,
      );

      await tester.pump(const Duration(seconds: 2));
      expect(
        controller.progressBarStatus.value.current,
        requestedPosition,
        reason: 'elapsed time must not advance while online audio is buffering',
      );
      expect(
        tester.widget<ProgressBar>(progressFinder).progress,
        requestedPosition,
        reason: 'the visible timer bar must remain frozen while buffering',
      );

      await tester.tap(find.byIcon(Icons.keyboard_arrow_down).hitTestable());
      await tester.pump(const Duration(milliseconds: 700));
      expect(loadingIndicatorWithin(find.byType(MiniPlayer)), findsOneWidget);

      handle.audioHandler.completeCurrentLoad();
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.buttonState.value, PlayButtonState.playing);
      expect(loadingIndicatorWithin(find.byType(MiniPlayer)), findsNothing);
    },
  );

  testWidgets(
    'a newly selected online song stays at zero with loading buttons until ready',
    (tester) async {
      final handle = await startFixturePlayback(
        tester,
        completeSourceLoad: false,
      );
      final controller = handle.container.read(playerControllerProvider);

      expect(controller.progressBarStatus.value.current, Duration.zero);
      expect(controller.progressBarStatus.value.buffered, Duration.zero);
      expect(controller.buttonState.value, PlayButtonState.loading);
      expect(loadingIndicatorWithin(find.byType(MiniPlayer)), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(MiniPlayer),
          matching: find.byKey(const Key('online-song-artwork-shimmer')),
        ),
        findsOneWidget,
      );

      await openFullPlayer(tester);
      expect(
        loadingIndicatorWithin(find.byType(PlayerControlWidget)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AlbumArtNLyrics),
          matching: find.byKey(const Key('online-song-artwork-shimmer')),
        ),
        findsOneWidget,
      );
      expect(
        loadingIndicatorWithin(find.byType(AlbumArtNLyrics)),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(
        controller.progressBarStatus.value.current,
        Duration.zero,
        reason: 'a source that has not started must remain at 0:00',
      );
      final progressFinder = find.descendant(
        of: find.byType(PlayerControlWidget),
        matching: find.byType(ProgressBar),
      );
      expect(
        tester.widget<ProgressBar>(progressFinder).progress,
        Duration.zero,
        reason: 'the visible timer bar must remain at 0:00 before source start',
      );
      expect(controller.buttonState.value, PlayButtonState.loading);

      handle.audioHandler.completeCurrentLoad();
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.buttonState.value, PlayButtonState.playing);
      expect(
        find.byKey(const Key('online-song-artwork-shimmer')),
        findsNothing,
      );
      expect(
        loadingIndicatorWithin(find.byType(PlayerControlWidget)),
        findsNothing,
      );
    },
  );

  testWidgets(
    'lyrics show loading then synced and plain content and can be closed',
    (tester) async {
      const syncedLyrics = '[00:00.00]Fixture synced line';
      const plainLyrics = 'Fixture plain line one\nFixture plain line two';
      final lyricsRepository = FakeLyricsRepository(
        lyrics: const {'synced': syncedLyrics, 'plainLyrics': plainLyrics},
        completeReadsAutomatically: false,
      );
      final handle = await startFixturePlayback(
        tester,
        lyricsRepository: lyricsRepository,
      );
      final controller = handle.container.read(playerControllerProvider);
      await openFullPlayer(tester);

      await tester.tap(fullPlayerArtwork());
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.showLyricsFlag.value, isTrue);
      expect(controller.isLyricsLoading.value, isTrue);
      expect(loadingIndicatorWithin(find.byType(LyricsWidget)), findsOneWidget);

      lyricsRepository.completePendingRead();
      await pumpUntil(
        tester,
        () => !controller.isLyricsLoading.value,
        reason: 'cached lyrics should replace the loading indicator',
      );
      expect(controller.lyrics['synced'], syncedLyrics);
      expect(find.byType(LyricView), findsOneWidget);
      final lyricsContext = tester.element(find.byType(LyricsSwitch));
      expect(find.text(lyricsContext.l10n.synced), findsOneWidget);
      expect(find.text(lyricsContext.l10n.plain), findsOneWidget);

      await selectPlainLyrics(tester);
      expect(controller.lyricsMode.value, 1);
      expect(find.text(plainLyrics), findsOneWidget);

      final artworkBounds = tester.getRect(
        find.byType(AlbumArtNLyrics).hitTestable(),
      );
      await tester.tapAt(artworkBounds.topLeft + const Offset(20, 20));
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.showLyricsFlag.value, isFalse);
      expect(fullPlayerArtwork(), findsOneWidget);
      expect(lyricsRepository.getCallCount, 1);
    },
  );

  testWidgets('unavailable lyrics show clear messages in both modes', (
    tester,
  ) async {
    final lyricsRepository = FakeLyricsRepository(
      lyrics: const {'synced': 'NA', 'plainLyrics': 'NA'},
    );
    final handle = await startFixturePlayback(
      tester,
      lyricsRepository: lyricsRepository,
    );
    final controller = handle.container.read(playerControllerProvider);
    await openFullPlayer(tester);

    await tester.tap(fullPlayerArtwork());
    await tester.pump(const Duration(milliseconds: 300));
    await pumpUntil(
      tester,
      () => !controller.isLyricsLoading.value,
      reason: 'the unavailable cached result should finish loading',
    );
    final lyricsContext = tester.element(find.byType(LyricsSwitch));
    expect(
      find.text(lyricsContext.l10n.syncedLyricsNotAvailable),
      findsOneWidget,
    );

    await selectPlainLyrics(tester);
    expect(find.text(lyricsContext.l10n.lyricsNotAvailable), findsOneWidget);
    expect(lyricsRepository.getCallCount, 1);
  });

  testWidgets('changing songs closes lyrics and ignores a stale fetch', (
    tester,
  ) async {
    final lyricsRepository = FakeLyricsRepository(
      lyrics: const {
        'synced': '[00:00.00]Stale first-song lyric',
        'plainLyrics': 'Stale first-song lyric',
      },
      completeReadsAutomatically: false,
    );
    final handle = await startFixturePlayback(
      tester,
      lyricsRepository: lyricsRepository,
    );
    final controller = handle.container.read(playerControllerProvider);
    await openFullPlayer(tester);

    await tester.tap(fullPlayerArtwork());
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.isLyricsLoading.value, isTrue);

    await tester.tap(fullPlayerIcon(Icons.skip_next));
    await pumpUntil(
      tester,
      () => controller.currentSong.value?.id == 'song-2',
      reason: 'next should replace the song while lyrics are pending',
    );
    expect(controller.showLyricsFlag.value, isFalse);
    expect(controller.isLyricsLoading.value, isFalse);
    expect(controller.lyrics['synced'], isEmpty);
    expect(controller.lyrics['plainLyrics'], isEmpty);

    lyricsRepository.completePendingRead();
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.currentSong.value?.id, 'song-2');
    expect(controller.showLyricsFlag.value, isFalse);
    expect(controller.lyrics['synced'], isEmpty);
    expect(controller.lyrics['plainLyrics'], isEmpty);
    expect(find.text('Stale first-song lyric'), findsNothing);
  });

  testWidgets('shuffle and single-song repeat toggle on and back off', (
    tester,
  ) async {
    final handle = await startFixturePlayback(tester);
    final controller = handle.container.read(playerControllerProvider);
    await openFullPlayer(tester);

    await tester.tap(fullPlayerIcon(Icons.shuffle));
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.isShuffleModeEnabled.value, isTrue);
    expect(handle.audioHandler.shuffleModes.last, AudioServiceShuffleMode.all);

    await tester.tap(fullPlayerIcon(Icons.shuffle));
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.isShuffleModeEnabled.value, isFalse);
    expect(handle.audioHandler.shuffleModes.last, AudioServiceShuffleMode.none);

    await tester.tap(fullPlayerIcon(Icons.all_inclusive));
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.isLoopModeEnabled.value, isTrue);
    expect(handle.audioHandler.repeatModes.last, AudioServiceRepeatMode.one);

    await tester.tap(fullPlayerIcon(Icons.all_inclusive));
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.isLoopModeEnabled.value, isFalse);
    expect(handle.audioHandler.repeatModes.last, AudioServiceRepeatMode.none);
  });

  testWidgets('favorite toggles persist from the full player', (tester) async {
    await startFixturePlayback(tester);
    await openFullPlayer(tester);
    final favourites = await Hive.openBox(BoxNames.libFav);

    await tester.tap(fullPlayerIcon(Icons.favorite_border));
    await tester.pump(const Duration(milliseconds: 300));
    expect(favourites.containsKey('song-1'), isTrue);
    expect(fullPlayerIcon(Icons.favorite), findsOneWidget);

    await tester.tap(fullPlayerIcon(Icons.favorite));
    await tester.pump(const Duration(milliseconds: 300));
    expect(favourites.containsKey('song-1'), isFalse);
    expect(fullPlayerIcon(Icons.favorite_border), findsOneWidget);
  });

  testWidgets('queue rows select songs and remove only non-current songs', (
    tester,
  ) async {
    final handle = await startFixturePlayback(tester);
    final controller = handle.container.read(playerControllerProvider);
    await openFullPlayer(tester);
    await openQueue(tester);

    await tester.tap(find.byKey(const Key('queue-row-song-2-1')).hitTestable());
    await pumpUntil(
      tester,
      () => controller.currentSong.value?.id == 'song-2',
      reason: 'tapping a queue row should select that song',
    );
    expect(handle.audioHandler.playedIndices.last, 1);

    await tester.drag(
      find.byKey(const Key('queue-dismiss-song-1-0')).hitTestable(),
      const Offset(-500, 0),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(handle.audioHandler.queue.value.map((song) => song.id), ['song-2']);
    expect(controller.currentSong.value?.id, 'song-2');

    await tester.drag(
      find.byKey(const Key('queue-dismiss-song-2-0')).hitTestable(),
      const Offset(-500, 0),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      handle.audioHandler.queue.value.map((song) => song.id),
      ['song-2'],
      reason: 'the current song must not be dismissible from the queue',
    );
  });

  testWidgets('queue loop and clear controls reach the audio session', (
    tester,
  ) async {
    final handle = await startFixturePlayback(tester);
    final controller = handle.container.read(playerControllerProvider);
    await openFullPlayer(tester);
    await openQueue(tester);

    final initialQueueLoopMode = controller.isQueueLoopModeEnabled.value;
    await tester.tap(find.text('Queue loop').hitTestable());
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      controller.isQueueLoopModeEnabled.value,
      isNot(initialQueueLoopMode),
    );
    expect(
      handle.audioHandler.customActionNames,
      contains('toggleQueueLoopMode'),
    );

    await tester.tap(find.byIcon(Icons.playlist_remove).hitTestable());
    await pumpUntil(
      tester,
      () => handle.audioHandler.queue.value.isEmpty,
      reason: 'clear queue should empty the audio session queue',
    );
    expect(handle.audioHandler.customActionNames, contains('clearQueue'));
    expect(controller.currentQueue, isEmpty);
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preloading is exposed and scheduled on Android and Windows', () {
    final runtimePlatform = File(
      'lib/utils/runtime_platform.dart',
    ).readAsStringSync();
    final platformUtils = File(
      'lib/utils/platform_utils.dart',
    ).readAsStringSync();
    final settingsScreen = File(
      'lib/ui/screens/Settings/settings_screen.dart',
    ).readAsStringSync();
    final preloadService = File(
      'lib/services/playback_preload_service.dart',
    ).readAsStringSync();
    final preloadManager = File(
      'lib/services/playback_preload_manager.dart',
    ).readAsStringSync();
    final audioHandler = File(
      'lib/services/audio_handler.dart',
    ).readAsStringSync();
    final settingsRepository = File(
      'lib/data/repositories/hive_settings_repository.dart',
    ).readAsStringSync();

    expect(
      runtimePlatform,
      contains('supportsPlaybackPreloading => isAndroid || isWindows'),
    );
    expect(
      platformUtils,
      contains(
        'isPlaybackPreloadPlatform => isAndroidPlatform || isWindowsPlatform',
      ),
    );
    expect(
      settingsScreen,
      contains('if (RuntimePlatform.supportsPlaybackPreloading)'),
    );
    expect(
      preloadService,
      contains('if (!isPlaybackPreloadPlatform) return false'),
    );
    expect(
      preloadManager,
      contains('if (!isPlaybackPreloadPlatform || range <= 0 || !isPlaying)'),
    );
    expect(
      RegExp(
        r'if \(RuntimePlatform\.supportsPlaybackPreloading &&\s+playing &&',
      ).hasMatch(audioHandler),
      isTrue,
    );
    expect(
      RegExp(
        r'playbackPreloadRange[\s\S]*?value\.clamp\(0, 5\)[\s\S]*?'
        r'value\.clamp\(0, 5\)',
      ).hasMatch(settingsRepository),
      isTrue,
      reason: 'all five preload-range choices must persist',
    );
  });
}

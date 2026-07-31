import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows Auth0 callback separates Debug and Release protocols', () {
    final service = File('lib/services/auth0_service.dart').readAsStringSync();
    final runner = File('windows/runner/main.cpp').readAsStringSync();
    final resources = File('windows/runner/Runner.rc').readAsStringSync();
    final localRegistration = File(
      'windows/register_auth0_protocol.ps1',
    ).readAsStringSync();
    final installer = File(
      'windows/packaging/exe/inno_setup.iss',
    ).readAsStringSync();

    expect(
      service,
      contains("kDebugMode ? 'harmonymusic-dev' : 'harmonymusic'"),
    );
    expect(service, contains("appCustomURL: '\$_callbackScheme://callback'"));
    expect(
      runner,
      contains('kCallbackPrefix[] = L"harmonymusic-dev://callback"'),
    );
    expect(runner, contains('kCallbackPrefix[] = L"harmonymusic://callback"'));
    expect(runner, contains('harmony_music_dev_single_instance_mutex'));
    expect(runner, contains('harmony_music_single_instance_mutex'));
    expect(runner, contains('harmony_music_dev_auth0_callback'));
    expect(runner, contains('harmony_music_auth0_callback'));
    expect(runner, contains('Software\\\\Classes\\\\harmonymusic-dev'));
    expect(runner, contains('Software\\\\Classes\\\\harmonymusic'));
    expect(runner, contains('kWindowTitle[] = L"Harmony Music Dev"'));
    expect(runner, contains('kWindowTitle[] = L"Harmony Music"'));
    expect(
      runner,
      contains('FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", kWindowTitle)'),
    );
    expect(runner, contains('PLUGIN_STARTUP_URL'));
    expect(runner, contains('CreateNamedPipeW'));
    expect(runner, contains('RegisterProtocolHandlerIfMissing()'));
    expect(runner, contains('HasRegisteredProtocolHandler()'));
    expect(runner, contains('RegGetValueW'));
    expect(runner, contains('RegCreateKeyExW'));
    expect(runner, contains('GetModuleFileNameW'));
    expect(
      runner.indexOf('RegisterProtocolHandlerIfMissing();'),
      lessThan(runner.indexOf('CreateMutexW')),
    );
    expect(resources, contains('#ifdef _DEBUG'));
    expect(
      resources,
      contains('#define HARMONY_PRODUCT_NAME "harmonymusic_dev"'),
    );
    expect(resources, contains('#define HARMONY_PRODUCT_NAME "harmonymusic"'));
    expect(
      resources,
      contains('VALUE "ProductName", HARMONY_PRODUCT_NAME "\\0"'),
    );
    expect(
      localRegistration,
      contains(r'HKCU:\Software\Classes\harmonymusic-dev'),
    );
    expect(localRegistration, contains('harmonymusic-dev://'));
    expect(installer, contains('Software\\Classes\\harmonymusic'));
    expect(installer, isNot(contains('Software\\Classes\\harmonymusic-dev')));
    expect(installer, contains('harmonymusic.exe'));
  });
}

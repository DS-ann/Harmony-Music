import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows Auth0 callback uses one registered protocol', () {
    final service = File('lib/services/auth0_service.dart').readAsStringSync();
    final runner = File('windows/runner/main.cpp').readAsStringSync();
    final installer = File(
      'windows/packaging/exe/inno_setup.iss',
    ).readAsStringSync();

    expect(service, contains("_windowsCallbackScheme = 'harmonymusic'"));
    expect(service, contains("appCustomURL: '\$_callbackScheme://callback'"));
    expect(runner, contains('kCallbackPrefix[] = L"harmonymusic://callback"'));
    expect(runner, contains('PLUGIN_STARTUP_URL'));
    expect(runner, contains('CreateNamedPipeW'));
    expect(installer, contains('Software\\Classes\\harmonymusic'));
    expect(installer, contains('harmonymusic.exe'));
  });
}

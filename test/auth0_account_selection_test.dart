import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = File('lib/services/auth0_service.dart').readAsStringSync();

  test('account-switch login forces Auth0 reauthentication', () {
    expect(
      service,
      contains(
        'static const _accountSelectionLoginParameters = <String, String>{',
      ),
    );
    expect(service, contains("'prompt': 'login'"));
    expect(service, isNot(contains('ext-google-prompt')));
    expect(service, contains('final parameters = chooseAccount'));
    expect(
      RegExp(r'parameters:\s*parameters').allMatches(service),
      hasLength(2),
    );
  });

  test('ordinary login does not force account selection', () {
    expect(
      RegExp(
        r'chooseAccount\s*\?\s*_accountSelectionLoginParameters\s*'
        r':\s*const <String, String>\{\}',
      ).hasMatch(service),
      isTrue,
    );
  });

  test('ordinary logout stays scoped to the app', () {
    expect(service, isNot(contains('federated: true')));
  });

  test('session restoration diagnostics do not include exception contents', () {
    expect(
      RegExp(r'_logSessionRestoreFailure\(error\)').allMatches(service),
      hasLength(2),
    );
    expect(
      service,
      contains("'Auth0 session restoration failed (\${error.runtimeType}).'"),
    );
    expect(
      service,
      isNot(contains(r'Auth0 session restoration failed: $error')),
    );
  });
}

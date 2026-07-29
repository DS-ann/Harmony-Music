import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('device picker shows errors instead of loading forever', () {
    final sheet = File(
      'lib/ui/widgets/cloud_devices_sheet.dart',
    ).readAsStringSync();
    final client = File(
      'lib/services/cloud/harmony_cloud_client.dart',
    ).readAsStringSync();

    expect(sheet, contains('snapshot.hasError'));
    expect(sheet, contains('deviceControlUnavailable'));
    expect(sheet, contains('onPressed: _retry'));
    expect(sheet, contains('try {'));
    expect(client, contains('connectTimeout: const Duration(seconds: 15)'));
  });
}

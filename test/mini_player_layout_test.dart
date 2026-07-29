import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('compact mini-player controls fit their minimum touch targets', () {
    final source = File(
      'lib/ui/player/components/mini_player.dart',
    ).readAsStringSync();

    expect(source, contains(': 144,'));
    expect(source, contains('SizedBox.square('));
    expect(source, contains('dimension: 50,'));
    expect(source, contains('width: 40,'));
  });
}

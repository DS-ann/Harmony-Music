import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('album screen listens to its observable song list', () {
    final source = File(
      'lib/ui/screens/Album/album_screen.dart',
    ).readAsStringSync();

    expect(source, contains('albumController.songList'));
  });
}

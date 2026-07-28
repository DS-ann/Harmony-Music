import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wide mini player uses the same play-button wrapper as mobile', () {
    final source = File(
      'lib/ui/player/components/mini_player.dart',
    ).readAsStringSync();

    expect(source, contains('? const CircleAvatar('));
    expect(source, contains('radius: 35,'));
    expect(source, contains("key: Key('playButton')"));
    expect(
      source,
      isNot(
        contains(
          'backgroundColor: Theme.of(\n                                            context,\n                                          ).colorScheme.secondary',
        ),
      ),
    );
  });
}

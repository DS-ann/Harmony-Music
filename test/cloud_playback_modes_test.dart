import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/services/cloud/playback_modes.dart';

void main() {
  test('missing mode fields remain unspecified for older sessions', () {
    final modes = CloudPlaybackModes.fromMap(const {'queueIds': []});

    expect(modes.hasAny, isFalse);
    expect(modes.toMap(), isEmpty);
  });

  test('explicit false values survive parsing and merging', () {
    final existing = const CloudPlaybackModes(
      shuffle: true,
      repeat: true,
      queueLoop: true,
    );
    final incoming = CloudPlaybackModes.fromMap(const {
      'shuffle': false,
      'repeat': false,
      'queueLoop': false,
    });

    expect(existing.merge(incoming).toMap(), {
      'shuffle': false,
      'repeat': false,
      'queueLoop': false,
    });
  });

  test('partial updates preserve fields they did not carry', () {
    const existing = CloudPlaybackModes(
      shuffle: false,
      repeat: false,
      queueLoop: true,
    );

    expect(existing.merge(const CloudPlaybackModes(repeat: true)).toMap(), {
      'shuffle': false,
      'repeat': true,
      'queueLoop': true,
    });
  });
}

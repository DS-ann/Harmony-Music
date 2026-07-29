import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('song info artist metadata guard', () {
    late String source;

    setUpAll(() {
      source = File(
        'lib/ui/widgets/song_info_bottom_sheet.dart',
      ).readAsStringSync();
    });

    test(
      'legacy strings and malformed entries are rejected before map access',
      () {
        expect(source, contains('if (artists is! List) return const [];'));
        expect(source, contains('if (entry is! Map) continue;'));
        expect(
          source,
          contains("if (id is! String || id.trim().isEmpty) continue;"),
        );
        expect(source, isNot(contains('each.containsKey("id")')));
      },
    );

    test('both widget and controller use the guarded artist list', () {
      expect(RegExp(r'_navigableArtists\(song\)').allMatches(source).length, 2);
    });
  });
}

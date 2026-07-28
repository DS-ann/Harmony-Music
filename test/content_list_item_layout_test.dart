import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('content cards reserve enough text space in every grid', () {
    final item = File(
      'lib/ui/widgets/content_list_widget_item.dart',
    ).readAsStringSync();
    final library = File(
      'lib/ui/screens/Library/library.dart',
    ).readAsStringSync();

    expect(item, contains('const contentListItemHeight = 192.0;'));
    expect(item, contains('height: contentListItemHeight,'));
    expect(
      library,
      contains('const double itemHeight = contentListItemHeight;'),
    );
  });
}

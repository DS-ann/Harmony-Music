import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Android debug builds can run without committed Firebase credentials',
    () {
      final buildGradle = File('android/app/build.gradle').readAsStringSync();

      expect(buildGradle, contains("file('google-services.json').exists()"));
      expect(
        buildGradle,
        contains("apply plugin: 'com.google.gms.google-services'"),
      );
      expect(buildGradle, contains("contains('release')"));
      expect(
        buildGradle,
        contains('google-services.json is required for release'),
      );
    },
  );
}

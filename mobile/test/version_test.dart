import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vayora/config.dart';

void main() {
  test('Settings version label equals pubspec version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final m = RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+\d+', multiLine: true).firstMatch(pubspec);
    expect(m, isNotNull);
    expect(Config.versionLabel, m!.group(1));
  });
}

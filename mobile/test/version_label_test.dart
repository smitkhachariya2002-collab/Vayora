import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vayora/theme.dart';

void main() {
  test('Settings version label matches pubspec version', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    final name = line.split(':')[1].trim().split('+').first;
    expect(AppBrand.version, name);
  });
}

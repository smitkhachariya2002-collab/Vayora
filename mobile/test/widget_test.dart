import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vayora/theme.dart';

void main() {
  test('text and action colours remain readable on the new palette', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
    }
    for (final surface in [Tokens.background, Tokens.surface]) {
      expect(contrast(Tokens.text, surface), greaterThanOrEqualTo(4.5));
      expect(contrast(Tokens.muted, surface), greaterThanOrEqualTo(4.5));
      expect(contrast(Tokens.accent, surface), greaterThanOrEqualTo(4.5));
    }
    for (final colour in Tokens.gradient.colors) {
      expect(contrast(const Color(0xFFFFFFFF), colour), greaterThanOrEqualTo(4.5));
    }
    expect(Tokens.gold, const Color(0xFFFFC94D));
  });
}


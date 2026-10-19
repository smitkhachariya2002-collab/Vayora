import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vayora/theme.dart';

double contrast(Color a,Color b) {
  final x=a.computeLuminance(),y=b.computeLuminance();
  return ((x>y?x:y)+.05)/((x<y?x:y)+.05);
}
void main() {
  test('Royal Violet controls and reading surfaces meet AA',() {
    expect(AppColors.primary,const Color(0xFF7C5CFF));
    expect(AppColors.accent,const Color(0xFFFF5CA8));
    for (final bg in [AppColors.background,AppColors.surface,AppColors.surfaceHigh,AppColors.selectedPlan]) {
      expect(contrast(AppColors.text,bg),greaterThanOrEqualTo(4.5));
      expect(contrast(AppColors.muted,bg),greaterThanOrEqualTo(4.5));
      expect(contrast(AppColors.primaryText,bg),greaterThanOrEqualTo(4.5));
    }
    for (final bg in [AppColors.controlPrimary,...AppColors.actionGradient.colors]) {
      expect(contrast(AppColors.white,bg),greaterThanOrEqualTo(4.5));
    }
    expect(contrast(AppColors.ink,AppColors.gold),greaterThanOrEqualTo(4.5));
    final t=buildTheme();
    expect(t.textSelectionTheme.cursorColor,AppColors.primary);
    expect(t.appBarTheme.systemOverlayStyle!.systemNavigationBarColor,AppColors.background);
  });
}

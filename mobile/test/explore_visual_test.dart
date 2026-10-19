import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vayora/screens/content.dart';
import 'package:vayora/theme.dart';
import 'package:vayora/widgets/common.dart';
import 'account_test.dart' show Fixture;

void main() {
  for (final suggestions in [false, true]) {
    testWidgets('Explore categories lead with 16px inset; suggestions=$suggestions', (tester) async {
      tester.view.physicalSize = const Size(360, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = Fixture();
      f.intercept = (r) {
        if (r.url.path.endsWith('/channels') || r.url.path.endsWith('/posts')) {
          return http.Response(jsonEncode(r.url.path.endsWith('/channels') && suggestions ? [
            {'id':'demo-channel','name':'India stories','audience':'all','created_by':'other','review_status':'approved','status':'published'}
          ] : []), 200, request: r, headers: {'content-type':'application/json'});
        }
        return null;
      };
      await tester.runAsync(f.start);
      await tester.pumpWidget(MaterialApp(theme:buildTheme(),home:Scaffold(body:ContentList(state:f.state))));
      for (var i=0;i<12;i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds:20)));
        await tester.pump(const Duration(milliseconds:100));
      }
      expect(tester.getTopLeft(find.byType(ChoiceChip).first).dy, 16);
      expect(find.text('Latest'),findsOneWidget);
      expect(find.text('Nothing here yet'),findsOneWidget, reason: find.byType(Text).evaluate().map((e) => (e.widget as Text).data).join(' | '));
      expect(find.text('Discover a channel or create your own.'),findsOneWidget);
      expect(find.byType(NoticeCard),findsNothing);
      expect(find.text('India stories'), suggestions ? findsOneWidget : findsNothing);
      if (suggestions) {
        expect(tester.getTopLeft(find.text('India stories')).dy, greaterThan(tester.getTopLeft(find.byType(ChoiceChip).first).dy));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(f.close);
    });
  }
}

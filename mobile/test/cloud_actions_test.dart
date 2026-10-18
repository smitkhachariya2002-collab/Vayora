import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vayora/main.dart';
import 'package:vayora/theme.dart';
import 'account_test.dart' show Fixture;

void main() {
  testWidgets(
    'Cloud has one working Upload action and no overlapping floating button',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final kinds = <String>[];
      const media = MethodChannel('app/media');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(media, (
        call,
      ) async {
        kinds.add((call.arguments as Map)['kind'] as String);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          media,
          null,
        ),
      );
      final f = Fixture();
      f.intercept = (r) =>
          [
            '/cloud_files',
            '/posts',
            '/channel_members',
            '/profiles',
          ].any((p) => r.url.path.endsWith(p))
          ? http.Response(
              jsonEncode(<Object>[]),
              200,
              request: r,
              headers: {'content-type': 'application/json'},
            )
          : null;
      await tester.runAsync(f.start);
      await f.state.prefs.setBool('consent_v1', true);
      f.currentStatus = {
        'is_premium': true,
        'plan_name': 'Trial',
        'quota_bytes': 2199023255552,
        'used_bytes': 0,
      };
      await tester.runAsync(
        () => f.state.login('member@example.test', 'password123'),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Home(state: f.state),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cloud').last);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('Upload'), findsOneWidget);
      expect(find.text('Add files or folder'), findsNothing);
      await tester.ensureVisible(find.text('Upload'));
      await tester.runAsync(() async {
        await tester.tap(find.text('Upload'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Photos & Videos'), findsOneWidget);
      expect(find.text('Files'), findsOneWidget);
      await tester.tap(find.text('Photos & Videos'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(kinds, ['media']);
      await tester.runAsync(() async {
        await tester.tap(find.text('Upload'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(kinds, ['media', 'any']);
      expect(find.byTooltip('New folder'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(f.close);
    },
  );
}

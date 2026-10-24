import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vayora/main.dart';
import 'package:vayora/theme.dart';
import 'account_test.dart' show Fixture;

void main() {
  testWidgets(
    'Server free mode removes plans, prices and payment actions from account UI',
    (tester) async {
      final f = Fixture();
      f.intercept = (request) {
        if (request.url.path.endsWith('/plans') ||
            request.url.path.endsWith('/payment_orders')) {
          return http.Response(
            jsonEncode(<Object>[]),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        return null;
      };
      await tester.runAsync(f.start);
      f.currentStatus = {
        'free_mode': true,
        'has_ads_access': false,
        'access_status': 'pending',
        'quota_bytes': 15 * 1024 * 1024 * 1024,
      };
      await tester.runAsync(
        () => f.state.login('existing@example.test', 'password123'),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Plans(state: f.state),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Vayora is free'), findsOneWidget);
      expect(find.text('Request received'), findsOneWidget);
      expect(find.text('Continue to payment'), findsNothing);
      expect(find.textContaining('₹'), findsNothing);
      expect(find.textContaining('UPI'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(body: Profile(state: f.state)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AccountProfile), findsOneWidget);
      expect(find.byKey(const ValueKey('web-plans')), findsNothing);
      expect(find.textContaining('₹'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(f.close);
    },
  );
}

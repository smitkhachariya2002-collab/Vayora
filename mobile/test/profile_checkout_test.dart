import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vayora/plan_catalog.dart';
import 'package:vayora/screens/profile.dart';
import 'package:vayora/screens/premium.dart';
import 'package:vayora/theme.dart';
import 'account_test.dart' show Fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Profile selection pays exact price and opens server-confirmed success',
    (tester) async {
      final f = Fixture();
      var launches = 0;
      final plan = {
        'id': 'trial',
        'name': 'Trial',
        'price_inr': 1,
        'duration_days': 1,
        'active': true,
      };
      final order = {
        'id': 'fresh',
        'reference': 'VYPROFILE',
        'amount_paise': 100,
        'duration_days': 1,
        'plan_id': 'trial',
        'upi_id': 'test@upi',
        'payee_name': 'Test',
        'status': 'paid',
        'plans': {'name': 'Trial'},
      };
      http.Response reply(http.Request r, Object? body) => http.Response(
        jsonEncode(body),
        200,
        request: r,
        headers: {'content-type': 'application/json'},
      );
      f.intercept = (r) {
        if (r.url.path.endsWith('/plans')) return reply(r, [plan]);
        if (r.url.path.endsWith('/create_payment_order')) {
          return reply(r, order);
        }
        if (r.url.path.endsWith('/report_result')) {
          f.currentStatus = {'is_premium':true,'plan_name':'Trial'};
          return reply(r, 'paid');
        }
        if (r.url.path.endsWith('/payment_orders')) {
          return reply(
            r,
            r.url.queryParameters.containsKey('id') ? order : [order],
          );
        }
        return null;
      };
      await tester.runAsync(f.start);
      await tester.runAsync(
        () => f.state.login('member@example.test', 'password123'),
      );
      final catalog = PlanCatalog(f.db, changes: const Stream<void>.empty());
      await tester.runAsync(catalog.refresh);
      const channel = MethodChannel('app/upi');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'pending') return <String, String>{};
            if (call.method == 'pay') {
              launches++;
              final uri = Uri.parse((call.arguments as Map)['uri'] as String);
              expect(uri.queryParameters['tr'], 'VYPROFILE');
              expect(uri.queryParameters['am'], '1.00');
              return 'Status=SUCCESS&txnRef=VYPROFILE&txnId=PROFILE001';
            }
            return null;
          });
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(body: Profile(state: f.state, catalog: catalog)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PlanCard), findsOneWidget);
      expect(find.text('Explore Premium'), findsNothing);
      expect(find.text('My Channels'), findsNothing);
      await tester.tap(find.text('Trial'));
      await tester.pumpAndSettle();
      expect(find.text('Pay ₹1 via UPI'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Pay ₹1 via UPI'));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(launches, 1);
      expect(
        find.text('Payment successful! Your plan is now active.'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(find.text('Done'),200,scrollable:find.byType(Scrollable).first);
      await tester.tap(find.text('Done'));
      await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:100)));
      await tester.pumpAndSettle();
      expect(find.byType(AccountProfile), findsOneWidget);
      expect(find.byType(PlanCard), findsNothing);
      expect(find.text('My Channels'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      catalog.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await tester.runAsync(f.close);
    },
  );
}

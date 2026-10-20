import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vayora/plan_catalog.dart';
import 'package:vayora/screens/premium.dart';
import 'package:vayora/theme.dart';
import 'account_test.dart' show Fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final outcome in ['NO_UPI_APP', 'LAUNCH_FAILED', 'no_upi', 'cancelled', 'legacy_raw']) {
    testWidgets('Checkout clears opening state for $outcome', (tester) async {
      final f = Fixture();
      final response = Completer<String>();
      var launches = 0;
      final plan = {
        'id': 'trial', 'name': 'Trial', 'price_inr': 1,
        'duration_days': 1, 'active': true,
      };
      final order = {
        'id': 'fresh', 'reference': 'VYLAUNCH', 'amount_paise': 100,
        'duration_days': 1, 'plan_id': 'trial', 'upi_id': 'test@upi',
        'payee_name': 'Test', 'status': 'pending', 'plans': {'name': 'Trial'},
        'raw_response': outcome == 'legacy_raw'
            ? 'Status=NO_RESPONSE&resultCode=no_upi_app' : null,
      };
      http.Response reply(http.Request r, Object? body) => http.Response(
        jsonEncode(body), 200, request: r,
        headers: {'content-type': 'application/json'},
      );
      f.intercept = (r) {
        if (r.url.path.endsWith('/plans')) {
          return reply(r, [plan]);
        }
        if (r.url.path.endsWith('/create_payment_order')) {
          return reply(r, order);
        }
        if (r.url.path.endsWith('/report_result')) {
          return reply(r, 'pending');
        }
        if (r.url.path.endsWith('/payment_orders')) {
          return reply(r, r.url.queryParameters.containsKey('id') ? order : []);
        }
        return null;
      };
      await tester.runAsync(f.start);
      await tester.runAsync(() => f.state.login('member@example.test', 'password123'));
      final catalog = PlanCatalog(f.db, changes: const Stream<void>.empty());
      await tester.runAsync(catalog.refresh);
      const channel = MethodChannel('app/upi');
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'pending') {
          return <String, String>{};
        }
        if (call.method == 'pay') {
          launches++;
          expect((call.arguments as Map)['uri'],
            'upi://pay?pa=test@upi&pn=Test&tr=VYLAUNCH&am=1.00&cu=INR&tn=Vayora%20VYLAUNCH');
          return response.future;
        }
        return null;
      });
      await tester.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(body: Plans(state: f.state, catalog: catalog)),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trial'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Pay ₹1 via UPI'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(find.text('Opening UPI…'), findsOneWidget);
      if (outcome == 'cancelled') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump();
        expect(find.text('Opening UPI…'), findsNothing);
        await tester.runAsync(() async {
          response.complete('Status=NO_RESPONSE&resultCode=0');
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
      } else {
        await tester.runAsync(() async {
          if (outcome == 'legacy_raw') {
            response.complete('Status=NO_RESPONSE&resultCode=no_upi_app');
          } else {
            response.completeError(PlatformException(code: outcome));
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
      }
      await tester.pumpAndSettle();
      expect(find.text('Opening UPI…'), findsNothing);
      expect(find.text('No UPI app found'),
        outcome == 'NO_UPI_APP' ? findsOneWidget : findsNothing);
      if (outcome == 'NO_UPI_APP') {
        expect(find.text('Copy UPI ID'), findsOneWidget);
        // The button is reset even while the fallback is still open.
        expect(find.text('Pay ₹1 via UPI'), findsOneWidget);
        await tester.tapAt(const Offset(2, 2));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pumpAndSettle();
        expect(find.text('No UPI app found'), findsNothing);
      }
      expect(launches, 1);
      if (outcome == 'legacy_raw' || outcome == 'cancelled') {
        expect(f.calls.where((r) => r.url.path.endsWith('/report_result')), hasLength(1));
      } else {
        expect(f.calls.where((r) => r.url.path.endsWith('/report_result')), isEmpty);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      catalog.dispose();
      messenger.setMockMethodCallHandler(channel, null);
      await tester.runAsync(f.close);
    });
  }
}

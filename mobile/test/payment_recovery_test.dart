import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vayora/app_state.dart';
import 'package:vayora/screens/payments.dart';
import 'package:vayora/theme.dart';
import 'account_test.dart' show Fixture, existingId;

http.Response json(http.Request r, Object? value, [int status = 200]) =>
    http.Response(
      jsonEncode(value),
      status,
      request: r,
      headers: {'content-type': 'application/json'},
    );
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app/upi');
  test(
    'Native result survives a failed report, refreshes session and acknowledges only acceptance',
    () async {
      final f = Fixture();
      var accept = false;
      var acknowledgements = 0;
      final native = {'order': 'Status=SUCCESS&txnId=RECOVER01'};
      f.intercept = (r) => r.url.path.endsWith('/report_payment_result')
          ? (accept
                ? json(r, 'paid')
                : json(r, {
                    'code': 'P0001',
                    'message': 'Temporarily unavailable',
                  }, 503))
          : null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'pending') {
              expect((call.arguments as Map)['user_id'], existingId);
              return native;
            }
            if (call.method == 'ack') {
              acknowledgements++;
              native.remove((call.arguments as Map)['order_id']);
            }
            return null;
          });
      await f.start();
      await f.state.login('member@example.test', 'password123');
      expect(readQueue(f)['order'], contains('RECOVER01'));
      expect(acknowledgements, 0);
      f.state.remoteChangesEnabled = true;
      accept = true;
      await f.state.retryPayments();
      expect(readQueue(f), isEmpty);
      expect(acknowledgements, 1);
      expect(
        f.calls.where(
          (r) =>
              r.url.path.endsWith('/token') &&
              r.url.queryParameters['grant_type'] == 'refresh_token',
        ),
        isNotEmpty,
      );
      await f.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );
  test(
    'App-level recovery reports saved native response without the checkout screen',
    () async {
      final f = Fixture();
      var recover = false;
      var accepted = 0;
      f.intercept = (r) => r.url.path.endsWith('/report_payment_result')
          ? json(r, 'paid')
          : null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'pending') {
              return recover
                  ? {'restored-order': 'Status=SUCCESS&txnId=RESTART01'}
                  : <String, String>{};
            }
            if (call.method == 'ack') accepted++;
            return null;
          });
      await f.start();
      await f.state.login('member@example.test', 'password123');
      recover = true;
      final restarted = AppState(f.db, f.state.prefs);
      await restarted.initialize(watchRemoteChanges: false);
      expect(accepted, 1);
      expect(
        f.calls
            .lastWhere((r) => r.url.path.endsWith('/report_payment_result'))
            .body,
        contains('restored-order'),
      );
      restarted.dispose();
      await f.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );
  test(
    'Missing orders are dropped; another account response is retained for its owner',
    () async {
      final f = Fixture();
      var acks = 0;
      f.intercept = (r) => r.url.path.endsWith('/report_payment_result')
          ? json(r, {'code': 'P0001', 'message': 'Order not found'}, 400)
          : null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'pending') return <String, String>{};
            if (call.method == 'ack') acks++;
            return null;
          });
      await f.start();
      await f.state.login('member@example.test', 'password123');
      await f.state.prefs.setString(
        'pending_payments',
        jsonEncode({
          'missing': 'Status=NO_RESPONSE',
          'other': 'Status=SUCCESS',
        }),
      );
      await f.state.prefs.setString('payment_owner:other', 'another-user');
      await f.state.retryPayments();
      expect(readQueue(f), {'other': 'Status=SUCCESS'});
      expect(acks, 1);
      expect(
        f.calls.where((r) => r.url.path.endsWith('/report_payment_result')),
        hasLength(1),
      );
      await f.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );
  testWidgets(
    'Failed payment accepts exactly 12-digit UTR and displays submitted state',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = Fixture();
      var submitted = false;
      final order = {
        'id': 'order',
        'reference': 'VYUTRTEST',
        'status': 'failed',
        'amount_paise': 4900,
        'plans': {'name': 'Trial'},
      };
      f.intercept = (r) {
        if (r.url.path.endsWith('/payment_orders')) {
          return json(r, [
            {
              ...order,
              if (submitted) 'status': 'submitted',
              if (submitted) 'utr': '123456789012',
            },
          ]);
        }
        if (r.url.path.endsWith('/submit_payment_utr')) {
          expect(jsonDecode(r.body), {
            'order_id': 'order',
            'utr': '123456789012',
          });
          submitted = true;
          return json(r, null);
        }
        return null;
      };
      await tester.runAsync(f.start);
      await tester.runAsync(
        () => f.state.login('member@example.test', 'password123'),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Payments(state: f.state, orderId: 'order'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Payment failed. Please try again.'), findsOneWidget);
      final action = find.text('Paid but not active? Enter UTR');
      await tester.scrollUntilVisible(
        action,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(action);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '123456789012');
      await tester.tap(find.text('Submit'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(submitted, true);
      expect(find.text('Submitted'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(f.close);
    },
  );
}

Map<String, dynamic> readQueue(Fixture f) =>
    jsonDecode(f.state.prefs.getString('pending_payments') ?? '{}')
        as Map<String, dynamic>;

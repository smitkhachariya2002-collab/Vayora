import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vayora/screens/payment_flow.dart';
import 'package:vayora/theme.dart';
import 'account_test.dart' show Fixture;

http.Response reply(http.Request request, Object? body, [int status = 200]) =>
    http.Response(
      jsonEncode(body),
      status,
      request: request,
      headers: {'content-type': 'application/json'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Non-owner no-app checkout shows server payee without reading owner settings',
    (tester) async {
      final f = Fixture();
      final order = {
        'id': 'checkout-order',
        'reference': 'VYTEST',
        'amount_paise': 100,
        'duration_days': 1,
        'upi_id': 'merchant@upi',
        'payee_name': 'Test Merchant',
        'status': 'pending',
        'raw_response': 'Status=NO_RESPONSE&resultCode=no_upi_app',
      };
      f.intercept = (request) {
        if (request.url.path.endsWith('/create_payment_order')) {
          return reply(request, order);
        }
        if (request.url.path.endsWith('/payment_orders')) {
          return reply(request, order);
        }
        if (request.url.path.endsWith('/report_result')) {
          return reply(request, 'pending');
        }
        if (request.url.path.endsWith('/payment_settings')) {
          return reply(request, {
            'code': 'PGRST116',
            'message': 'No rows visible to this member',
          }, 406);
        }
        return null;
      };
      await tester.runAsync(f.start);
      await tester.runAsync(
        () => f.state.login('member@example.test', 'password123'),
      );
      const channel = MethodChannel('app/upi');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'pay') {
              expect(
                (call.arguments as Map)['uri'],
                contains('pa=merchant@upi'),
              );
              throw PlatformException(code: 'NO_UPI_APP');
            }
            if (call.method == 'pending') return <String, String>{};
            return null;
          });
      Map<String, dynamic>? result;
      var launchFinished = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await launchPlanPayment(
                    context,
                    f.state,
                    'trial',
                    displayedPrice: 1,
                    onLaunchFinished: () => launchFinished = true,
                  );
                },
                child: const Text('Pay'),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Pay'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(launchFinished, isTrue);
      expect(find.text('No UPI app found'), findsOneWidget);
      expect(find.textContaining('merchant@upi'), findsOneWidget);
      expect(find.text('Copy UPI ID'), findsOneWidget);
      expect(
        f.calls.where((r) => r.url.path.endsWith('/payment_settings')),
        isEmpty,
      );
      expect(f.state.paymentUpiId('checkout-order'), 'merchant@upi');
      await tester.runAsync(() async {
        await tester.tap(find.text('Continue'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(result?['id'], 'checkout-order');
      expect(
        find.text(
          'Could not start payment. Check your payment history before trying again.',
        ),
        findsNothing,
      );
      expect(
        f.state.prefs.getString('open_payment_order:${f.state.userId}'),
        'checkout-order',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await tester.runAsync(f.close);
    },
  );
}

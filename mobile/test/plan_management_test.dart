import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vayora/plan_catalog.dart';
import 'package:vayora/screens/premium.dart';
import 'package:vayora/screens/payment_flow.dart';
import 'package:vayora/theme.dart';
import 'account_test.dart' show Fixture;
import 'flutter_test_config.dart' show fakeWebPlanIds;

const capturePlans = bool.fromEnvironment('PLAN_SCREENSHOTS');
Map<String, dynamic> plan(
  String id,
  String name,
  int price,
  int days,
  int order, {
  String? badge,
}) => {
  'id': id,
  'name': name,
  'price_inr': price,
  'duration_days': days,
  'position': order,
  'active': true,
  'badge': badge,
  'perks': [
    'Full premium videos',
    '2 TB cloud storage',
    'Download to your phone',
  ],
};
http.Response reply(http.Request r, Object? value) => http.Response(
  jsonEncode(value),
  200,
  request: r,
  headers: {'content-type': 'application/json'},
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (!capturePlans) return;
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final fonts = FontLoader('Poppins');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      fonts.addFont(rootBundle.load('assets/fonts/Poppins-$w.ttf'));
    }
    await fonts.load();
  });
  test('Catalog requests ascending owner-defined order explicitly', () async {
    final f = Fixture();
    f.intercept = (r) => r.url.path.endsWith('/plans') ? reply(r, []) : null;
    await f.start();
    final catalog = PlanCatalog(f.db);
    await catalog.refresh();
    final request = f.calls.lastWhere((r) => r.url.path.endsWith('/plans'));
    expect(
      request.url.queryParameters['order'],
      'position.asc.nullslast,created_at.asc.nullslast',
    );
    catalog.dispose();
    await f.close();
  });
  test('Duration labels match days, month and year rules', () {
    for (final entry in {
      7: '7 days',
      30: '1 month',
      180: '6 months',
      365: '1 year',
      90: '90 days',
      2: '2 days',
    }.entries) {
      expect(planDuration(entry.key), entry.value);
    }
  });
  test('Perks use selected plan then first plan', () {
    final first = plan('a', 'A', 49, 7, 0);
    expect(
      planPerks(
        {
          'perks': ['Selected'],
        },
        [first],
      ),
      ['Selected'],
    );
    expect(planPerks({'perks': []}, [first]), first['perks']);
    expect(planPerks(null, []), isEmpty);
  });
  testWidgets(
    'Open Premium keeps live plan data and refuses a plan removed by the owner',
    (tester) async {
      fakeWebPlanIds = ['trial'];
      addTearDown(() => fakeWebPlanIds = []);
      final fixture = Fixture(), events = StreamController<void>(sync: true);
      var rows = [
        plan('trial', 'Trial', 49, 7, 0),
        plan('gold', 'Gold', 259, 30, 1),
      ];
      fixture.intercept = (r) => r.url.path.endsWith('/plans')
          ? reply(r, rows)
          : r.url.path.endsWith('/payment_orders')
          ? reply(r, [])
          : null;
      await tester.runAsync(fixture.start);
      await tester.runAsync(
        () => fixture.state.login('member@example.test', 'password123'),
      );
      final catalog = PlanCatalog(fixture.db, changes: events.stream);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Plans(state: fixture.state, catalog: catalog),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('web-plans')), findsOneWidget);
      expect(catalog.rows.map((p) => p['price_inr']), [49, 259]);
      rows = [plan('gold', 'Gold', 299, 30, 0)];
      await tester.runAsync(() async {
        events.add(null);
        await Future<void>.delayed(const Duration(milliseconds: 60));
      });
      await tester.pumpAndSettle();
      expect(catalog.rows.single['price_inr'], 299);
      await tester.runAsync(() async {
        await tester.tap(find.text('Buy trial'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('This plan is no longer available.'), findsOneWidget);
      expect(
        fixture.calls.where(
          (r) => r.url.path.endsWith('/create_payment_order'),
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        catalog.dispose();
        await events.close();
        await fixture.close();
      });
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
  testWidgets('Server price change is disclosed before opening UPI', (
    tester,
  ) async {
    final fixture = Fixture();
    var nativeCalls = 0;
    final order = {
      'id': 'order',
      'reference': 'PRICEORDER',
      'amount_paise': 7900,
      'duration_days': 7,
      'upi_id': 'test@upi',
      'payee_name': 'Test',
      'status': 'initiated',
    };
    fixture.intercept = (r) =>
        r.url.path.endsWith('/create_payment_order') ||
            r.url.path.endsWith('/payment_orders')
        ? reply(r, order)
        : null;
    await tester.runAsync(fixture.start);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('app/upi'), (call) async {
          if (call.method == 'pay') {
            nativeCalls++;
            expect((call.arguments as Map)['uri'], contains('am=79.00'));
          }
          return null;
        });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => launchPlanPayment(
                context,
                fixture.state,
                'trial',
                displayedPrice: 49,
              ),
              child: const Text('Pay'),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Pay'));
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pumpAndSettle();
    expect(find.text('Price updated to ₹79'), findsOneWidget);
    expect(nativeCalls, 0);
    await tester.runAsync(() async {
      await tester.tap(find.text('Continue'));
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
    await tester.pumpAndSettle();
    expect(nativeCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('app/upi'), null);
    await tester.runAsync(fixture.close);
  });
}

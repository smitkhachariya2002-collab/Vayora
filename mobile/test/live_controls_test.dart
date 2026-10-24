import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vayora/plan_catalog.dart';
import 'package:vayora/screens/account_ui.dart';
import 'package:vayora/screens/premium.dart';
import 'package:vayora/screens/web_plans.dart';
import 'package:vayora/theme.dart';
import 'account_test.dart' show Fixture;
import 'plan_management_test.dart' show plan, reply;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Button label covers free and paused payments', () {
    expect(
      premiumButtonLabel(
        selected: true,
        guest: false,
        busy: false,
        price: 99,
        free: true,
      ),
      'Activate for free',
    );
    expect(
      premiumButtonLabel(selected: true, guest: true, busy: false, free: true),
      'Next',
    );
    expect(
      premiumButtonLabel(
        selected: true,
        guest: false,
        busy: false,
        price: 99,
        paymentsAvailable: false,
      ),
      'Payments unavailable',
    );
    expect(
      premiumButtonLabel(selected: true, guest: false, busy: false, price: 99),
      'Pay ₹99 via UPI',
    );
    expect(
      premiumButtonLabel(selected: true, guest: false, busy: true, free: true),
      'Activating…',
    );
  });

  test('Website plans page URL carries free plans and paused state', () {
    expect(
      webPlansUri().toString(),
      'https://vayora-eta.vercel.app/subscribe?app=1',
    );
    expect(webPlansUri(free: {'b', 'a'}, paused: true).queryParameters, {
      'app': '1',
      'free': 'a,b',
      'paused': '1',
    });
  });

  test('Only buy messages with a plan ID start checkout', () {
    expect(webPlansPurchase('{"type":"buy","plan_id":"gold"}'), 'gold');
    expect(webPlansPurchase('{"type":"buy","plan_id":"  "}'), isNull);
    expect(webPlansPurchase('{"type":"other","plan_id":"gold"}'), isNull);
    expect(webPlansPurchase('not json'), isNull);
    expect(webPlansPurchase('[1,2]'), isNull);
  });

  test('WebView only loads our plans page', () {
    expect(webPlansAllowed(webPlansUri()), isTrue);
    expect(
      webPlansAllowed(Uri.parse('https://vayora-eta.vercel.app/d')),
      isTrue,
    );
    expect(
      webPlansAllowed(Uri.parse('https://vayora-eta.vercel.app/payments')),
      isFalse,
    );
    expect(
      webPlansAllowed(Uri.parse('https://example.com/subscribe')),
      isFalse,
    );
    expect(
      webPlansAllowed(Uri.parse('http://vayora-eta.vercel.app/subscribe')),
      isFalse,
    );
  });

  test('Catalog keeps paid behaviour when offers are missing', () async {
    final f = Fixture();
    f.intercept = (r) => r.url.path.endsWith('/plans')
        ? reply(r, [plan('gold', 'Gold', 259, 30, 0)])
        : null;
    await f.start();
    final catalog = PlanCatalog(f.db);
    await catalog.refresh();
    expect(catalog.paymentsAvailable, isTrue);
    expect(catalog.freeIds, isEmpty);
    catalog.dispose();
    await f.close();
  });

  Future<void> pumpPlans(
    WidgetTester tester,
    Map<String, dynamic> offers,
    Future<void> Function(PlanCatalog catalog) check,
  ) async {
    tester.view.physicalSize = const Size(400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = Fixture(), events = StreamController<void>(sync: true);
    fixture.intercept = (r) => r.url.path.endsWith('/plans')
        ? reply(r, [
            plan('trial', 'Trial', 49, 7, 0),
            plan('gold', 'Gold', 259, 30, 1),
          ])
        : r.url.path.endsWith('/plan_offers')
        ? reply(r, offers)
        : r.url.path.endsWith('/payment_orders')
        ? reply(r, [])
        : null;
    await tester.runAsync(fixture.start);
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
    await check(catalog);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() async {
      catalog.dispose();
      await events.close();
      await fixture.close();
    });
  }

  testWidgets('Website page gets free plans from the server', (tester) async {
    await pumpPlans(
      tester,
      {
        'free_plan_ids': ['trial'],
        'payments_available': true,
        'free_plans_for': 'organic',
      },
      (catalog) async {
        expect(catalog.isFree('trial'), isTrue);
        expect(catalog.isFree('gold'), isFalse);
        expect(find.byKey(const ValueKey('web-plans')), findsOneWidget);
        expect(
          find.text('https://vayora-eta.vercel.app/subscribe?app=1&free=trial'),
          findsOneWidget,
        );
      },
    );
  });

  testWidgets('Cleared UPI ID tells the website page payments are paused', (
    tester,
  ) async {
    await pumpPlans(
      tester,
      {
        'free_plan_ids': <String>[],
        'payments_available': false,
        'free_plans_for': 'none',
      },
      (catalog) async {
        expect(catalog.paymentsAvailable, isFalse);
        expect(
          find.text('https://vayora-eta.vercel.app/subscribe?app=1&paused=1'),
          findsOneWidget,
        );
      },
    );
  });

  for (final subscribed in [false, true]) {
    testWidgets(
      'Hidden plans show no subscribe page${subscribed ? '; the active plan stays visible' : ''}',
      (tester) async {
        final f = Fixture();
        f.intercept = (r) => r.url.path.endsWith('/plans')
            ? reply(r, [plan('gold', 'Gold', 259, 30, 0)])
            : r.url.path.endsWith('/payment_orders')
            ? reply(r, [])
            : null;
        f.currentStatus = {
          'plans_visible': false,
          if (subscribed) ...{
            'is_premium': true,
            'plan_name': 'Gold',
            'plan_ends_at': '2026-12-01T00:00:00Z',
          },
        };
        await tester.runAsync(f.start);
        await tester.runAsync(
          () => f.state.login('member@example.test', 'password123'),
        );
        expect(f.state.plansVisible, isFalse);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(),
            home: Plans(state: f.state),
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('web-plans')), findsNothing);
        expect(find.textContaining('₹'), findsNothing);
        expect(find.text('Get 2 TB with Premium'), findsNothing);
        expect(
          find.text('Gold active'),
          subscribed ? findsOneWidget : findsNothing,
        );
        expect(find.text('Payment history'), findsOneWidget);
        expect(
          f.calls.where((r) => r.url.path.endsWith('/create_payment_order')),
          isEmpty,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(f.close);
      },
    );
  }
}

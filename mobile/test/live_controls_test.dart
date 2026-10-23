import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vayora/plan_catalog.dart';
import 'package:vayora/screens/account_ui.dart';
import 'package:vayora/screens/premium.dart';
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

  testWidgets('Free plan shows FREE badge and free notice', (tester) async {
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
        expect(find.text('FREE'), findsOneWidget);
        expect(find.text('Free for you'), findsOneWidget);
        expect(find.text('₹ 259'), findsOneWidget);
        await tester.tap(find.text('Trial'));
        await tester.pumpAndSettle();
        expect(find.text('Next'), findsOneWidget);
      },
    );
  });

  testWidgets('Cleared UPI ID disables paid plans', (tester) async {
    await pumpPlans(
      tester,
      {
        'free_plan_ids': <String>[],
        'payments_available': false,
        'free_plans_for': 'none',
      },
      (catalog) async {
        expect(catalog.paymentsAvailable, isFalse);
        expect(find.text('Payments paused'), findsOneWidget);
        await tester.tap(find.text('Gold'));
        await tester.pumpAndSettle();
        expect(find.text('Payments unavailable'), findsOneWidget);
        expect(find.text('FREE'), findsNothing);
      },
    );
  });
}

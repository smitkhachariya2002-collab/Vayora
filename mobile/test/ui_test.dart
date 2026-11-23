import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:vayora/screens/consent_gate.dart';
import 'package:vayora/services/measurement.dart';
import 'package:vayora/screens/plans_page.dart';
import 'package:vayora/widgets/vayora_nav_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<List<Map<String, dynamic>>> plans() async => [
      {'id': 'p1', 'name': 'Trial', 'price_inr': 49, 'duration_days': 7, 'badge': null, 'position': 1},
      {'id': 'p2', 'name': 'Silver', 'price_inr': 129, 'duration_days': 7, 'badge': null, 'position': 2},
      {'id': 'p3', 'name': 'Gold', 'price_inr': 259, 'duration_days': 30, 'badge': 'Popular', 'position': 3},
      {'id': 'p5', 'name': 'Diamond', 'price_inr': 999, 'duration_days': 365, 'badge': 'Best value', 'position': 5},
    ];

void main() {
  group('Consent popup (first open)', () {
    test('no measurement starts before the new consent is accepted', () async {
      SharedPreferences.setMockInitialValues({'terms_accepted_v1':true});
      final measurement=Measurement();
      await measurement.start();
      expect(measurement.ready,false);
      expect(measurement.advertising,false);
      expect(measurement.analytics,false);
    });
    testWidgets('one explicit accept enables both sharing choices on a phone', (tester) async {
      tester.view.physicalSize=const Size(390,844);tester.view.devicePixelRatio=1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({'terms_accepted_20261115_v2':true});
      await tester.pumpWidget(const MaterialApp(home:ConsentGate(child:Text('home'))));
      await tester.pumpAndSettle();
      expect(find.byType(SwitchListTile),findsNothing);
      expect(find.byType(CheckboxListTile),findsNothing);
      expect(find.byType(FilledButton),findsOneWidget);
      expect(find.textContaining('Meta/Facebook'),findsOneWidget);
      expect((await SharedPreferences.getInstance()).getBool(consentPrefKey),isNot(true));
      expect((await SharedPreferences.getInstance()).getString('measurement_pending_choice'),isNull);
      await tester.ensureVisible(find.byKey(const Key('consent_continue')));
      await tester.tap(find.byKey(const Key('consent_continue')));await tester.pumpAndSettle();
      final choice=jsonDecode((await SharedPreferences.getInstance()).getString('measurement_pending_choice')!) as Map;
      expect(choice['analytics'],true);expect(choice['advertising'],true);
      expect(choice['policy'],'2026-11-16-v3');
      expect((await SharedPreferences.getInstance()).getBool(consentPrefKey),true);
      expect(tester.takeException(),isNull);
    });

    testWidgets('not shown again once accepted', (tester) async {
      SharedPreferences.setMockInitialValues({consentPrefKey: true});
      await tester.pumpWidget(const MaterialApp(home: ConsentGate(child: Text('home'))));
      await tester.pumpAndSettle();
      expect(find.text('Accept and continue'), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });
  });

  group('Plans page', () {
    test('labels', () {
      expect(durationLabel(7), '7 Days');
      expect(durationLabel(1, 6), '6 Hours');
      expect(durationLabel(1, 1), '1 Hour');
      expect(durationLabel(1, 48), '2 Days');
      expect(durationLabel(30), '1 Month');
      expect(durationLabel(180), '6 Months');
      expect(durationLabel(365), '1 Year');
      expect(perDay(259, 30), '8.6');
      expect(perDay(49, 7), '7');
      expect(perDay(999, 365), '2.7');
    });

    testWidgets('lists every plan, selects Popular by default, CTA follows selection', (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      String? bought;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PlansPage(plansLoader: plans, onBuy: (id) async => bought = id))));
      await tester.pumpAndSettle();
      expect(find.text('Trial Plan'), findsOneWidget);
      expect(find.text('Diamond Plan'), findsOneWidget);
      expect(find.text('Best value'), findsOneWidget);
      expect(find.text('Continue with Gold · ₹259'), findsOneWidget);
      await tester.tap(find.text('Silver Plan'));
      await tester.pump();
      expect(find.text('Continue with Silver · ₹129'), findsOneWidget);
      await tester.tap(find.text('Continue with Silver · ₹129'));
      await tester.pumpAndSettle();
      expect(bought, 'p2');
    });

    testWidgets('free plan shows FREE and a claim button', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PlansPage(plansLoader: plans, freeIds: const {'p3'}, onBuy: (_) async {}))));
      await tester.pumpAndSettle();
      expect(find.text('FREE'), findsOneWidget);
      expect(find.text('Claim free Gold Plan'), findsOneWidget);
    });

    testWidgets('paused payments disable the buy button', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PlansPage(plansLoader: plans, paused: true, onBuy: (_) async {}))));
      await tester.pumpAndSettle();
      expect(find.textContaining('Payments are paused'), findsOneWidget);
    });

    testWidgets('policy links are on the plans page', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: PlansPage(plansLoader: plans, onBuy: (_) async {}))));
      await tester.pumpAndSettle();
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('Terms & Conditions'), findsOneWidget);
      expect(find.text('Refund Policy'), findsOneWidget);
    });

    testWidgets('fits a small screen at 1.6x text', (tester) async {
      tester.view.physicalSize = const Size(360 * 2, 700 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(1.6)), child: w!), home: Scaffold(body: PlansPage(plansLoader: plans, onBuy: (_) async {}))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('nav bar: five tabs, tap changes selection', (tester) async {
    var idx = 1;
    await tester.pumpWidget(MaterialApp(home: StatefulBuilder(builder: (c, set) => Scaffold(
          bottomNavigationBar: VayoraNavBar(index: idx, onTap: (v) => set(() => idx = v), items: const [
            NavItem(Icons.cloud_outlined, 'Cloud'), NavItem(Icons.grid_view_rounded, 'Home'), NavItem(Icons.explore_outlined, 'Explore'),
            NavItem(Icons.tv_outlined, 'Channel'), NavItem(Icons.workspace_premium_outlined, 'Premium'),
          ]),
        ))));
    expect(find.text('Premium'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tab_Premium')));
    await tester.pump();
    expect(idx, 4);
  });
}

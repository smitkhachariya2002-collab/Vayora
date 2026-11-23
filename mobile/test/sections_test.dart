import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vayora/screens/cloud_screen.dart';
import 'package:vayora/screens/profile_screen.dart';
import 'package:vayora/services/app_scope.dart';
import 'package:vayora/services/app_state.dart';
import 'package:vayora/models/status.dart';

/// Six user types from the spec: GO/GA guests, LO/LA logged in without a plan, PO/PA with a plan.
Map<String, dynamic> st({bool guest = false, bool ads = false, bool plan = false, bool free = false, bool visible = true, int quota = 0}) => {
      'is_guest': guest,
      'source': ads ? 'ads' : 'organic',
      'has_ads_access': ads,
      'is_premium': plan,
      'plan_name': plan ? 'Gold' : null,
      'plan_ends_at': plan ? '2027-01-01T00:00:00Z' : null,
      'free_mode': free,
      'plans_visible': visible,
      'payments_available': true,
      'quota_bytes': quota,
      'used_bytes': 0,
    };

const types = <String, Map<String, bool>>{
  'GO': {'guest': true, 'ads': false, 'plan': false},
  'GA': {'guest': true, 'ads': true, 'plan': false},
  'LO': {'guest': false, 'ads': false, 'plan': false},
  'LA': {'guest': false, 'ads': true, 'plan': false},
  'PO': {'guest': false, 'ads': false, 'plan': true},
  'PA': {'guest': false, 'ads': true, 'plan': true},
};

Widget host(AppState app, Widget child) => MaterialApp(
      home: Scaffold(
        body: AppScope(
          state: app,
          child: child,
        ),
      ),
    );

Future<List<Map<String, dynamic>>> fakePlans() async => [
      {'id': 'p1', 'name': 'Trial', 'price_inr': 49, 'duration_days': 7, 'badge': null, 'position': 1},
      {'id': 'p3', 'name': 'Gold', 'price_inr': 259, 'duration_days': 30, 'badge': 'Popular', 'position': 3},
    ];

AppState appWith(Map<String, dynamic> m) => AppState()..status = AppStatus(m);

const playBuild = bool.fromEnvironment('PLAY_STORE') && !bool.fromEnvironment('PLAY_SELLS_UPI');

void main() {
  scopeAboveNavigatorTests();
  group('Play build hides purchases', () {
    for (final e in types.entries) {
      testWidgets('${e.key}: Profile is the account card, no plans page', (tester) async {
        final t = e.value;
        final app = appWith(st(guest: t['guest']!, ads: t['ads']!, plan: t['plan']!));
        await tester.pumpWidget(host(app, const ProfileScreen(plansLoader: fakePlans)));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('account_view')), findsOneWidget);
        expect(find.byKey(const Key('plans_page')), findsNothing);
      });
    }
  }, skip: !playBuild);

  if (playBuild) return;

  group('Profile tab', () {
    for (final e in types.entries) {
      final t = e.value;
      testWidgets('${e.key}: ${t['plan']! ? 'account card first' : 'plans page opens directly'}', (tester) async {
        final app = appWith(st(guest: t['guest']!, ads: t['ads']!, plan: t['plan']!, quota: t['plan']! ? 2 * 1024 * 1024 * 1024 * 1024 : 0));
        await tester.pumpWidget(host(app, const ProfileScreen(plansLoader: fakePlans)));
        await tester.pumpAndSettle();
        if (t['plan']!) {
          expect(find.byKey(const Key('account_view')), findsOneWidget);
          expect(find.text('Upgrade / Renew'), findsOneWidget);
          expect(find.byKey(const Key('plans_page')), findsNothing);
          expect(find.textContaining('Gold active until'), findsOneWidget);
        } else {
          expect(find.byKey(const Key('plans_page')), findsOneWidget);
          expect(find.text('Continue with Gold · ₹259'), findsOneWidget);
          expect(find.byKey(const Key('account_button')), findsOneWidget);
          expect(find.byKey(const Key('login_link')), t['guest']! ? findsOneWidget : findsNothing);
        }
        // Payment history lives in the account card (plan holders land there directly).
        if (t['plan']!) {
          expect(find.text('Payment history'), findsOneWidget);
        }
      });
    }

    testWidgets('live switch: plan bought -> account card; plan revoked -> plans again', (tester) async {
      final app = appWith(st());
      await tester.pumpWidget(host(app, const ProfileScreen(plansLoader: fakePlans)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('plans_page')), findsOneWidget);
      app.status = AppStatus(st(plan: true, quota: 1));
      app.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('account_view')), findsOneWidget);
      app.status = AppStatus(st());
      app.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('plans_page')), findsOneWidget);
    });

    testWidgets('free mode: account card, no prices entry', (tester) async {
      final app = appWith(st(free: true, quota: 15 * 1024 * 1024 * 1024));
      await tester.pumpWidget(host(app, const ProfileScreen(plansLoader: fakePlans)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('account_view')), findsOneWidget);
      expect(find.byKey(const Key('plans_page')), findsNothing);
      expect(find.text('Upgrade / Renew'), findsNothing);
    });

    testWidgets('plans hidden for this group: account card, no Premium entry', (tester) async {
      final app = appWith(st(visible: false));
      await tester.pumpWidget(host(app, const ProfileScreen(plansLoader: fakePlans)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('account_view')), findsOneWidget);
      expect(find.byKey(const Key('plans_page')), findsNothing);
      expect(find.text('Payment history'), findsNothing);
    });
  });

  group('Cloud tab', () {
    testWidgets('guest: Log in card', (tester) async {
      await tester.pumpWidget(host(appWith(st(guest: true)), const CloudScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Add an email to save your account'), findsOneWidget);
    });
    for (final k in ['LO', 'LA']) {
      testWidgets('$k: 0 GB -> Get 2 TB with Premium', (tester) async {
        await tester.pumpWidget(host(appWith(st(ads: k == 'LA')), const CloudScreen()));
        await tester.pumpAndSettle();
        expect(find.text('Get 2 TB with Premium'), findsOneWidget);
        expect(find.text('Upload'), findsNothing);
      });
    }
    for (final k in ['PO', 'PA']) {
      testWidgets('$k: 2 TB and Upload', (tester) async {
        await tester.pumpWidget(host(appWith(st(ads: k == 'PA', plan: true, quota: 2 * 1024 * 1024 * 1024 * 1024)), const CloudScreen()));
        await tester.pumpAndSettle();
        expect(find.textContaining('of 2.00 TB used'), findsOneWidget);
        expect(find.text('Upload'), findsOneWidget);
      });
    }
  });
}

/// Regression: a pushed route (payment status, history...) must find AppScope. It used to sit inside
/// `home`, so those routes crashed to a blank grey screen after a successful payment.
void scopeAboveNavigatorTests() {
  testWidgets('pushed routes can read AppScope when it wraps MaterialApp', (tester) async {
    final app = appWith(st(plan: true));
    await tester.pumpWidget(AppScope(
      state: app,
      child: MaterialApp(
        home: Builder(builder: (c) => TextButton(
          onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (c2) => Text('plan:${AppScope.of(c2).status.isPremium}'))),
          child: const Text('go'),
        )),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('plan:true'), findsOneWidget);
  });
}


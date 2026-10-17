import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vayora/main.dart';
import 'package:vayora/theme.dart';
import 'account_test.dart' show Fixture, existingId;

const captureAccounts = bool.fromEnvironment('SCREENSHOTS');
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final fonts = FontLoader('Poppins');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      fonts.addFont(rootBundle.load('assets/fonts/Poppins-$weight.ttf'));
    }
    await fonts.load();
  });
  for (final width in [360.0, 430.0]) {
    for (final scale in [1.0, 1.6]) {
      for (final name in [
        'profile-guest',
        'profile-member',
        'profile-premium',
        'settings',
        'premium-paid',
        'premium-free',
        'payment-pending',
        'payment-not-completed',
        'payment-success',
        'payment-failed',
        'payment-cancelled',
        'payment-reversed',
        'payment-history',
      ]) {
        testWidgets(
          '$name at $width / $scale',
          (tester) async {
            tester.view.physicalSize = Size(width, 1000);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final f = Fixture();
            final plans = [
              for (final p in [
                ('trial', 'Trial', 49, 7),
                ('silver', 'Silver', 129, 7),
                ('gold', 'Gold', 259, 30),
                ('platinum', 'Platinum', 599, 180),
                ('diamond', 'Diamond', 999, 365),
              ])
                {
                  'id': p.$1,
                  'name': p.$2,
                  'price_inr': p.$3,
                  'duration_days': p.$4,
                  'active': true,
                  'perks': [
                    'Full premium videos',
                    '2 TB cloud storage',
                    'Download to your phone',
                  ],
                },
            ];
            final status = name == 'payment-not-completed'
                ? 'initiated'
                : name == 'payment-success'
                ? 'success'
                : name == 'payment-failed'
                ? 'failed'
                : name == 'payment-cancelled'
                ? 'cancelled'
                : name == 'payment-reversed'
                ? 'revoked'
                : 'pending';
            final payment = {
              'id': 'order-one',
              'user_id': existingId,
              'plan_id': 'gold',
              'plans': {'name': 'Gold'},
              'reference': 'VAY-DEMO-2026',
              'amount_paise': 25900,
              'created_at': '2026-10-17T10:00:00Z',
              'status': status,
              'raw_response': 'Status=UNKNOWN',
            };
            final owned = {
              'id': 'owned',
              'name': 'India in focus',
              'created_by': existingId,
              'review_status': 'approved',
              'status': 'active',
              'members_count': 1280,
              'audience': 'all',
            };
            final pending = {
              'id': 'pending',
              'name': 'My travel diary',
              'created_by': existingId,
              'review_status': 'pending',
              'status': 'active',
              'members_count': 0,
              'audience': 'all',
            };
            final joined = {
              'id': 'joined',
              'name': 'Food across India',
              'created_by': 'creator',
              'review_status': 'approved',
              'status': 'active',
              'members_count': 510,
              'audience': 'all',
            };
            f.intercept = (r) {
              Object? value;
              if (r.url.path.endsWith('/plans')) {
                value = plans;
              } else if (r.url.path.endsWith('/payment_orders')) {
                value = name.startsWith('payment-') ? [payment] : <Object>[];
              } else if (r.url.path.endsWith('/channel_members')) {
                value = [
                  {'channel_id': 'joined'},
                ];
              } else if (r.url.path.endsWith('/channels')) {
                value = r.url.queryParameters.containsKey('created_by')
                    ? [owned, pending]
                    : [joined];
              } else {
                return null;
              }
              return http.Response(
                jsonEncode(value),
                200,
                request: r,
                headers: {'content-type': 'application/json'},
              );
            };
            await tester.runAsync(f.start);
            await f.state.prefs.setBool('consent_v1', true);
            final premium =
                name == 'profile-premium' || name == 'payment-success';
            f.currentStatus = {
              'display_name': name == 'profile-guest' ? '' : 'Kavya Sharma',
              'source': 'organic',
              'free_mode': name == 'premium-free',
              'is_premium': premium,
              'plan_name': premium ? 'Gold' : null,
              'plan_ends_at': premium ? '2026-11-17T10:00:00Z' : null,
              'has_ads_access': false,
              'access_status': name == 'premium-free' ? 'pending' : 'none',
              'quota_bytes': premium
                  ? 2199023255552
                  : name == 'premium-free'
                  ? 16106127360
                  : 0,
            };
            if (name != 'profile-guest') {
              await tester.runAsync(
                () => f.state.login('test@example.test', 'password123'),
              );
            }
            await tester.runAsync(f.state.refreshStatus);
            final Widget page = name.startsWith('profile-')
                ? Scaffold(body: Profile(state: f.state))
                : name == 'settings'
                ? SettingsPage(state: f.state)
                : name.startsWith('premium-')
                ? Plans(state: f.state)
                : Payments(
                    state: f.state,
                    orderId: name == 'payment-history' ? null : 'order-one',
                  );
            await tester.pumpWidget(
              MaterialApp(
                theme: buildTheme(),
                debugShowCheckedModeBanner: false,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: true,
                  ),
                  child: child!,
                ),
                home: RepaintBoundary(
                  key: const ValueKey('account-screen'),
                  child: page,
                ),
              ),
            );
            for (var i = 0; i < 8; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
            expect(
              tester.takeException(),
              isNull,
              reason: '$name at $width / $scale',
            );
            await expectLater(
              find.byKey(const ValueKey('account-screen')),
              matchesGoldenFile(
                'goldens/after/$name-${width.toInt()}-$scale.png',
              ),
            );
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            await tester.runAsync(f.close);
          },
          skip: !captureAccounts,
          timeout: const Timeout(Duration(seconds: 45)),
        );
      }
    }
  }
}

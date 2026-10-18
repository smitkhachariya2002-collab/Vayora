import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vayora/app_state.dart';
import 'package:vayora/screens/premium.dart';
import 'package:vayora/screens/profile.dart';
import 'package:vayora/theme.dart';
import 'account_test.dart' show Fixture;

void main() {
  testWidgets(
    'Play builds hide plans, prices, UPI and payment history while billing is off',
    (tester) async {
      final f = Fixture();
      await tester.runAsync(f.start);
      await tester.runAsync(
        () => f.state.login('member@example.test', 'password123'),
      );
      expect(playStore, isTrue);
      expect(f.state.paidEnabled, isFalse);
      await expectLater(f.state.pay('trial'), throwsStateError);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Plans(state: f.state),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Continue to payment'), findsNothing);
      expect(find.text('Request full access'), findsOneWidget);
      expect(f.calls.where((r) => r.url.path.endsWith('/plans')), isEmpty);
      expect(
        f.calls.where((r) => r.url.path.endsWith('/create_payment_order')),
        isEmpty,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Scaffold(body: Profile(state: f.state)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Payment history'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(f.close);
    },
    skip: !playStore,
  );
}

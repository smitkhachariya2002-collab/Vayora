import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vayora/models/status.dart';
import 'package:vayora/screens/channels_screen.dart';
import 'package:vayora/screens/premium_screen.dart';
import 'package:vayora/services/app_scope.dart';
import 'package:vayora/services/app_state.dart';

void main() {
  for (final source in ['ads', 'organic']) {
    for (final guest in [true, false]) {
      testWidgets('$source free user guest=$guest goes to Premium before channel form', (tester) async {
        final app = AppState()..status = AppStatus({
          'is_guest': guest, 'source': source, 'is_premium': false,
          'plans_visible': false, 'free_mode': false,
        });
        await tester.pumpWidget(AppScope(state: app, child: const MaterialApp(home: ChannelsScreen())));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FloatingActionButton, 'Create'));
        await tester.pumpAndSettle();
        expect(find.byType(PremiumScreen), findsOneWidget);
        expect(find.byKey(const Key('channel_name')), findsNothing);
        await tester.pumpWidget(const SizedBox());
        app.dispose();
      });
    }
  }
}


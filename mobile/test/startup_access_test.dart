import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vayora/models/status.dart';
import 'package:vayora/screens/home_screen.dart';
import 'package:vayora/screens/home_shell.dart';
import 'package:vayora/services/app_scope.dart';
import 'package:vayora/services/app_state.dart';

void main() {
  testWidgets('content waits for session classification and handles an access change', (tester) async {
    final app = AppState();
    await tester.pumpWidget(AppScope(state: app, child: const MaterialApp(home: HomeShell())));
    await tester.pump();
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    app.status = AppStatus({'user_id': 'guest-a', 'is_guest': true, 'source': 'ads'});
    app.loaded = true;
    app.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    app.status = AppStatus({'user_id': 'guest-b', 'is_guest': true, 'source': 'organic'});
    app.notifyListeners();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
}


import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vayora/config.dart';
import 'package:vayora/screens/login_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: Config.supabaseUrl,
      publishableKey: Config.supabaseKey,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false, detectSessionInUri: false,
      ),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  test('Google OAuth uses PKCE and preserves each Android callback', () async {
    for (final scheme in ['com.vayora.app', 'com.vayora.play']) {
      final response = await Supabase.instance.client.auth.getOAuthSignInUrl(
        provider: OAuthProvider.google,
        redirectTo: '$scheme://login-callback',
        queryParams: {'prompt': 'select_account'},
      );
      final url = Uri.parse(response.url);
      expect(url.host, 'fzloulsjhkdxwagonsgt.supabase.co');
      expect(url.queryParameters['provider'], 'google');
      expect(url.queryParameters['redirect_to'], '$scheme://login-callback');
      expect(url.queryParameters['code_challenge'], isNotEmpty);
      expect(url.queryParameters['code_challenge_method'], 's256');
      expect(url.queryParameters['prompt'], 'select_account');
    }
  });

  for (final saveMode in [false, true]) {
    testWidgets('Google is available when saveMode=$saveMode', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: LoginSheet(saveMode: saveMode, startSignup: saveMode),
      )));
      await tester.pumpAndSettle();
      final button = find.byKey(const Key('google_login'));
      expect(button, findsOneWidget);
      expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.textContaining('coming soon'), findsNothing);
    });
  }
}


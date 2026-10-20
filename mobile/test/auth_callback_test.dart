import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vayora/app_state.dart';
import 'account_test.dart' show Fixture;

void main() {
  test('Auth callbacks match the compiled Android distribution', () {
    expect(androidAppId, playStore ? 'com.vayora.play' : 'com.vayora.app');
    expect(authCallback, '$androidAppId://login-callback');
  });

  test('Google OAuth returns to this distribution, not the other installed app', () async {
    final fixture = Fixture();
    await fixture.start();
    try {
      final response = await fixture.db.auth.getOAuthSignInUrl(
        provider: OAuthProvider.google,
        redirectTo: authCallback,
      );
      final url = Uri.parse(response.url);
      expect(url.queryParameters['provider'], 'google');
      expect(url.queryParameters['redirect_to'], authCallback);
    } finally {
      await fixture.close();
    }
  });
}

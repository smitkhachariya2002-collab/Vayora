/// Vayora build-time configuration. Nothing secret lives here: the Supabase URL and
/// publishable key are public by design (access is enforced by RLS on the server).
class Config {
  static const consentPrefKey = 'terms_accepted_20261116_v3';
  static const consentPolicy = '2026-11-16-v3';
  static const appName = 'Vayora';
  static const shortCode = 'VY';
  static const websiteUrl = String.fromEnvironment('WEBSITE_URL', defaultValue: 'https://vayora-eta.vercel.app');
  static const supportEmail = String.fromEnvironment('SUPPORT_EMAIL', defaultValue: 'help.vayora@gmail.com');
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://fzloulsjhkdxwagonsgt.supabase.co');
  static const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY', defaultValue: 'sb_publishable_yhWaOl1wsOEpqCkCN_CzMw_Guaabspq');

  /// Standard Play build hides checkout. The separate plans bundle explicitly opts in.
  static const playStore = bool.fromEnvironment('PLAY_STORE');
  static const playSellsUpi = bool.fromEnvironment('PLAY_SELLS_UPI');
  static const restrictPlayPurchases = playStore && !playSellsUpi;

  /// Set by CI for the ads APK: utm_source=meta&utm_medium=paid_social&utm_campaign=apk_download
  static const apkReferrer = String.fromEnvironment('APK_REFERRER');
  static const authScheme = String.fromEnvironment('AUTH_SCHEME', defaultValue: String.fromEnvironment('ANDROID_APP_ID', defaultValue: 'com.vayora.app'));

  /// Kept in sync with pubspec.yaml; a test fails when they differ.
  static const versionLabel = '1.0.13';
}



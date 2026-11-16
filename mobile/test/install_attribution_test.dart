import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayora/services/install_attribution.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app/install-referrer');
  setUp(() { SharedPreferences.setMockInitialValues({}); });
  tearDown(() { TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null); });
  test('Meta and organic Play referrers are classified separately', () {
    final p = parseInstallReferrer('utm_source=meta&utm_medium=paid_social&utm_campaign=Summer%20Sale');
    expect(classifyInstallReferrer(p), 'meta');
    expect(p['utm_campaign'], 'Summer Sale');
    expect(classifyInstallReferrer(parseInstallReferrer('utm_source=google-play&utm_medium=organic')), 'organic');
    expect(classifyInstallReferrer(parseInstallReferrer('utm_source%3Dinstagram%26utm_medium%3Dpaid_social')), 'meta');
    expect(classifyInstallReferrer(parseInstallReferrer('%not-valid')), 'unknown');
  });
  test('real Play evidence wins over APK fallback and is cached', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return {'status':'ok','is_play':true,'referrer':'utm_source=google-play&utm_medium=organic','click_timestamp':10,'install_timestamp':20};
    });
    final r = await InstallAttribution.read('utm_source=meta');
    expect(r['classification'], 'organic');
    expect(r['install_timestamp'], 20);
    await InstallAttribution.read('utm_source=meta');
    expect(calls, 1);
  });
  test('unavailable Play service retries and cannot use APK fallback', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return {'status':'timeout','is_play':true};
    });
    expect((await InstallAttribution.read('utm_source=meta'))['classification'], 'unknown');
    await InstallAttribution.read('utm_source=meta');
    expect(calls, 2);
  });
  test('direct ads APK has explicit fallback', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async => {'status':'not_play','is_play':false});
    expect((await InstallAttribution.read('utm_source=meta'))['classification'], 'meta');
  });
}

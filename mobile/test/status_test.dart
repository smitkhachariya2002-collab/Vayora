import 'package:flutter_test/flutter_test.dart';
import 'package:vayora/models/status.dart';

void main() {
  test('guest default has no quota', () {
    final s = AppStatus.guest();
    expect(s.isGuest, isTrue);
    expect(s.quotaBytes, 0);
  });

  test('reads server flags without computing anything itself', () {
    final s = AppStatus({
      'is_guest': false,
      'is_premium': true,
      'plans_visible': false,
      'free_mode': false,
      'quota_bytes': 2199023255552,
      'plan_name': 'Gold',
      'plan_ends_at': '2026-12-09T00:00:00Z',
    });
    expect(s.isPremium, isTrue);
    expect(s.plansVisible, isFalse);
    expect(s.quotaBytes, 2199023255552);
    expect(s.planName, 'Gold');
    expect(s.planEndsAt, isNotNull);
  });
}

/// Mirrors the server's my_status() JSON. The app never computes access itself.
class AppStatus {
  AppStatus(this.raw);
  final Map<String, dynamic> raw;

  static AppStatus guest() => AppStatus({'is_guest': true, 'quota_bytes': 0, 'used_bytes': 0});

  bool _b(String k) => raw[k] == true;
  int _i(String k) => (raw[k] as num?)?.toInt() ?? 0;

  bool get isGuest => _b('is_guest');
  bool get isPremium => _b('is_premium');
  bool get canPlayPremium => _b('can_play_premium');
  bool get freeMode => _b('free_mode');
  bool get plansVisible => _b('plans_visible');
  bool get paymentsAvailable => _b('payments_available');
  bool get hasAdsAccess => _b('has_ads_access');
  bool get playBillingEnabled => _b('play_billing_enabled');
  String get source => (raw['source'] as String?) ?? 'organic';
  String? get accessStatus => raw['access_status'] as String?;
  String? get planName => raw['plan_name'] as String?;
  DateTime? get planEndsAt => raw['plan_ends_at'] == null ? null : DateTime.tryParse(raw['plan_ends_at'] as String)?.toLocal();
  int get usedBytes => _i('used_bytes');
  int get quotaBytes => _i('quota_bytes');
}

class OrderInfo {
  OrderInfo(this.json);
  final Map<String, dynamic> json;
  String get orderId => json['order_id'] as String;
  String get reference => json['reference'] as String;
  String get status => (json['status'] as String?) ?? 'pending';
  String get planName => (json['plan_name'] as String?) ?? '';
  num get amountInr => (json['amount_inr'] as num?) ?? 0;
  String? get upiId => json['upi_id'] as String?;
  String? get payeeName => json['payee_name'] as String?;
}

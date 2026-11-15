import 'dart:convert';

import '../config.dart';

enum UpiOutcome { success, failure, noResponse, unknown }

/// Builds the upi://pay URI exactly as the spec requires.
String buildUpiUri({
  required String upiId,
  required String payee,
  required String reference,
  required num amountInr,
  String appName = Config.appName,
}) {
  final q = <String, String>{
    'pa': upiId,
    'pn': payee,
    'tr': reference,
    'am': amountInr.toStringAsFixed(2),
    'cu': 'INR',
    'tn': '$appName $reference',
  };
  final body = q.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
  return 'upi://pay?$body';
}

/// Parses the raw response string a UPI app returns (e.g. "Status=SUCCESS&txnId=…&txnRef=…").
/// This is client-reported and only ever *reported* to the server, never trusted by the app.
UpiOutcome parseUpiResult(String? raw) {
  if (raw == null || raw.trim().isEmpty) return UpiOutcome.noResponse;
  final map = <String, String>{};
  for (final part in raw.split('&')) {
    final i = part.indexOf('=');
    if (i > 0) map[part.substring(0, i).trim().toLowerCase()] = part.substring(i + 1).trim();
  }
  final s = (map['status'] ?? map['txnstatus'] ?? '').toLowerCase();
  if (s == 'success' || s == 'submitted') return UpiOutcome.success;
  if (s == 'failure' || s == 'failed') return UpiOutcome.failure;
  if (raw.toLowerCase().contains('no_response')) return UpiOutcome.noResponse;
  return UpiOutcome.unknown;
}

/// Message sent by the website /subscribe page through the JS channel.
class BuyMessage {
  BuyMessage(this.planId);
  final String planId;
  static BuyMessage? tryParse(Object? json) {
    try {
      final m = json is String ? jsonDecode(json) : json;
      if (m is Map && m['type'] == 'buy' && m['plan_id'] is String && (m['plan_id'] as String).isNotEmpty) {
        return BuyMessage(m['plan_id'] as String);
      }
    } catch (_) {}
    return null;
  }
}

/// Allowed WebView navigation: only WEBSITE_URL/subscribe and /d.
bool isAllowedWebUrl(String url, {String site = Config.websiteUrl}) {
  final u = Uri.tryParse(url);
  final s = Uri.parse(site);
  if (u == null || u.scheme != 'https' || u.host != s.host) return false;
  return u.path == '/subscribe' || u.path.startsWith('/subscribe/') || u.path == '/d' || u.path.startsWith('/d/');
}

/// URL of the plans page with the spec's query params.
Uri subscribeUri({List<String> freeIds = const [], bool paused = false, String site = Config.websiteUrl}) {
  final q = <String, String>{'app': '1'};
  if (freeIds.isNotEmpty) q['free'] = freeIds.join(',');
  if (paused) q['paused'] = '1';
  return Uri.parse('$site/subscribe').replace(queryParameters: q);
}

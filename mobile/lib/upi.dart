import 'dart:convert';

String buildUpiLink({
  required String upiId,
  required String payeeName,
  required String reference,
  required int amountPaise,
}) {
  final values = <String, String>{
    'pa': upiId,
    'pn': payeeName,
    'tr': reference,
    'am': (amountPaise / 100).toStringAsFixed(2),
    'cu': 'INR',
    'tn': 'Vayora $reference',
  };
  return 'upi://pay?${values.entries.map((e) => '${Uri.encodeComponent(e.key)}=${e.key == 'pa' ? Uri.encodeComponent(e.value).replaceAll('%40', '@') : Uri.encodeComponent(e.value)}').join('&')}';
}

Map<String, String> parseUpiResponse(String raw) {
  try {
    final query = raw.contains('?') ? raw.substring(raw.indexOf('?') + 1) : raw;
    return Uri.splitQueryString(
      query,
    ).map((k, v) => MapEntry(k.toLowerCase(), v));
  } on Object {
    return {'status': 'unknown', 'raw': raw};
  }
}

Map<String, String> readPendingPayments(String? raw) {
  if (raw == null) return {};
  try {
    return Map<String, String>.from(jsonDecode(raw) as Map);
  } on Object {
    return {};
  }
}

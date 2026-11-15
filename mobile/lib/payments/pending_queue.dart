import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A UPI result saved locally BEFORE it is reported, so a killed app never loses it.
class PendingPayment {
  PendingPayment({required this.orderId, required this.raw, this.attempts = 0});
  final String orderId;
  final String raw;
  final int attempts;
  Map<String, dynamic> toJson() => {'orderId': orderId, 'raw': raw, 'attempts': attempts};
  static PendingPayment fromJson(Map<String, dynamic> j) =>
      PendingPayment(orderId: j['orderId'] as String, raw: j['raw'] as String, attempts: (j['attempts'] as int?) ?? 0);
}

typedef Reporter = Future<void> Function(String orderId, String raw);

class PendingQueue {
  static const _key = 'pending_payments';

  Future<List<PendingPayment>> all() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_key);
    if (s == null) return [];
    return (jsonDecode(s) as List).map((e) => PendingPayment.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<void> _save(List<PendingPayment> l) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(l.map((e) => e.toJson()).toList()));
  }

  Future<void> add(String orderId, String raw) async {
    final l = await all();
    l.removeWhere((e) => e.orderId == orderId);
    l.add(PendingPayment(orderId: orderId, raw: raw));
    await _save(l);
  }

  /// Tries every queued result. Items the server answers are removed; failures stay for the next resume/launch.
  Future<int> flush(Reporter report) async {
    final l = await all();
    final keep = <PendingPayment>[];
    var sent = 0;
    for (final it in l) {
      try {
        await report(it.orderId, it.raw);
        sent++;
      } catch (_) {
        keep.add(PendingPayment(orderId: it.orderId, raw: it.raw, attempts: it.attempts + 1));
      }
    }
    await _save(keep);
    return sent;
  }

  /// Backoff delay for the n-th attempt, capped at 5 minutes.
  static Duration backoff(int attempts) => Duration(seconds: (2 << attempts.clamp(0, 8)).clamp(2, 300));
}

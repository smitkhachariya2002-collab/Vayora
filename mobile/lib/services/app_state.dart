import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config.dart';
import 'measurement.dart';
import '../models/status.dart';
import '../payments/pending_queue.dart';
import '../payments/upi.dart';

SupabaseClient get sb => Supabase.instance.client;

/// Holds what the SERVER says (my_status). The app never decides access or prices.
class AppState extends ChangeNotifier {
  AppState({PendingQueue? queue}) : queue = queue ?? PendingQueue();

  final PendingQueue queue;
  AppStatus status = AppStatus.guest();
  Set<String> freePlanIds = {};
  bool loaded = false;
  Timer? _poll;
  RealtimeChannel? _rt;

  static const upiChannel = MethodChannel('app/upi');

  Future<void> start() async {
    if (sb.auth.currentSession == null) {
      try {
        await sb.auth.signInAnonymously();
      } catch (_) {/* guest session unavailable: browse with the public guest status */}
    }
    await _recordInstallOnce();
    await refresh();
    unawaited(Measurement.instance.start());
    flushPending();
    _rt = sb
        .channel('mode')
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'app_mode', callback: (_) => refresh())
        .subscribe();
    _poll = Timer.periodic(const Duration(seconds:60),(_){refresh();Measurement.instance.flush();});
    sb.auth.onAuthStateChange.listen((event) async {
      await refresh();
      if(event.event==AuthChangeEvent.signedIn||event.event==AuthChangeEvent.userUpdated){await Measurement.instance.start();}
    });
  }

  Future<void> _recordInstallOnce() async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool('install_recorded') == true) return;
    final id = p.getString('install_id') ?? const Uuid().v4();
    final secret = p.getString('install_secret') ?? const Uuid().v4();
    await p.setString('install_id', id);
    await p.setString('install_secret', secret);
    try {
      await sb.rpc('record_install', params: {
        'p_install_id': id,
        'p_referrer_status': Config.apkReferrer.isEmpty ? 'none' : 'apk_define',
        'p_raw_referrer': Config.apkReferrer,
        'p_install_secret': secret,
      });
      await p.setBool('install_recorded', true);
    } catch (_) {/* retried next launch */}
  }

  /// Makes sure there is an auth session (a guest/anonymous one if needed). Returns false if none could be created.
  Future<bool> ensureSession() async {
    if (sb.auth.currentSession != null) return true;
    try {
      await sb.auth.signInAnonymously();
    } catch (_) {
      return false;
    }
    await refresh();
    return sb.auth.currentSession != null;
  }

  Future<void> refresh() async {
    try {
      final r = await sb.rpc(sb.auth.currentSession == null ? 'guest_status' : 'my_status');
      status = AppStatus(Map<String, dynamic>.from(r as Map));
      if (status.plansVisible && !Config.playStore) {
        final o = await sb.rpc('plan_offers');
        freePlanIds = {...((o as Map)['free_plan_ids'] as List? ?? const []).map((e) => e.toString())};
      }
    } catch (_) {
      // keep last known; if we never had a real status, use the public guest status
      if (!loaded) {
        try {
          final r = await sb.rpc('guest_status');
          status = AppStatus(Map<String, dynamic>.from(r as Map));
        } catch (_) {}
      }
    }
    loaded = true;
    notifyListeners();
  }

  // ---- premium visibility rules (Part D) -------------------------------------------------
  bool get showPrices => !Config.playStore && !status.freeMode && status.plansVisible;
  bool get showPremiumEntry => showPrices;

  // ---- payments -------------------------------------------------------------------------
  Future<Map<String, dynamic>> createOrder(String planId) async {
    final r = await sb.rpc('create_order', params: {'p_plan': planId});
    final order=Map<String,dynamic>.from(r as Map);
    return order;
  }

  Future<Map<String, dynamic>> claimFree(String planId) async {
    final r = await sb.rpc('claim_free_plan', params: {'p_plan': planId});
    await refresh();
    return Map<String, dynamic>.from(r as Map);
  }

  /// Launches the UPI chooser. Returns the raw response string (or null) or throws
  /// [PlatformException] with code 'NO_APP' when no activity could handle the intent.
  Future<String?> launchUpi(String uri) async {
    return await upiChannel.invokeMethod<String>('pay', {'uri': uri});
  }

  Future<void> report(String orderId, String raw) async {
    await sb.rpc('report_result', params: {'p_order': orderId, 'p_raw': raw});
  }

  /// Saves the result locally FIRST, then reports; failures stay queued.
  Future<void> saveAndReport(String orderId, String raw) async {
    await queue.add(orderId, raw);
    await flushPending();
  }

  Future<void> flushPending() async {
    if (sb.auth.currentSession == null) return;
    final n = await queue.flush(report);
    if (n > 0) await refresh();
  }

  Future<Map<String, dynamic>?> orderStatus(String orderId) async {
    final rows = await sb.from('payment_orders').select('id,status,reference,plan_name,amount_paise').eq('id', orderId).limit(1);
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  static UpiOutcome outcomeOf(String? raw) => parseUpiResult(raw);

  @override
  void dispose() {
    _poll?.cancel();
    _rt?.unsubscribe();
    super.dispose();
  }
}


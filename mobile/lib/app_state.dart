import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'upi.dart';

const backendUrl = String.fromEnvironment('SUPABASE_URL',
    defaultValue: 'https://fzloulsjhkdxwagonsgt.supabase.co');
const backendKey = String.fromEnvironment('SUPABASE_KEY');
const androidAppId = String.fromEnvironment('ANDROID_APP_ID', defaultValue: 'com.vayora.app');
const authCallback = '$androidAppId://login-callback';
const apkReferrer = String.fromEnvironment('APK_REFERRER');

class AppState extends ChangeNotifier {
  AppState(this.db, this.prefs, {http.Client? authSettingsClient}) : _settingsClient = authSettingsClient ?? http.Client(), _ownsSettingsClient = authSettingsClient == null {
    _authEvents = db.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.passwordRecovery) {
        recoveringPassword = true;
        notifyListeners();
      }
    });
  }
  late final StreamSubscription<AuthState> _authEvents;
  final SupabaseClient db;
  final SharedPreferences prefs;
  final http.Client _settingsClient;
  final bool _ownsSettingsClient;
  int membershipRevision = 0;
  void membershipChanged() { membershipRevision++; notifyListeners(); }
  Map<String, dynamic> status = {};
  bool busy = false;
  bool _reporting = false;
  Timer? _statusPoll;
  bool recoveringPassword = false;
  int _statusRequest = 0;
  RealtimeChannel? _modeChannel;
  String? error;
  bool get guest => status['is_guest'] != false;
  bool get premium => status['is_premium'] == true;
  bool get adsAccess => status['has_ads_access'] == true;
  bool get paidEnabled => status['free_mode'] == false;
  bool canSee(String audience) => status['is_admin'] == true || audience == 'all' ||
      (audience == 'organic' && status['source'] == 'organic') ||
      (audience == 'ads' && adsAccess);
  String get userId => db.auth.currentUser!.id;
  String get installId => prefs.getString('install_id')!;
  String get installSecret => prefs.getString('install_secret')!;
  Set<String> get blocked => (prefs.getStringList('blocked_channels') ?? []).toSet();

  Future<void> initialize({bool watchRemoteChanges = true}) async {
    if (!prefs.containsKey('install_id')) {
      await prefs.setString('install_id', const Uuid().v4());
      await prefs.setString('install_secret', '${const Uuid().v4()}${const Uuid().v4()}');
    }
    if (db.auth.currentSession == null) await db.auth.signInAnonymously();
    if (prefs.getBool('install_recorded') != true) {
      await db.rpc('record_install', params: {
        'install_id': installId,
        'referrer_status': apkReferrer.isEmpty ? 'none' : 'provided',
        'raw_referrer': apkReferrer,
        'install_secret': installSecret,
      });
      await prefs.setBool('install_recorded', true);
    }
    await afterLogin();
    if (!watchRemoteChanges) return;
    // Realtime switches mode immediately; polling also picks up approvals,
    // revocations and expiry while a screen remains open.
    _statusPoll ??= Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(refreshStatus().catchError((Object _) {}));
    });
    _modeChannel ??= db.channel('vayora-operating-mode')
      .onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'app_mode',
        callback: (_) { unawaited(refreshStatus().catchError((Object _) {})); }).subscribe();
  }

  Future<void> afterLogin() async {
    await db.rpc('attribute_user',
        params: {'install_id': installId, 'install_secret': installSecret});
    await refreshStatus();
    if (prefs.getBool('consent_v1') == true) await syncConsent();
    await retryPayments();
  }

  Future<void> refreshStatus() async {
    final request = ++_statusRequest;
    final id = db.auth.currentUser?.id;
    final next = Map<String, dynamic>.from(await db.rpc('my_status') as Map);
    if (request == _statusRequest && id == db.auth.currentUser?.id && next['user_id'] == id) {
      status = next;
      notifyListeners();
    }
  }

  Future<void> acceptConsent() async {
    await syncConsent();
    await prefs.setBool('consent_v1', true);
    notifyListeners();
  }

  Future<void> syncConsent() async {
    final rows = await db.from('consents').select('policy_version')
        .eq('user_id', userId).eq('policy_version', 'v1');
    if (rows.isEmpty) {
      await db.from('consents').insert({'user_id': userId, 'policy_version': 'v1'});
    }
  }

  Future<void> login(String email, String password, {bool create = false}) async {
    if (create && db.auth.currentUser?.isAnonymous == true) {
      await db.auth.updateUser(UserAttributes(email: email, password: password),
          emailRedirectTo: authCallback);
    } else {
      await db.auth.signInWithPassword(email: email, password: password);
    }
    await afterLogin();
  }

  Future<void> google({bool linkGuest = false}) async {
    final response = await _settingsClient.get(Uri.parse('$backendUrl/auth/v1/settings'), headers: {'apikey': backendKey});
    if (response.statusCode != 200) throw StateError('Could not check sign-in options');
    final settings = jsonDecode(response.body) as Map;
    if ((settings['external'] as Map?)?['google'] != true) {
      throw const AuthException('Google sign-in is coming soon. Please log in with email.', code: 'provider_disabled');
    }
    if (linkGuest && db.auth.currentUser?.isAnonymous == true) {
      await db.auth.linkIdentity(OAuthProvider.google,
          redirectTo: authCallback);
    } else {
      await db.auth.signInWithOAuth(OAuthProvider.google,
          redirectTo: authCallback);
    }
  }

  Future<void> logout() async {
    status = {};
    recoveringPassword = false;
    notifyListeners();
    await db.auth.signOut();
    await db.auth.signInAnonymously();
    await afterLogin();
  }

  Future<void> sendPasswordReset(String email) async {
    if (email.isEmpty) throw StateError('Enter your email address first');
    await db.auth.resetPasswordForEmail(email, redirectTo: authCallback);
  }

  Future<void> saveRecoveredPassword(String password) async {
    if (!recoveringPassword) throw StateError('Open the password reset email first');
    if (password.length < 8) throw StateError('Use at least 8 characters');
    await db.auth.updateUser(UserAttributes(password: password));
    recoveringPassword = false;
    await afterLogin();
  }

  @override
  void dispose() {
    _statusPoll?.cancel();
    if (_ownsSettingsClient) _settingsClient.close();
    unawaited(_authEvents.cancel());
    if (_modeChannel != null) unawaited(db.removeChannel(_modeChannel!));
    super.dispose();
  }

  Future<void> block(String channelId) async {
    final values = blocked;
    if (!values.add(channelId)) values.remove(channelId);
    await prefs.setStringList('blocked_channels', values.toList());
    notifyListeners();
  }

  Future<void> requestAccess() async {
    await db.rpc('request_full_access');
    await refreshStatus();
  }

  Future<String> pay(String planId) async {
    final order = Map<String, dynamic>.from(
        await db.rpc('create_payment_order', params: {'plan_id': planId}) as Map);
    const channel = MethodChannel('app/upi');
    final raw = await channel.invokeMethod<String>('pay', {
      'uri': buildUpiLink(
          upiId: order['upi_id'] as String,
          payeeName: order['payee_name'] as String,
          reference: order['reference'] as String,
          amountPaise: (order['amount_paise'] as num).toInt()),
      'order_id': order['id'],
    });
    if (raw != null) {
      final pending = readPendingPayments(prefs.getString('pending_payments'));
      pending[order['id'] as String] = raw;
      await prefs.setString('pending_payments', jsonEncode(pending));
      await retryPayments();
    }
    return order['id'] as String;
  }

  Future<void> retryPayments() async {
    if (_reporting) return;
    _reporting = true;
    try {
      const native = MethodChannel('app/upi');
      final queue = readPendingPayments(prefs.getString('pending_payments'));
      try {
        final recovered = await native.invokeMapMethod<String, String>('pending');
        if (recovered != null) queue.addAll(recovered);
      } on MissingPluginException {
        // Native recovery is only available on Android.
      }
      await prefs.setString('pending_payments', jsonEncode(queue));
      for (final entry in Map<String, String>.from(queue).entries) {
        try {
          await db.rpc('report_payment_result',
              params: {'order_id': entry.key, 'raw': entry.value});
          queue.remove(entry.key);
          await prefs.setString('pending_payments', jsonEncode(queue));
          await native.invokeMethod<void>('ack', {'order_id': entry.key});
        } on Object {
          // Keep the response until the server accepts it; retry on resume/start.
        }
      }
      await refreshStatus();
    } finally {
      _reporting = false;
    }
  }
}

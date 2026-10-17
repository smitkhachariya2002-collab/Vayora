import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vayora/app_state.dart';

const guestId = '11111111-1111-4111-8111-111111111111';
const existingId = '22222222-2222-4222-8222-222222222222';

class Fixture {
  final calls = <http.Request>[];
  String id = guestId;
  bool anonymous = true;
  late final SupabaseClient db;
  late final AppState state;
  Map<String, dynamic> currentStatus = {};
  Map<String, dynamic> user() => {
    'id': id, 'aud': 'authenticated', 'role': 'authenticated',
    'email': anonymous ? '' : 'test@example.test', 'is_anonymous': anonymous,
    'created_at': '2026-01-01T00:00:00Z', 'app_metadata': {}, 'user_metadata': {},
  };
  Map<String, dynamic> session() => {
    'access_token': '${base64Url.encode(utf8.encode('{"alg":"HS256"}'))}.${base64Url.encode(utf8.encode(jsonEncode({'sub':id,'exp':4102444800})))}.signature',
    'refresh_token': 'test-refresh', 'expires_in': 3600, 'token_type': 'bearer', 'user': user(),
  };
  Future<void> start() async {
    SharedPreferences.setMockInitialValues({});
    db = SupabaseClient('https://example.supabase.co', 'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        calls.add(request);
        Object? body;
        if (request.url.path.endsWith('/signup')) {
          anonymous = true; id = guestId; body = session();
        } else if (request.url.path.endsWith('/token')) {
          anonymous = false; id = existingId; body = session();
        } else if (request.url.path.endsWith('/user')) {
          anonymous = false; body = user();
        } else if (request.url.path.endsWith('/my_status')) {
          body = {'user_id':id,'is_guest':anonymous,'source':'organic',
            'free_mode':false,'has_ads_access':false,'is_premium':false,
            ...currentStatus};
        } else if (request.url.path.endsWith('/consents')) {
          body = <Object>[];
        } else { body = null; }
        return http.Response(jsonEncode(body), 200, headers: {'content-type':'application/json'});
      }));
    state = AppState(db, await SharedPreferences.getInstance());
    await state.initialize();
  }
  Future<void> close() async { state.dispose(); await db.dispose(); }
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Fixture f;
  setUp(() async { f = Fixture(); await f.start(); });
  tearDown(() async { await f.close(); });

  test('First open creates guest and records persisted install only once', () async {
    expect(f.state.guest, isTrue);
    final install = f.state.installId;
    expect(f.state.installSecret.length, greaterThanOrEqualTo(32));
    await f.state.initialize();
    expect(f.state.installId, install);
    expect(f.calls.where((r) => r.url.path.endsWith('/record_install')), hasLength(1));
  });
  test('Guest signup updates same user with mobile email confirmation callback', () async {
    await f.state.login('test@example.test', 'password123', create: true);
    final update = f.calls.singleWhere((r) => r.method == 'PUT' && r.url.path.endsWith('/user'));
    expect(jsonDecode(update.body)['email'], 'test@example.test');
    expect(update.url.queryParameters['redirect_to'], authCallback);
    expect(f.db.auth.currentUser!.id, guestId);
    expect(f.calls.where((r) => r.url.path.endsWith('/signup')), hasLength(1));
    expect(f.calls.lastWhere((r) => r.url.path.endsWith('/attribute_user')).body,
      contains(f.state.installId));
  });
  test('Existing login switches account and reattributes same device', () async {
    final install = f.state.installId;
    await f.state.login('existing@example.test', 'password123');
    expect(f.db.auth.currentUser!.id, existingId);
    expect(f.state.status['user_id'], existingId);
    expect(f.state.installId, install);
    expect(f.calls.where((r) => r.url.path.endsWith('/attribute_user')).length, greaterThan(1));
  });
  test('Logout replaces member session with a guest', () async {
    await f.state.login('existing@example.test', 'password123');
    await f.state.logout();
    expect(f.state.guest, isTrue);
    expect(f.db.auth.currentUser!.isAnonymous, isTrue);
  });
  test('Reset email uses Android callback and recovery requires eight characters', () async {
    await f.state.sendPasswordReset('test@example.test');
    final reset = f.calls.singleWhere((r) => r.url.path.endsWith('/recover'));
    expect(reset.url.queryParameters['redirect_to'], authCallback);
    await expectLater(f.state.saveRecoveredPassword('password123'), throwsStateError);
    f.state.recoveringPassword = true;
    await expectLater(f.state.saveRecoveredPassword('short'), throwsStateError);
    await f.state.saveRecoveredPassword('new-password123');
    expect(f.state.recoveringPassword, isFalse);
  });
  test('Screens consume server mode and audience approval independently of premium', () async {
    f.currentStatus = {'free_mode':true,'is_premium':true,'has_ads_access':false};
    await f.state.refreshStatus();
    expect(f.state.paidEnabled, isFalse);
    expect(f.state.canSee('ads'), isFalse);
    expect(f.state.canSee('organic'), isTrue);
    f.currentStatus = {'free_mode':false,'is_premium':false,'has_ads_access':true};
    await f.state.refreshStatus();
    expect(f.state.paidEnabled, isTrue);
    expect(f.state.canSee('ads'), isTrue);
    expect(f.state.premium, isFalse);
  });
}

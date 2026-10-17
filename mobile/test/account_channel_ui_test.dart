import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vayora/account_page.dart';
import 'package:vayora/channel_page.dart';
import 'account_test.dart' show Fixture, existingId;

void main() {
  late Fixture f;
  late List<Map<String, dynamic>> channels;
  late bool rejectCreate;
  http.Response reply(http.Request request, Object? body, {int status = 200}) =>
    http.Response(jsonEncode(body), status, request: request, headers: {'content-type': 'application/json'});

  Future<void> open(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) =>
      TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page)), child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }
  Future<void> submit(WidgetTester tester, String key) async {
    tester.testTextInput.hide();
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
  }
  setUp(() async {
    f = Fixture(); channels = []; rejectCreate = false;
    f.intercept = (request) {
      if (request.url.path.contains('/storage/v1/object/')) return reply(request, {'Key': request.url.path});
      if (!request.url.path.endsWith('/channels')) return null;
      if (request.method == 'POST') {
        if (rejectCreate) return reply(request, {'message': 'Try again', 'code': 'P0001'}, status: 400);
        final row = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
        channels.add({...row, 'review_status': 'pending', 'status': 'active'});
        return reply(request, null);
      }
      if (request.method == 'PATCH') return reply(request, {'id': channels.single['id']});
      final mine = request.url.queryParameters['created_by'];
      final review = request.url.queryParameters['review_status'];
      return reply(request, channels.where((row) =>
        (mine == null || mine == 'eq.${row['created_by']}') &&
        (review == null || review == 'eq.${row['review_status']}')).toList());
    };
    await f.start();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('app/photo'), (_) async => null);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('app/photo'), null);
    await f.close();
  });

  testWidgets('Account starts in Log in with clear sign-up choice and no guest switch', (tester) async {
    await open(tester, Login(state: f.state));
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.textContaining('guest'), findsNothing);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('login-email')), 'existing@example.test');
    await tester.enterText(find.byKey(const ValueKey('login-password')), 'password123');
    await submit(tester, 'account-submit');
    expect(f.db.auth.currentUser!.id, existingId);
    expect(f.calls.where((r) => r.url.path.endsWith('/token')), hasLength(1));
  });

  testWidgets('Duplicate sign-up switches to login with helpful wording', (tester) async {
    final previous = f.intercept;
    f.intercept = (request) => request.method == 'PUT' && request.url.path.endsWith('/user')
      ? reply(request, {'msg': 'Email already registered', 'code': 'email_exists'}, status: 422) : previous!(request);
    await open(tester, Login(state: f.state));
    await tester.tap(find.text('Sign up')); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('login-email')), 'existing@example.test');
    await tester.enterText(find.byKey(const ValueKey('login-password')), 'password123');
    await submit(tester, 'account-submit');
    expect(find.text('This email already has an account. Log in or reset your password.'), findsOneWidget);
    expect(find.textContaining('AuthApiException'), findsNothing);
    expect(find.text('Forgot password?'), findsOneWidget);
  });

  testWidgets('Create saves name, optional description and normalized tags', (tester) async {
    await f.state.login('existing@example.test', 'password123');
    await open(tester, ChannelEditor(state: f.state));
    await tester.enterText(find.byKey(const ValueKey('channel-name')), 'My India');
    await tester.enterText(find.byKey(const ValueKey('channel-tags')), '#Music, INDIA, music');
    await submit(tester, 'channel-submit');
    expect(channels, hasLength(1));
    expect(channels.single['name'], 'My India');
    expect(channels.single['description'], '');
    expect(channels.single['tags'], ['music', 'india']);
    expect(channels.single['created_by'], existingId);
  });

  testWidgets('Invalid channel fields never send a creation request', (tester) async {
    await f.state.login('existing@example.test', 'password123');
    await open(tester, ChannelEditor(state: f.state));
    await submit(tester, 'channel-submit');
    expect(find.text('Enter a channel name'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('channel-name')), 'Music');
    await tester.enterText(find.byKey(const ValueKey('channel-tags')), List.generate(11, (i) => 'tag$i').join(','));
    await submit(tester, 'channel-submit');
    expect(find.text('Add up to 10 tags'), findsOneWidget);
    expect(channels, isEmpty);
  });

  testWidgets('My channels shows private submission status and edit without approval copy', (tester) async {
    await f.state.login('existing@example.test', 'password123');
    channels.add({'id': 'channel-one', 'name': 'My channel', 'created_by': existingId, 'description': 'For music fans',
      'tags': ['music'], 'review_status': 'pending', 'status': 'active', 'icon_url': null});
    await open(tester, ChannelList(state: f.state, onOpen: (_) {}));
    await tester.tap(find.text('My channels')); await tester.pumpAndSettle();
    expect(find.text('My channel'), findsOneWidget);
    expect(find.text('Under review'), findsOneWidget);
    expect(find.byTooltip('Edit channel'), findsOneWidget);
    expect(find.textContaining('owner approval'), findsNothing);
  });

  testWidgets('Cancelled photo selection keeps the channel form', (tester) async {
    await f.state.login('existing@example.test', 'password123');
    await open(tester, ChannelEditor(state: f.state));
    await tester.enterText(find.byKey(const ValueKey('channel-name')), 'Keep my name');
    await tester.tap(find.byKey(const ValueKey('channel-photo'))); await tester.pumpAndSettle();
    expect(find.text('Keep my name'), findsOneWidget);
    expect(find.textContaining('Could not open'), findsNothing);
  });

  testWidgets('Photo upload rolls back on save failure and form can retry', (tester) async {
    await f.state.login('existing@example.test', 'password123');
    final Uint8List pixel = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('app/photo'), (_) async => pixel);
    rejectCreate = true;
    await open(tester, ChannelEditor(state: f.state));
    await tester.tap(find.byKey(const ValueKey('channel-photo'))); await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('channel-name')), 'Photo channel');
    await submit(tester, 'channel-submit');
    expect(find.textContaining('Could not save your channel.'), findsOneWidget);
    expect(find.text('Photo channel'), findsOneWidget);
    expect(f.calls.where((r) => r.method == 'DELETE' && r.url.path.contains('/storage/v1/object/')), hasLength(1));
    rejectCreate = false;
    await submit(tester, 'channel-submit');
    expect(channels.single['icon_url'], contains('$existingId/channel-photos/'));
  });
}

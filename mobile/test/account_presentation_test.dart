import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vayora/main.dart';
import 'package:vayora/screens/account_ui.dart';
import 'package:vayora/screens/new_post.dart';
import 'package:vayora/theme.dart';
import 'package:vayora/widgets/common.dart';
import 'account_test.dart' show Fixture, existingId;

void main() {
  test('Plan action labels cover selection, guest, member and launch states', () {
    expect(premiumButtonLabel(selected: false, guest: true, busy: false), 'Select a plan');
    expect(premiumButtonLabel(selected: true, guest: true, busy: false), 'Next');
    expect(premiumButtonLabel(selected: true, guest: false, busy: false), 'Continue to payment');
    expect(premiumButtonLabel(selected: true, guest: false, busy: true), 'Opening UPI…');
  });
  test('An active server plan takes priority over an open order', () {
    expect(premiumBanner({'plan_name': 'Gold', 'is_premium': true}, [{'status': 'pending'}]), PremiumBannerKind.active);
    expect(premiumBanner({'plan_name': 'Gold', 'is_premium': false}, [{'status': 'pending'}]), PremiumBannerKind.pending);
    expect(premiumBanner({}, []), PremiumBannerKind.none);
  });
  test('All server payment states have distinct messages and history tones', () {
    expect(paymentMessage('success'), 'Payment successful! Your plan is now active.');
    expect(paymentMessage('failed'), 'Payment failed. Please try again.');
    expect(paymentMessage('cancelled'), 'Payment cancelled. You can try again.');
    expect(paymentMessage('revoked'), contains('reversed after review'));
    expect(paymentMessage('initiated'), 'Payment not completed. You can try again.');
    expect(paymentLabel('revoked'), 'Reversed');
    expect(paymentTone('revoked'), NoticeTone.danger);
    expect(paymentTone('failed'), NoticeTone.neutral);
    expect(paymentPending('revoked'), isFalse);
  });
  test('Names use the persisted value or deterministic user ID fallback', () {
    expect(profileName({}, existingId), 'User-22222222');
    expect(profileName({'display_name': '  Kavya  '}, existingId), 'Kavya');
  });
  testWidgets('Guest profile has one login choice and Add Channel asks for login', (tester) async {
    final f = Fixture(); await tester.runAsync(f.start);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: Profile(state: f.state))));
    await tester.pumpAndSettle();
    expect(find.text("You're using the app as a guest."), findsOneWidget);
    expect(find.text('Log in / Create account'), findsOneWidget);
    expect(find.text('Delete Account'), findsNothing);
    expect(find.text('Payment history'), findsNothing);
    await tester.ensureVisible(find.text('Add Channel'));
    await tester.tap(find.text('Add Channel')); await tester.pumpAndSettle();
    expect(find.text('Log in to create a channel'), findsOneWidget);
    await tester.tap(find.text('Not now')); await tester.pumpAndSettle();
    expect(f.calls.where((r) => r.url.path.endsWith('/token')), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink()); await tester.runAsync(f.close);
  });
  testWidgets('Profile upload is limited to owned approved active channels', (tester) async {
    final f = Fixture();
    f.intercept = (r) => r.url.path.endsWith('/channels') ? response(r, [
      {'id': 'owned', 'name': 'My India', 'created_by': existingId, 'review_status': 'approved', 'status': 'active'},
    ]) : r.url.path.endsWith('/channel_members') ? response(r, []) : null;
    await tester.runAsync(f.start);
    await tester.runAsync(() => f.state.login('test@example.test', 'password123'));
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: Profile(state: f.state))));
    await tester.pumpAndSettle();
    expect(find.text('Upload content'), findsOneWidget);
    await tester.tap(find.text('Upload content')); await tester.pumpAndSettle();
    expect(find.text('Upload to which channel?'), findsOneWidget);
    await tester.tap(find.text('My India').last); await tester.pumpAndSettle();
    expect(find.byType(NewPost), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink()); await tester.runAsync(f.close);
  });
  testWidgets('Selected plan survives login navigation and does not create an order early', (tester) async {
    final f = Fixture();
    f.intercept = (r) => r.url.path.endsWith('/plans') ? response(r, [
      {'id': 'gold', 'name': 'Gold', 'price_inr': 259, 'duration_days': 30, 'perks': ['Real perk']},
    ]) : r.url.path.endsWith('/payment_orders') ? response(r, []) : null;
    await tester.runAsync(f.start);
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Plans(state: f.state)));
    await tester.pumpAndSettle();
    expect(find.text('Select a plan'), findsOneWidget);
    await tester.ensureVisible(find.text('Gold')); await tester.tap(find.text('Gold')); await tester.pumpAndSettle();
    expect(find.text('Next'), findsOneWidget);
    await tester.tap(find.text('Next')); await tester.pumpAndSettle();
    expect(find.text('Please log in to buy Gold.'), findsOneWidget);
    await tester.tap(find.text('Log in').last); await tester.pumpAndSettle();
    expect(find.byType(Login), findsOneWidget);
    await tester.pageBack(); await tester.pumpAndSettle();
    expect(find.text('Next'), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    expect(f.calls.where((r) => r.url.path.endsWith('/create_payment_order')), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink()); await tester.runAsync(f.close);
  });
  testWidgets('Specific pending order polls to success and refreshes server entitlements', (tester) async {
    final f = Fixture(); var success = false;
    f.intercept = (r) => r.url.path.endsWith('/payment_orders') ? response(r, [
      {'id': 'order', 'reference': 'VAY-TEST', 'plan_id': 'gold', 'plans': {'name':'Gold'}, 'amount_paise':25900,
       'status': success ? 'success' : 'pending'},
    ]) : null;
    await tester.runAsync(f.start);
    await tester.runAsync(() => f.state.login('test@example.test','password123'));
    await tester.pumpWidget(MaterialApp(theme: buildTheme(), home: Payments(state:f.state, orderId:'order')));
    for (var i=0;i<5;i++) { await tester.pump(const Duration(milliseconds:100)); }
    expect(find.text('Checking your payment…'), findsOneWidget);
    success = true; f.currentStatus = {'is_premium':true, 'plan_name':'Gold'};
    await tester.pump(const Duration(seconds:5));
    await tester.runAsync(() async { await Future<void>.delayed(const Duration(milliseconds:30)); });
    for (var i=0;i<5;i++) { await tester.pump(const Duration(milliseconds:100)); }
    expect(find.text('Payment successful! Your plan is now active.'), findsOneWidget);
    expect(f.state.premium, isTrue);
    final query = f.calls.lastWhere((r) => r.url.path.endsWith('/payment_orders'));
    expect(query.url.queryParameters['user_id'], 'eq.$existingId');
    await tester.pumpWidget(const SizedBox.shrink()); await tester.runAsync(f.close);
  });
  testWidgets('A missing specific order never displays another user order', (tester) async {
    final f=Fixture();
    f.intercept=(r)=>r.url.path.endsWith('/payment_orders')?response(r,[{'id':'other','reference':'OTHER','status':'success'}]):null;
    await tester.runAsync(f.start);
    await tester.runAsync(()=>f.state.login('test@example.test','password123'));
    await tester.pumpWidget(MaterialApp(theme:buildTheme(),home:Payments(state:f.state,orderId:'missing')));
    for(var i=0;i<5;i++){await tester.pump(const Duration(milliseconds:100));}
    expect(find.text('Order unavailable'),findsOneWidget);
    expect(find.text('OTHER'),findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());await tester.runAsync(f.close);
  });
  testWidgets('New post validates before uploading and publishes through existing private storage path', (tester) async {
    tester.view.physicalSize=const Size(430,1400);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final f=Fixture();
    f.intercept=(r){
      if(r.url.path.endsWith('/channels'))return response(r,{'id':'channel','created_by':existingId,'review_status':'approved','status':'active','audience':'all'});
      if(r.url.path.endsWith('/posts'))return response(r,r.method=='PATCH'?{'id':'post'}:null);
      if(r.url.path.endsWith('/post_items'))return response(r,null);
      if(r.url.path.contains('/storage/v1/object/'))return response(r,{'Key':'image'});
      return null;
    };
    await tester.runAsync(f.start);
    await tester.runAsync(()=>f.state.login('test@example.test','password123'));
    final pixel=base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('app/photo'),(_)async=>pixel);
    await tester.pumpWidget(MaterialApp(theme:buildTheme(),home:NewPost(state:f.state,channel:const{'id':'channel','name':'My India'})));
    await tester.ensureVisible(find.text('Publish post'));
    await tester.runAsync(() async { await tester.tap(find.text('Publish post')); await Future<void>.delayed(const Duration(milliseconds: 150)); });
    await tester.pumpAndSettle();
    expect(find.text('Enter a title'),findsOneWidget);
    await tester.tap(find.text('Choose photo'));await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first,'A new story');
    FocusManager.instance.primaryFocus?.unfocus();tester.testTextInput.hide();await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Publish post'));await tester.tap(find.text('Publish post'));await tester.pumpAndSettle();
    final draft=f.calls.singleWhere((r)=>r.method=='POST'&&r.url.path.endsWith('/posts'));
    final values=jsonDecode(draft.body) as Map;
    expect(values['status'],'draft');expect(values['created_by'],existingId);
    final item=f.calls.singleWhere((r)=>r.method=='POST'&&r.url.path.endsWith('/post_items'));
    expect(jsonDecode(item.body)['media_key'],startsWith('$existingId/${values['id']}/'));
    expect(f.calls.where((r)=>r.method=='PATCH'&&r.url.path.endsWith('/posts')),hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());await tester.runAsync(f.close);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('app/photo'),null);
  });
}
http.Response response(http.Request r,Object? value)=>http.Response(jsonEncode(value),200,request:r,headers:{'content-type':'application/json'});

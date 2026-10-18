import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vayora/screens/profile.dart';
import 'package:vayora/screens/premium.dart';
import 'package:vayora/theme.dart';
import 'account_test.dart' show Fixture;

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:100)));
  await tester.pumpAndSettle();
}
void plans(Fixture f) {
  f.intercept=(r)=>r.url.path.endsWith('/plans')
    ? http.Response(jsonEncode([
      {'id':'trial','name':'Trial','price_inr':1,'duration_days':1,'active':true},
      {'id':'gold','name':'Gold','price_inr':259,'duration_days':30,'active':true},
    ]),200,request:r,headers:{'content-type':'application/json'}) : null;
}
void main(){
  for(final member in [false,true]){
    testWidgets('${member ? "Member" : "Guest"} opens full plans directly from Profile',(tester)async{
      final f=Fixture(); plans(f);
      await tester.runAsync(f.start);
      if(member)await tester.runAsync(()=>f.state.login('member@example.test','password123'));
      await tester.pumpWidget(MaterialApp(theme:buildTheme(),home:Scaffold(body:Profile(state:f.state))));
      await settle(tester);
      expect(find.byType(PlanCard),findsNWidgets(2));
      expect(find.byType(PremiumHero),findsOneWidget);
      expect(find.text('Explore Premium'),findsNothing);
      expect(find.text('My Channels'),findsNothing);
      expect(find.text('Privacy Policy'),findsNothing);
      expect(find.byType(DropdownButtonFormField<String>),findsNothing);
      expect(f.calls.where((r)=>r.url.path.endsWith('/create_payment_order')),isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(f.close);
    });
  }
  testWidgets('Active subscription shows account options; expiry restores plans live',(tester)async{
    final f=Fixture(); plans(f);
    await tester.runAsync(f.start);
    f.currentStatus={'is_premium':true,'plan_name':'Gold'};
    await tester.runAsync(()=>f.state.login('member@example.test','password123'));
    await tester.pumpWidget(MaterialApp(theme:buildTheme(),home:Scaffold(body:Profile(state:f.state))));
    await settle(tester);
    expect(find.byType(AccountProfile),findsOneWidget);
    expect(find.byType(PlanCard),findsNothing);
    expect(find.text('Privacy Policy'),findsOneWidget);
    expect(find.text('My Channels'),findsOneWidget);
    expect(f.calls.where((r)=>r.url.path.endsWith('/plans')),isEmpty);
    f.currentStatus={'is_premium':false,'plan_name':null};
    await tester.runAsync(f.state.refreshStatus);
    await tester.pump();
    await settle(tester);
    expect(find.byType(PlanCard),findsNWidgets(2));
    expect(find.text('Privacy Policy'),findsNothing);
    f.currentStatus={'is_premium':true,'plan_name':'Gold'};
    await tester.runAsync(f.state.refreshStatus);
    await tester.pump();
    await settle(tester);
    expect(find.byType(AccountProfile),findsOneWidget);
    expect(find.byType(PlanCard),findsNothing);
    expect(f.calls.where((r)=>r.url.path.endsWith('/create_payment_order')),isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(f.close);
  });
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vayora/screens/payments.dart';
import 'package:vayora/theme.dart';
import 'account_test.dart' show Fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Review order returns existing ID without another native payment launch', () async {
    final f = Fixture();
    f.intercept = (request) => request.url.path.endsWith('/create_payment_order')
      ? http.Response(jsonEncode({
          'id':'existing-paid-claim','checkout_allowed':false,
          'upi_id':'test@upi','amount_paise':100,
        }),200,request:request,headers:{'content-type':'application/json'}) : null;
    await f.start();
    await f.state.login('member@example.test','password123');
    var launches=0, priceDialogs=0;
    const channel = MethodChannel('app/upi');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,(call) async {
      if(call.method=='pay') launches++;
      return null;
    });
    expect(await f.state.pay('trial',beforeLaunch:(_)async{priceDialogs++;}),'existing-paid-claim');
    expect(launches,0);
    expect(priceDialogs,0);
    expect(f.state.prefs.getString('open_payment_order:${f.state.userId}'),'existing-paid-claim');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,null);
    await f.close();
  });
  testWidgets('Reported SUCCESS explains review and directs to UTR without claiming activation',(tester)async{
    await tester.pumpWidget(MaterialApp(theme:buildTheme(),home:Scaffold(body:PaymentStatusView(
      order:{'id':'late','reference':'VYLATE','status':'pending','client_status':'SUCCESS',
        'raw_response':'Status=SUCCESS&txnId=LATEWIN01','amount_paise':100},
      onDone:(){},onRetry:(){},onSupport:(){},onSubmitUtr:(){},
    ))));
    expect(find.textContaining('Do not pay again'),findsOneWidget);
    expect(find.text('Paid but not active? Enter UTR'),findsOneWidget);
    expect(find.text('Payment successful! Your plan is now active.'),findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

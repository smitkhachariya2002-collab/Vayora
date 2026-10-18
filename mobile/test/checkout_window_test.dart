import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vayora/screens/account_ui.dart';
import 'account_test.dart' show Fixture;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Each checkout launches its fresh server order and reports the exact raw answer', () async {
    final f = Fixture();
    var created=0, launches=0, reports=0, acknowledgements=0;
    f.intercept = (request) {
      if(request.url.path.endsWith('/create_payment_order')){
        created++;
        return http.Response(jsonEncode({
          'id':'fresh-$created','reference':'VYFRESH$created','upi_id':'test@upi',
          'payee_name':'Test','amount_paise':100,'duration_days':1,
        }),200,request:request,headers:{'content-type':'application/json'});
      }
      if(request.url.path.endsWith('/report_result')){
        reports++;
        final body=jsonDecode(request.body) as Map;
        expect(body['order_id'],'fresh-$reports');
        expect(body['raw_answer'],'Status=SUCCESS&txnRef=VYFRESH$reports&txnId=FRESH000$reports');
        return http.Response(jsonEncode('paid'),200,request:request,headers:{'content-type':'application/json'});
      }
      return null;
    };
    await f.start();
    await f.state.login('member@example.test','password123');
    const channel=MethodChannel('app/upi');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,(call)async{
      if(call.method=='pay'){
        launches++;
        final args=call.arguments as Map;
        final uri=Uri.parse(args['uri'] as String);
        expect(args['order_id'],'fresh-$launches');
        expect(uri.queryParameters['tr'],'VYFRESH$launches');
        expect(uri.queryParameters['am'],'1.00');
        expect(uri.queryParameters['pa'],'test@upi');
        return 'Status=SUCCESS&txnRef=VYFRESH$launches&txnId=FRESH000$launches';
      }
      if(call.method=='pending')return <String,String>{};
      if(call.method=='ack')acknowledgements++;
      return null;
    });
    expect(await f.state.pay('trial'),'fresh-1');
    expect(await f.state.pay('trial'),'fresh-2');
    expect(created,2);expect(launches,2);expect(reports,2);expect(acknowledgements,2);
    expect(f.state.prefs.getString('open_payment_order:${f.state.userId}'),'fresh-2');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel,null);
    await f.close();
  });
  test('UPI button shows exact current server plan price',(){
    expect(premiumButtonLabel(selected:true,guest:false,busy:false,price:1),'Pay ₹1 via UPI');
    expect(premiumButtonLabel(selected:true,guest:false,busy:false,price:999),'Pay ₹999 via UPI');
  });
}

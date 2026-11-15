import 'package:flutter_test/flutter_test.dart';
import 'package:vayora/payments/upi.dart';

void main() {
  group('buildUpiUri', () {
    test('has every required parameter, 2-decimal amount, encoded payee', () {
      final u = buildUpiUri(upiId: '2728412a@bandhan', payee: 'As Enterprice', reference: 'OB261109AB12CD34', amountInr: 49);
      expect(u, startsWith('upi://pay?'));
      final q = Uri.parse(u).queryParameters;
      expect(q['pa'], '2728412a@bandhan');
      expect(q['pn'], 'As Enterprice');
      expect(q['tr'], 'OB261109AB12CD34');
      expect(q['am'], '49.00');
      expect(q['cu'], 'INR');
      expect(q['tn'], 'Vayora OB261109AB12CD34');
      expect(u.contains('As%20Enterprice'), isTrue);
    });
  });

  group('parseUpiResult', () {
    test('success', () => expect(parseUpiResult('txnId=1&Status=SUCCESS&txnRef=OB1'), UpiOutcome.success));
    test('failure', () => expect(parseUpiResult('Status=FAILURE&txnId=1'), UpiOutcome.failure));
    test('no response', () {
      expect(parseUpiResult(null), UpiOutcome.noResponse);
      expect(parseUpiResult(''), UpiOutcome.noResponse);
      expect(parseUpiResult('NO_RESPONSE'), UpiOutcome.noResponse);
    });
    test('garbage', () => expect(parseUpiResult('%%%&&=='), UpiOutcome.unknown));
  });

  group('BuyMessage', () {
    test('parses valid', () => expect(BuyMessage.tryParse('{"type":"buy","plan_id":"abc"}')!.planId, 'abc'));
    test('rejects others', () {
      expect(BuyMessage.tryParse('{"type":"sell","plan_id":"abc"}'), isNull);
      expect(BuyMessage.tryParse('{"type":"buy"}'), isNull);
      expect(BuyMessage.tryParse('not json'), isNull);
      expect(BuyMessage.tryParse('{"type":"buy","plan_id":""}'), isNull);
    });
  });

  group('navigation allowlist', () {
    const site = 'https://vayora.example.app';
    test('allows /subscribe and /d on the site', () {
      expect(isAllowedWebUrl('$site/subscribe?app=1', site: site), isTrue);
      expect(isAllowedWebUrl('$site/d', site: site), isTrue);
    });
    test('blocks everything else', () {
      expect(isAllowedWebUrl('$site/privacy', site: site), isFalse);
      expect(isAllowedWebUrl('https://evil.example/subscribe', site: site), isFalse);
      expect(isAllowedWebUrl('http://vayora.example.app/subscribe', site: site), isFalse);
      expect(isAllowedWebUrl('intent://foo', site: site), isFalse);
    });
  });

  group('subscribeUri', () {
    test('adds app, free and paused', () {
      final u = subscribeUri(freeIds: ['a', 'b'], paused: true, site: 'https://x.app');
      expect(u.path, '/subscribe');
      expect(u.queryParameters, {'app': '1', 'free': 'a,b', 'paused': '1'});
    });
    test('omits free and paused when empty', () {
      expect(subscribeUri(site: 'https://x.app').queryParameters, {'app': '1'});
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:vayora/upi.dart';

void main() {
  test('Trial link exactly matches owner-confirmed UPI settings', () {
    expect(
      buildUpiLink(
        upiId: '2728412a@bandhan',
        payeeName: 'AS Enterprice',
        reference: 'VY261017AABBCCDDEEFF',
        amountPaise: 4900,
      ),
      'upi://pay?pa=2728412a@bandhan&pn=AS%20Enterprice&tr=VY261017AABBCCDDEEFF&am=49.00&cu=INR&tn=Vayora%20VY261017AABBCCDDEEFF',
    );
  });
  test('UPI fields have exact order, amount and percent encoding', () {
    expect(
      buildUpiLink(
        upiId: 'merchant@upi',
        payeeName: 'Vayora India',
        reference: 'VY123',
        amountPaise: 4900,
      ),
      'upi://pay?pa=merchant@upi&pn=Vayora%20India&tr=VY123&am=49.00&cu=INR&tn=Vayora%20VY123',
    );
  });
  test('UPI amount preserves paise', () {
    expect(
      buildUpiLink(
        upiId: 'a@b',
        payeeName: 'A&B',
        reference: 'r',
        amountPaise: 12901,
      ),
      contains('pn=A%26B&tr=r&am=129.01'),
    );
  });
  test('Responses normalize field case and decode values', () {
    final value = parseUpiResponse(
      'Status=SUCCESS&txnRef=VY123&ApprovalRefNo=ABC123456&note=hello%20India',
    );
    expect(value['status'], 'SUCCESS');
    expect(value['txnref'], 'VY123');
    expect(value['note'], 'hello India');
  });
  test('Malformed responses do not become success', () {
    expect(parseUpiResponse('Status=%ZZ')['status'], 'unknown');
  });
  test('Multiple pending results survive serialization', () {
    expect(
      readPendingPayments(
        '{"one":"Status=SUCCESS","two":"Status=FAILURE"}',
      ).length,
      2,
    );
    expect(readPendingPayments('invalid'), isEmpty);
  });
}

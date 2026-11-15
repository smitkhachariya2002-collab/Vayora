import 'package:flutter_test/flutter_test.dart';
import 'package:vayora/payments/pending_queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('result is stored before reporting and survives a failed report', () async {
    final q = PendingQueue();
    await q.add('o1', 'Status=SUCCESS');
    expect((await q.all()).single.orderId, 'o1');

    final sent = await q.flush((id, raw) async => throw Exception('offline'));
    expect(sent, 0);
    final left = await q.all();
    expect(left.single.attempts, 1);
    expect(left.single.raw, 'Status=SUCCESS');
  });

  test('queue empties once the server answers', () async {
    final q = PendingQueue();
    await q.add('o1', 'Status=SUCCESS');
    await q.add('o2', 'NO_RESPONSE');
    final seen = <String>[];
    final sent = await q.flush((id, raw) async => seen.add(id));
    expect(sent, 2);
    expect(seen, ['o1', 'o2']);
    expect(await q.all(), isEmpty);
  });

  test('same order is not queued twice', () async {
    final q = PendingQueue();
    await q.add('o1', 'a');
    await q.add('o1', 'b');
    final all = await q.all();
    expect(all.length, 1);
    expect(all.single.raw, 'b');
  });

  test('backoff grows and is capped', () {
    expect(PendingQueue.backoff(0) < PendingQueue.backoff(3), isTrue);
    expect(PendingQueue.backoff(50), const Duration(seconds: 300));
  });
}

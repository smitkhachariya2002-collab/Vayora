import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vayora/widgets/ui.dart';

void main() {
  testWidgets('EmptyState shows title, message and action', (t) async {
    var tapped = false;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: EmptyState(icon: Icons.add, title: 'No channels yet', message: 'Start one.', actionLabel: 'Create a channel', onAction: () => tapped = true)),
    ));
    expect(find.text('No channels yet'), findsOneWidget);
    expect(find.text('Start one.'), findsOneWidget);
    await t.tap(find.text('Create a channel'));
    expect(tapped, isTrue);
  });

  testWidgets('PickTile shows optional badge, chosen state and clear button', (t) async {
    var cleared = false;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: PickTile(icon: Icons.image, title: 'Thumbnail', badge: 'OPTIONAL', subtitle: 'cover.jpg', chosen: true, onTap: () {}, onClear: () => cleared = true)),
    ));
    expect(find.text('OPTIONAL'), findsOneWidget);
    expect(find.text('cover.jpg'), findsOneWidget);
    await t.tap(find.byIcon(Icons.close_rounded));
    expect(cleared, isTrue);
  });

  testWidgets('InitialAvatar uses the first letter', (t) async {
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: InitialAvatar(name: 'vayora'))));
    expect(find.text('V'), findsOneWidget);
  });

  test('fmtDuration formats minutes and hours', () {
    expect(fmtDuration(const Duration(seconds: 5)), '0:05');
    expect(fmtDuration(const Duration(minutes: 3, seconds: 7)), '3:07');
    expect(fmtDuration(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
  });
}

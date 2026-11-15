import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vayora/widgets/ui.dart';

void main() {
  for (final width in [320.0, 390.0, 768.0]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('video grid fits $width at text scale $scale', (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var selected = -1;
        await tester.pumpWidget(MaterialApp(home: MediaQuery(
          data: MediaQueryData(size: Size(width, 1000), textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: VideoGrid(itemCount: 8, itemBuilder: (_, i) => VideoCard(
            title: i == 0 ? 'A long video title that should wrap into two lines' : 'Video $i',
            channel: 'A channel with a long name', premium: i == 0, seconds: 120,
            onTap: () => selected = i,
          ))),
        )));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final cards = find.byType(VideoCard);
        expect(tester.getTopLeft(cards.at(0)).dy, tester.getTopLeft(cards.at(1)).dy);
        if (width <= 390) {
          expect(tester.getTopLeft(cards.at(0)).dy, tester.getTopLeft(cards.at(2)).dy);
          expect(tester.getTopLeft(cards.at(3)).dy, greaterThan(tester.getTopLeft(cards.at(0)).dy));
        }
        final posters = find.byType(VideoThumb);
        expect(tester.getSize(posters.at(0)), tester.getSize(posters.at(1)));
        final posterSize = tester.getSize(posters.at(0));
        expect(posterSize.width / posterSize.height, closeTo(2 / 3, .001));
        await tester.tap(cards.at(1));
        expect(selected, 1);
      });
    }
  }
}


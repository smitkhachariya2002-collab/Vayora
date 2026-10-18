import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vayora/screens/new_post.dart';
import 'package:vayora/theme.dart';
import 'account_test.dart' show Fixture, existingId;

const captureParity = bool.fromEnvironment('SCREENSHOTS');
void main() {
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final fonts = FontLoader('Poppins');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      fonts.addFont(rootBundle.load('assets/fonts/Poppins-$w.ttf'));
    }
    await fonts.load();
  });
  for (final width in [360.0, 430.0]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets(
        'New video post at $width / $scale',
        (tester) async {
          tester.view.physicalSize = Size(width, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final f = Fixture();
          await tester.runAsync(f.start);
          await tester.runAsync(
            () => f.state.login('test@example.test', 'password123'),
          );
          late Directory temp;
          late File image;
          await tester.runAsync(() async {
            temp = await Directory.systemTemp.createTemp('vayora-poster-');
            final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
            canvas.drawRect(
              const Rect.fromLTWH(0, 0, 640, 360),
              Paint()
                ..shader = ui.Gradient.linear(
                  const Offset(0, 0),
                  const Offset(640, 360),
                  [const Color(0xFF8A2D05), const Color(0xFFFF7A1A)],
                ),
            );
            canvas.drawCircle(
              const Offset(480, 95),
              45,
              Paint()..color = const Color(0xFFFFC24D),
            );
            canvas.drawPath(
              Path()
                ..moveTo(0, 360)
                ..lineTo(180, 125)
                ..lineTo(320, 300)
                ..lineTo(410, 180)
                ..lineTo(640, 360)
                ..close(),
              Paint()..color = const Color(0xFF2A1408),
            );
            final picture = recorder.endRecording(),
                bitmap = await picture.toImage(640, 360),
                bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
            image = File('${temp.path}/poster.png');
            await image.writeAsBytes(bytes!.buffer.asUint8List());
            bitmap.dispose();
            picture.dispose();
          });
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                const MethodChannel('app/media'),
                (_) async => {
                  'path': image.path,
                  'name': 'India-in-focus.mp4',
                  'mime': 'video/mp4',
                  'size': 12000000,
                  'thumbnail_path': image.path,
                  'duration_s': 222,
                },
              );
          await tester.pumpWidget(
            MaterialApp(
              theme: buildTheme(),
              debugShowCheckedModeBanner: false,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: RepaintBoundary(
                key: const ValueKey('video-post'),
                child: NewPost(
                  state: f.state,
                  channel: const {
                    'id': 'owned',
                    'name': 'India in focus',
                    'created_by': existingId,
                  },
                ),
              ),
            ),
          );
          await tester.runAsync(() async {
            await tester.tap(find.text('Choose video or photo'));
            await Future<void>.delayed(const Duration(milliseconds: 100));
          });
          await tester.runAsync(
            () => precacheImage(
              FileImage(image),
              tester.element(find.byType(NewPost)),
            ),
          );
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byType(TextFormField).first,
            'A journey beyond the familiar',
          );
          await tester.enterText(
            find.byType(TextFormField).last,
            'Stories from every corner of India.',
          );
          FocusManager.instance.primaryFocus?.unfocus();
          tester.testTextInput.hide();
          await tester.pumpAndSettle();
          await tester.tap(find.byType(SwitchListTile));
          await tester.pumpAndSettle();
          final scroll = find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first;
          await tester.drag(scroll, const Offset(0, 160));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(const ValueKey('video-post')),
            matchesGoldenFile(
              'goldens/after/new-post-video-${width.toInt()}-$scale.png',
            ),
          );
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(f.close);
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(const MethodChannel('app/media'), null);
          await tester.runAsync(() => temp.delete(recursive: true));
        },
        skip: !captureParity,
        timeout: const Timeout(Duration(seconds: 45)),
      );
    }
  }
}

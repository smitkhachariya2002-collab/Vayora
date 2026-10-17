import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:vayora/main.dart';
import 'package:vayora/theme.dart';
import 'account_test.dart' show Fixture, existingId;
import 'support/fake_video.dart';

class FailOnceVideo extends ScreenshotVideo {
  int attempts = 0;
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    if (attempts++ == 0) throw PlatformException(code: 'fixture_failure');
    return 1;
  }
}

void main() {
  testWidgets(
    'Player shows a friendly error and Retry recreates the decoder',
    (tester) async {
      final f = Fixture();
      await tester.runAsync(f.start);
      await tester.runAsync(
        () => f.state.login('test@example.test', 'password123'),
      );
      final native = FailOnceVideo();
      VideoPlayerPlatform.instance = native;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('app/screen'),
            (_) async => null,
          );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Watch(
            url: 'https://example.test/fixture.mp4',
            trailer: false,
            isPremium: false,
            state: f.state,
            audience: 'all',
            channelAudience: 'all',
            createdBy: existingId,
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Try again'), findsOneWidget);
      expect(find.textContaining('PlatformException'), findsNothing);
      await tester.tap(find.text('Try again'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(native.attempts, 2);
      expect(find.byTooltip('Pause'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(f.close);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('app/screen'), null);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}

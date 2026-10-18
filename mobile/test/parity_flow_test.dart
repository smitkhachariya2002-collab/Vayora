import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:vayora/main.dart';
import 'package:vayora/theme.dart';
import 'account_test.dart' show Fixture, existingId;
import 'support/fake_video.dart';

class RenewingVideo extends ScreenshotVideo {
  final urls = <String?>[],
      events = <int, StreamController<VideoEvent>>{},
      seeks = <Duration>[];
  int last = 0;
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    urls.add(options.dataSource.uri);
    events[++last] = StreamController<VideoEvent>();
    return last;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) async* {
    yield VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(minutes: 3),
      size: const Size(1920, 1080),
    );
    yield* events[playerId]!.stream;
  }

  @override
  Future<void> seekTo(int playerId, Duration value) async {
    seeks.add(value);
    position = value;
  }

  @override
  Future<void> dispose(int playerId) async {
    await events[playerId]?.close();
  }
}

void main() {
  test(
    'Disabled Google provider gives email guidance before any OAuth launch',
    () async {
      final f = Fixture();
      f.intercept = (r) => r.url.path.endsWith('/settings')
          ? http.Response('{"external":{"google":false}}', 200, request: r)
          : null;
      await f.start();
      await expectLater(
        f.state.google(),
        throwsA(
          predicate(
            (e) => e.toString().contains(
              'Google sign-in is coming soon. Please log in with email.',
            ),
          ),
        ),
      );
      expect(f.calls.where((r) => r.url.path.contains('/authorize')), isEmpty);
      await f.close();
    },
  );
  testWidgets(
    'Player Retry renews signed URL and seeks back to saved position',
    (tester) async {
      final f = Fixture();
      await tester.runAsync(f.start);
      await tester.runAsync(
        () => f.state.login('member@example.test', 'password123'),
      );
      final native = RenewingVideo();
      VideoPlayerPlatform.instance = native;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('app/screen'),
            (_) async => null,
          );
      var renewed = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: Watch(
            url: 'https://example.test/old',
            refreshUrl: () async {
              renewed++;
              return 'https://example.test/new';
            },
            trailer: false,
            isPremium: false,
            state: f.state,
            audience: 'all',
            channelAudience: 'all',
            createdBy: existingId,
          ),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      native.events[native.last]!.addError(
        PlatformException(code: 'expired', message: 'Expired URL'),
      );
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Try again'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(renewed, 1);
      expect(native.urls, [
        'https://example.test/old',
        'https://example.test/new',
      ]);
      expect(native.seeks, contains(const Duration(seconds: 24)));
      expect(find.byTooltip('Pause'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(f.close);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('app/screen'), null);
    },
  );
}

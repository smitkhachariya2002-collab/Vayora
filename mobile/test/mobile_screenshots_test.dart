import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:vayora/main.dart';
// Kept explicit so the same harness also runs against the pre-redesign main library.
// ignore: unnecessary_import
import 'package:vayora/account_page.dart';
import 'account_test.dart' show Fixture, existingId;
import 'capture_theme.dart';
import 'support/fake_video.dart';

const capture = bool.fromEnvironment('SCREENSHOTS');
const before = bool.fromEnvironment('BEFORE');
const channelId = '33333333-3333-4333-8333-333333333333';
final channel = <String, dynamic>{
  'id': channelId,
  'name': 'India in focus',
  'description': 'Stories from every corner of India.',
  'category': 'Travel',
  'tags': ['travel', 'india'],
  'members_count': 1280,
  'audience': 'all',
  'created_by': 'creator',
  'review_status': 'approved',
  'status': 'active',
  'icon_url': null,
  'created_at': '2026-10-01',
};
final post = <String, dynamic>{
  'id': 'post-one',
  'title': 'A journey beyond the familiar',
  'description':
      'Take the scenic route. Discover quieter places, local stories and a different view of India.',
  'created_by': 'creator',
  'channel_id': channelId,
  'channels': channel,
  'view_count': 12480,
  'audience': 'all',
  'created_at': '2026-10-01',
  'post_items': [
    {
      'id': 'item-one',
      'position': 0,
      'is_premium': true,
      'mime': 'video/mp4',
      'thumbnail_key': null,
      'media_key': 'fixture.mp4',
      'trailer_key': 'fixture-trailer.mp4',
      'duration_s': 222,
    },
  ],
};
final order = <String, dynamic>{
  'id': 'order-one',
  'user_id': existingId,
  'reference': 'VAY-DEMO-2026',
  'amount_paise': 9900,
  'status': 'pending',
  'created_at': '2026-10-10T12:00:00Z',
  'plans': {'name': 'Silver'},
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    if (before) {
      final root = Platform.environment['FLUTTER_ROOT'];
      if (root != null) {
        final file = File(
          '$root/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
        );
        if (file.existsSync()) {
          await (FontLoader('Roboto')..addFont(
                Future.value(ByteData.sublistView(file.readAsBytesSync())),
              ))
              .load();
        }
      }
    } else {
      final fonts = FontLoader('Poppins');
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        fonts.addFont(rootBundle.load('assets/fonts/Poppins-$weight.ttf'));
      }
      await fonts.load();
    }
  });
  for (final width in [360.0, 430.0]) {
    for (final scale in [1.0, 1.6]) {
      for (final name in [
        'explore',
        'post',
        'player',
        'premium',
        'payment',
        'cloud',
        'channels',
        'profile',
        'login',
      ]) {
        testWidgets(
          '$name at $width / $scale',
          (tester) async {
            tester.view.physicalSize = Size(width, 900);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final f = Fixture();
            f.intercept = (request) {
              Object? value;
              if (request.url.path.endsWith('/posts')) {
                value = [post];
              } else if (request.url.path.endsWith('/channels')) {
                value = [channel];
              } else if (request.url.path.endsWith('/channel_members')) {
                value = <Object>[];
              } else if (request.url.path.endsWith('/plans')) {
                value = [
                  {
                    'id': 'trial',
                    'name': 'Trial',
                    'price_inr': 49.0,
                    'duration_days': 7,
                    'position': 0,
                    'perks': ['2 TB cloud', 'Full premium videos'],
                  },
                  {
                    'id': 'silver',
                    'name': 'Silver',
                    'price_inr': 129.0,
                    'duration_days': 7,
                    'position': 1,
                    'perks': ['2 TB cloud', 'Full premium videos'],
                  },
                  {
                    'id': 'gold',
                    'name': 'Gold',
                    'price_inr': 259.0,
                    'duration_days': 30,
                    'position': 2,
                    'perks': ['2 TB cloud', 'Full premium videos'],
                  },
                  {
                    'id': 'platinum',
                    'name': 'Platinum',
                    'price_inr': 599.0,
                    'duration_days': 180,
                    'position': 3,
                    'perks': ['2 TB cloud', 'Full premium videos'],
                  },
                  {
                    'id': 'diamond',
                    'name': 'Diamond',
                    'price_inr': 999.0,
                    'duration_days': 365,
                    'position': 4,
                    'perks': ['2 TB cloud', 'Full premium videos'],
                  },
                ];
              } else if (request.url.path.endsWith('/payment_orders')) {
                value = [order];
              } else {
                return null;
              }
              return http.Response(
                jsonEncode(value),
                200,
                request: request,
                headers: {'content-type': 'application/json'},
              );
            };
            await tester.runAsync(f.start);
            await f.state.prefs.setBool('consent_v1', true);
            f.currentStatus = {
              'has_ads_access': true,
              'source': 'ads',
              'quota_bytes': 15 * 1024 * 1024 * 1024,
              'used_bytes': 2 * 1024 * 1024 * 1024,
            };
            if (name != 'login') {
              await tester.runAsync(
                () => f.state.login('test@example.test', 'password123'),
              );
            }
            await tester.runAsync(f.state.refreshStatus);
            VideoPlayerPlatform.instance = ScreenshotVideo();
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
                .setMockMethodCallHandler(
                  const MethodChannel('app/screen'),
                  (_) async => null,
                );
            final Widget page = switch (name) {
              'post' => PostPage(state: f.state, post: post),
              'player' => Watch(
                url: 'https://example.test/fixture.mp4',
                trailer: false,
                isPremium: false,
                state: f.state,
                audience: 'all',
                channelAudience: 'all',
                createdBy: existingId,
              ),
              'premium' => Plans(state: f.state),
              'payment' => paymentScreen(f.state),
              'login' => Login(state: f.state),
              _ => Home(state: f.state),
            };
            await tester.pumpWidget(
              MaterialApp(
                theme: captureTheme(),
                debugShowCheckedModeBanner: false,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    disableAnimations: true,
                  ),
                  child: child!,
                ),
                home: RepaintBoundary(
                  key: const ValueKey('screen'),
                  child: page,
                ),
              ),
            );
            for (var i = 0; i < 8; i++) {
              await tester.pump(const Duration(milliseconds: 100));
            }
            if (['cloud', 'channels', 'profile'].contains(name)) {
              await tester.tap(
                find
                    .descendant(
                      of: find.byType(NavigationBar),
                      matching: find.text(
                        {
                          'cloud': 'Cloud',
                          'channels': 'Channels',
                          'profile': 'Profile',
                        }[name]!,
                      ),
                    )
                    .last,
              );
              for (var i = 0; i < 8; i++) {
                await tester.pump(const Duration(milliseconds: 100));
              }
            }
            final errors = <Object>[];
            Object? error;
            while ((error = tester.takeException()) != null) {
              errors.add(error!);
            }
            if (!before) {
              expect(
                errors,
                isEmpty,
                reason: '$name must fit at $width with text scale $scale',
              );
            }
            await expectLater(
              find.byKey(const ValueKey('screen')),
              matchesGoldenFile(
                'goldens/${before ? 'before' : 'after'}/$name-${width.toInt()}-$scale.png',
              ),
            );
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
            await tester.runAsync(f.close);
          },
          skip: !capture,
          timeout: const Timeout(Duration(seconds: 45)),
        );
      }
    }
  }
}

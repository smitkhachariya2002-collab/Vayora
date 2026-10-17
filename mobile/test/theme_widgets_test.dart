import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vayora/theme.dart';
import 'package:vayora/screens/premium.dart';
import 'package:vayora/widgets/common.dart';
import 'package:vayora/widgets/post_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final fonts = FontLoader('Poppins');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      fonts.addFont(rootBundle.load('assets/fonts/Poppins-$weight.ttf'));
    }
    await fonts.load();
  });
  test('Theme uses the requested palette, font and readable body sizes', () {
    final theme = buildTheme();
    expect(theme.scaffoldBackgroundColor, AppColors.background);
    expect(theme.colorScheme.primary, AppColors.primary);
    expect(theme.textTheme.bodyLarge!.fontFamily, 'Poppins');
    expect(theme.textTheme.bodyLarge!.fontSize, 15);
    expect(theme.textTheme.bodyMedium!.fontSize, 14);
  });
  for (final scale in [1.0, 1.6, 2.0]) {
    testWidgets('Buttons and post card fit 360px at text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var tapped = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: MediaQuery(
            data: MediaQueryData(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: Gap.page,
                  child: Column(
                    children: [
                      GradientButton(
                        label: 'Continue to payment',
                        onPressed: () => tapped++,
                      ),
                      const SizedBox(height: Gap.l),
                      OutlinedButton(
                        onPressed: () => tapped++,
                        child: const Text('Trailer'),
                      ),
                      const SizedBox(height: Gap.l),
                      PostCard(
                        post: const {
                          'title':
                              'A long cinematic title that wraps across two lines without overflowing',
                          'channels': {'name': 'India in focus'},
                          'view_count': 12480,
                          'post_items': [
                            {
                              'position': 0,
                              'is_premium': true,
                              'duration_s': 222,
                            },
                          ],
                        },
                        onTap: () => tapped++,
                      ),
                      const CrownButton(visible: false, onPressed: noop),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Continue to payment'));
      expect(tapped, 1);
      await tester.tap(find.text('Trailer'));
      expect(tapped, 2);
      await tester.ensureVisible(find.byType(PostCard));
      await tester.tap(find.byType(PostCard));
      expect(tapped, 3);
      expect(find.text('Premium'), findsOneWidget);
      expect(find.byTooltip('Get Premium'), findsNothing);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('SCREENSHOTS')) {
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/after/components-$scale.png'),
        );
      }
    });
  }
  test('Plan labels retain exact prices and readable durations', () {
    expect(planPrice(999.0), '₹999');
    expect(planPrice(49.5), '₹49.50');
    expect(planDuration(7), '7 Days');
    expect(planDuration(30), '1 Month');
    expect(planDuration(180), '6 Months');
    expect(planDuration(365), '1 Year');
  });
  for (final scale in [1.0, 1.6]) {
    testWidgets('Compact plans show benefits once and preserve selection at $scale', (tester) async {
      tester.view.physicalSize = const Size(360, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final plans = [
        {'name':'Trial','price_inr':49.0,'duration_days':7,'perks':['Do not repeat this']},
        {'name':'Silver','price_inr':129.0,'duration_days':7,'perks':['Do not repeat this']},
        {'name':'Gold','price_inr':259.0,'duration_days':30,'perks':['Do not repeat this']},
        {'name':'Platinum','price_inr':599.0,'duration_days':180,'perks':['Do not repeat this']},
        {'name':'Diamond','price_inr':999.0,'duration_days':365,'perks':['Do not repeat this']},
      ];
      var selected = 'Trial';
      await tester.pumpWidget(MaterialApp(theme:buildTheme(),home:MediaQuery(
        data:MediaQueryData(textScaler:TextScaler.linear(scale)),
        child:Scaffold(body:StatefulBuilder(builder:(context,update)=>SingleChildScrollView(
          child:Padding(padding:Gap.page,child:Column(children:[
            const PremiumHero(),
            for(final plan in plans)Padding(padding:const EdgeInsets.only(top:Gap.m),
              child:PlanCard(plan:plan,selected:plan['name']==selected,onTap:()=>update(()=>selected=plan['name'] as String))),
          ])),
        ))),
      )));
      expect(find.text('2 TB cloud allowance'),findsOneWidget);
      expect(find.text('Full premium videos'),findsOneWidget);
      expect(find.text('Do not repeat this'),findsNothing);
      expect(find.text('₹999'),findsOneWidget);
      expect(find.text('₹999.0'),findsNothing);
      await tester.ensureVisible(find.text('Gold'));
      await tester.tap(find.text('Gold'));
      await tester.pumpAndSettle();
      expect(selected,'Gold');
      expect(find.byIcon(Icons.radio_button_checked),findsOneWidget);
      expect(tester.takeException(),isNull);
    });
  }

}

void noop() {}

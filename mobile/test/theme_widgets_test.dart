import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vayora/theme.dart';
import 'package:vayora/widgets/common.dart';
import 'package:vayora/widgets/post_card.dart';

void main(){
  test('Theme uses the requested palette, font and readable body sizes',(){
    final theme=buildTheme();
    expect(theme.scaffoldBackgroundColor,AppColors.background);
    expect(theme.colorScheme.primary,AppColors.primary);
    expect(theme.textTheme.bodyLarge!.fontFamily,'Poppins');
    expect(theme.textTheme.bodyLarge!.fontSize,15);
    expect(theme.textTheme.bodyMedium!.fontSize,14);
  });
  for(final scale in [1.0,1.6,2.0]){
    testWidgets('Buttons and post card fit 360px at text scale $scale',(tester)async{
      tester.view.physicalSize=const Size(360,900);tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
      var tapped=0;
      await tester.pumpWidget(MaterialApp(theme:buildTheme(),home:MediaQuery(
        data:MediaQueryData(textScaler:TextScaler.linear(scale),disableAnimations:true),
        child:Scaffold(body:SingleChildScrollView(child:Padding(padding:Gap.page,child:Column(children:[
          GradientButton(label:'Continue to payment',onPressed:()=>tapped++),
          const SizedBox(height:Gap.l),
          OutlinedButton(onPressed:()=>tapped++,child:const Text('Trailer')),
          const SizedBox(height:Gap.l),
          PostCard(post:const{'title':'A long cinematic title that wraps across two lines without overflowing',
            'channels':{'name':'India in focus'},'view_count':12480,
            'post_items':[{'position':0,'is_premium':true,'duration_s':222}]},onTap:()=>tapped++),
          const CrownButton(visible:false,onPressed:noop),
        ])))))));
      await tester.pump();
      await tester.tap(find.text('Continue to payment'));expect(tapped,1);
      await tester.tap(find.text('Trailer'));expect(tapped,2);
      expect(find.text('Premium'),findsOneWidget);
      expect(find.byTooltip('Get Premium'),findsNothing);
      expect(tester.takeException(),isNull);
      if(const bool.fromEnvironment('SCREENSHOTS'))await expectLater(find.byType(Scaffold),
        matchesGoldenFile('goldens/after/components-$scale.png'));
    });
  }
}
void noop(){}

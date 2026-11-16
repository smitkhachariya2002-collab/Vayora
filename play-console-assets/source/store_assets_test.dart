import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vayora/theme.dart';
import 'package:vayora/models/status.dart';
import 'package:vayora/services/app_state.dart';
import 'package:vayora/services/app_scope.dart';
import 'package:vayora/screens/plans_page.dart';
import 'package:vayora/screens/profile_screen.dart';
import 'package:vayora/screens/cloud_screen.dart';
import 'package:vayora/widgets/vayora_nav_bar.dart';

void main(){
 testWidgets('Capture current app widgets and create vector store artwork',(t) async {
  GoogleFonts.config.allowRuntimeFetching=false;
  await t.runAsync(() async {
   await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
   await (FontLoader('Inter')..addFont(rootBundle.load('assets/storefonts/Inter-Regular.ttf'))).load();
  });
  t.view.physicalSize=const Size(1080,1920);t.view.devicePixelRatio=3;
  addTearDown(t.view.resetPhysicalSize);addTearDown(t.view.resetDevicePixelRatio);
  final state=AppState()..loaded=true..status=AppStatus({'is_guest':false,'source':'organic','is_premium':true,'plan_name':'Gold','plan_ends_at':'2026-12-16T00:00:00Z','plans_visible':true,'payments_available':true,'quota_bytes':2199023255552,'used_bytes':0,'has_ads_access':true});
  const items=[NavItem(Icons.cloud_outlined,'Cloud'),NavItem(Icons.home_outlined,'Home'),NavItem(Icons.explore_outlined,'Explore'),NavItem(Icons.groups_outlined,'Channel'),NavItem(Icons.person_outline,'Profile')];
  Future<void> capture(String name,Widget child,int tab) async {
   await t.pumpWidget(AppScope(state:state,child:MaterialApp(theme:buildTheme(),home:RepaintBoundary(key:const Key('capture'),child:Scaffold(body:SafeArea(child:child),bottomNavigationBar:VayoraNavBar(items:items,index:tab,onTap:(_){}))))));
   await t.pumpAndSettle();
   final boundary=t.renderObject<RenderRepaintBoundary>(find.byKey(const Key('capture')));
   await t.runAsync(() async {
    final image=await boundary.toImage(pixelRatio:3);final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
    File('../play-console-assets/phone-screenshots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());image.dispose();
   });
  }
  await capture('01-plans',PlansPage(onBuy:(_)async{},plansLoader:()async=>[
   {'id':'trial','name':'Trial','price_inr':1,'duration_days':1},
   {'id':'silver','name':'Silver','price_inr':129,'duration_days':7},
   {'id':'gold','name':'Gold','price_inr':259,'duration_days':30,'badge':'Popular'},
   {'id':'platinum','name':'Platinum','price_inr':599,'duration_days':180},
   {'id':'diamond','name':'Diamond','price_inr':999,'duration_days':365},
  ]),4);
  await capture('02-cloud',const CloudScreen(),0);
  await capture('03-account',const AccountView(),4);
  await t.pumpWidget(const SizedBox());state.dispose();
  await t.runAsync(()async{
   final out=Directory('../play-console-assets');out.createSync(recursive:true);
   Future<void> artwork(String name,int w,int h,bool feature)async{
    final rec=ui.PictureRecorder();final c=Canvas(rec);final bounds=Rect.fromLTWH(0,0,w.toDouble(),h.toDouble());
    c.drawRect(bounds,Paint()..shader=const LinearGradient(colors:[Color(0xFF090F1E),Color(0xFF173A77)]).createShader(bounds));
    c.drawCircle(Offset(w*.85,h*.2),h*.6,Paint()..color=const Color(0xFF3478F6).withValues(alpha:.15));
    c.save();c.translate(feature?75:95,feature?125:100);final scale=feature?2.3:3.0;c.scale(scale);
    final white=Paint()..color=Colors.white;
    c.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(12,34,80,39),const Radius.circular(20)),white);
    c.drawCircle(const Offset(45,36),24,white);c.drawCircle(const Offset(68,43),20,white);
    c.drawPath(Path()..moveTo(43,31)..lineTo(43,62)..lineTo(68,46.5)..close(),Paint()..color=const Color(0xFF245ED1));c.restore();
    if(feature){
     final text=TextPainter(text:const TextSpan(text:'Vayora',style:TextStyle(fontFamily:'Inter',fontSize:82,fontWeight:FontWeight.w700,color:Colors.white)),textDirection:TextDirection.ltr)..layout();text.paint(c,const Offset(365,150));
     final sub=TextPainter(text:const TextSpan(text:'Your cloud. Your channels.',style:TextStyle(fontFamily:'Inter',fontSize:27,color:Color(0xFFAFC0D9))),textDirection:TextDirection.ltr)..layout();sub.paint(c,const Offset(370,260));
    }
    final img=await rec.endRecording().toImage(w,h);final bytes=await img.toByteData(format:ui.ImageByteFormat.png);File('${out.path}/$name').writeAsBytesSync(bytes!.buffer.asUint8List());img.dispose();
   }
   await artwork('icon-512.png',512,512,false);await artwork('feature-1024x500.png',1024,500,true);
  });
 });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:vayora/app_state.dart';
import 'package:vayora/theme.dart';
import 'package:vayora/screens/home.dart';
import 'package:vayora/screens/post.dart';
import 'package:vayora/screens/player.dart';
import 'package:vayora/screens/channel_detail.dart';
import 'account_test.dart' show Fixture, existingId;
import 'support/fake_video.dart';

const storeCapture = bool.fromEnvironment('STORE_SCREENSHOTS');
final artRoot = Directory('../docs/store/source-art');
final rawRoot = Directory('../docs/store/raw');

Map<String,dynamic> demoChannel(int index) => {
  'id':'33333333-3333-4333-8333-${(index+1).toString().padLeft(12,'0')}',
  'name':['Nature trails','Kitchen stories','Quiet melodies','Weekend journeys'][index],
  'description':['Fresh air, quiet trails and a little wonder.','Simple recipes and everyday inspiration.','Original melodies for slower moments.','A new view around every corner.'][index],
  'category':['Nature','Cooking','Music','Travel'][index],
  'tags':[['nature','outdoors'],['cooking'],['music'],['travel']][index],
  'members_count':[128,84,96,112][index],
  'audience':'all','created_by':'demo-creator',
  'review_status':'approved','status':'published','icon_url':null,
  'created_at':'2026-10-01T10:00:00Z',
};
Map<String,dynamic> demoPost(int index) => {
  'id':'44444444-4444-4444-8444-${(index+1).toString().padLeft(12,'0')}',
  'title':['A morning in the mountains','Cooking with the seasons','Notes for a quiet afternoon','Take the scenic route'][index],
  'description':['Follow a quiet trail through the hills. A little nature, a slower pace, and room to explore.','A simple bowl of seasonal goodness, made with care.','An original melody inspired by a gentle afternoon.','Find a different view around the next bend.'][index],
  'created_by':'demo-creator','channel_id':demoChannel(index)['id'],
  'channels':demoChannel(index),'view_count':[240,180,160,210][index],
  'audience':'all','created_at':'2026-10-01T10:00:00Z',
  'post_items':[{'id':'demo-item-$index','position':0,'is_premium':false,
    'mime':'video/mp4','thumbnail_key':'store/art-$index.png',
    'media_key':'demo/nature.mp4','trailer_key':'demo/trailer.mp4','duration_s':222}],
};

/// Original artwork only; REST calls use Fixture's MockClient, never production.
class ArtClient extends Fake implements HttpClient {
  @override set autoUncompress(bool value){}
  @override Future<HttpClientRequest> getUrl(Uri url) async {
    final match=RegExp(r'art-(\d)').firstMatch(url.path);
    final index=match?.group(1)??'0';
    return ArtRequest(File('${artRoot.path}/art-$index.png').readAsBytesSync());
  }
  @override void close({bool force=false}){}
}
class ArtHeaders extends Fake implements HttpHeaders {
  @override void add(String name,Object value,{bool preserveHeaderCase=false}){}
  @override void set(String name,Object value,{bool preserveHeaderCase=false}){}
  @override List<String>? operator [](String name)=>name.toLowerCase()=='content-type'?['image/png']:null;
}
class ArtRequest extends Fake implements HttpClientRequest {
  ArtRequest(this.bytes);
  final Uint8List bytes;
  @override HttpHeaders get headers=>ArtHeaders();
  @override Future<HttpClientResponse> close() async=>ArtResponse(bytes);
}
class ArtResponse extends Stream<List<int>> implements HttpClientResponse {
  ArtResponse(this.bytes);
  final Uint8List bytes;
  @override int get statusCode=>200;
  @override int get contentLength=>bytes.length;
  @override HttpHeaders get headers=>ArtHeaders();
  @override HttpClientResponseCompressionState get compressionState=>HttpClientResponseCompressionState.notCompressed;
  @override StreamSubscription<List<int>> listen(void Function(List<int>)? onData,{Function? onError,void Function()? onDone,bool? cancelOnError})=>Stream<List<int>>.value(bytes).listen(onData,onError:onError,onDone:onDone,cancelOnError:cancelOnError);
  @override dynamic noSuchMethod(Invocation invocation)=>super.noSuchMethod(invocation);
}
/// Only the native decoder surface is replaced with an original landscape still.
/// Watch and all player controls are the unmodified production Flutter widgets.
class StoreVideo extends ScreenshotVideo {
  @override Widget buildViewWithOptions(VideoViewOptions options)=>Image.memory(
    File('${artRoot.path}/art-0.png').readAsBytesSync(),fit:BoxFit.cover);
}
Future<void> settle(WidgetTester tester) async {
  for(var i=0;i<12;i++){
    await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:30)));
    await tester.pump(const Duration(milliseconds:100));
  }
}
void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final fonts=FontLoader('Poppins');
    for(final weight in ['Regular','Medium','SemiBold','Bold']){
      fonts.addFont(rootBundle.load('assets/fonts/Poppins-$weight.ttf'));
    }
    await fonts.load();
    rawRoot.createSync(recursive:true);
  });
  final devices=<String,(Size,double)>{
    'phone':(const Size(1080,1920),3),
    'tablet7':(const Size(1200,1920),2),
    'tablet10':(const Size(1600,2560),2),
  };
  for(final device in devices.entries){
    final names=device.key=='phone'?['explore','post','player','channels','cloud','menu','profile']:['explore','post','cloud','channels'];
    for(final name in names){
      testWidgets('Play store ${device.key} $name',(tester) async {
        expect(playStore,isTrue,reason:'Capture must compile with PLAY_STORE=true');
        tester.view.physicalSize=device.value.$1;
        tester.view.devicePixelRatio=device.value.$2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await HttpOverrides.runZoned(() async {
          final f=Fixture();
          f.intercept=(request){
            Object? data;
            final path=request.url.path;
            if(path.endsWith('/token')||path.endsWith('/user')){
              f.anonymous=false;f.id=existingId;
              final user=f.user()..['email']='';
              data=path.endsWith('/token')?(f.session()..['user']=user):user;
            }else if(path.endsWith('/channels')){
              data=request.url.queryParameters.containsKey('created_by')?[]:List.generate(4,demoChannel);
            }else if(path.endsWith('/posts')||path.endsWith('/search_posts')){
              data=List.generate(4,demoPost);
            }else if(path.endsWith('/channel_members')){
              data=[];
            }else if(path.endsWith('/cloud_files')){
              data=[
                {'id':'folder','name':'Nature collection','is_folder':true,'parent_id':null,'ready':true,'deleting':false},
                {'id':'video','name':'Mountain morning.mp4','is_folder':false,'parent_id':null,'mime':'video/mp4','size':12400000,'ready':true,'deleting':false,'storage_key':'demo/video'},
                {'id':'photo','name':'Quiet valley.jpg','is_folder':false,'parent_id':null,'mime':'image/jpeg','size':2450000,'ready':true,'deleting':false,'storage_key':'demo/photo'},
              ];
            }else if(path.endsWith('/increment_view')){
              data=240;
            }else if(path.endsWith('/plans')||path.endsWith('/payment_orders')){
              throw StateError('Store capture must never request payment data');
            }else{return null;}
            return http.Response(jsonEncode(data),200,request:request,headers:{'content-type':'application/json'});
          };
          await tester.runAsync(f.start);
          await f.state.prefs.setBool('consent_v1',true);
          f.currentStatus={
            'is_guest':false,'source':'organic','free_mode':true,
            'play_verified':true,'play_billing_enabled':false,
            'has_ads_access':true,'is_premium':true,'display_name':'Vayora Explorer',
            'plan_name':null,'quota_bytes':15*1024*1024*1024,'used_bytes':512*1024*1024,
          };
          await tester.runAsync(()=>f.state.login('demo@vayora.invalid','fixture-only'));
          expect(f.state.paidEnabled,isFalse);
          VideoPlayerPlatform.instance=StoreVideo();
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('app/screen'),(_)async=>null);
          final Widget page=switch(name){
            'post'=>PostPage(state:f.state,post:demoPost(0)),
            'player'=>Watch(url:'https://demo.invalid/nature.mp4',title:'A morning in the mountains',trailer:false,isPremium:false,state:f.state,audience:'all',channelAudience:'all',createdBy:'demo-creator'),
            'menu'=>ChannelDetail(state:f.state,channel:demoChannel(0)),
            _=>Home(state:f.state),
          };
          await tester.pumpWidget(RepaintBoundary(key:const ValueKey('store-screen'),child:MaterialApp(
            theme:buildTheme(),debugShowCheckedModeBanner:false,
            builder:(context,child)=>MediaQuery(data:MediaQuery.of(context).copyWith(disableAnimations:true,textScaler:TextScaler.noScaling),child:child!),
            home:page)));
          await settle(tester);
          if(['cloud','channels','profile'].contains(name)){
            await tester.tap(find.descendant(of:find.byType(NavigationBar),matching:find.text({'cloud':'Cloud','channels':'Channels','profile':'Profile'}[name]!)).last);
            await settle(tester);
          }
          if(name=='menu'){
            await tester.tap(find.byTooltip('Channel options'));
            await tester.pumpAndSettle();
            expect(find.text('Report'),findsOneWidget);
            expect(find.text('Block'),findsOneWidget);
          }
          if(name=='post'){expect(find.text('Play'),findsOneWidget);expect(find.text('Trailer'),findsOneWidget);}
          if(name=='cloud'){expect(find.textContaining('15 GB'),findsWidgets);}
          expect(find.textContaining('Lorem ipsum'),findsNothing);
          for(final forbidden in ['UPI','₹','Payment history','Explore Premium','Choose your plan','Buy','Continue to payment']){
            expect(find.textContaining(forbidden),findsNothing,reason:'Forbidden store content: $forbidden');
          }
          expect(tester.takeException(),isNull);
          final boundary=tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('store-screen')));
          final image=await boundary.toImage(pixelRatio:device.value.$2);
          expect(image.width,device.value.$1.width.toInt());
          expect(image.height,device.value.$1.height.toInt());
          final bytes=await image.toByteData(format:ui.ImageByteFormat.png);
          await tester.runAsync(()=>File('${rawRoot.path}/${device.key}-$name.png').writeAsBytes(bytes!.buffer.asUint8List()));
          image.dispose();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await tester.runAsync(f.close);
        },createHttpClient:(_)=>ArtClient());
      },skip:!storeCapture,timeout:const Timeout(Duration(minutes:2)));
    }
  }
}

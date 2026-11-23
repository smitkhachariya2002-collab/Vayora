import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config.dart';
import '../screens/channel_page.dart';
import '../screens/post_page.dart';
import '../screens/premium_screen.dart';
import 'app_state.dart';

class PushNotifications {
 static final instance=PushNotifications();
 static final navigator=GlobalKey<NavigatorState>();
 final _local=FlutterLocalNotificationsPlugin();
 bool _ready=false,_starting=false;
 String? _lastToken;
 StreamSubscription<String>? _tokens;
 StreamSubscription<RemoteMessage>? _foreground,_opened;
 Map<String,dynamic>? _pending;
 Future<void> dispose() async {await _tokens?.cancel();await _foreground?.cancel();await _opened?.cancel();_ready=false;}
 Future<void> requestPermission() async {
  try {await Permission.notification.request();}catch(_){/* Permission API may be unavailable on this platform. */}
  await start();
 }
 Future<void> start() async {
  if(_starting||_ready||sb.auth.currentUser==null)return;
  final prefs=await SharedPreferences.getInstance();
  if(prefs.getBool(Config.consentPrefKey)!=true)return;
  _starting=true;
  try {
   final config=await sb.from('integration_public_config').select('firebase_options').eq('id',1).maybeSingle();
   final raw=config?['firebase_options'];
   final package=(await PackageInfo.fromPlatform()).packageName;
   final options=raw is Map ? raw[package] : null;
   if(options is! Map||options['apiKey']==null||options['appId']==null||options['projectId']==null||options['messagingSenderId']==null)return;
   if(!await Permission.notification.isGranted)return;
   await const MethodChannel('app/integrations').invokeMethod('configure-firebase',Map<String,dynamic>.from(options));
   if(Firebase.apps.isEmpty)await Firebase.initializeApp(options:FirebaseOptions(apiKey:options['apiKey'],appId:options['appId'],messagingSenderId:options['messagingSenderId'],projectId:options['projectId'],storageBucket:options['storageBucket']));
   await _local.initialize(settings:const InitializationSettings(android:AndroidInitializationSettings('@mipmap/ic_launcher')),onDidReceiveNotificationResponse:(response){if(response.payload!=null){try{_navigate(Map<String,dynamic>.from(jsonDecode(response.payload!) as Map));}catch(_){}}});
   await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(const AndroidNotificationChannel('new_releases_offers','New releases & offers',description:'New videos, account updates and offers',importance:Importance.high));
   _tokens=FirebaseMessaging.instance.onRegistered.listen((token){_lastToken=token;unawaited(_register(token).catchError((Object _){}));});
   await FirebaseMessaging.instance.register();
   _foreground=FirebaseMessaging.onMessage.listen((message){
    final notification=message.notification;
    unawaited(_local.show(id:message.messageId?.hashCode??DateTime.now().millisecondsSinceEpoch.remainder(2147483647),title:notification?.title??message.data['title'],body:notification?.body??message.data['body'],notificationDetails:const NotificationDetails(android:AndroidNotificationDetails('new_releases_offers','New releases & offers',importance:Importance.high,priority:Priority.high)),payload:jsonEncode(message.data)));
   });
   _opened=FirebaseMessaging.onMessageOpenedApp.listen((message)=>_navigate(message.data));
   final initial=await FirebaseMessaging.instance.getInitialMessage();if(initial!=null)_navigate(initial.data);
   _ready=true;
  }catch(_){/* Deferred configuration or transient failure must not block the app. */}
  finally{_starting=false;}
 }
 Future<void> _register(String token) async {
  final p=await SharedPreferences.getInstance(),id=p.getString('install_id');if(id==null)return;
  await sb.rpc('register_push_token_v2',params:{'p_token':token,'p_install_id':id,'p_allowed':await Permission.notification.isGranted,'p_secret':p.getString('install_secret')??''});
 }
 Future<void> refreshRegistration() async {
  if(!_ready){await start();return;}
  try{if(_lastToken!=null){await _register(_lastToken!);}else{await FirebaseMessaging.instance.register();}}catch(_){}
 }
 void drainPending(){final value=_pending;if(value!=null){_pending=null;_navigate(value);}}
 void _navigate(Map<String,dynamic> data) {
  final nav=navigator.currentState;if(nav==null){_pending=data;return;}
  final delivery=data['delivery_id'];if(delivery is String)unawaited(sb.rpc('record_push_tap',params:{'p_delivery':delivery}).then((_){}).catchError((Object _){}));
  final type=data['type'],id=data['id'];
  if(type=='video'&&id is String&&RegExp(r'^[0-9a-f-]{36}$').hasMatch(id)){nav.push(MaterialPageRoute(builder:(_)=>PostPage(postId:id)));}
  else if(type=='channel'&&id is String&&RegExp(r'^[0-9a-f-]{36}$').hasMatch(id)){nav.push(MaterialPageRoute(builder:(_)=>ChannelPage(channelId:id)));}
  else if(type=='premium'){nav.push(MaterialPageRoute(builder:(_)=>const PremiumScreen()));}
  else if(type=='link'&&data['url'] is String){final url=Uri.tryParse(data['url']);if(url?.scheme=='https'&&url!.userInfo.isEmpty)unawaited(launchUrl(url,mode:LaunchMode.externalApplication));}
 }
}

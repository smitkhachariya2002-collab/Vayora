import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../config.dart';

/// Optional measurement only. Keys, prices and purchase authority stay on the server.
class Measurement extends ChangeNotifier {
  static final instance=Measurement();
  final _uuid=const Uuid();
  SupabaseClient get _sb=>Supabase.instance.client;
  bool analytics=false, advertising=false, ready=false, hasChoice=false;
  String? _uid;
  String _session=const Uuid().v4();
  DateTime _lastActive=DateTime.now();
  bool _busy=false;
  Future<void> _writing=Future.value();
  Future<void> _serial(Future<void> Function() f) {final next=_writing.then((_)=>f());_writing=next.catchError((Object _){});return next;}
  Future<void> start() async {
    final prefs=await SharedPreferences.getInstance();
    if(prefs.getBool(Config.consentPrefKey)!=true){ready=false;analytics=false;advertising=false;hasChoice=false;return;}
    final uid=_sb.auth.currentUser?.id;
    if(uid==null)return;
    if(_uid!=uid){_uid=uid;ready=false;analytics=false;advertising=false;hasChoice=false;
      final p=await SharedPreferences.getInstance();
      hasChoice=p.containsKey('measurement_choice_$uid');
      if(hasChoice){final v=jsonDecode(p.getString('measurement_choice_$uid')!) as Map;analytics=v['analytics']==true;advertising=v['advertising']==true;}
      // A server revocation wins over a stale device preference.
      try{final row=await _sb.from('measurement_preferences').select('analytics,advertising').eq('user_id',uid).maybeSingle();
        if(row!=null){analytics=row['analytics']==true;advertising=row['advertising']==true;hasChoice=true;}}catch(_){}
    }
    final pending=prefs.getString('measurement_pending_choice');
    if(pending!=null){final v=jsonDecode(pending) as Map;analytics=v['analytics']==true;advertising=v['advertising']==true;hasChoice=true;}
    try{
      await _sb.rpc('accept_app_consent',params:{'p_policy':Config.consentPolicy});
      await _sync();
      if(pending!=null){await prefs.setString('measurement_choice_$uid',pending);await prefs.remove('measurement_pending_choice');}
    }catch(_){ready=false;notifyListeners();return;}
    ready=true;notifyListeners();await track('AppOpen');unawaited(flush());
  }
  Future<Map<String,dynamic>> _context() async{
    if(!advertising)return {};
    final p=await SharedPreferences.getInstance();
    final id=p.getString('install_id')??_uuid.v4();await p.setString('install_id',id);
    final native=await const MethodChannel('app/measurement').invokeMapMethod<String,dynamic>('context')??{};
    final view=PlatformDispatcher.instance.views.first;
    return {'install_id':id,'extinfo':['a2',Config.authScheme,'17',Config.versionLabel,
      '${native['os']??''}','${native['model']??''}',PlatformDispatcher.instance.locale.toLanguageTag(),DateTime.now().timeZoneName,'',
      view.physicalSize.width.round().toString(),view.physicalSize.height.round().toString(),view.devicePixelRatio.toString(),'${native['cores']??''}','','','']};
  }
  Future<void> _sync() async {await _sb.rpc('set_measurement_preferences',params:{'p_analytics':analytics,'p_advertising':advertising,'p_context':await _context()});}
  Future<void> save(bool usage,bool ads) async{
    final oldA=analytics,oldD=advertising;analytics=usage;advertising=ads;
    try{await _sync();}catch(_){analytics=oldA;advertising=oldD;rethrow;}
    ready=true;hasChoice=true;final uid=_sb.auth.currentUser!.id;
    final p=await SharedPreferences.getInstance();
    await p.setString('measurement_choice_$uid',jsonEncode({'analytics':usage,'advertising':ads}));
    if(!usage&&!ads)await _serial(()async{await p.remove('measurement_queue');});
    notifyListeners();if(usage||ads){await track('AppOpen');unawaited(flush());}
  }
  Future<void> saveInitialChoice(bool usage,bool ads) async {
    final p=await SharedPreferences.getInstance();
    await p.setString('measurement_pending_choice',jsonEncode({'analytics':usage,'advertising':ads,'policy':Config.consentPolicy,'accepted_at':DateTime.now().toUtc().toIso8601String()}));
    await p.setBool(Config.consentPrefKey,true);
    try{await start();}catch(_){/* Saved locally; sync after the session is available. */}
  }
  Future<void> resumed() async{
    if(DateTime.now().difference(_lastActive)>const Duration(minutes:30))_session=_uuid.v4();
    _lastActive=DateTime.now();await track('AppOpen');unawaited(flush());
  }
  Future<void> track(String name,[Map<String,dynamic> properties=const {}]) async{
    if(!ready||_uid!=_sb.auth.currentUser?.id)return;
    // Registration is measured by the server.
    if(name=='CompleteRegistration')return;
    if(!analytics&&!advertising)return;
    final event={'uid':_uid,'p_event_id':_uuid.v4(),'p_name':name,'p_session_id':_session,'p_properties':properties,'p_occurred_at':DateTime.now().toUtc().toIso8601String()};
    await _serial(()async{final p=await SharedPreferences.getInstance();final rows=_read(p)..add(event);if(rows.length>200)rows.removeRange(0,rows.length-200);await p.setString('measurement_queue',jsonEncode(rows));});
    unawaited(flush());
  }
  List<Map<String,dynamic>> _read(SharedPreferences p){try{return (jsonDecode(p.getString('measurement_queue')??'[]') as List).map((x)=>Map<String,dynamic>.from(x as Map)).where((x)=>DateTime.tryParse(x['p_occurred_at'] as String? ??'')?.isAfter(DateTime.now().subtract(const Duration(days:1)))??false).toList();}catch(_){return [];}}
  Future<void> flush() async{
    if(_busy||!ready||(!analytics&&!advertising))return;_busy=true;
    try{
      for(var i=0;i<200;i++){
        final p=await SharedPreferences.getInstance();Map<String,dynamic>? row;
        await _serial(()async{final rows=_read(p);if(rows.isNotEmpty)row=rows.first;});
        if(row==null)break;
        if(row!['uid']==_sb.auth.currentUser?.id){final params=Map<String,dynamic>.from(row!)..remove('uid');await _sb.rpc('record_activity',params:params);}
        await _serial(()async{final rows=_read(p)..removeWhere((x)=>x['p_event_id']==row!['p_event_id']);await p.setString('measurement_queue',jsonEncode(rows));});
        if(!analytics&&!advertising)break;
      }
    }catch(_){/* Best-effort bounded retry, never blocks app use or payments. */}
    finally{_busy=false;}
  }
}


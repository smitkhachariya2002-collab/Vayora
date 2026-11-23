import 'dart:io';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_state.dart';

class BunnyMedia {
 static Future<String?> playback(String itemId,{bool thumbnail=false,bool preview=false}) async {
  final r=await sb.functions.invoke('bunny-stream-url',body:{'item_id':itemId,'thumbnail':thumbnail,'preview':preview});
  return (r.data as Map)['url'] as String?;
 }
 static Future<bool> upload(String itemId,File file,{String slot='main',void Function(double)? progress}) async {
  dynamic body;
  try {body=(await sb.functions.invoke('bunny-stream-create',body:{'item_id':itemId,'slot':slot,'title':file.uri.pathSegments.last,'size':await file.length()})).data;}
  on FunctionException catch(e) {if(e.status==503&&e.details is Map&&(e.details as Map)['code']=='NOT_CONFIGURED')return false;rethrow;}
  final data=Map<String,dynamic>.from(body as Map);
  if(data['completed']==true){progress?.call(1);return true;}
  final headers=Map<String,String>.from(data['headers'] as Map)..['Tus-Resumable']='1.0.0';
  final client=HttpClient()..connectionTimeout=const Duration(seconds:30);
  try {
   final length=await file.length();
   final prefs=await SharedPreferences.getInstance();
   final key='bunny_tus_${itemId}_${slot}_${length}_${(await file.lastModified()).millisecondsSinceEpoch}';
   final endpoint=Uri.parse(data['endpoint'] as String);
   Uri? location;
   var offset=0;
   final saved=prefs.getString(key);
   if(saved!=null) {
    final candidate=Uri.parse(saved);
    if(candidate.scheme=='https'&&candidate.host=='video.bunnycdn.com'&&candidate.path.startsWith('/tusupload')) {
     final head=await client.openUrl('HEAD',candidate);headers.forEach(head.headers.set);final reply=await head.close().timeout(const Duration(seconds:30));
     final n=int.tryParse(reply.headers.value('upload-offset')??'');await reply.drain<void>();
     if([200,204].contains(reply.statusCode)&&n!=null&&n>=0&&n<=length){location=candidate;offset=n;}
    }
   }
   if(location==null) {
    final request=await client.postUrl(endpoint);headers.forEach(request.headers.set);
    request.headers.set('Upload-Length','$length');request.headers.set('Upload-Metadata','filetype ${base64Encode(utf8.encode('video/mp4'))},title ${base64Encode(utf8.encode(file.uri.pathSegments.last))}');
    final response=await request.close().timeout(const Duration(minutes:2));final target=response.headers.value('location');await response.drain<void>();
    if(response.statusCode!=201||target==null)throw Exception('Could not start video upload');
    location=endpoint.resolve(target);
    if(location.scheme!='https'||location.host!='video.bunnycdn.com'||!location.path.startsWith('/tusupload'))throw Exception('Invalid upload destination');
    await prefs.setString(key,location.toString());
   }
   var retries=0;

   while(offset<length) {
    final end=(offset+32*1024*1024).clamp(0,length);
    try {
     final patch=await client.openUrl('PATCH',location);headers.forEach(patch.headers.set);
     patch.headers.set('Upload-Offset','$offset');patch.headers.set('Content-Type','application/offset+octet-stream');patch.contentLength=end-offset;
     var sent=0;await patch.addStream(file.openRead(offset,end).map((chunk){sent+=chunk.length;progress?.call((offset+sent)/length);return chunk;}));
     final reply=await patch.close().timeout(const Duration(minutes:3));final next=int.tryParse(reply.headers.value('upload-offset')??'');await reply.drain<void>();
     if(reply.statusCode!=204||next!=end)throw Exception('Upload interrupted');offset=end;retries=0;
    }catch(_) {
     if(++retries>3)rethrow;await Future<void>.delayed(Duration(seconds:1<<retries));
     final head=await client.openUrl('HEAD',location);headers.forEach(head.headers.set);final reply=await head.close();final next=int.tryParse(reply.headers.value('upload-offset')??'');await reply.drain<void>();
     if(reply.statusCode!=200&&reply.statusCode!=204||next==null||next<offset||next>length)rethrow;offset=next;
    }
   }
   return true;
  } finally {client.close(force:true);}
 }
}

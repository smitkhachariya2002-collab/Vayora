import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../app_state.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../services/device_media.dart';
import 'premium.dart';
import 'player.dart';

class StorageMeter extends StatelessWidget {
  const StorageMeter({super.key,required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context){
    final used=(state.status['used_bytes'] as num? ?? 0).toDouble(),total=(state.status['quota_bytes'] as num? ?? 0).toDouble();
    return Card(child:Padding(padding:Gap.page,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Row(children:[Icon(Icons.cloud_upload_outlined,color:AppColors.primary),SizedBox(width:8),Text('Your cloud space')]),
      const SizedBox(height:16),Text(storageLabel(used),style:Theme.of(context).textTheme.headlineMedium),
      Text('of ${storageLabel(total)} used',style:Theme.of(context).textTheme.bodySmall),
      const SizedBox(height:16),ClipRRect(borderRadius:Radii.chipRadius,child:LinearProgressIndicator(minHeight:8,value:total>0?(used/total).clamp(0,1):0)),
      const SizedBox(height:8),Text(total>0?'${storageLabel((total-used).clamp(0,total))} available':state.paidEnabled?'Get 2 TB with Premium':'Log in for 15 GB free',style:Theme.of(context).textTheme.bodySmall),
    ])));
  }
}
Future<void> showCloudActions(BuildContext context,AppState state) async {
  final target=CloudScope.maybeOf(context);
  if(target!=null){await target.actions();return;}
  if(!await loginGate(context,state)||!context.mounted)return;
  await Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>AppPage(title:'Cloud',body:CloudView(state:state))));
}
class CloudScope extends InheritedWidget{
  const CloudScope({super.key,required this.controller,required super.child});
  final CloudController controller;
  static CloudController? maybeOf(BuildContext context)=>context.findAncestorWidgetOfExactType<CloudScope>()?.controller;
  @override bool updateShouldNotify(CloudScope oldWidget)=>controller!=oldWidget.controller;
}
abstract interface class CloudController{Future<void> actions();}
class CloudView extends StatefulWidget {
  const CloudView({super.key,required this.state});
  final AppState state;
  @override State<CloudView> createState()=>CloudViewState();
}
class CloudViewState extends State<CloudView> implements CloudController{
  final crumbs=<Map<String,dynamic>>[];
  List<Map<String,dynamic>> rows=[];
  bool loading=true,busy=false;
  double progress=0;
  String? failure,user;
  String? get parent=>crumbs.isEmpty?null:crumbs.last['id'] as String;
  AppState get state=>widget.state;
  @override void initState(){super.initState();state.addListener(changed);load();}
  void changed(){if(user!=state.db.auth.currentUser?.id){crumbs.clear();load();}}
  @override void dispose(){state.removeListener(changed);super.dispose();}
  Future<void> load() async {
    final id=state.db.auth.currentUser?.id;user=id;
    if(state.guest||id==null){if(mounted)setState((){rows=[];loading=false;});return;}
    try{
      var query=state.db.from('cloud_files').select().eq('user_id',id);
      final result=await (parent==null?query.isFilter('parent_id',null):query.eq('parent_id',parent!))
        .order('is_folder',ascending:false).order('name');
      if(mounted&&id==state.db.auth.currentUser?.id)setState((){rows=result;loading=false;failure=null;});
    }on Object{if(mounted)setState((){failure='Could not load your files.';loading=false;});}
  }
  Future<void> refresh()async{await state.refreshStatus();await load();}
  Future<String?> askName(String title,{String value=''})async{
    var text=value;
    return showDialog<String>(context:context,builder:(dialog)=>AlertDialog(title:Text(title),
      content:TextFormField(initialValue:value,autofocus:true,maxLength:255,onChanged:(v)=>text=v,decoration:const InputDecoration(labelText:'Name')),
      actions:[TextButton(onPressed:()=>Navigator.pop(dialog),child:const Text('Cancel')),
      FilledButton(onPressed:(){if(text.trim().isNotEmpty)Navigator.pop(dialog,text.trim());},child:const Text('Save'))]));
  }
  @override Future<void> actions() async {
    if(busy||!await loginGate(context,state)||!mounted)return;
    await state.refreshStatus();if(!mounted)return;
    if((state.status['quota_bytes'] as num? ?? 0)<=0){
      await Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>Plans(state:state)));return;
    }
    final action=await showModalBottomSheet<String>(context:context,showDragHandle:true,builder:(sheet)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
      ListTile(leading:const Icon(Icons.upload_file_outlined),title:const Text('Upload file'),onTap:()=>Navigator.pop(sheet,'upload')),
      ListTile(leading:const Icon(Icons.create_new_folder_outlined),title:const Text('New folder'),onTap:()=>Navigator.pop(sheet,'folder')),
    ])));
    if(action=='folder'&&mounted){
      final name=await askName('New folder');if(name==null||!mounted)return;
      await runAction(context,()async{await state.db.rpc('cloud_reserve',params:{'name':name,'parent_id':parent,'is_folder':true});await refresh();});
    }else if(action=='upload'){await upload();}
  }
  Future<void> upload()async{
    final file=await PickedMedia.pick(kind:'any');if(file==null||!mounted)return;
    if(file.size>52428800){showFeedback(context,'50 MB maximum per file');return;}
    setState((){busy=true;progress=0;failure=null;});
    final client=state.uploadClient;
    try{
      final request=http.MultipartRequest('POST',Uri.parse('$backendUrl/functions/v1/cloud-files'));
      request.headers.addAll({'apikey':backendKey,'Authorization':'Bearer ${state.db.auth.currentSession!.accessToken}'});
      request.fields['name']=file.name;request.fields['mime']=file.mime;if(parent!=null)request.fields['parent_id']=parent!;
      request.files.add(await http.MultipartFile.fromPath('file',file.path));
      final length=request.contentLength,source=request.finalize();
      final outgoing=http.StreamedRequest('POST',request.url)..headers.addAll(request.headers)..contentLength=length;
      final response=client.send(outgoing);var sent=0;
      await for(final bytes in source){outgoing.sink.add(bytes);sent+=bytes.length;if(mounted)setState(()=>progress=sent/length);}
      await outgoing.sink.close();final result=await http.Response.fromStream(await response);
      if(result.statusCode!=200){final body=jsonDecode(result.body)as Map;throw StateError(body['message'] as String? ??'Upload failed');}
      if(mounted)showFeedback(context,'File uploaded.');await refresh();
    }on Object catch(e){if(mounted)setState(()=>failure=e is StateError?e.message.toString():'Upload could not finish.');await load();}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> open(Map<String,dynamic> row)async{
    if(row['is_folder']==true){setState(()=>crumbs.add(row));await load();return;}
    if(row['ready']!=true||row['deleting']==true){await menu(row);return;}
    if((state.status['quota_bytes'] as num? ??0)<=0){await Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>Plans(state:state)));return;}
    await runAction(context,()async{
      final key=row['storage_key']as String;
      Future<String> url()=>state.db.storage.from('cloud').createSignedUrl(key,3600);
      final signed=await url();if(!mounted)return;
      final mime=row['mime']as String;
      if(mime.startsWith('video/')){
        await Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>Watch(url:signed,refreshUrl:url,title:row['name']as String,
          personalCloud:true,trailer:false,isPremium:false,state:state,audience:'all',channelAudience:'all',createdBy:state.userId)));
      }else if(mime.startsWith('image/')){
        await Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>AppPage(title:row['name']as String,
          body:Center(child:InteractiveViewer(child:Image.network(signed))))));
      }else{await openOtherFile(signed,row['name']as String,mime);}
    });
  }
  Future<void> move(Map<String,dynamic> row)async{
    final folders=await state.db.from('cloud_files').select('id,name,parent_id').eq('user_id',state.userId).eq('is_folder',true);
    if(!mounted)return;
    final target=await showModalBottomSheet<String>(context:context,isScrollControlled:true,builder:(sheet)=>SafeArea(child:ListView(
      shrinkWrap:true,children:[ListTile(title:const Text('Cloud root'),onTap:()=>Navigator.pop(sheet,'root')),
      for(final folder in folders.where((f)=>f['id']!=row['id']))ListTile(leading:const Icon(Icons.folder_outlined),
        title:Text(folder['name']as String),onTap:()=>Navigator.pop(sheet,folder['id']as String))])));
    if(target==null||!mounted)return;
    await runAction(context,()async{await state.db.from('cloud_files').update({'parent_id':target=='root'?null:target})
      .eq('id',row['id']).eq('user_id',state.userId).select('id').single();await load();});
  }
  Future<void> menu(Map<String,dynamic> row)async{
    if(busy)return;
    final action=await showModalBottomSheet<String>(context:context,showDragHandle:true,builder:(sheet)=>SafeArea(child:Column(mainAxisSize:MainAxisSize.min,children:[
      ListTile(title:const Text('Rename'),leading:const Icon(Icons.edit_outlined),onTap:()=>Navigator.pop(sheet,'rename')),
      ListTile(title:const Text('Move'),leading:const Icon(Icons.drive_file_move_outlined),onTap:()=>Navigator.pop(sheet,'move')),
      ListTile(title:const Text('Delete'),leading:const Icon(Icons.delete_outline,color:AppColors.danger),onTap:()=>Navigator.pop(sheet,'delete')),
    ])));
    if(!mounted)return;
    if(action=='rename'){
      final name=await askName('Rename',value:row['name']as String);if(name==null||!mounted)return;
      await runAction(context,()async{await state.db.from('cloud_files').update({'name':name}).eq('id',row['id']).eq('user_id',state.userId).select('id').single();await load();});
    }else if(action=='move'){await move(row);}
    else if(action=='delete'&&await confirmAction(context,title:'Delete ${row['name']}?',message:row['is_folder']==true?'This also deletes every file and folder inside.':'This permanently deletes this file.',action:'Delete',destructive:true)&&mounted){
      await runAction(context,()async{await state.db.functions.invoke('cloud-files',body:{'operation':'delete','entry_id':row['id']});await refresh();});
    }
  }
  IconData icon(Map<String,dynamic> row)=>row['is_folder']==true?Icons.folder_rounded:
    (row['mime']as String).startsWith('image/')?Icons.image_outlined:
    (row['mime']as String).startsWith('video/')?Icons.video_file_outlined:Icons.insert_drive_file_outlined;
  @override Widget build(BuildContext context)=>ListenableBuilder(listenable:state,builder:(context,_)=>CloudScope(controller:this,
    child:RefreshIndicator(onRefresh:refresh,child:PageWidth(child:ListView(physics:const AlwaysScrollableScrollPhysics(),padding:Gap.page,children:[
      StorageMeter(state:state),const SizedBox(height:24),
      if(state.guest)EmptyState(icon:Icons.cloud_outlined,title:'Your cloud awaits',
        message:state.paidEnabled?'Log in to manage your storage.':'Log in for 15 GB free',actionLabel:'Log in',onAction:()=>loginGate(context,state))
      else ...[
        if((state.status['quota_bytes']as num? ??0)<=0)NoticeCard(title:'Get 2 TB with Premium',message:'Choose a plan to upload and open files.',
          onTap:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>Plans(state:state)))),
        Wrap(crossAxisAlignment:WrapCrossAlignment.center,children:[
          TextButton(onPressed:(){setState(crumbs.clear);load();},child:const Text('Cloud')),
          for(var i=0;i<crumbs.length;i++)TextButton(onPressed:(){setState(()=>crumbs.removeRange(i+1,crumbs.length));load();},child:Text('/ ${crumbs[i]['name']}')),
        ]),
        if(busy)...[LinearProgressIndicator(value:progress),Text(progress>=1?'Finishing upload…':'Uploading ${(progress*100).round()}%')],
        if(failure!=null)NoticeCard(title:'Please try again',message:failure!,tone:NoticeTone.danger),
        if(loading)const SkeletonList()else if(rows.isEmpty)const EmptyState(icon:Icons.folder_open_outlined,title:'No files yet',message:'Tap + to upload a file or create a folder.')
        else for(final row in rows)Card(child:ListTile(leading:Icon(icon(row),color:AppColors.primary),title:Text(row['name']as String),
          subtitle:row['is_folder']==true?null:Text(row['ready']==true?storageLabel(row['size']as num?):'Upload not completed'),
          onTap:()=>open(row),onLongPress:()=>menu(row),trailing:IconButton(tooltip:'File options',icon:const Icon(Icons.more_vert),onPressed:()=>menu(row)))),
        const SizedBox(height:16),GradientButton(label:'Add files or folder',icon:Icons.add,onPressed:busy?null:actions),
      ],
    ])))));
}

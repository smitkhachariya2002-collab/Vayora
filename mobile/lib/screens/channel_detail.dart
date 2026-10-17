import 'package:flutter/material.dart';
import '../app_state.dart';
import '../channel_page.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/report_dialog.dart';
import 'content.dart';
import 'premium.dart';

class ChannelDetail extends StatefulWidget {
  const ChannelDetail({super.key,required this.state,required this.channel});
  final AppState state;
  final Map<String,dynamic> channel;
  @override
  State<ChannelDetail> createState()=>_ChannelDetailState();
}
class _ChannelDetailState extends State<ChannelDetail>{
  late Map<String,dynamic> channel=widget.channel;
  bool joined=false,busy=false;
  @override
  void initState(){super.initState();loadMembership();}
  Future<void> loadMembership()async{
    if(widget.state.guest)return;
    try{
      final rows=await widget.state.db.from('channel_members').select('channel_id').eq('user_id',widget.state.userId).eq('channel_id',channel['id']);
      if(mounted)setState(()=>joined=rows.isNotEmpty);
    }on Object{/* A later Join is idempotent if membership could not be loaded. */}
  }
  Future<void> join()async{
    if(busy||!await loginGate(context,widget.state)||!mounted)return;
    if(joined&&!await confirmAction(context,title:'Leave this channel?',message:'Its posts will no longer appear in your feed.',
      action:'Leave channel',icon:Icons.logout_rounded)){return;}
    if(!mounted)return;
    setState(()=>busy=true);
    try{
      if(joined){await widget.state.db.from('channel_members').delete().eq('user_id',widget.state.userId).eq('channel_id',channel['id']);}
      else{await widget.state.db.from('channel_members').upsert({'user_id':widget.state.userId,'channel_id':channel['id']},ignoreDuplicates:true);}
      if(mounted){setState(()=>joined=!joined);showFeedback(context,joined?'Channel joined.':'You left the channel.');}
    }on Object{if(mounted)showFeedback(context,'Could not update your channels. Please try again.');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> menu(String action)async{
    if(!mounted)return;
    if(action=='report'){await reportContent(context,widget.state,channelId:channel['id'] as String);}
    if(action=='edit'){
      if(!mounted)return;
      final saved=await Navigator.push<bool>(context,MaterialPageRoute<bool>(builder:(_)=>ChannelEditor(state:widget.state,channel:channel)));
      if(saved==true&&mounted){await runAction(context,()async{
        final row=await widget.state.db.from('channels').select().eq('id',channel['id']).single();
        if(mounted){setState(()=>channel=row);showFeedback(context,'Channel updated.');}
      });}
    }
    if(action=='block'){
      if(!mounted)return;
      final blocked=widget.state.blocked.contains(channel['id']);
      if(!await confirmAction(context,title:blocked?'Unblock this channel?':'Block this channel?',
        message:blocked?'Its posts can appear again.':'You won’t see its posts while browsing.',action:blocked?'Unblock':'Block',
        icon:Icons.block)||!mounted){return;}
      await widget.state.block(channel['id'] as String);
      if(mounted){showFeedback(context,blocked?'Channel unblocked.':'Channel blocked.');if(!blocked)Navigator.pop(context);}
    }
  }
  @override
  Widget build(BuildContext context)=>ListenableBuilder(listenable:widget.state,builder:(context,_){
    final state=widget.state;
    return AppPage(title:channel['name'] as String,actions:[
      CrownButton(visible:state.paidEnabled,onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>Plans(state:state)))),
      PopupMenuButton<String>(tooltip:'Channel options',onSelected:menu,itemBuilder:(_)=>[
        const PopupMenuItem(value:'report',child:Text('Report')),
        PopupMenuItem(value:'block',child:Text(state.blocked.contains(channel['id'])?'Unblock':'Block')),
        if(channel['created_by']==state.userId)const PopupMenuItem(value:'edit',child:Text('Edit')),
      ]),
    ],body:ContentList(state:state,channel:channel['id'] as String,intro:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      GlowHeader(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        ChannelAvatar(channel:channel,radius:AppSizes.avatarLarge),const SizedBox(height:Gap.l),
        Text(channel['name'] as String,style:Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height:Gap.s),Text('${compactNumber(channel['members_count'] as num?)} members',
          style:Theme.of(context).textTheme.bodySmall),
        if((channel['description'] as String? ?? '').isNotEmpty)...[const SizedBox(height:Gap.l),ExpandableCopy(channel['description'] as String)],
        if((channel['tags'] as List? ?? []).isNotEmpty)...[const SizedBox(height:Gap.m),Wrap(spacing:Gap.s,runSpacing:Gap.s,
          children:(channel['tags'] as List).map((tag)=>Chip(label:Text('#$tag'))).toList())],
        const SizedBox(height:Gap.xl),
        if(joined)SizedBox(width:double.infinity,child:OutlinedButton.icon(onPressed:busy?null:join,
          icon:const Icon(Icons.check),label:Text(busy?'Please wait…':'Joined')))
        else GradientButton(label:'Join',icon:Icons.add,busy:busy,onPressed:busy?null:join),
      ])),
      const SectionTitle('Stories from this channel'),const SizedBox(height:Gap.l),
    ])));
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_state.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/report_dialog.dart';
import 'channel_detail.dart';
import 'content.dart';
import 'premium.dart';
import 'player.dart';

class PostPage extends StatelessWidget {
  const PostPage({super.key,required this.state,required this.post});
  final AppState state;
  final Map<String,dynamic> post;
  bool get ownsMedia => state.status['is_admin'] == true || post['created_by'] == state.userId;
  Future<void> play(BuildContext context, Map<String, dynamic> item, {bool trailer = false}) async {
    await runAction(context, state.refreshStatus);
    if (!context.mounted) return;
    if (!trailer && state.guest && state.paidEnabled && item['is_premium'] == true &&
        state.adsAccess && item['trailer_key'] != null) {
      await play(context, item, trailer: true);
      return;
    }
    if (!trailer && !await loginGate(context, state)) return;
    if (!context.mounted) return;
    if (!trailer && !ownsMedia && item['is_premium'] == true && !state.premium) {
      if (state.adsAccess && item['trailer_key'] != null) {
        await play(context, item, trailer: true);
      } else {
        await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => Plans(state: state)));
      }
      return;
    }
    await runAction(context, () async {
      final key = (trailer ? item['trailer_key'] : item['media_key']) as String?;
      if (key == null) throw StateError('Trailer unavailable');
      final url = await state.db.storage.from('media').createSignedUrl(key, 60);
      if (!context.mounted) return;
      if (!trailer && (item['mime'] as String).startsWith('image/')) {
        await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => Scaffold(appBar: AppBar(title: Text(post['title'] as String)),
          body: Center(child: InteractiveViewer(child: Image.network(url))))));
      } else {
        await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => Watch(title: post['title'] as String, url: url, trailer: trailer, isPremium: item['is_premium'] == true, state: state, audience: post['audience'] as String, channelAudience: (post['channels'] as Map?)?['audience'] as String? ?? 'all', createdBy: post['created_by'] as String)));
      }
    });
  }

  Future<void> download(BuildContext context,Map<String,dynamic> item)async{
    await runAction(context,()async{
      if(!await loginGate(context,state)||!context.mounted)return;
      if(!state.premium&&!ownsMedia){await Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>Plans(state:state)));return;}
      final url=await state.db.storage.from('media').createSignedUrl(item['media_key'] as String,60);
      await const MethodChannel('app/download').invokeMethod<void>('download',{'url':url,'name':'vayora-${item['id']}.mp4'});
      if(context.mounted)showFeedback(context,'Download started.');
    });
  }
  Future<void> channel(BuildContext context)async{
    await runAction(context,()async{
      final row=await state.db.from('channels').select().eq('id',post['channel_id']).single();
      if(context.mounted)await Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>ChannelDetail(state:state,channel:row)));
    });
  }
  @override
  Widget build(BuildContext context)=>ListenableBuilder(listenable:state,builder:(context,_){
    final channelAudience=(post['channels'] as Map?)?['audience'] as String? ?? 'all';
    if(!ownsMedia&&(!state.canSee(post['audience'] as String)||!state.canSee(channelAudience))){
      return const AppPage(title:AppBrand.name,body:EmptyState(icon:Icons.lock_outline,title:'This post is unavailable',
        message:'Your access may have changed. Explore other stories.'));
    }
    final items=List<Map<String,dynamic>>.from(post['post_items'] as List)
      ..sort((a,b)=>(a['position'] as int).compareTo(b['position'] as int));
    return AppPage(title:AppBrand.name,actions:[
      IconButton(tooltip:state.blocked.contains(post['channel_id'])?'Unblock channel':'Block channel',
        icon:const Icon(Icons.block),onPressed:()async{
          final blocked=state.blocked.contains(post['channel_id']);
          if(!await confirmAction(context,title:blocked?'Unblock this channel?':'Block this channel?',
            message:blocked?'Its posts can appear again.':'Its posts will be hidden while browsing.',
            action:blocked?'Unblock':'Block',icon:Icons.block)||!context.mounted)return;
          await runAction(context,()async{await state.block(post['channel_id'] as String);if(context.mounted)Navigator.pop(context);});
        }),
    ],body:PageWidth(child:ListView(padding:Gap.page,children:[
      for(final item in items)...[
        ClipRRect(borderRadius:Radii.cardRadius,child:NetThumb(
          url:item['thumbnail_key']==null?null:state.db.storage.from('public').getPublicUrl(item['thumbnail_key'] as String),
          overlays:[Center(child:PlayOverlay(onPressed:()=>play(context,item))),
            Positioned(left:Gap.m,bottom:Gap.m,child:ThumbPill(durationLabel(item['duration_s'] as num?)))])),
        const SizedBox(height:Gap.xl),
        Text(post['title'] as String,style:Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height:Gap.m),
        Wrap(spacing:Gap.m,runSpacing:Gap.s,crossAxisAlignment:WrapCrossAlignment.center,children:[
          if(item['is_premium']==true)const PremiumBadge(),
          Text('${durationLabel(item['duration_s'] as num?)} · ${compactNumber(post['view_count'] as num?)} views',
            style:Theme.of(context).textTheme.bodySmall),
        ]),
        const SizedBox(height:Gap.xl),
        LayoutBuilder(builder:(context,limits){
          final buttons=<Widget>[
            GradientButton(label:'Play',icon:Icons.play_arrow_rounded,onPressed:()=>play(context,item)),
            if((state.adsAccess||ownsMedia)&&item['trailer_key']!=null)
              OutlinedButton.icon(onPressed:()=>play(context,item,trailer:true),icon:const Icon(Icons.movie_outlined),label:const Text('Trailer')),
          ];
          if(MediaQuery.textScalerOf(context).scale(AppSizes.body)>AppSizes.title){
            return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
              for(final button in buttons)Padding(padding:const EdgeInsets.only(bottom:Gap.s),child:button)]);
          }
          return Row(children:[for(var index=0;index<buttons.length;index++)...[
            if(index>0)const SizedBox(width:Gap.m),Expanded(child:buttons[index])]]);
        }),
        const SizedBox(height:Gap.l),
        Wrap(spacing:Gap.s,runSpacing:Gap.s,children:[
          TextButton.icon(icon:const Icon(Icons.share_outlined),label:const Text('Share'),onPressed:()=>runAction(context,()async{
            await const MethodChannel('app/share').invokeMethod<void>('share',{'text':'Watch ${post['title']} on Vayora'});
          })),
          TextButton.icon(icon:const Icon(Icons.live_tv_outlined),label:const Text('Channel'),onPressed:()=>channel(context)),
          TextButton.icon(icon:const Icon(Icons.flag_outlined),label:const Text('Report'),
            onPressed:()=>reportContent(context,state,postId:post['id'] as String,channelId:post['channel_id'] as String)),
          TextButton.icon(icon:const Icon(Icons.download_outlined),label:const Text('Download'),onPressed:()=>download(context,item)),
        ]),
        const SizedBox(height:Gap.l),ExpandableCopy(post['description'] as String? ?? ''),const SizedBox(height:Gap.xl),
      ],
      const SectionTitle('More like this'),const SizedBox(height:Gap.l),
      SizedBox(height:AppSizes.relatedHeight*MediaQuery.textScalerOf(context).scale(AppSizes.body)/AppSizes.body,
        child:ContentList(state:state,creator:post['created_by'] as String,horizontal:true)),
    ])));
  });
}

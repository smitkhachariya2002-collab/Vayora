import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'account_page.dart';
import 'app_state.dart';
import 'theme.dart';
import 'widgets/common.dart';
export 'widgets/common.dart' show ChannelAvatar;

List<String> parseChannelTags(String raw) => raw.split(',').map((tag) =>
  tag.trim().replaceFirst(RegExp(r'^#+'), '').trim().toLowerCase()).where((tag) => tag.isNotEmpty).toSet().toList();

class ChannelList extends StatefulWidget {
  const ChannelList({super.key, required this.state, required this.onOpen, this.initialMine = false});
  final AppState state;
  final void Function(Map<String, dynamic>) onOpen;
  final bool initialMine;
  @override
  State<ChannelList> createState() => _ChannelListState();
}
class _ChannelListState extends State<ChannelList> {
  final rows = <Map<String,dynamic>>[], joined = <String>{};
  final scroll = ScrollController();
  bool mine=false,loading=false,hasMore=true;
  int offset=0,request=0;
  String search='',fingerprint='';
  String? failure;
  String get accessKey => '${widget.state.userId}:${widget.state.adsAccess}:${widget.state.status['is_admin']}';
  @override
  void initState() {
    super.initState();mine=widget.initialMine;fingerprint=accessKey;scroll.addListener(more);reload();
  }
  @override
  void didUpdateWidget(covariant ChannelList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if(fingerprint!=accessKey){fingerprint=accessKey;reload();}
  }
  @override
  void dispose(){scroll.dispose();super.dispose();}
  void more(){if(scroll.hasClients&&scroll.position.extentAfter<AppSizes.mediaHero)load();}
  Future<void> reload() async {
    try {
      final membership=widget.state.guest?<Map<String,dynamic>>[]:
        await widget.state.db.from('channel_members').select('channel_id').eq('user_id',widget.state.userId);
      if(!mounted)return;
      joined..clear()..addAll(membership.map((row)=>row['channel_id'] as String));
    } on Object { if(mounted)showFeedback(context,'Could not refresh your joined channels.'); }
    if(mounted)await load(refresh:true);
  }
  Future<void> load({bool refresh=false})async{
    if(!refresh&&(loading||!hasMore))return;
    final current=++request;
    setState((){loading=true;failure=null;if(refresh)offset=0;});
    try{
      var query=widget.state.db.from('channels').select();
      if(mine){query=query.eq('created_by',widget.state.userId);}
      else{query=query.eq('review_status','approved').eq('status','active');}
      final next=await query.order('created_at',ascending:false).range(offset,offset+AppSizes.pageSize-1);
      if(!mounted||current!=request)return;
      setState((){
        if(refresh)rows.clear();
        final ids=rows.map((row)=>row['id']).toSet();
        rows.addAll(next.where((row)=>ids.add(row['id'])));
        offset+=next.length;hasMore=next.length==AppSizes.pageSize;loading=false;
      });
    }on Object{if(mounted&&current==request)setState((){loading=false;failure="Couldn't load. Check your connection.";});}
  }
  Future<void> edit([Map<String,dynamic>? channel])async{
    if(!await ensureSignedIn(context,widget.state)||!mounted)return;
    final saved=await Navigator.push<bool>(context,MaterialPageRoute<bool>(builder:(_)=>ChannelEditor(state:widget.state,channel:channel)));
    if(saved==true&&mounted){
      setState(()=>mine=true);await reload();
      if(mounted)showFeedback(context,channel==null?'Channel created.':'Channel updated.');
    }
  }
  Future<void> membership(Map<String,dynamic> channel)async{
    if(!await ensureSignedIn(context,widget.state)||!mounted)return;
    final id=channel['id'] as String;
    final leaving=joined.contains(id);
    if(leaving&&!await confirmAction(context,title:'Leave this channel?',message:'Its posts will no longer appear in your feed.',
      action:'Leave channel',icon:Icons.logout_rounded))return;
    if(!mounted)return;
    try{
      if(leaving){await widget.state.db.from('channel_members').delete().eq('user_id',widget.state.userId).eq('channel_id',id);}
      else{await widget.state.db.from('channel_members').upsert({'user_id':widget.state.userId,'channel_id':id},ignoreDuplicates:true);}
      if(mounted){setState((){if(leaving){joined.remove(id);}else{joined.add(id);}});showFeedback(context,leaving?'You left the channel.':'Channel joined.');}
    }on Object{if(mounted)showFeedback(context,'Could not update your channels. Please try again.');}
  }
  String statusLabel(Map<String,dynamic> row)=>row['review_status']=='pending'?'Under review':
    row['review_status']=='rejected'?'Not published':row['status']=='hidden'?'Hidden':'Live';
  @override
  Widget build(BuildContext context){
    final term=search.toLowerCase().trim();
    final visible=rows.where((row)=>!widget.state.blocked.contains(row['id'])&&
      (term.isEmpty||'${row['name']} ${row['description']} ${row['category']} ${row['tags']}'.toLowerCase().contains(term))).toList();
    return RefreshIndicator(onRefresh:reload,child:PageWidth(child:ListView(
      controller:scroll,physics:const AlwaysScrollableScrollPhysics(),padding:Gap.page,children:[
        Card(child:DecoratedBox(decoration:const BoxDecoration(gradient:AppColors.softGradient,borderRadius:Radii.cardRadius),
          child:Padding(padding:Gap.page,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Icon(Icons.live_tv_rounded,color:AppColors.primary,size:AppSizes.dialogIcon),
            const SizedBox(height:Gap.l),Text('Create a space for what you love',style:Theme.of(context).textTheme.titleLarge),
            const SizedBox(height:Gap.s),Text('Bring people together. Share your stories.',style:Theme.of(context).textTheme.bodySmall),
            const SizedBox(height:Gap.xl),GradientButton(label:'Create channel',icon:Icons.add,onPressed:()=>edit()),
          ])))),
        const SizedBox(height:Gap.xl),
        TextField(decoration:const InputDecoration(hintText:'Search channels',prefixIcon:Icon(Icons.search)),
          onChanged:(value)=>setState(()=>search=value)),
        const SizedBox(height:Gap.l),
        SegmentedButton<bool>(segments:const[ButtonSegment(value:true,label:Text('My channels')),
          ButtonSegment(value:false,label:Text('Discover'))],selected:{mine},showSelectedIcon:false,
          onSelectionChanged:(values)async{
            if(values.single&&!await ensureSignedIn(context,widget.state))return;
            if(mounted){setState(()=>mine=values.single);await reload();}
          }),
        const SizedBox(height:Gap.xl),
        SectionTitle(mine?'Shared by you':'Find your community'),const SizedBox(height:Gap.l),
        if(loading&&visible.isEmpty)const SkeletonList()
        else if(failure!=null&&visible.isEmpty)ErrorRetry(onRetry:reload)
        else if(visible.isEmpty)EmptyState(icon:Icons.live_tv_outlined,title:mine?'Make this space yours':'New communities are on the way',
          message:term.isNotEmpty?'Try a different name or tag.':mine?'Create your first channel and start sharing.':'Explore again soon, or start a channel of your own.',
          actionLabel:'Create channel',onAction:()=>edit()),
        for(final row in visible)Padding(padding:const EdgeInsets.only(bottom:Gap.l),child:PressScale(onTap:()=>widget.onOpen(row),
          child:Card(child:Padding(padding:const EdgeInsets.all(Gap.l),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Row(children:[ChannelAvatar(channel:row),const SizedBox(width:Gap.m),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(row['name'] as String,maxLines:2,overflow:TextOverflow.ellipsis,style:Theme.of(context).textTheme.titleMedium),
              const SizedBox(height:Gap.xs),Text('${(row['category'] as String? ?? '').isEmpty?'Channel':row['category']} · ${compactNumber(row['members_count'] as num?)} members',
                style:Theme.of(context).textTheme.bodySmall),
            ]))]),
            if((row['description'] as String? ?? '').isNotEmpty)...[const SizedBox(height:Gap.m),
              Text(row['description'] as String,maxLines:2,overflow:TextOverflow.ellipsis,style:Theme.of(context).textTheme.bodySmall)],
            if((row['tags'] as List? ?? []).isNotEmpty)...[const SizedBox(height:Gap.m),
              Wrap(spacing:Gap.s,runSpacing:Gap.xs,children:(row['tags'] as List).take(3).map((tag)=>Text('#$tag',style:Theme.of(context).textTheme.bodySmall)).toList())],
            const SizedBox(height:Gap.l),
            if(row['created_by']==widget.state.userId)...[
              StatusPill(statusLabel(row),tone:row['review_status']=='approved'?NoticeTone.success:NoticeTone.warning),
              const SizedBox(height:Gap.s),
              SizedBox(width:double.infinity,child:OutlinedButton.icon(onPressed:()=>edit(row),icon:const Icon(Icons.edit_outlined),
                label:const Text('Edit channel'))),
            ]else SizedBox(width:double.infinity,child:joined.contains(row['id'])?
              OutlinedButton.icon(onPressed:()=>membership(row),icon:const Icon(Icons.check),label:const Text('Joined')):
              GradientButton(label:'Join',icon:Icons.add,onPressed:()=>membership(row))),
          ]))))),
        if(loading&&visible.isNotEmpty)const SkeletonBlock(height:AppSizes.button),
        if(failure!=null&&visible.isNotEmpty)ErrorRetry(onRetry:()=>load()),
        if(hasMore&&!loading)OutlinedButton(onPressed:()=>load(),child:const Text('Load more')),
        const SizedBox(height:Gap.xl),
      ])));
  }
}
class ChannelEditor extends StatefulWidget {
  const ChannelEditor({super.key, required this.state, this.channel});
  final AppState state;
  final Map<String, dynamic>? channel;
  @override
  State<ChannelEditor> createState() => _ChannelEditorState();
}
class _ChannelEditorState extends State<ChannelEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name, description, tags;
  Uint8List? photo;
  bool busy = false, picking = false, removePhoto = false;
  String? failure;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.channel?['name'] as String? ?? '');
    description = TextEditingController(text: widget.channel?['description'] as String? ?? '');
    tags = TextEditingController(text: (widget.channel?['tags'] as List? ?? []).join(', '));
  }
  @override
  void dispose() { name.dispose(); description.dispose(); tags.dispose(); super.dispose(); }
  Future<void> pickPhoto() async {
    setState(() { picking = true; failure = null; });
    try {
      final selected = await const MethodChannel('app/photo').invokeMethod<Uint8List>('pick');
      if (selected != null && mounted) {
        if (selected.length > 5 * 1024 * 1024) throw StateError('Photo too large');
        setState(() { photo = selected; removePhoto = false; });
      }
    } on Object {
      if (mounted) setState(() => failure = 'Could not open this photo. Try another image.');
    } finally { if (mounted) setState(() => picking = false); }
  }
  Future<void> save() async {
    if (busy || form.currentState?.validate() != true) return;
    if (widget.state.guest) { setState(() => failure = 'Log in before creating a channel.'); return; }
    setState(() { busy = true; failure = null; });
    final bucket = widget.state.db.storage.from('public');
    final id = widget.channel?['id'] as String? ?? const Uuid().v4();
    final ownerPrefix = '${widget.state.userId}/channel-photos/';
    String? uploaded;
    var committed = false;
    try {
      String? url = removePhoto ? null : widget.channel?['icon_url'] as String?;
      if (photo != null) {
        uploaded = '$ownerPrefix$id/${const Uuid().v4()}.jpg';
        await bucket.uploadBinary(uploaded, photo!, fileOptions: const FileOptions(contentType: 'image/jpeg', cacheControl: '31536000'));
        url = bucket.getPublicUrl(uploaded);
      }
      final values = {'name': name.text.trim(), 'description': description.text.trim(),
        'tags': parseChannelTags(tags.text), 'icon_url': url};
      if (widget.channel == null) {
        await widget.state.db.from('channels').insert({...values, 'id': id, 'created_by': widget.state.userId});
      } else {
        await widget.state.db.from('channels').update(values).eq('id', id).eq('created_by', widget.state.userId).select('id').single();
      }
      committed = true;
      final previous = widget.channel?['icon_url'] as String?;
      final publicPrefix = bucket.getPublicUrl(ownerPrefix);
      if (previous != null && previous != url && previous.startsWith(publicPrefix)) {
        try { await bucket.remove(['$ownerPrefix${previous.substring(publicPrefix.length)}']); } on Object { /* A saved channel must not fail because old-photo cleanup was unavailable. */ }
      }
      if (mounted) Navigator.pop(context, true);
    } on Object {
      if (uploaded != null && !committed) {
        try { await bucket.remove([uploaded]); } on Object { /* The channel was not saved; cleanup can be retried later. */ }
      }
      if (mounted) setState(() => failure = 'Could not save your channel. Your details are still here; please try again.');
    } finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) {
    final preview=photo;
    final oldUrl=removePhoto?null:widget.channel?['icon_url'] as String?;
    return AppPage(title:widget.channel==null?'Create channel':'Edit channel',body:PageWidth(form:true,
      child:Form(key:form,child:ListView(padding:Gap.page,children:[
        GlowHeader(child:Column(children:[
          Center(child:Container(width:AppSizes.logoLarge,height:AppSizes.logoLarge,
            decoration:const BoxDecoration(shape:BoxShape.circle,gradient:AppColors.gradient),
            child:ClipOval(child:preview!=null?Image.memory(preview,fit:BoxFit.cover):
              oldUrl!=null?Image.network(oldUrl,fit:BoxFit.cover,errorBuilder:(_,_,_)=>const Icon(Icons.live_tv_rounded,size:AppSizes.dialogIcon)):
              const Icon(Icons.live_tv_rounded,size:AppSizes.dialogIcon,color:AppColors.ink)))),
          const SizedBox(height:Gap.s),
          TextButton.icon(key:const ValueKey('channel-photo'),onPressed:busy||picking?null:pickPhoto,
            icon:const Icon(Icons.add_a_photo_outlined),label:Text(picking?'Opening photos…':'Choose channel photo')),
          if(preview!=null||oldUrl!=null)TextButton(onPressed:busy?null:()=>setState((){photo=null;removePhoto=true;}),child:const Text('Remove photo')),
        ])),
        Text('Make it yours',style:Theme.of(context).textTheme.headlineSmall),const SizedBox(height:Gap.s),
        Text('A name, a little personality, and something worth sharing.',style:Theme.of(context).textTheme.bodySmall),
        const SizedBox(height:Gap.xl),
        TextFormField(key:const ValueKey('channel-name'),controller:name,enabled:!busy,maxLength:120,
          textCapitalization:TextCapitalization.words,decoration:const InputDecoration(labelText:'Channel name'),
          validator:(value)=>value==null||value.trim().isEmpty?'Enter a channel name':value.trim().length>120?'Use 120 characters or fewer':null),
        const SizedBox(height:Gap.l),
        TextFormField(key:const ValueKey('channel-description'),controller:description,enabled:!busy,maxLength:2000,
          minLines:3,maxLines:5,textCapitalization:TextCapitalization.sentences,
          decoration:const InputDecoration(labelText:'Description (optional)',hintText:'What is your channel about?')),
        const SizedBox(height:Gap.l),
        TextFormField(key:const ValueKey('channel-tags'),controller:tags,enabled:!busy,
          decoration:const InputDecoration(labelText:'Tags',hintText:'music, travel, food',helperText:'Separate tags with commas. Add up to 10.',helperMaxLines:2),
          onChanged:(_)=>setState((){}),validator:(value){final parsed=parseChannelTags(value??'');
            return parsed.length>10?'Add up to 10 tags':parsed.any((tag)=>tag.length>30)?'Keep each tag within 30 characters':null;}),
        const SizedBox(height:Gap.s),Wrap(spacing:Gap.s,runSpacing:Gap.xs,
          children:parseChannelTags(tags.text).take(10).map((tag)=>Chip(label:Text('#$tag'))).toList()),
        if(failure!=null)...[const SizedBox(height:Gap.l),NoticeCard(title:'Please try again',message:failure!,tone:NoticeTone.danger)],
        const SizedBox(height:Gap.xl),GradientButton(key:const ValueKey('channel-submit'),busy:busy,
          label:widget.channel==null?'Create channel':'Save changes',onPressed:busy||picking?null:save),
        const SizedBox(height:Gap.xl),
      ]))));
  }
}

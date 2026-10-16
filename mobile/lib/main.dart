import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (backendKey.isEmpty) {
    runApp(const MaterialApp(home: Scaffold(body: Center(
      child: Text('Vayora needs its Supabase publishable key. Build using the configured GitHub Actions workflow.'),
    ))));
    return;
  }
  await Supabase.initialize(url: backendUrl, anonKey: backendKey);
  final state = AppState(Supabase.instance.client, await SharedPreferences.getInstance());
  runApp(Vayora(state: state));
}

class Vayora extends StatelessWidget {
  const Vayora({super.key, required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Vayora',
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF7A1A), brightness: Brightness.dark),
      scaffoldBackgroundColor: const Color(0xFF111318),
    ),
    home: Startup(state: state),
  );
}

class Startup extends StatefulWidget {
  const Startup({super.key, required this.state});
  final AppState state;
  @override
  State<Startup> createState() => _StartupState();
}
class _StartupState extends State<Startup> {
  late Future<void> startup;
  @override
  void initState() { super.initState(); startup = widget.state.initialize(); }
  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: startup,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Scaffold(body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Vayora could not connect. Check your connection and try again.'),
          TextButton(onPressed: () => setState(() { startup = widget.state.initialize(); }), child: const Text('Retry')),
        ])));
      }
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return Home(state: widget.state);
    },
  );
}

Future<void> runAction(BuildContext context, Future<void> Function() action) async {
  try { await action(); } on Object catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
  }
}
Future<bool> loginGate(BuildContext context, AppState state) async {
  if (!state.guest) return true;
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => Login(state: state)));
  return !state.guest;
}

class Home extends StatefulWidget {
  const Home({super.key, required this.state});
  final AppState state;
  @override
  State<Home> createState() => _HomeState();
}
class _HomeState extends State<Home> with WidgetsBindingObserver {
  int selected = 2;
  late final StreamSubscription<AuthState> auth;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    auth = widget.state.db.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedIn || event.event == AuthChangeEvent.userUpdated) {
        unawaited(runAction(context, widget.state.afterLogin));
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.state.prefs.getBool('consent_v1') != true) consent();
    });
  }
  Future<void> consent() async {
    await showDialog<void>(context: context, barrierDismissible: false, builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(title: const Text('Welcome to Vayora'), content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Please review and accept our policies before continuing. Policy version v1.'),
        for (final name in ['Privacy', 'Terms', 'Refund', 'Community rules'])
          TextButton(onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
            builder: (_) => Policy(name: name))), child: Text(name)),
      ]), actions: [
        FilledButton(onPressed: () async {
          await runAction(ctx, () async { await widget.state.acceptConsent(); if (ctx.mounted) Navigator.pop(ctx); });
        }, child: const Text('Accept and continue')),
      ]),
    ));
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    if (value == AppLifecycleState.resumed) unawaited(runAction(context, widget.state.afterLogin));
  }
  @override
  void dispose() { auth.cancel(); WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: widget.state, builder: (context, _) {
    final s = widget.state;
    return Scaffold(
      appBar: AppBar(title: Text(['Cloud','Feed','Explore','Channels','Profile'][selected]), actions: [
        IconButton(tooltip: 'Access and plans', icon: const Icon(Icons.workspace_premium, color: Colors.amber),
          onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => Plans(state: s)))),
      ]),
      body: [
        Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_outlined, size: 64), const Text('Your personal cloud'),
          Text('${s.status['used_bytes'] ?? 0} bytes used of ${s.status['quota_bytes'] ?? 0}'),
          const Padding(padding: EdgeInsets.all(20), child: Text('Cloud file upload is coming in the storage milestone.')),
        ])),
        ContentList(state: s, feed: true, key: const ValueKey('feed')),
        ContentList(state: s, key: const ValueKey('explore')),
        ChannelList(state: s),
        Profile(state: s),
      ][selected],
      bottomNavigationBar: NavigationBar(selectedIndex: selected, onDestinationSelected: (i) => setState(() => selected = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.cloud), label: 'Cloud'),
          NavigationDestination(icon: Icon(Icons.dynamic_feed), label: 'Feed'),
          NavigationDestination(icon: Icon(Icons.explore), label: 'Explore'),
          NavigationDestination(icon: Icon(Icons.groups), label: 'Channels'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
        ]),
    );
  });
}

class Policy extends StatelessWidget {
  const Policy({super.key, required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(name)), body: Padding(
    padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$name · v1', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 16),
      Text(switch(name) {
        'Privacy' => 'Vayora stores account details, install attribution, consent, uploaded content and payment records to provide the service. Contact help.vayora@gmail.com to request access or deletion.',
        'Refund' => 'Plans do not renew automatically. If a verified payment does not unlock your plan, contact help.vayora@gmail.com with your order reference. Refund requests are reviewed by support.',
        'Community rules' => 'Upload only content you have permission to share. Illegal, abusive or infringing content is prohibited. Report content from its post or channel page. User channels require review.',
        _ => 'Use Vayora lawfully and respect other users and creators. Paid access lasts for the selected plan duration. Payment access begins after verification. Contact help.vayora@gmail.com for assistance.',
      }),
      const SizedBox(height: 20), const Text('Contact: help.vayora@gmail.com'),
    ]),
  ));
}

class Login extends StatefulWidget {
  const Login({super.key, required this.state});
  final AppState state;
  @override
  State<Login> createState() => _LoginState();
}
class _LoginState extends State<Login> {
  final email = TextEditingController(), password = TextEditingController();
  bool create = false, busy = false;
  @override
  void dispose() { email.dispose(); password.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Your Vayora account')),
    body: ListView(padding: const EdgeInsets.all(24), children: [
      TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
      TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
      SwitchListTile(title: const Text('Create account from this guest'), value: create, onChanged: (v) => setState(() => create = v)),
      FilledButton(onPressed: busy ? null : () async {
        setState(() => busy = true);
        await runAction(context, () async {
          await widget.state.login(email.text.trim(), password.text, create: create);
          if (context.mounted && !widget.state.guest) Navigator.pop(context);
        });
        if (mounted) setState(() => busy = false);
      }, child: Text(create ? 'Create account' : 'Log in')),
      TextButton(onPressed: () => runAction(context, () => widget.state.google(linkGuest: create)),
        child: Text(create ? 'Link Google to guest account' : 'Log in with Google')),
      TextButton(onPressed: () => runAction(context, () async {
        await widget.state.db.auth.resetPasswordForEmail(email.text.trim(),
          redirectTo: 'com.vayora.app://login-callback');
      }), child: const Text('Send password reset email')),
      const Text('Creating an account preserves your guest ID. Check your email to confirm the address.'),
    ]));
}

class ContentList extends StatefulWidget {
  const ContentList({super.key, required this.state, this.feed = false, this.channel, this.creator});
  final AppState state;
  final bool feed;
  final String? channel, creator;
  @override
  State<ContentList> createState() => _ContentListState();
}
class _ContentListState extends State<ContentList> {
  late Future<List<Map<String, dynamic>>> data;
  @override
  void initState() { super.initState(); data = load(); }
  Future<List<Map<String, dynamic>>> load() async {
    List<String>? joined;
    if (widget.feed) {
      final memberships = await widget.state.db.from('channel_members').select('channel_id').eq('user_id', widget.state.userId);
      joined = memberships.map((r) => r['channel_id'] as String).toList();
      if (joined.isEmpty) return [];
    }
    var query = widget.state.db.from('posts').select('*,post_items(*)');
    if (widget.channel != null) query = query.eq('channel_id', widget.channel!);
    if (widget.creator != null) query = query.eq('created_by', widget.creator!);
    if (joined != null) query = query.inFilter('channel_id', joined);
    return query.order('created_at', ascending: false).limit(50);
  }
  @override
  Widget build(BuildContext context) => FutureBuilder(future: data, builder: (context, snap) {
    if (snap.hasError) return Center(child: TextButton(onPressed: () => setState(() => data = load()), child: const Text('Could not load posts. Retry')));
    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
    final rows = snap.data!.where((r) => !widget.state.blocked.contains(r['channel_id'])).toList();
    if (rows.isEmpty) return const Center(child: Text('No posts yet. Explore channels to get started.'));
    return RefreshIndicator(onRefresh: () async { setState(() => data = load()); await data; },
      child: ListView(children: rows.map((p) => Card(child: ListTile(
        leading: const Icon(Icons.play_circle_outline), title: Text(p['title'] as String),
        subtitle: Text(p['description'] as String),
        onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => PostPage(state: widget.state, post: p))),
      ))).toList()));
  });
}

class ChannelList extends StatefulWidget {
  const ChannelList({super.key, required this.state});
  final AppState state;
  @override
  State<ChannelList> createState() => _ChannelListState();
}
class _ChannelListState extends State<ChannelList> {
  late Future<List<Map<String, dynamic>>> rows;
  @override
  void initState() { super.initState(); reload(); }
  void reload() { rows = widget.state.db.from('channels').select().order('created_at', ascending: false).limit(100); }
  @override
  Widget build(BuildContext context) => FutureBuilder(future: rows, builder: (context, snap) {
    if (snap.hasError) return const Center(child: Text('Could not load channels.'));
    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
    final channels = snap.data!.where((c) => !widget.state.blocked.contains(c['id'])).toList();
    return ListView(children: [
      for (final c in channels) ListTile(title: Text(c['name'] as String), subtitle: Text(c['review_status'] as String),
        onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => Scaffold(
          appBar: AppBar(title: Text(c['name'] as String), actions: [
            IconButton(tooltip: 'Join channel', icon: const Icon(Icons.add), onPressed: () => runAction(context, () async {
              if (!await loginGate(context, widget.state)) return;
              await widget.state.db.from('channel_members').upsert({'user_id': widget.state.userId, 'channel_id': c['id']}, ignoreDuplicates: true);
            })),
            IconButton(tooltip: 'Leave channel', icon: const Icon(Icons.remove), onPressed: () => runAction(context, () async {
              await widget.state.db.from('channel_members').delete().eq('user_id', widget.state.userId).eq('channel_id', c['id']);
            })),
          ]), body: ContentList(state: widget.state, channel: c['id'] as String),
        )))),
      TextButton(onPressed: () async {
        if (!await loginGate(context, widget.state) || !context.mounted) return;
        final controller = TextEditingController();
        final name = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: const Text('Create channel'),
          content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Channel name')),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Submit for review'))]));
        controller.dispose();
        if (name != null && name.trim().isNotEmpty && context.mounted) {
          await runAction(context, () async {
            await widget.state.db.from('channels').insert({'name': name.trim(), 'created_by': widget.state.userId});
            setState(reload);
          });
        }
      }, child: const Text('Add channel · owner approval required')),
    ]);
  });
}

class PostPage extends StatelessWidget {
  const PostPage({super.key, required this.state, required this.post});
  final AppState state;
  final Map<String, dynamic> post;
  Future<void> play(BuildContext context, Map<String, dynamic> item, {bool trailer = false}) async {
    if (!trailer && !await loginGate(context, state)) return;
    if (!context.mounted) return;
    if (!trailer && item['is_premium'] == true && !state.premium) {
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
      final url = await state.db.storage.from('media').createSignedUrl(key, 3600);
      if (!context.mounted) return;
      await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => Watch(url: url, trailer: trailer, state: state)));
    });
  }
  @override
  Widget build(BuildContext context) {
    final items = List<Map<String, dynamic>>.from(post['post_items'] as List)
      ..sort((a,b) => (a['position'] as int).compareTo(b['position'] as int));
    return Scaffold(appBar: AppBar(title: const Text('Vayora')), body: ListView(padding: const EdgeInsets.all(20), children: [
      for (final i in items) ...[
        if (i['thumbnail_key'] != null) Image.network(state.db.storage.from('public').getPublicUrl(i['thumbnail_key'] as String),
          height: 220, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.movie, size: 100)),
        Text(post['title'] as String, style: Theme.of(context).textTheme.headlineMedium),
        if (i['is_premium'] == true) const Chip(label: Text('Premium'), avatar: Icon(Icons.workspace_premium, color: Colors.amber)),
        Text('${i['duration_s'] ?? 0} seconds · ${post['view_count']} views'),
        Text(post['description'] as String),
        Row(children: [
          if (state.adsAccess && i['trailer_key'] != null) OutlinedButton(onPressed: () => play(context,i,trailer:true), child: const Text('Trailer')),
          FilledButton(onPressed: () => play(context,i), child: const Text('Play')),
        ]),
        Wrap(spacing: 8, children: [
          TextButton(onPressed: () => runAction(context, () async {
            await const MethodChannel('app/share').invokeMethod<void>('share', {'text': 'Watch ${post['title']} on Vayora'});
          }), child: const Text('Share')),
          TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Channel')), body: ContentList(state: state, channel: post['channel_id'] as String)))),
            child: const Text('Channel')),
          TextButton(onPressed: () => runAction(context, () async {
            await state.db.rpc('report_content_in_app', params: {'post_id':post['id'],'channel_id':post['channel_id'],
              'reason':'Content review requested','details':''});
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted')));
          }), child: const Text('Report')),
          TextButton(onPressed: () => runAction(context, () async {
            if (!await loginGate(context,state) || !context.mounted) return;
            if (!state.premium) { await Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>Plans(state:state))); return; }
            final url = await state.db.storage.from('media').createSignedUrl(i['media_key'] as String,3600);
            await const MethodChannel('app/download').invokeMethod<void>('download',{'url':url,'name':'vayora-${i['id']}.mp4'});
          }), child: const Text('Download')),
        ]),
      ],
      TextButton(onPressed: () => runAction(context, () async {
        await state.block(post['channel_id'] as String);
        if (context.mounted) Navigator.pop(context);
      }), child: const Text('Block / unblock channel')),
      Text('More like this',style:Theme.of(context).textTheme.titleLarge),
      SizedBox(height:320,child:ContentList(state:state,creator:post['created_by'] as String)),
    ]));
  }
}

class Watch extends StatefulWidget {
  const Watch({super.key,required this.url,required this.trailer,required this.state});
  final String url;
  final bool trailer;
  final AppState state;
  @override
  State<Watch> createState()=>_WatchState();
}
class _WatchState extends State<Watch> {
  late final VideoPlayerController video;
  ChewieController? controls;
  bool ended=false;
  String? failure;
  int rotation=0;
  @override
  void initState(){super.initState();video=VideoPlayerController.networkUrl(Uri.parse(widget.url));unawaited(prepare());}
  Future<void> prepare() async {
    try {
      await video.initialize();
      if(!mounted)return;
      controls=ChewieController(videoPlayerController:video,autoPlay:true,looping:false);
      video.addListener(checkEnd);
      setState((){});
    } on Object { if(mounted)setState(()=>failure='Could not play this video.'); }
  }
  void checkEnd(){
    if(!widget.trailer||ended||!video.value.isInitialized)return;
    if(video.value.position>=video.value.duration && video.value.duration>Duration.zero){
      ended=true;
      unawaited(showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
        title:const Text('Enjoyed the trailer?'),content:const Text('Please subscribe to watch the full video'),
        actions:[TextButton(onPressed:()async{
          Navigator.pop(ctx);
          if(await loginGate(context,widget.state)&&mounted){
            await Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>Plans(state:widget.state)));
          }
        },child:const Text('Continue'))])));
    }
  }
  @override
  void dispose(){video.removeListener(checkEnd);controls?.dispose();video.dispose();
    unawaited(const MethodChannel('app/screen').invokeMethod<void>('rotation',{'mode':'auto'}));super.dispose();}
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(widget.trailer?'Trailer':'Now playing'),
    actions:[IconButton(tooltip:'Rotation',icon:const Icon(Icons.screen_rotation),onPressed:()async{
      rotation=(rotation+1)%3;
      await const MethodChannel('app/screen').invokeMethod<void>('rotation',{'mode':['auto','landscape','portrait'][rotation]});
    })]),body:Center(child:failure!=null?Text(failure!):controls==null?const CircularProgressIndicator():Chewie(controller:controls!)));
}

class Plans extends StatefulWidget {
  const Plans({super.key,required this.state});
  final AppState state;
  @override
  State<Plans> createState()=>_PlansState();
}
class _PlansState extends State<Plans> {
  late final Future<List<Map<String,dynamic>>> plans;
  @override
  void initState(){super.initState();plans=widget.state.db.from('plans').select().eq('active',true).order('position');}
  @override
  Widget build(BuildContext context)=>ListenableBuilder(listenable:widget.state,builder:(context,_){
    final s=widget.state;
    return Scaffold(appBar:AppBar(title:const Text('Access and plans')),body:ListView(padding:const EdgeInsets.all(20),children:[
      Text(s.status['plan_name']!=null?'Active: ${s.status['plan_name']} until ${s.status['plan_ends_at']}':'Free account'),
      Text('Cloud allowance: ${s.status['quota_bytes']??0} bytes'),
      Text('Full access: ${s.status['access_status']??'none'}'),
      if(!s.adsAccess) OutlinedButton(onPressed:()=>runAction(context,()async{
        if(await loginGate(context,s))await s.requestAccess();
      }),child:const Text('Request full access')),
      if(s.paidEnabled)...[
        const Text('Upgrade for 2 TB cloud storage and premium videos. No automatic renewal.'),
        FutureBuilder(future:plans,builder:(context,snap){
          if(snap.hasError)return const Text('Plans unavailable. Please try again later.');
          if(!snap.hasData)return const LinearProgressIndicator();
          return Column(children:snap.data!.map((p)=>Card(child:ListTile(
            title:Text('${p['name']} · ₹${p['price_inr']} / ${p['duration_days']} days'),
            subtitle:Text((p['perks'] as List).join(' · ')),
            trailing:const Icon(Icons.arrow_forward),
            onTap:()=>runAction(context,()async{
              if(!await loginGate(context,s)||!context.mounted)return;
              try { await s.pay(p['id'] as String); } finally {
                if(context.mounted)await Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>Payments(state:s)));
              }
            }),
          ))).toList());
        }),
        TextButton(onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>Payments(state:s))),child:const Text('Open orders and payment history')),
      ],
    ]));
  });
}

class Payments extends StatefulWidget {
  const Payments({super.key,required this.state});
  final AppState state;
  @override
  State<Payments> createState()=>_PaymentsState();
}
class _PaymentsState extends State<Payments> with WidgetsBindingObserver {
  Timer? poll;
  late Future<List<Map<String,dynamic>>> rows;
  int ticks=0;
  @override
  void initState(){super.initState();WidgetsBinding.instance.addObserver(this);reload();
    poll=Timer.periodic(const Duration(seconds:5),(_){if(++ticks>=120){poll?.cancel();} unawaited(runAction(context,refresh));});}
  void reload(){rows=widget.state.db.from('payment_orders').select('*,plans(name)').eq('user_id',widget.state.userId).order('created_at',ascending:false);}
  Future<void> refresh()async{await widget.state.retryPayments();if(mounted)setState(reload);}
  @override
  void didChangeAppLifecycleState(AppLifecycleState s){if(s==AppLifecycleState.resumed)unawaited(runAction(context,refresh));}
  @override
  void dispose(){poll?.cancel();WidgetsBinding.instance.removeObserver(this);super.dispose();}
  @override
  Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Payments')),body:FutureBuilder(future:rows,builder:(context,snap){
    if(snap.hasError)return const Center(child:Text('Could not load payments.'));
    if(!snap.hasData)return const Center(child:CircularProgressIndicator());
    return ListView(children:[
      const Padding(padding:EdgeInsets.all(16),child:Text('Payments stay pending until verified. Status refreshes every 5 seconds for 10 minutes.')),
      for(final o in snap.data!)ListTile(title:Text('${o['reference']} · ${o['status']}'),
        subtitle:Text('₹${(o['amount_paise'] as num)/100} · ${o['reason']??''}')),
    ]);
  }));
}

class Profile extends StatelessWidget {
  const Profile({super.key,required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(20),children:[
    Text(state.guest?'Guest account':state.db.auth.currentUser?.email??'Your account',style:Theme.of(context).textTheme.titleLarge),
    Text('Source: ${state.status['source']} · Plan: ${state.status['plan_name']??'Free'}'),
    if(state.guest)FilledButton(onPressed:()=>loginGate(context,state),child:const Text('Log in / create account')),
    if(!state.guest)TextButton(onPressed:()=>runAction(context,state.logout),child:const Text('Log out')),
    TextButton(onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>Payments(state:state))),child:const Text('Payment history')),
    for(final name in ['Privacy','Terms','Refund','Community rules'])TextButton(
      onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>Policy(name:name))),child:Text(name)),
    TextButton(onPressed:()=>launchUrl(Uri(scheme:'mailto',path:'help.vayora@gmail.com')),child:const Text('Contact support')),
    for(final id in state.blocked)ListTile(title:Text('Blocked channel $id'),trailing:TextButton(onPressed:()=>state.block(id),child:const Text('Unblock'))),
    if(!state.guest)TextButton(onPressed:()async{
      final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Delete your account?'),
        content:const Text('This permanently deletes your account and uploaded content. Payment records are retained.'),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
          TextButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Delete'))]));
      if(yes==true&&context.mounted)await runAction(context,()async{
        await state.db.functions.invoke('delete-account',body:{'confirm':true});
        await state.logout();
      });
    },child:const Text('Delete account')),
  ]);
}

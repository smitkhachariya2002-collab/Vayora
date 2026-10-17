import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_state.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'screens/home.dart';
export 'account_page.dart';
export 'channel_page.dart';
export 'navigation.dart';
export 'screens/home.dart';
export 'screens/content.dart';
export 'screens/post.dart';
export 'screens/player.dart';
export 'screens/premium.dart';
export 'screens/payments.dart';
export 'screens/cloud.dart';
export 'screens/profile.dart';
export 'screens/policies.dart';

Future<void> main()async{
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSize=AppSizes.imageCacheCount;
  PaintingBinding.instance.imageCache.maximumSizeBytes=AppSizes.imageCacheBytes;
  if(backendKey.isEmpty){
    runApp(MaterialApp(theme:buildTheme(),home:const AppPage(body:EmptyState(icon:Icons.cloud_off_outlined,
      title:'Vayora is getting ready',message:'Please install the latest app update and try again.'))));
    return;
  }
  await Supabase.initialize(url:backendUrl,anonKey:backendKey);
  final state=AppState(Supabase.instance.client,await SharedPreferences.getInstance());
  runApp(Vayora(state:state));
}
class Vayora extends StatelessWidget{
  const Vayora({super.key,required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context)=>MaterialApp(title:AppBrand.name,debugShowCheckedModeBanner:false,
    theme:buildTheme(),home:Startup(state:state));
}
class Startup extends StatefulWidget{
  const Startup({super.key,required this.state});
  final AppState state;
  @override
  State<Startup> createState()=>_StartupState();
}
class _StartupState extends State<Startup>{
  late Future<void> startup;
  @override
  void initState(){super.initState();startup=widget.state.initialize();}
  @override
  Widget build(BuildContext context)=>FutureBuilder(future:startup,builder:(context,snapshot){
    if(snapshot.hasError)return AppPage(body:ErrorRetry(onRetry:()=>setState(()=>startup=widget.state.initialize())));
    if(snapshot.connectionState!=ConnectionState.done){return const AppPage(body:Center(child:Column(
      mainAxisSize:MainAxisSize.min,children:[GlowHeader(child:BrandMark(large:true)),SizedBox(height:Gap.xl),
        Text(AppBrand.name),SizedBox(height:Gap.xl),Padding(padding:Gap.page,child:LinearProgressIndicator())])));}
    return Home(state:widget.state);
  });
}

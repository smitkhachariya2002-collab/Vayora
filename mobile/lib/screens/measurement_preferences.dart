import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config.dart';
import '../services/measurement.dart';
class MeasurementPreferences extends StatefulWidget {
 const MeasurementPreferences({super.key});
 @override State<MeasurementPreferences> createState()=>_MeasurementPreferencesState();
}
class _MeasurementPreferencesState extends State<MeasurementPreferences>{
 final m=Measurement.instance;late bool usage=m.analytics,ads=m.advertising;bool saving=false;String? error;
 Future<void> save(bool a,bool b)async{setState((){saving=true;error=null;});try{await m.save(a,b);if(mounted)Navigator.pop(context);}catch(_){if(mounted)setState((){saving=false;error='Could not save your choice. Please try again.';});}}
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Measurement preferences')),body:ListView(padding:const EdgeInsets.all(20),children:[
 const Icon(Icons.privacy_tip_outlined,size:42),const SizedBox(height:16),
 const Text('Your choice, your privacy',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
 const SizedBox(height:12),const Text('These choices are optional. Your account, plan, storage, playback and payment flow work the same when all optional choices are off.'),
 SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('App analytics'),subtitle:const Text('Share basic app activity with Vayora to understand use, sessions and returning users.'),value:usage,onChanged:saving?null:(v)=>setState(()=>usage=v)),
 SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Advertising measurement with Meta'),subtitle:const Text('Share app activity and verified purchases with Meta for ad measurement and optimisation. This includes hashed account details, a random install ID, IP address and basic device information. No advertising ID, passwords, search text or private files are shared.'),value:ads,onChanged:saving?null:(v)=>setState(()=>ads=v)),
 const Text('Change this anytime in Account. Turning sharing off stops future events and cancels unsent advertising events. It cannot recall events Meta has already received.'),
 TextButton(onPressed:()=>launchUrl(Uri.parse('${Config.websiteUrl}/privacy'),mode:LaunchMode.externalApplication),child:const Text('Read privacy policy')),
 if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
 FilledButton(onPressed:saving?null:()=>save(usage,ads),child:Text(saving?'Saving…':'Save choices')),
 OutlinedButton(onPressed:saving?null:()=>save(false,false),child:const Text('Essential only')),
 ]));
}


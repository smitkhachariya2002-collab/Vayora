import 'package:flutter/material.dart';
import '../app_state.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'premium.dart';

class StorageMeter extends StatelessWidget {
  const StorageMeter({super.key,required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context){
    final used=(state.status['used_bytes'] as num? ?? 0).toDouble();
    final total=(state.status['quota_bytes'] as num? ?? 0).toDouble();
    return Card(child:Padding(padding:Gap.page,child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Row(children:[Icon(Icons.cloud_upload_outlined,color:AppColors.primary),SizedBox(width:Gap.s),Text('Your cloud space')]),
      const SizedBox(height:Gap.xl),
      Text(storageLabel(used),style:Theme.of(context).textTheme.headlineMedium),
      Text('of ${storageLabel(total)} used',style:Theme.of(context).textTheme.bodySmall),
      const SizedBox(height:Gap.l),
      ClipRRect(borderRadius:Radii.chipRadius,child:LinearProgressIndicator(
        minHeight:AppSizes.progress,value:total>0?(used/total).clamp(0.0,1.0).toDouble():0)),
      const SizedBox(height:Gap.s),
      Text(total>0?'${storageLabel((total-used).clamp(0,total))} available':'Choose the access that works for you.',
        style:Theme.of(context).textTheme.bodySmall),
    ])));
  }
}
Future<void> showCloudActions(BuildContext context,AppState state)async{
  if(!await loginGate(context,state)||!context.mounted)return;
  await showModalBottomSheet<void>(context:context,showDragHandle:true,builder:(sheet)=>SafeArea(child:Padding(padding:Gap.page,
    child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('Your cloud',style:Theme.of(sheet).textTheme.titleLarge),
      const SizedBox(height:Gap.s),const Text('File uploads and folders aren’t available in this build yet.'),
      const SizedBox(height:Gap.l),
      const ListTile(enabled:false,leading:Icon(Icons.upload_file_outlined),title:Text('Upload file'),subtitle:Text('Coming soon')),
      const ListTile(enabled:false,leading:Icon(Icons.create_new_folder_outlined),title:Text('New folder'),subtitle:Text('Coming soon')),
      const SizedBox(height:Gap.l),SizedBox(width:double.infinity,
        child:OutlinedButton(onPressed:()=>Navigator.pop(sheet),child:const Text('Done'))),
    ]))));
}
class CloudView extends StatelessWidget {
  const CloudView({super.key,required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context){
    final available=!state.guest&&(state.status['quota_bytes'] as num? ?? 0)>0;
    return RefreshIndicator(onRefresh:state.refreshStatus,child:PageWidth(child:ListView(
      key:const PageStorageKey('cloud-scroll'),physics:const AlwaysScrollableScrollPhysics(),padding:Gap.page,children:[
        StorageMeter(state:state),const SizedBox(height:Gap.xl),
        if(!available)EmptyState(icon:state.paidEnabled?Icons.workspace_premium_outlined:Icons.cloud_outlined,
          title:state.paidEnabled?'Space for everything you love':'Your free cloud awaits',
          message:state.paidEnabled?'Get 2 TB with Premium.':'Log in for 15 GB free.',
          actionLabel:state.paidEnabled?'Get Premium':'Log in',onAction:()async{
            if(!await loginGate(context,state)||!context.mounted)return;
            if(state.paidEnabled)await Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>Plans(state:state)));
          })
        else...[
          const SectionTitle('Your files'),const SizedBox(height:Gap.l),
          const EmptyState(icon:Icons.folder_open_rounded,title:'A little room for your world',
            message:'File uploads and folders aren’t available in this build yet. Your storage allowance is ready.'),
          OutlinedButton.icon(onPressed:()=>showCloudActions(context,state),icon:const Icon(Icons.add),label:const Text('Cloud options')),
        ],
        const SizedBox(height:Gap.hero),
      ])));
  }
}

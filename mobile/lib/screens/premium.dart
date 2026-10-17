import 'package:flutter/material.dart';
import '../app_state.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'cloud.dart';
import 'payments.dart';

class Plans extends StatefulWidget {
  const Plans({super.key,required this.state});
  final AppState state;
  @override
  State<Plans> createState()=>_PlansState();
}
class _PlansState extends State<Plans> {
  late Future<List<Map<String,dynamic>>> plans,openOrders;
  String? selected;
  bool busy=false;
  @override
  void initState(){super.initState();reload();widget.state.addListener(reload);}
  void reload(){
    plans=widget.state.db.from('plans').select().eq('active',true).order('position');
    openOrders=widget.state.db.from('payment_orders').select().eq('user_id',widget.state.userId).inFilter('status',['created','pending']);
  }
  Future<void> refresh()async{await widget.state.refreshStatus();if(mounted)setState(reload);await Future.wait([plans,openOrders]);}
  @override
  void dispose(){widget.state.removeListener(reload);super.dispose();}
  Future<void> pay(String id)async{
    if(busy)return;
    if(!await loginGate(context,widget.state)||!mounted)return;
    setState(()=>busy=true);
    await runAction(context,()async{
      try{await widget.state.pay(id);}finally{
        if(mounted)await Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>Payments(state:widget.state,showLatest:true)));
      }
    });
    if(mounted)setState(()=>busy=false);
  }
  Widget freeAccount(){
    final state=widget.state;
    return RefreshIndicator(onRefresh:refresh,child:PageWidth(form:true,child:ListView(
      physics:const AlwaysScrollableScrollPhysics(),padding:Gap.page,children:[
        const GlowHeader(child:Center(child:Icon(Icons.cloud_done_outlined,size:AppSizes.emptyIcon,color:AppColors.primary))),
        Text('Free account',style:Theme.of(context).textTheme.headlineSmall),const SizedBox(height:Gap.s),
        Text('A little more space for your world.',style:Theme.of(context).textTheme.bodySmall),
        const SizedBox(height:Gap.xl),StorageMeter(state:state),
        const SizedBox(height:Gap.xl),
        NoticeCard(title:state.adsAccess?'Full access':state.status['access_status']=='pending'?'Request received':'Your access',
          message:state.adsAccess?'Your account can enjoy the available full videos.':
            state.status['access_status']=='pending'?'You’ll see an update here when your request is reviewed.':'Request full access to explore more.'),
        const SizedBox(height:Gap.xl),
        if(!state.adsAccess)GradientButton(label:'Request full access',onPressed:()=>runAction(context,()async{
          if(await loginGate(context,state)){await state.requestAccess();if(mounted)showFeedback(context,'Your request was sent.');}
        })),
        const SizedBox(height:Gap.xl),
      ])));
  }
  @override
  Widget build(BuildContext context)=>ListenableBuilder(listenable:widget.state,builder:(context,_){
    final state=widget.state;
    if(!state.paidEnabled)return AppPage(title:'Your account',body:freeAccount());
    return FutureBuilder(future:plans,builder:(context,snapshot){
      final rows=snapshot.data??<Map<String,dynamic>>[];
      final chosen=rows.where((row)=>row['id']==selected).toList();
      final plan=chosen.isNotEmpty?chosen.first:rows.isNotEmpty?rows.first:null;
      return AppPage(title:'Premium',navigation:SafeArea(top:false,child:Container(
        padding:Gap.page,decoration:const BoxDecoration(color:AppColors.surface,border:Border(top:BorderSide(color:AppColors.border))),
        child:PageWidth(form:true,child:GradientButton(label:'Continue to payment',icon:Icons.arrow_forward,busy:busy,
          onPressed:plan==null||busy?null:()=>pay(plan['id'] as String))))),
        body:RefreshIndicator(onRefresh:refresh,child:PageWidth(form:true,child:ListView(
          physics:const AlwaysScrollableScrollPhysics(),padding:Gap.page,children:[
            if(state.status['plan_name']!=null)...[NoticeCard(title:'${state.status['plan_name']} is active',
              message:'Until ${shortDate(state.status['plan_ends_at'] as String?)}',tone:NoticeTone.success),const SizedBox(height:Gap.l)],
            FutureBuilder(future:openOrders,builder:(context,orders)=>orders.hasData&&orders.data!.isNotEmpty?
              Padding(padding:const EdgeInsets.only(bottom:Gap.l),child:NoticeCard(title:'Payment pending — tap to check',
                message:'Your existing order is waiting for verification.',tone:NoticeTone.warning,onTap:()=>Navigator.push(context,
                  MaterialPageRoute<void>(builder:(_)=>Payments(state:state,showLatest:true))))):const SizedBox.shrink()),
            const PremiumHero(),const SizedBox(height:Gap.xl),
            const SectionTitle('Choose your plan'),const SizedBox(height:Gap.l),
            if(snapshot.hasError)ErrorRetry(onRetry:()=>setState(reload))
            else if(!snapshot.hasData)const SkeletonList()
            else if(rows.isEmpty)const EmptyState(icon:Icons.workspace_premium_outlined,title:'Plans are taking a break',
              message:'Please check again soon.')
            else for(final row in rows)Padding(padding:const EdgeInsets.only(bottom:Gap.l),child:PlanCard(
              plan:row,selected:row['id']==plan?['id'],onTap:busy?null:()=>setState(()=>selected=row['id'] as String))),
            const SizedBox(height:Gap.s),
            Text('One-time payment. No automatic renewal.',style:Theme.of(context).textTheme.bodySmall,textAlign:TextAlign.center),
            TextButton(onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>Payments(state:state))),
              child:const Text('Payment history')),
            const SizedBox(height:Gap.xl),
          ]))));
    });
  });
}
class PremiumHero extends StatelessWidget {
  const PremiumHero({super.key});
  @override
  Widget build(BuildContext context)=>Container(padding:Gap.page,
    decoration:const BoxDecoration(gradient:AppColors.gradient,borderRadius:Radii.cardRadius),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const CrownIcon(color:AppColors.ink,size:AppSizes.dialogIcon),const SizedBox(height:Gap.l),
      Text('Go Premium',style:Theme.of(context).textTheme.headlineMedium?.copyWith(color:AppColors.ink)),
      const SizedBox(height:Gap.s),Text('More room. More stories. More you.',style:Theme.of(context).textTheme.bodyLarge?.copyWith(color:AppColors.ink)),
      const SizedBox(height:Gap.xl),
      for(final perk in const ['2 TB cloud allowance','Full premium videos','Fast downloads'])Padding(
        padding:const EdgeInsets.only(bottom:Gap.s),child:Row(children:[const Icon(Icons.check_circle_outline,color:AppColors.ink),
          const SizedBox(width:Gap.s),Expanded(child:Text(perk,style:Theme.of(context).textTheme.bodyLarge?.copyWith(color:AppColors.ink)))])),
    ]));
}
class PlanCard extends StatelessWidget {
  const PlanCard({super.key,required this.plan,required this.selected,required this.onTap});
  final Map<String,dynamic> plan;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context)=>PressScale(onTap:onTap,child:Container(padding:Gap.page,
    decoration:BoxDecoration(color:AppColors.surface,borderRadius:Radii.cardRadius,border:Border.all(
      color:selected?AppColors.primary:AppColors.border,width:selected?AppSizes.focusStroke:AppSizes.stroke)),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Wrap(spacing:Gap.m,runSpacing:Gap.s,crossAxisAlignment:WrapCrossAlignment.center,children:[
        Text(plan['name'] as String,style:Theme.of(context).textTheme.titleLarge),
        if((plan['name'] as String).toLowerCase().contains('gold'))const StatusPill('Best value',tone:NoticeTone.warning),
        if(selected)const Icon(Icons.check_circle,color:AppColors.primary),
      ]),
      const SizedBox(height:Gap.l),
      Text('₹${plan['price_inr']}',style:Theme.of(context).textTheme.headlineMedium),
      Text('for ${plan['duration_days']} days',style:Theme.of(context).textTheme.bodySmall),
      const SizedBox(height:Gap.l),
      for(final perk in (plan['perks'] as List? ?? []))Padding(padding:const EdgeInsets.only(bottom:Gap.s),child:Row(
        crossAxisAlignment:CrossAxisAlignment.start,children:[const Icon(Icons.check,size:AppSizes.iconSmall,color:AppColors.success),
          const SizedBox(width:Gap.s),Expanded(child:Text(perk.toString(),style:Theme.of(context).textTheme.bodySmall))])),
    ])));
}

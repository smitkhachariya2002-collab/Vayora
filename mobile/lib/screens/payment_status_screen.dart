import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import '../config.dart';

import 'package:flutter/material.dart';

import '../services/app_scope.dart';
import '../services/app_state.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'login_sheet.dart';

class PaymentStatusScreen extends StatefulWidget {
  const PaymentStatusScreen({super.key, required this.orderId});
  final String orderId;
  @override
  State<PaymentStatusScreen> createState() => _PaymentStatusScreenState();
}

class _PaymentStatusScreenState extends State<PaymentStatusScreen> {
  Map<String, dynamic>? _o;
  Timer? _t;
  AppState? _app;
  int _ticks = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_app == null) {
      _app = AppScope.of(context);
      _check();
      _t = Timer.periodic(const Duration(seconds: 2), (_) => _check());
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    final app = _app;
    if (app == null) return;
    _ticks++;
    try {
      // Re-send a stored result if the first report did not reach the server.
      if (_ticks % 5 == 1) await app.flushPending();
      final o = await app.orderStatus(widget.orderId);
      if (!mounted) return;
      setState(() => _o = o);
      final st = o?['status'];
      if (st == 'paid') { _t?.cancel(); app.refresh(); }
      if (st == 'failed' || st == 'cancelled' || st == 'rejected') _t?.cancel();
    } catch (_) {/* try again on the next tick */}
  }

  Future<void> _enterUtr() async {
    final input=TextEditingController();
    final value=await showDialog<String>(context:context,builder:(c)=>AlertDialog(title:const Text('I’ve paid - enter UTR'),content:TextField(controller:input,keyboardType:TextInputType.number,maxLength:12,decoration:const InputDecoration(labelText:'12-digit bank reference',helperText:'Find it in your UPI app payment details.')),actions:[TextButton(onPressed:()=>Navigator.pop(c),child:const Text('Cancel')),FilledButton(onPressed:(){if(RegExp(r'^[0-9]{12}$').hasMatch(input.text.trim()))Navigator.pop(c,input.text.trim());},child:const Text('Submit'))]));
    input.dispose();if(value==null)return;
    try {await sb.rpc('submit_payment_utr',params:{'p_order':widget.orderId,'p_utr':value});await _check();if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Reference saved for review.')));}
    catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not save the reference. Please retry.')));}
  }

  @override
  Widget build(BuildContext context) {
    final st = (_o?['status'] as String?) ?? 'pending';
    late final IconData icon; late final Color color; late final String text;
    switch (st) {
      case 'paid':
        icon = Icons.check_circle; color = Tokens.success; text = 'Payment successful! Your plan is now active.';
      case 'review':
        icon = Icons.hourglass_top; color = Tokens.warning; text = 'Payment received, being verified';
      case 'failed':
      case 'cancelled':
      case 'rejected':
        icon = Icons.error; color = Tokens.danger; text = 'Payment not completed';
      default:
        icon = Icons.sync; color = Tokens.muted; text = 'Waiting for confirmation…';
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Payment')),
      body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 72, color: color),
        const SizedBox(height: 16),
        Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        if (_o?['reference'] != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Ref ${_o!['reference']}', style: const TextStyle(color: Tokens.muted))),
        if (st == 'paid' && (_app?.status.isGuest ?? false)) ...[
          const SizedBox(height: 16),
          const Text('Add your email so you never lose this plan if you change phone or reinstall.', textAlign: TextAlign.center, style: TextStyle(color: Tokens.muted, fontSize: 13)),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: () => showLoginSheet(context, signup: true, saveMode: true), child: const Text('Add email & password')),
        ],
        const SizedBox(height: 16),
        if(!['paid','revoked'].contains(st))OutlinedButton(onPressed:_enterUtr,child:const Text('I’ve paid - enter UTR')),
        TextButton(onPressed:()=>launchUrl(Uri(scheme:'mailto',path:Config.supportEmail,queryParameters:{'subject':'Payment help - ${_o?['reference']??widget.orderId}'})),child:const Text('Get help')),
        const SizedBox(height: 24),
        if (st == 'failed' || st == 'cancelled' || st == 'rejected')
          GradientButton(label: 'Try again', onPressed: () => Navigator.pop(context))
        else if (st == 'pending')
          OutlinedButton(onPressed: _check, child: const Text('Check again'))
        else
          GradientButton(label: 'Done', onPressed: () => Navigator.pop(context)),
      ]))),
    );
  }
}

class PaymentHistoryScreen extends StatelessWidget {
  const PaymentHistoryScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Payment history')),
        body: FutureBuilder(
          future: sb.from('payment_orders').select('id,reference,plan_name,amount_paise,status,created_at').order('created_at', ascending: false),
          builder: (c, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final rows = List<Map<String, dynamic>>.from(snap.data as List);
            if (rows.isEmpty) return const Center(child: EmptyState(icon: Icons.receipt_long_outlined, title: 'No payments yet', message: 'Plans you buy will be listed here.'));
            return ListView(children: [
              for (final r in rows)
                ListTile(
                  title: Text('${r['plan_name']} · ₹${((r['amount_paise'] as num) / 100).toStringAsFixed(0)}'),
                  subtitle: Text('${r['reference']} · ${r['status']}'),
                  onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => PaymentStatusScreen(orderId: r['id'] as String))),
                ),
            ]);
          },
        ),
      );
}

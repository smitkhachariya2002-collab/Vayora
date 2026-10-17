import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_state.dart';
import '../widgets/common.dart';

/// UI orchestration only; order creation, UPI launch and durable reporting stay in AppState.
Future<Map<String, dynamic>?> launchPlanPayment(BuildContext context, AppState state, String planId) async {
  try {
    final previous = await state.db.from('payment_orders').select('id')
      .eq('user_id', state.userId).eq('plan_id', planId).order('created_at', ascending: false).limit(1);
    await state.pay(planId);
    final latest = await state.db.from('payment_orders').select('*,plans(name)')
      .eq('user_id', state.userId).eq('plan_id', planId).order('created_at', ascending: false).limit(1);
    if (latest.isEmpty || (previous.isNotEmpty && previous.first['id'] == latest.first['id'])) return null;
    if (latest.first['status'] == 'cancelled') return null;
    return latest.first;
  } on PlatformException catch (error) {
    if (!context.mounted) return null;
    if (error.code == 'no_upi') {
      await showDialog<void>(context: context, builder: (dialog) => AlertDialog(
        title: const Text('No UPI app found'),
        content: const Text('Install a UPI app, then return to choose your plan.'),
        actions: [TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('OK'))]));
    } else { showFeedback(context, 'Could not open payment. Please try again.'); }
  } on Object {
    if (context.mounted) showFeedback(context, 'Could not start payment. Check your payment history before trying again.');
  }
  return null;
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_state.dart';
import '../widgets/common.dart';

/// UI orchestration only; order creation, UPI launch and durable reporting stay in AppState.
Future<Map<String, dynamic>?> launchPlanPayment(
  BuildContext context,
  AppState state,
  String planId, {
  num? displayedPrice,
}) async {
  try {
    final id = playStore
        ? await state.payPlay(
            planId,
            chooseBillingState: () => billingStateDialog(context),
          )
        : await state.pay(
            planId,
            beforeLaunch: (amountPaise) async {
              if (displayedPrice != null &&
                  (displayedPrice * 100).round() != amountPaise &&
                  context.mounted) {
                final amount = amountPaise / 100;
                await showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (dialog) => PopScope(
                    canPop: false,
                    child: AlertDialog(
                      title: Text(
                        'Price updated to ₹${amount.toStringAsFixed(amount == amount.roundToDouble() ? 0 : 2)}',
                      ),
                      content: const Text(
                        'The plan price changed. This payment uses the current price.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialog),
                          child: const Text('Continue'),
                        ),
                      ],
                    ),
                  ),
                );
              }
            },
          );
    if (id == null) {
      if (context.mounted && state.premium) {
        showFeedback(context, 'Payment successful! Your plan is now active.');
      }
      return null;
    }
    final order = await state.db
        .from('payment_orders')
        .select('*,plans(name)')
        .eq('user_id', state.userId)
        .eq('id', id)
        .single();
    if ((order['raw_response'] as String? ?? '').contains('no_upi_app') &&
        context.mounted) {
      final upiId = state.paymentUpiId(id);
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('No UPI app found'),
            content: Text(
              'You can pay this UPI ID from another device, then enter the 12-digit UTR on the payment screen.\n\n${upiId ?? 'Return to your plan and try again to load the UPI ID.'}',
            ),
            actions: [
              if (upiId != null)
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: upiId));
                  },
                  child: const Text('Copy UPI ID'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Continue'),
              ),
            ],
          ),
        );
      }
    }
    return order;
  } on PlatformException catch (error) {
    if (!context.mounted) return null;
    if (error.code == 'no_upi') {
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('No UPI app found'),
          content: const Text(
            'Install a UPI app, then return to choose your plan.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } else {
      showFeedback(context, 'Could not open payment. Please try again.');
    }
  } on Object {
    if (context.mounted) {
      showFeedback(
        context,
        'Could not start payment. Check your payment history before trying again.',
      );
    }
  }
  return null;
}

const indianBillingStates = [
  'ANDAMAN AND NICOBAR ISLANDS',
  'ANDHRA PRADESH',
  'ARUNACHAL PRADESH',
  'ASSAM',
  'BIHAR',
  'CHANDIGARH',
  'CHHATTISGARH',
  'DADRA AND NAGAR HAVELI AND DAMAN AND DIU',
  'DELHI',
  'GOA',
  'GUJARAT',
  'HARYANA',
  'HIMACHAL PRADESH',
  'JAMMU AND KASHMIR',
  'JHARKHAND',
  'KARNATAKA',
  'KERALA',
  'LADAKH',
  'LAKSHADWEEP',
  'MADHYA PRADESH',
  'MAHARASHTRA',
  'MANIPUR',
  'MEGHALAYA',
  'MIZORAM',
  'NAGALAND',
  'ODISHA',
  'PUDUCHERRY',
  'PUNJAB',
  'RAJASTHAN',
  'SIKKIM',
  'TAMIL NADU',
  'TELANGANA',
  'TRIPURA',
  'UTTAR PRADESH',
  'UTTARAKHAND',
  'WEST BENGAL',
];
Future<String?> billingStateDialog(BuildContext context) async {
  String? selected;
  return showDialog<String>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, update) => AlertDialog(
        title: const Text('Your billing state'),
        content: DropdownButtonFormField<String>(
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'State or union territory',
          ),
          items: indianBillingStates
              .map(
                (s) => DropdownMenuItem(value: s, child: Text(s, maxLines: 2)),
              )
              .toList(),
          onChanged: (s) => update(() => selected = s),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: selected == null
                ? null
                : () => Navigator.pop(dialog, selected),
            child: const Text('Continue'),
          ),
        ],
      ),
    ),
  );
}

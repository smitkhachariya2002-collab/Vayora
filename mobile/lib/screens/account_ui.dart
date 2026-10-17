import 'package:flutter/material.dart';
import '../app_state.dart';
import '../account_page.dart';
import '../theme.dart';
import '../widgets/common.dart';

String profileName(Map<String, dynamic> status, String id) {
  final value = (status['display_name'] as String? ?? '').trim();
  return value.isEmpty ? 'User-${id.substring(0, id.length < 8 ? id.length : 8)}' : value;
}
String premiumButtonLabel({required bool selected, required bool guest, required bool busy}) =>
    busy ? 'Opening UPI…' : !selected ? 'Select a plan' : guest ? 'Next' : 'Continue to payment';

enum PremiumBannerKind { active, pending, none }
PremiumBannerKind premiumBanner(Map<String, dynamic> status, List<Map<String, dynamic>> orders) =>
    status['plan_name'] != null && status['is_premium'] == true
    ? PremiumBannerKind.active : orders.isNotEmpty ? PremiumBannerKind.pending : PremiumBannerKind.none;

const warmProfileGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
  colors: [Color(0xFFFF7A1A), Color(0xFF8A2D05), Color(0xFF2A1408)]);

Future<bool> accountLoginDialog(BuildContext context, AppState state, {String? plan, bool channel = false}) async {
  if (!state.guest) return true;
  final yes = await showDialog<bool>(context: context, builder: (dialog) => AlertDialog(
    title: const Text('Please log in'),
    content: Text(channel ? 'Log in to create a channel' : plan != null ? 'Please log in to buy $plan.' : 'Log in to continue.'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Not now')),
      FilledButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Log in')),
    ])) ?? false;
  if (!yes || !context.mounted) return false;
  await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => Login(state: state)));
  return !state.guest;
}

class DetailRow extends StatelessWidget {
  const DetailRow(this.label, this.value, {super.key, this.selectable = false});
  final String label, value;
  final bool selectable;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: Gap.s),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: Gap.xs),
      if (selectable) SelectableText(value) else Text(value),
    ]));
}

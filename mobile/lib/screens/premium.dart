import 'package:flutter/material.dart';
import '../app_state.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'account_ui.dart';
import 'cloud.dart';
import 'payment_flow.dart';
import 'payments.dart';
import 'profile.dart';

class Plans extends StatefulWidget {
  const Plans({super.key, required this.state});
  final AppState state;
  @override
  State<Plans> createState() => _PlansState();
}
class _PlansState extends State<Plans> {
  late Future<List<Map<String, dynamic>>> plans, openOrders;
  String? selected;
  bool busy = false;
  @override
  void initState() { super.initState(); reload(); widget.state.addListener(changed); }
  void changed() { if (mounted) setState(reload); }
  void reload() {
    if (!widget.state.paidEnabled) {
      plans = Future.value([]); openOrders = Future.value([]); return;
    }
    plans = widget.state.db.from('plans').select().eq('active', true).order('position');
    openOrders = widget.state.guest ? Future.value([]) : widget.state.db.from('payment_orders').select('*,plans(name)')
      .eq('user_id', widget.state.userId).inFilter('status', ['initiated', 'pending']).order('created_at', ascending: false);
  }
  Future<void> refresh() async {
    await widget.state.refreshStatus();
    if (mounted) setState(reload);
    await Future.wait([plans, openOrders]);
  }
  @override
  void dispose() { widget.state.removeListener(changed); super.dispose(); }
  Future<void> pay(Map<String, dynamic> plan) async {
    if (busy) return;
    if (!await accountLoginDialog(context, widget.state, plan: plan['name'] as String) || !mounted) return;
    if (!await loginGate(context, widget.state) || !mounted) return;
    await widget.state.refreshStatus();
    if (!mounted || !widget.state.paidEnabled) return;
    setState(() => busy = true);
    try {
      final order = await launchPlanPayment(context, widget.state, plan['id'] as String);
      if (order != null && mounted) { await Navigator.push(context, MaterialPageRoute<void>(
        builder: (_) => Payments(state: widget.state, orderId: order['id'] as String))); }
      if (mounted) await refresh();
    } finally { if (mounted) setState(() => busy = false); }
  }
  Widget freeAccount({required bool freeMode}) {
    final state = widget.state, status = widget.state.status['access_status'];
    final granted = !state.guest && state.adsAccess;
    final pending = status == 'pending', rejected = status == 'rejected';
    return RefreshIndicator(onRefresh: refresh, child: PageWidth(form: true, child: ListView(
      physics: const AlwaysScrollableScrollPhysics(), padding: Gap.page, children: [
        const GlowHeader(child: Center(child: Icon(Icons.cloud_done_outlined, size: 64, color: AppColors.primary))),
        Card(child: Padding(padding: Gap.page, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(freeMode ? '${AppBrand.name} is free' : 'Free account', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Text(state.guest ? (freeMode ? 'Log in to get 15 GB of free cloud storage for your photos, videos and files.' : 'Log in to manage your account.') :
            (state.status['quota_bytes'] as num? ?? 0) > 0 ? 'Your allowance is ${storageLabel(state.status['quota_bytes'] as num?)}.' : 'Get 2 TB with Premium'),
          if (!state.guest) ...[const SizedBox(height: 16), StorageMeter(state: state)],
          if (state.guest) ...[const SizedBox(height: 16), GradientButton(label: 'Log in', onPressed: () => loginGate(context, state))],
          if (freeMode) ...[
            const SizedBox(height: 24),
            NoticeCard(title: granted ? 'Full access' : pending ? 'Request received' : rejected ? 'Not approved' : 'Your access',
              message: granted ? 'Full access: all videos and downloads are unlocked.' :
                pending ? 'Your request for full access is being reviewed.' :
                rejected ? 'Full access was not approved for this account.' : 'Some videos and downloads need approval from our team.',
              tone: granted ? NoticeTone.success : pending ? NoticeTone.warning : rejected ? NoticeTone.danger : NoticeTone.neutral),
            if (!state.adsAccess && !pending) ...[
              const SizedBox(height: 16),
              GradientButton(label: 'Request full access', onPressed: () => runAction(context, () async {
                if (await loginGate(context, state)) await state.requestAccess();
              })),
            ],
          ],
        ]))),
      ])));
  }
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: widget.state, builder: (context, _) {
    final state = widget.state;
    final actions = [IconButton(tooltip: 'Profile', icon: const Icon(Icons.account_circle_outlined),
      onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => AppPage(body: Profile(state: state)))))];
    if (!state.paidEnabled) return AppPage(title: 'Premium', actions: actions, body: freeAccount(freeMode: true));
    return FutureBuilder<List<Map<String, dynamic>>>(future: plans, builder: (context, snapshot) {
      if (snapshot.hasData && snapshot.data!.isEmpty) return AppPage(title: 'Premium', actions: actions, body: freeAccount(freeMode: false));
      final rows = snapshot.data ?? <Map<String, dynamic>>[];
      final matches = rows.where((p) => p['id'] == selected);
      final plan = matches.isEmpty ? null : matches.first;
      final perks = (plan?['perks'] ?? (rows.isEmpty ? null : rows.first['perks'])) as List?;
      return AppPage(title: 'Premium', actions: actions,
        navigation: SafeArea(top: false, child: Container(padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(color: AppColors.surface, border: Border(top: BorderSide(color: AppColors.border))),
          child: PageWidth(form: true, child: GradientButton(
            label: premiumButtonLabel(selected: plan != null, guest: state.guest, busy: busy),
            icon: Icons.arrow_forward, busy: busy,
            onPressed: busy || plan == null ? null : () => pay(plan))))),
        body: RefreshIndicator(onRefresh: refresh, child: PageWidth(form: true, child: ListView(
          physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
            FutureBuilder<List<Map<String, dynamic>>>(future: openOrders, builder: (context, snapshot) {
              final orders = snapshot.data ?? [];
              final banner = premiumBanner(state.status, orders);
              if (banner == PremiumBannerKind.none) return const SizedBox.shrink();
              final active = banner == PremiumBannerKind.active;
              final order = orders.isEmpty ? null : orders.first;
              return Padding(padding: const EdgeInsets.only(bottom: 16), child: NoticeCard(
                title: active ? 'Premium active' : order?['status'] == 'initiated' ? 'Payment not completed' : 'Payment being checked',
                message: active ? 'You have ${state.status['plan_name']} until ${shortDate(state.status['plan_ends_at'] as String?)}.' :
                  'Payment for ${(order?['plans'] as Map?)?['name'] ?? 'Premium'} (order ${order?['reference']}) is ${order?['status'] == 'initiated' ? 'not completed' : 'being checked'}. Tap to see the status.',
                tone: active ? NoticeTone.success : NoticeTone.warning,
                onTap: active ? null : () => Navigator.push(context, MaterialPageRoute<void>(
                  builder: (_) => Payments(state: state, orderId: order!['id'] as String)))));
            }),
            PremiumHero(perks: perks?.whereType<String>().toList() ?? []),
            const SizedBox(height: 24), const SectionTitle('Choose your plan'), const SizedBox(height: 16),
            if (snapshot.hasError) ErrorRetry(onRetry: () => setState(reload))
            else if (!snapshot.hasData) const SkeletonList()
            else for (final row in rows) Padding(padding: const EdgeInsets.only(bottom: 12), child: PlanCard(
              plan: row, selected: row['id'] == selected, onTap: busy ? null : () => setState(() => selected = row['id'] as String))),
            const SizedBox(height: 8),
            Text('One-time payment. No automatic renewal.', style: Theme.of(context).textTheme.bodySmall, textAlign: TextAlign.center),
            if (!state.guest) TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
              builder: (_) => Payments(state: state))), child: const Text('Payment history')),
          ]))));
    });
  });
}

String planPrice(num value) {
  final fraction = value != value.roundToDouble();
  return '₹ ${value.toStringAsFixed(fraction ? 2 : 0)}';
}

String planDuration(num raw) {
  final days = raw.toInt();
  return switch (days) {
    1 => '1 day',
    30 => '1 month',
    90 => '3 months',
    180 => '6 months',
    365 => '1 year',
    _ => '$days days',
  };
}

class PremiumHero extends StatelessWidget {
  const PremiumHero({super.key, this.perks = const []});
  final List<String> perks;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(gradient: AppColors.gradient, borderRadius: BorderRadius.circular(24),
      boxShadow: const [BoxShadow(color: Color(0x33FF7A1A), blurRadius: 24, offset: Offset(0, 8))]),
    child: Padding(
      padding: const EdgeInsets.all(Gap.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PremiumBadge(),
          const SizedBox(height: Gap.l),
          for (final perk in perks.isNotEmpty ? perks : const ['Full premium videos', '2 TB cloud storage', 'Download to your phone'])
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.s),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    color: Colors.white,
                    size: AppSizes.iconSmall,
                  ),
                  const SizedBox(width: Gap.s),
                  Expanded(
                    child: Text(
                      perk,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class PlanCard extends StatelessWidget {
  const PlanCard({
    super.key,
    required this.plan,
    required this.selected,
    required this.onTap,
  });
  final Map<String, dynamic> plan;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    inMutuallyExclusiveGroup: true,
    child: PressScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fade,
        padding: const EdgeInsets.all(Gap.l),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF261A10) : AppColors.surface,
          boxShadow: selected ? const [BoxShadow(color: Color(0x22FF7A1A), blurRadius: 16)] : null,
          borderRadius: Radii.cardRadius,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? AppColors.primary : AppColors.muted,
            ),
            const SizedBox(width: Gap.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan['name'] as String,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: Gap.xs),
                  Text(
                    planDuration(plan['duration_days'] as num),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: Gap.s),
            Text(
              planPrice(plan['price_inr'] as num),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      ),
    ),
  );
}

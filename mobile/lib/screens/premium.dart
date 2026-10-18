import 'dart:async';
import '../plan_catalog.dart';
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
  const Plans({super.key, required this.state, this.catalog});
  final AppState state;
  final PlanCatalog? catalog;
  @override
  State<Plans> createState() => _PlansState();
}

class _PlansState extends State<Plans> with WidgetsBindingObserver {
  late Future<List<Map<String, dynamic>>> openOrders;
  late final PlanCatalog catalog;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    catalog =
        widget.catalog ??
        PlanCatalog(
          widget.state.db,
          changes: widget.state.remoteChangesEnabled
              ? null
              : const Stream<void>.empty(),
        );
    catalog.start();
    reload();
    WidgetsBinding.instance.addObserver(this);
    widget.state.addListener(changed);
  }

  void changed() {
    if (mounted) setState(reload);
  }

  void reload() {
    catalog.enabled = widget.state.paidEnabled;
    if (!widget.state.paidEnabled) {
      catalog.clear();
      openOrders = Future.value([]);
      return;
    }
    unawaited(catalog.refresh());
    openOrders = widget.state.guest
        ? Future.value([])
        : widget.state.db
              .from('payment_orders')
              .select('*,plans(name)')
              .eq('user_id', widget.state.userId)
              .inFilter('status', ['pending', 'submitted', 'review'])
              .order('created_at', ascending: false);
  }

  Future<void> refresh() async {
    await widget.state.refreshStatus();
    if (mounted) setState(reload);
    await Future.wait([catalog.refresh(), openOrders]);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.catalog == null) catalog.dispose();
    widget.state.removeListener(changed);
    super.dispose();
  }

  Future<void> pay(Map<String, dynamic> plan) async {
    if (busy) return;
    if (!await accountLoginDialog(
          context,
          widget.state,
          plan: plan['name'] as String,
        ) ||
        !mounted) {
      return;
    }
    if (!await loginGate(context, widget.state) || !mounted) return;
    await widget.state.refreshStatus();
    if (!mounted || !widget.state.paidEnabled) return;
    setState(() => busy = true);
    try {
      final order = await launchPlanPayment(
        context,
        widget.state,
        plan['id'] as String,
        displayedPrice: plan['price_inr'] as num,
      );
      if (order != null && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) =>
                Payments(state: widget.state, orderId: order['id'] as String),
          ),
        );
      }
      if (mounted) await refresh();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget freeAccount({required bool freeMode}) {
    final state = widget.state, status = widget.state.status['access_status'];
    final granted = !state.guest && state.adsAccess;
    final pending = status == 'pending', rejected = status == 'rejected';
    return RefreshIndicator(
      onRefresh: refresh,
      child: PageWidth(
        form: true,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: Gap.page,
          children: [
            const GlowHeader(
              child: Center(
                child: Icon(
                  Icons.cloud_done_outlined,
                  size: 64,
                  color: AppColors.primary,
                ),
              ),
            ),
            Card(
              child: Padding(
                padding: Gap.page,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      freeMode ? '${AppBrand.name} is free' : 'Free account',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      state.guest
                          ? (freeMode
                                ? 'Log in to get 15 GB of free cloud storage for your photos, videos and files.'
                                : 'Log in to manage your account.')
                          : (state.status['quota_bytes'] as num? ?? 0) > 0
                          ? 'Your allowance is ${storageLabel(state.status['quota_bytes'] as num?)}.'
                          : 'Get 2 TB with Premium',
                    ),
                    if (!state.guest) ...[
                      const SizedBox(height: 16),
                      StorageMeter(state: state),
                    ],
                    if (state.guest) ...[
                      const SizedBox(height: 16),
                      GradientButton(
                        label: 'Log in',
                        onPressed: () => loginGate(context, state),
                      ),
                    ],
                    if (freeMode) ...[
                      const SizedBox(height: 24),
                      NoticeCard(
                        title: granted
                            ? 'Full access'
                            : pending
                            ? 'Request received'
                            : rejected
                            ? 'Not approved'
                            : 'Your access',
                        message: granted
                            ? 'Full access: all videos and downloads are unlocked.'
                            : pending
                            ? 'Your request for full access is being reviewed.'
                            : rejected
                            ? 'Full access was not approved for this account.'
                            : 'Some videos and downloads need approval from our team.',
                        tone: granted
                            ? NoticeTone.success
                            : pending
                            ? NoticeTone.warning
                            : rejected
                            ? NoticeTone.danger
                            : NoticeTone.neutral,
                      ),
                      if (!state.adsAccess && !pending) ...[
                        const SizedBox(height: 16),
                        GradientButton(
                          label: 'Request full access',
                          onPressed: () => runAction(context, () async {
                            if (await loginGate(context, state)) {
                              await state.requestAccess();
                            }
                          }),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) {
      final state = widget.state;
      final actions = [
        IconButton(
          tooltip: 'Profile',
          icon: const Icon(Icons.account_circle_outlined),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => AppPage(body: Profile(state: state)),
            ),
          ),
        ),
      ];
      if (!state.paidEnabled) {
        return AppPage(
          title: 'Premium',
          actions: actions,
          body: freeAccount(freeMode: true),
        );
      }
      return ListenableBuilder(
        listenable: catalog,
        builder: (context, _) {
          if (catalog.loaded && catalog.error == null && catalog.rows.isEmpty) {
            return AppPage(
              title: 'Premium',
              actions: actions,
              body: freeAccount(freeMode: false),
            );
          }
          final rows = catalog.rows;
          final matches = rows.where((p) => p['id'] == catalog.selected);
          final plan = matches.isEmpty ? null : matches.first;
          final perks = planPerks(plan, rows);
          return AppPage(
            title: 'Premium',
            actions: actions,
            navigation: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: PageWidth(
                  form: true,
                  child: GradientButton(
                    label: premiumButtonLabel(
                      selected: plan != null,
                      guest: state.guest,
                      busy: busy,
                    ),
                    icon: Icons.arrow_forward,
                    busy: busy,
                    onPressed: busy || plan == null ? null : () => pay(plan),
                  ),
                ),
              ),
            ),
            body: RefreshIndicator(
              onRefresh: refresh,
              child: PageWidth(
                form: true,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: openOrders,
                      builder: (context, snapshot) {
                        final orders = snapshot.data ?? [];
                        final banner = premiumBanner(state.status, orders);
                        if (banner == PremiumBannerKind.none) {
                          return const SizedBox.shrink();
                        }
                        final active = banner == PremiumBannerKind.active;
                        final order = orders.isEmpty ? null : orders.first;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: NoticeCard(
                            title: active
                                ? 'Premium active'
                                : order?['status'] == 'initiated'
                                ? 'Payment not completed'
                                : 'Payment being checked',
                            message: active
                                ? 'You have ${state.status['plan_name']} until ${shortDate(state.status['plan_ends_at'] as String?)}.'
                                : 'Payment for ${(order?['plans'] as Map?)?['name'] ?? 'Premium'} (order ${order?['reference']}) is ${order?['status'] == 'initiated' ? 'not completed' : 'being checked'}. Tap to see the status.',
                            tone: active
                                ? NoticeTone.success
                                : NoticeTone.warning,
                            onTap: active
                                ? null
                                : () => Navigator.push(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) => Payments(
                                        state: state,
                                        orderId: order!['id'] as String,
                                      ),
                                    ),
                                  ),
                          ),
                        );
                      },
                    ),
                    PremiumHero(perks: perks),
                    const SizedBox(height: 24),
                    const SectionTitle('Choose your plan'),
                    const SizedBox(height: 16),
                    if (catalog.error != null)
                      ErrorRetry(onRetry: () => setState(reload))
                    else if (!catalog.loaded)
                      const SkeletonList()
                    else
                      for (final row in rows)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: PlanCard(
                            plan: row,
                            selected: row['id'] == catalog.selected,
                            onTap: busy
                                ? null
                                : () => catalog.select(row['id'] as String),
                          ),
                        ),
                    const SizedBox(height: 8),
                    Text(
                      'One-time payment. No automatic renewal.',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    if (!state.guest)
                      TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => Payments(state: state),
                          ),
                        ),
                        child: const Text('Payment history'),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
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
    180 => '6 months',
    365 => '1 year',
    _ => '$days days',
  };
}

List<String> planPerks(
  Map<String, dynamic>? selected,
  List<Map<String, dynamic>> rows,
) {
  List<String> read(Map<String, dynamic>? row) => (row?['perks'] as List? ?? [])
      .whereType<String>()
      .where((p) => p.trim().isNotEmpty)
      .toList();
  final own = read(selected);
  if (own.isNotEmpty) return own;
  return read(rows.isEmpty ? null : rows.first);
}

class PremiumHero extends StatelessWidget {
  const PremiumHero({super.key, this.perks = const []});
  final List<String> perks;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      gradient: AppColors.gradient,
      borderRadius: BorderRadius.circular(24),
      boxShadow: const [
        BoxShadow(
          color: Color(0x33FF7A1A),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Padding(
      padding: const EdgeInsets.all(Gap.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PremiumBadge(),
          const SizedBox(height: Gap.l),
          for (final perk
              in perks.isNotEmpty
                  ? perks
                  : const [
                      'Full premium videos',
                      '2 TB cloud storage',
                      'Download to your phone',
                    ])
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
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
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
          boxShadow: selected
              ? const [BoxShadow(color: Color(0x22FF7A1A), blurRadius: 16)]
              : null,
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
                  if ((plan['badge'] as String? ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: Gap.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        plan['badge'] as String,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
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

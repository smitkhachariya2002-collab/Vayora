import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_state.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'account_ui.dart';
import 'payment_flow.dart';
import 'premium.dart';

String paymentLabel(String status) => switch (status) {
  'success' => 'Success',
  'failed' => 'Failed',
  'cancelled' => 'Cancelled',
  'revoked' => 'Reversed',
  'expired' => 'Expired',
  _ => 'Pending',
};
NoticeTone paymentTone(String status) => switch (status) {
  'success' => NoticeTone.success,
  'revoked' => NoticeTone.danger,
  'failed' || 'cancelled' || 'expired' => NoticeTone.neutral,
  _ => NoticeTone.warning,
};
String paymentMessage(String status) => switch (status) {
  'success' => 'Payment successful! Your plan is now active.',
  'failed' => 'Payment failed. Please try again.',
  'cancelled' => 'Payment cancelled. You can try again.',
  'revoked' =>
    'This payment was reversed after review. Contact support if you think this is wrong.',
  'expired' => 'This payment has expired. You can try again.',
  _ => 'Checking your payment…',
};
bool paymentPending(String status) =>
    status == 'created' || status == 'pending';
String orderAmount(Map<String, dynamic> order) {
  final value = (order['amount_paise'] as num? ?? 0) / 100;
  return '₹ ${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2)}';
}

String paymentDate(String? raw) {
  final date = DateTime.tryParse(raw ?? '')?.toLocal();
  return date == null
      ? ''
      : '${shortDate(raw)} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

class Payments extends StatefulWidget {
  const Payments({
    super.key,
    required this.state,
    this.showLatest = false,
    this.orderId,
  });
  final AppState state;
  final bool showLatest;
  final String? orderId;
  @override
  State<Payments> createState() => _PaymentsState();
}

class _PaymentsState extends State<Payments> with WidgetsBindingObserver {
  Timer? poll;
  late Future<List<Map<String, dynamic>>> rows;
  int ticks = 0;
  String? selected;
  late bool details;
  bool refreshing = false, paying = false;
  @override
  void initState() {
    super.initState();
    selected = widget.orderId;
    details = widget.showLatest || selected != null;
    WidgetsBinding.instance.addObserver(this);
    reload();
    if (details) startPolling();
  }

  void startPolling() {
    poll?.cancel();
    ticks = 0;
    poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (++ticks >= 120) poll?.cancel();
      if (details && widget.state.paidEnabled && !widget.state.guest) {
        unawaited(runAction(context, refresh));
      }
    });
  }

  Future<List<Map<String, dynamic>>> fetch() async {
    if (widget.state.guest || !widget.state.paidEnabled) return [];
    return widget.state.db
        .from('payment_orders')
        .select('*,plans(name)')
        .eq('user_id', widget.state.userId)
        .order('created_at', ascending: false);
  }

  void reload() {
    rows = fetch();
  }

  Future<void> refresh() async {
    if (refreshing ||
        !mounted ||
        !widget.state.paidEnabled ||
        widget.state.guest) {
      return;
    }
    refreshing = true;
    final user = widget.state.userId;
    try {
      await widget.state.retryPayments();
      final next = await fetch();
      if (!mounted || widget.state.userId != user) return;
      // The server is the only authority for payment success and entitlements.
      if (next.any((o) => o['status'] == 'success')) {
        await widget.state.refreshStatus();
      }
      if (mounted && widget.state.userId == user) {
        setState(() => rows = Future.value(next));
      }
    } finally {
      refreshing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    if (value == AppLifecycleState.resumed) {
      unawaited(runAction(context, refresh));
    }
  }

  @override
  void dispose() {
    poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void done() {
    if (widget.showLatest || widget.orderId != null) {
      Navigator.pop(context);
    } else {
      poll?.cancel();
      setState(() => details = false);
    }
  }

  Future<void> backToPlans() async {
    if (widget.showLatest || widget.orderId != null) {
      Navigator.pop(context);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => Plans(state: widget.state)),
    );
    await refresh();
  }

  Future<void> payAgain(Map<String, dynamic> order) async {
    if (paying ||
        !widget.state.paidEnabled ||
        widget.state.guest ||
        order['plan_id'] == null) {
      return;
    }
    setState(() => paying = true);
    try {
      final next = await launchPlanPayment(
        context,
        widget.state,
        order['plan_id'] as String,
      );
      if (next != null && mounted) {
        setState(() {
          selected = next['id'] as String;
          details = true;
        });
        startPolling();
        await refresh();
      }
    } finally {
      if (mounted) setState(() => paying = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) {
      if (!widget.state.paidEnabled) {
        return const AppPage(
          title: 'Payment',
          body: EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'Free account',
            message: 'Your account is currently in free mode.',
          ),
        );
      }
      if (widget.state.guest) {
        return const AppPage(
          title: 'Payment history',
          body: EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'Please log in',
            message: 'Log in to view your payments.',
          ),
        );
      }
      return AppPage(
        title: details ? 'Payment' : 'Payment history',
        leading: details
            ? IconButton(
                tooltip: 'Back',
                onPressed: paying ? null : done,
                icon: const Icon(Icons.arrow_back),
              )
            : null,
        body: RefreshIndicator(
          onRefresh: refresh,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: rows,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [ErrorRetry(onRetry: refresh)],
                );
              }
              if (!snapshot.hasData) {
                return const SingleChildScrollView(
                  physics: AlwaysScrollableScrollPhysics(),
                  padding: Gap.page,
                  child: SkeletonList(),
                );
              }
              final orders = snapshot.data!;
              if (orders.isEmpty) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'No payments yet',
                      message: 'Your payment history will appear here.',
                    ),
                  ],
                );
              }
              final matching = orders.where((o) => o['id'] == selected);
              if (details && selected != null && matching.isEmpty) {
                return ListView(
                  children: const [
                    EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'Order unavailable',
                      message: 'Return to payment history and refresh.',
                    ),
                  ],
                );
              }
              final order = matching.isEmpty ? orders.first : matching.first;
              if (details) {
                return PaymentStatusView(
                  order: order,
                  busy: paying,
                  onDone: done,
                  onRetry: backToPlans,
                  onPayAgain: () => payAgain(order),
                  onCheck: () => runAction(context, refresh),
                  onSupport: () => contactPaymentSupport(context, order),
                );
              }
              return PageWidth(
                form: true,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Your payments',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    for (final row in orders)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Card(
                          child: InkWell(
                            borderRadius: Radii.cardRadius,
                            onTap: () {
                              setState(() {
                                selected = row['id'] as String;
                                details = true;
                              });
                              startPolling();
                              unawaited(runAction(context, refresh));
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    alignment: WrapAlignment.spaceBetween,
                                    spacing: 16,
                                    runSpacing: 8,
                                    children: [
                                      Text(
                                        (row['plans'] as Map?)?['name']
                                                as String? ??
                                            'Premium plan',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                      Text(
                                        orderAmount(row),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  StatusPill(
                                    paymentLabel(row['status'] as String),
                                    tone: paymentTone(row['status'] as String),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Order ${row['reference']}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  Text(
                                    paymentDate(row['created_at'] as String?),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    },
  );
}

Future<void> contactPaymentSupport(
  BuildContext context,
  Map<String, dynamic> order,
) async {
  final uri = Uri(
    scheme: 'mailto',
    path: AppBrand.support,
    queryParameters: {
      'subject': '${AppBrand.name} payment ${order['reference']}',
      'body': 'Please help me with payment reference ${order['reference']}.',
    },
  );
  if (!await launchUrl(uri) && context.mounted) {
    showFeedback(
      context,
      'Email ${AppBrand.support} with your payment reference.',
    );
  }
}

class PaymentStatusView extends StatelessWidget {
  const PaymentStatusView({
    super.key,
    required this.order,
    required this.onDone,
    required this.onRetry,
    required this.onSupport,
    this.onCheck,
    this.onPayAgain,
    this.busy = false,
  });
  final Map<String, dynamic> order;
  final VoidCallback onDone, onRetry, onSupport;
  final VoidCallback? onCheck, onPayAgain;
  final bool busy;
  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String? ?? 'pending';
    final pending = paymentPending(status), success = status == 'success';
    final noAnswer =
        (order['raw_response'] as String? ?? '').isEmpty ||
        (order['raw_response'] as String? ?? '').toUpperCase().contains(
          'STATUS=UNKNOWN',
        );
    final iconTone = status == 'failed' || status == 'revoked'
        ? NoticeTone.danger
        : paymentTone(status);
    return PageWidth(
      form: true,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 24),
          PaymentStatusIcon(tone: iconTone),
          if (pending)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(top: 16),
                child: SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
          const SizedBox(height: 24),
          Text(
            paymentMessage(status),
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DetailRow(
                    'Order number',
                    order['reference'] as String? ?? '',
                    selectable: true,
                  ),
                  DetailRow(
                    'Plan',
                    (order['plans'] as Map?)?['name'] as String? ??
                        'Premium plan',
                  ),
                  DetailRow('Amount', orderAmount(order)),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: StatusPill(
                      paymentLabel(status),
                      tone: paymentTone(status),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (noAnswer && !success) ...[
            const SizedBox(height: 16),
            const Text(
              'If money was taken, keep this order number; we will verify it.',
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 24),
          if (!success) ...[
            OutlinedButton.icon(
              onPressed: busy ? null : onCheck,
              icon: const Icon(Icons.refresh),
              label: const Text('Check payment status'),
            ),
            const SizedBox(height: 12),
          ],
          if (['failed', 'cancelled', 'expired'].contains(status) &&
              onPayAgain != null) ...[
            GradientButton(
              label: busy ? 'Opening…' : 'Pay again',
              busy: busy,
              onPressed: busy ? null : onPayAgain,
            ),
            const SizedBox(height: 12),
          ],
          GradientButton(
            label: success ? 'Done' : 'Back to plans',
            onPressed: busy
                ? null
                : success
                ? onDone
                : onRetry,
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: busy ? null : onSupport,
            icon: const Icon(Icons.help_outline),
            label: const Text('Contact support'),
          ),
        ],
      ),
    );
  }
}

class PaymentStatusIcon extends StatelessWidget {
  const PaymentStatusIcon({super.key, required this.tone});
  final NoticeTone tone;
  @override
  Widget build(BuildContext context) {
    final color = tone == NoticeTone.success
        ? AppColors.success
        : tone == NoticeTone.danger
        ? AppColors.danger
        : tone == NoticeTone.warning
        ? AppColors.warning
        : AppColors.muted;
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: .12),
        ),
        child: Icon(
          tone == NoticeTone.success
              ? Icons.verified_rounded
              : tone == NoticeTone.danger
              ? Icons.cancel_rounded
              : tone == NoticeTone.warning
              ? Icons.hourglass_top
              : Icons.info_outline,
          size: 64,
          color: color,
        ),
      ),
    );
  }
}

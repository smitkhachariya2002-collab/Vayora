import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_state.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets/common.dart';

String paymentLabel(String status) => switch (status) {
  'success' => 'Paid',
  'failed' => 'Failed',
  'cancelled' => 'Cancelled',
  'expired' => 'Expired',
  _ => 'Pending',
};
NoticeTone paymentTone(String status) => status == 'success'
    ? NoticeTone.success
    : ['failed', 'cancelled', 'expired'].contains(status)
    ? NoticeTone.danger
    : NoticeTone.warning;
String orderAmount(Map<String, dynamic> order) {
  final value = (order['amount_paise'] as num? ?? 0) / 100;
  return '₹${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2)}';
}

class Payments extends StatefulWidget {
  const Payments({super.key, required this.state, this.showLatest = false});
  final AppState state;
  final bool showLatest;
  @override
  State<Payments> createState() => _PaymentsState();
}

class _PaymentsState extends State<Payments> with WidgetsBindingObserver {
  Timer? poll;
  late Future<List<Map<String, dynamic>>> rows;
  int ticks = 0;
  String? selected;
  late bool details = widget.showLatest;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    reload();
    poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (++ticks >= 120) {
        poll?.cancel();
      }
      unawaited(runAction(context, refresh));
    });
  }

  void reload() {
    rows = widget.state.db
        .from('payment_orders')
        .select('*,plans(name)')
        .eq('user_id', widget.state.userId)
        .order('created_at', ascending: false);
  }

  Future<void> refresh() async {
    await widget.state.retryPayments();
    if (mounted) setState(reload);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
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
    if (widget.showLatest) {
      Navigator.pop(context);
    } else {
      setState(() => details = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) {
      if (!widget.state.paidEnabled) {
        return const AppPage(
          title: 'Payments',
          body: EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'You’re in free mode',
            message: 'Plans and payments aren’t shown while free mode is on.',
          ),
        );
      }
      return AppPage(
        title: details ? 'Payment status' : 'Payment history',
        leading: details
            ? IconButton(
                tooltip: 'Back',
                onPressed: done,
                icon: const Icon(Icons.arrow_back),
              )
            : null,
        body: RefreshIndicator(
          onRefresh: refresh,
          child: FutureBuilder(
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
              final matching = orders
                  .where((order) => order['id'] == selected)
                  .toList();
              final order = matching.isEmpty ? orders.first : matching.first;
              if (details) {
                return PaymentStatusView(
                  order: order,
                  onDone: done,
                  onRetry: () => Navigator.pop(context),
                  onSupport: () => contactPaymentSupport(context, order),
                );
              }
              return PageWidth(
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: Gap.page,
                  children: [
                    Text(
                      'Your payments',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: Gap.s),
                    Text(
                      'A simple record of your Premium journey.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: Gap.xl),
                    for (final order in orders)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Gap.l),
                        child: PressScale(
                          onTap: () => setState(() {
                            selected = order['id'] as String;
                            details = true;
                          }),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(Gap.l),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          (order['plans'] as Map?)?['name']
                                                  as String? ??
                                              'Premium plan',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleMedium,
                                        ),
                                      ),
                                      Text(
                                        orderAmount(order),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: Gap.m),
                                  StatusPill(
                                    paymentLabel(order['status'] as String),
                                    tone: paymentTone(
                                      order['status'] as String,
                                    ),
                                  ),
                                  const SizedBox(height: Gap.m),
                                  Text(
                                    'Reference: ${order['reference']}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  if (shortDate(
                                    order['created_at'] as String?,
                                  ).isNotEmpty)
                                    Text(
                                      shortDate(order['created_at'] as String?),
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
      'subject': 'Vayora payment ${order['reference']}',
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
  });
  final Map<String, dynamic> order;
  final VoidCallback onDone, onRetry, onSupport;
  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String? ?? 'pending';
    final tone = paymentTone(status);
    final success = tone == NoticeTone.success,
        failed = tone == NoticeTone.danger;
    return PageWidth(
      form: true,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: Gap.page,
        children: [
          const SizedBox(height: Gap.xl),
          PaymentStatusIcon(tone: tone),
          const SizedBox(height: Gap.xl),
          Text(
            success
                ? 'You’re all set'
                : failed
                ? 'Payment not completed'
                : 'Your payment is pending',
            style: Theme.of(context).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Gap.s),
          Text(
            success
                ? 'Your payment has been verified.'
                : failed
                ? 'If money was debited, contact support with your reference.'
                : 'Waiting for payment verification. This screen refreshes automatically.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Gap.xxl),
          Card(
            child: Padding(
              padding: Gap.page,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    orderAmount(order),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: Gap.s),
                  Text(
                    (order['plans'] as Map?)?['name'] as String? ??
                        'Premium plan',
                  ),
                  const SizedBox(height: Gap.l),
                  const Divider(),
                  const SizedBox(height: Gap.l),
                  Text(
                    'Payment reference',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: Gap.xs),
                  SelectableText(order['reference'] as String? ?? ''),
                  const SizedBox(height: Gap.l),
                  StatusPill(paymentLabel(status), tone: tone),
                ],
              ),
            ),
          ),
          const SizedBox(height: Gap.xl),
          GradientButton(
            label: failed ? 'Try again' : 'Done',
            onPressed: failed ? onRetry : onDone,
            icon: failed ? Icons.refresh : Icons.check,
          ),
          const SizedBox(height: Gap.m),
          OutlinedButton.icon(
            onPressed: onSupport,
            icon: const Icon(Icons.help_outline),
            label: const Text('Contact support'),
          ),
          if (failed) TextButton(onPressed: onDone, child: const Text('Done')),
        ],
      ),
    );
  }
}

class PaymentStatusIcon extends StatefulWidget {
  const PaymentStatusIcon({super.key, required this.tone});
  final NoticeTone tone;
  @override
  State<PaymentStatusIcon> createState() => _PaymentStatusIconState();
}

class _PaymentStatusIconState extends State<PaymentStatusIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController pulse;
  @override
  void initState() {
    super.initState();
    pulse = AnimationController(vsync: this, duration: AppMotion.shimmer)
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.tone == NoticeTone.success
        ? AppColors.success
        : widget.tone == NoticeTone.danger
        ? AppColors.danger
        : AppColors.warning;
    final icon = widget.tone == NoticeTone.success
        ? Icons.check_circle_rounded
        : widget.tone == NoticeTone.danger
        ? Icons.cancel_rounded
        : Icons.hourglass_top_rounded;
    final child = Container(
      padding: const EdgeInsets.all(Gap.xl),
      decoration: BoxDecoration(
        color: widget.tone == NoticeTone.success
            ? AppColors.successBg
            : widget.tone == NoticeTone.danger
            ? AppColors.dangerBg
            : AppColors.warningBg,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: AppSizes.emptyIcon),
    );
    return Center(
      child:
          widget.tone == NoticeTone.warning &&
              !MediaQuery.disableAnimationsOf(context)
          ? ScaleTransition(
              scale: Tween<double>(
                begin: AppSizes.restingScale,
                end: AppSizes.pulseScale,
              ).animate(pulse),
              child: child,
            )
          : child,
    );
  }
}

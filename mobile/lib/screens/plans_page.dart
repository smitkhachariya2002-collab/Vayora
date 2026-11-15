import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../services/app_state.dart';
import '../theme.dart';

typedef PlansLoader = Future<List<Map<String, dynamic>>> Function();

Future<List<Map<String, dynamic>>> defaultPlansLoader() async {
  final r = await sb.rpc('public_plans');
  return [for (final e in (r as List)) Map<String, dynamic>.from(e as Map)];
}

String durationLabel(int days, [int hours = 0]) {
  if (hours > 0) {
    if (hours % 24 == 0) return durationLabel(hours ~/ 24);
    return hours == 1 ? '1 Hour' : '$hours Hours';
  }
  if (days >= 365 && days % 365 == 0) {
    final y = days ~/ 365;
    return y == 1 ? '1 Year' : '$y Years';
  }
  if (days >= 30 && days % 30 == 0) {
    final m = days ~/ 30;
    return m == 1 ? '1 Month' : '$m Months';
  }
  return days == 1 ? '1 Day' : '$days Days';
}

String perDay(num price, int days, [int hours = 0]) {
  final d = hours > 0 ? hours / 24 : days.toDouble();
  final v = price / (d <= 0 ? 1 : d);
  final s = v.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

/// "Go Premium": the plans page. Prices and durations come from the server (public_plans);
/// the buy decision and amount are re-checked by the server in create_order.
class PlansPage extends StatefulWidget {
  const PlansPage({
    super.key,
    required this.onBuy,
    this.plansLoader,
    this.freeIds = const {},
    this.paused = false,
    this.actions = const [],
    this.showHeader = true,
  });
  final Future<void> Function(String planId) onBuy;
  final PlansLoader? plansLoader;
  final Set<String> freeIds;
  final bool paused;
  final List<Widget> actions;
  final bool showHeader;

  @override
  State<PlansPage> createState() => _PlansPageState();
}

class _PlansPageState extends State<PlansPage> {
  List<Map<String, dynamic>> _plans = [];
  bool _loading = true, _error = false, _busy = false;
  String? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = false; });
    try {
      final l = await (widget.plansLoader ?? defaultPlansLoader)();
      l.sort((a, b) => ((a['position'] as num?) ?? 0).compareTo((b['position'] as num?) ?? 0));
      _plans = l;
      final pop = l.where((p) => p['badge'] == 'Popular');
      _selected = (pop.isNotEmpty ? pop.first : (l.isNotEmpty ? l.first : null))?['id'] as String?;
    } catch (_) {
      _error = true;
    }
    if (mounted) setState(() => _loading = false);
  }

  Map<String, dynamic>? get _sel {
    for (final p in _plans) {
      if (p['id'] == _selected) return p;
    }
    return null;
  }

  Future<void> _buy() async {
    final id = _selected;
    if (id == null || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.onBuy(id);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(String path) => launchUrl(Uri.parse('${Config.websiteUrl}$path'), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final sel = _sel;
    final isFree = sel != null && widget.freeIds.contains(sel['id']);
    final cta = sel == null
        ? 'Choose a plan'
        : isFree
            ? 'Claim free ${sel['name']} Plan'
            : 'Get ${sel['name']} Plan · ₹${sel['price_inr']}';
    return Container(
      key: const Key('plans_page'),
      decoration: BoxDecoration(
        gradient: RadialGradient(center: const Alignment(0, -1.1), radius: 1.2, colors: [Tokens.primary.withValues(alpha: .28), Tokens.background]),
      ),
      child: Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), children: [
            if (widget.showHeader)
              Row(children: [
                const Icon(Icons.workspace_premium, color: Tokens.gold, size: 30),
                const SizedBox(width: 10),
                const Expanded(child: Text('Go Premium', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700))),
                ...widget.actions,
              ]),
            const SizedBox(height: 6),
            const Text('Unlock more space, full-length videos and downloads.', style: TextStyle(color: Tokens.muted, fontSize: 13)),
            const SizedBox(height: 16),
            const Row(children: [
              Expanded(child: _Perk(Icons.cloud_outlined, '2 TB\ncloud')),
              SizedBox(width: 10),
              Expanded(child: _Perk(Icons.play_circle_outline, 'Full\nvideos')),
              SizedBox(width: 10),
              Expanded(child: _Perk(Icons.download_outlined, 'Offline\ndownloads')),
            ]),
            const SizedBox(height: 16),
            const Text('Choose your plan', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            if (widget.paused)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Tokens.warning.withValues(alpha: .15), borderRadius: BorderRadius.circular(12)),
                child: const Text('Payments are paused right now. Please try again later.'),
              ),
            if (_loading)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (_error)
              Center(child: Column(children: [
                const Text("Couldn't load plans"),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ]))
            else
              for (final p in _plans)
                _PlanTile(plan: p, selected: p['id'] == _selected, free: widget.freeIds.contains(p['id']), onTap: () => setState(() => _selected = p['id'] as String)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: SizedBox(
            width: double.infinity,
            child: GradientButton(label: _busy ? 'Please wait…' : cta, onPressed: (sel == null || _busy || (widget.paused && !isFree)) ? null : _buy),
          ),
        ),
        Wrap(alignment: WrapAlignment.center, children: [
          TextButton(key: const Key('link_privacy'), onPressed: () => _open('/privacy'), child: const Text('Privacy Policy', style: TextStyle(color: Tokens.muted, fontSize: 12))),
          TextButton(key: const Key('link_terms'), onPressed: () => _open('/terms'), child: const Text('Terms & Conditions', style: TextStyle(color: Tokens.muted, fontSize: 12))),
          TextButton(key: const Key('link_refund'), onPressed: () => _open('/refund'), child: const Text('Refund Policy', style: TextStyle(color: Tokens.muted, fontSize: 12))),
        ]),
      ]),
    );
  }
}

class _Perk extends StatelessWidget {
  const _Perk(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(color: Tokens.surface.withValues(alpha: .9), borderRadius: BorderRadius.circular(18), border: Border.all(color: Tokens.border)),
        child: Column(children: [
          Icon(icon, color: Tokens.primary, size: 26),
          const SizedBox(height: 6),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, height: 1.25)),
        ]),
      );
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({required this.plan, required this.selected, required this.free, required this.onTap});
  final Map<String, dynamic> plan;
  final bool selected, free;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final days = (plan['duration_days'] as num).toInt();
    final hours = ((plan['duration_hours'] ?? 0) as num).toInt();
    final price = plan['price_inr'] as num;
    final badge = plan['badge'] as String?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: selected ? Tokens.gradient : null,
            color: selected ? null : Tokens.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: selected ? Colors.white.withValues(alpha: .6) : Tokens.border, width: selected ? 1.5 : 1),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              child: Row(children: [
                SizedBox(width: 84, child: Center(child: Text(free ? 'FREE' : '₹$price', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)))),
                Container(width: 1, height: 40, margin: const EdgeInsets.symmetric(horizontal: 12), color: Colors.white.withValues(alpha: .18)),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
                      Text('${plan['name']} Plan', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      if (badge != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: selected ? .25 : .1), borderRadius: BorderRadius.circular(10)),
                          child: Text(badge, style: TextStyle(fontSize: 11, color: selected ? Colors.white : Tokens.accent)),
                        ),
                    ]),
                    const SizedBox(height: 2),
                    Text(hours > 0 && hours < 24 ? '${durationLabel(days, hours)} · ₹$price' : '${durationLabel(days, hours)} · ₹${perDay(price, days, hours)} / day', style: TextStyle(color: selected ? Colors.white.withValues(alpha: .85) : Tokens.muted, fontSize: 13)),
                  ]),
                ),
                if (selected)
                  Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: const Icon(Icons.check, color: Tokens.primary, size: 20),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

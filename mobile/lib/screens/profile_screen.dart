import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../services/app_scope.dart';
import '../services/app_state.dart';
import '../theme.dart';
import 'channels_screen.dart';
import 'measurement_preferences.dart';
import 'login_sheet.dart';
import 'payment_status_screen.dart';
import 'plans_page.dart';
import 'premium_screen.dart';

/// Profile tab: users without an active plan (when plans are visible to them) land on the
/// plans page directly; everyone else gets the account view. Reacts live to status changes.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, this.plansLoader});
  final PlansLoader? plansLoader;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        if (app.showPremiumEntry && !app.status.isPremium) {
          return PremiumScreen(
            plansLoader: plansLoader,
            embedded: true,
            actions: [
              if (app.status.isGuest)
                TextButton(key: const Key('login_link'), onPressed: () => requireAccount(context), child: const Text('Log in')),
              IconButton(
                key: const Key('account_button'),
                tooltip: 'Account',
                icon: const Icon(Icons.account_circle_outlined),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: const Text('Account')), body: const AccountView(key: Key('account_view'))))),
              ),
            ],
          );
        }
        return const AccountView(key: Key('account_view'));
      },
    );
  }
}

class AccountView extends StatelessWidget {
  const AccountView({super.key});

  Future<void> _web(String path) => launchUrl(Uri.parse('${Config.websiteUrl}$path'), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final s = app.status;
        final d = s.planEndsAt;
        return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
          _AccountCard(
            title: s.isGuest ? 'Guest' : (_email() ?? 'Account'),
            subtitle: _planLine(s, d),
            premium: s.isPremium,
            trailing: s.isGuest ? TextButton(onPressed: () => showLoginSheet(context, signup: s.isPremium, saveMode: s.isPremium), child: Text(s.isPremium ? 'Add email' : 'Log in')) : null,
          ),
          if (s.isGuest && s.isPremium) ...[
            const SizedBox(height: 10),
            _SaveAccountCard(onTap: () => showLoginSheet(context, signup: true, saveMode: true)),
          ],
          if (app.showPremiumEntry && s.isPremium) ...[
            const SizedBox(height: 10),
            _UpgradeCard(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PremiumScreen()))),
          ],
          const SizedBox(height: 14),
          _Group(children: [
            if (s.isPremium || app.showPrices)
              _Row(Icons.receipt_long_outlined, 'Payment history', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PaymentHistoryScreen()))),
            _Row(Icons.groups_outlined, 'My channels', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChannelsScreen(standalone: true)))),
          ]),
          const SizedBox(height: 12),
          _Group(children: [
            _Row(Icons.tune, 'Measurement preferences', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MeasurementPreferences()))),
            _Row(Icons.privacy_tip_outlined, 'Privacy policy', onTap: () => _web('/privacy')),
            _Row(Icons.description_outlined, 'Terms', onTap: () => _web('/terms')),
            _Row(Icons.currency_rupee, 'Refund policy', onTap: () => _web('/refund')),
            _Row(Icons.diversity_3_outlined, 'Community guidelines', onTap: () => _web('/community-guidelines')),
          ]),
          if (!s.isGuest) ...[
            const SizedBox(height: 12),
            _Group(children: [
              _Row(Icons.logout, 'Log out', onTap: () async {
                await sb.auth.signOut();
                try { await sb.auth.signInAnonymously(); } catch (_) {}
                await app.refresh();
              }),
              _Row(Icons.delete_outline, 'Delete account', color: Tokens.danger, onTap: () => _deleteAccount(context, app)),
            ]),
          ],
          const Padding(padding: EdgeInsets.only(top: 18), child: Center(child: Text('Version ${Config.versionLabel}', key: Key('version_label'), style: TextStyle(color: Tokens.muted, fontSize: 12)))),
        ]);
      },
    );
  }

  String? _email() {
    try {
      return sb.auth.currentUser?.email;
    } catch (_) {
      return null;
    }
  }

  String _planLine(dynamic s, DateTime? d) {
    if (s.isGuest && !s.isPremium) return 'Add an email to save your account';
    if (s.isPremium) return '${s.planName ?? 'Premium'} active${d == null ? '' : ' until ${d.day}/${d.month}/${d.year}'}';
    return 'No active Premium plan';
  }

  Future<void> _deleteAccount(BuildContext context, AppState app) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text('Your profile, files and posts will be permanently deleted. Payment records are kept anonymised for legal reasons.'),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete'))],
      ),
    );
    if (ok != true) return;
    try {
      await sb.functions.invoke('delete-account');
      await sb.auth.signOut();
      try { await sb.auth.signInAnonymously(); } catch (_) {}
      await app.refresh();
    } catch (_) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not delete. Please try again.')));
    }
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.title, required this.subtitle, required this.premium, this.trailing});
  final String title, subtitle;
  final bool premium;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Tokens.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: Tokens.border)),
        child: Row(children: [
          CircleAvatar(radius: 24, backgroundColor: Tokens.primary, child: Icon(premium ? Icons.workspace_premium : Icons.person, color: premium ? Tokens.gold : Colors.white)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(color: Tokens.muted, fontSize: 13)),
            ]),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

class _SaveAccountCard extends StatelessWidget {
  const _SaveAccountCard({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: Tokens.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: Tokens.warning.withValues(alpha: .6))),
            child: const Row(children: [
              Icon(Icons.shield_outlined, color: Tokens.warning),
              SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Save your plan', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  Text('Add an email so you can restore it on any phone', style: TextStyle(fontSize: 12, color: Tokens.muted)),
                ]),
              ),
              Icon(Icons.chevron_right),
            ]),
          ),
        ),
      );
}

class _UpgradeCard extends StatelessWidget {
  const _UpgradeCard({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(gradient: Tokens.gradient, borderRadius: BorderRadius.circular(18)),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                Icon(Icons.workspace_premium, color: Tokens.gold),
                SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Upgrade / Renew', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    Text('Renewing extends your end date', style: TextStyle(fontSize: 12, color: Colors.white70)),
                  ]),
                ),
                Icon(Icons.chevron_right),
              ]),
            ),
          ),
        ),
      );
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Material(
        color: Tokens.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Tokens.border)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 52, color: Tokens.border),
            children[i],
          ],
        ]),
      );
}

class _Row extends StatelessWidget {
  const _Row(this.icon, this.label, {required this.onTap, this.color});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -1),
        leading: Icon(icon, size: 22, color: color),
        title: Text(label, style: TextStyle(fontSize: 15, color: color)),
        trailing: color == null ? const Icon(Icons.chevron_right, size: 20, color: Tokens.muted) : null,
        onTap: onTap,
      );
}


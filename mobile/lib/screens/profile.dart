import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_state.dart';
import '../plan_catalog.dart';
import '../channel_page.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'account_ui.dart';
import 'channel_detail.dart';
import 'new_post.dart';
import 'payments.dart';
import 'policies.dart';
import 'premium.dart';

/// The Profile tab opens Premium directly until the server confirms an active plan.
class Profile extends StatefulWidget {
  const Profile({super.key, required this.state, this.catalog});
  final AppState state;
  final PlanCatalog? catalog;
  @override
  State<Profile> createState() => _ProfileState();
}

class _ProfileState extends State<Profile> {
  bool checkoutOpen = false;
  void checkoutChanged(bool value) {
    if (mounted && checkoutOpen != value) setState(() => checkoutOpen = value);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) =>
        widget.state.paidEnabled && (!widget.state.premium || checkoutOpen)
        ? Plans(
            state: widget.state,
            catalog: widget.catalog,
            onCheckoutChanged: checkoutChanged,
          )
        : AccountProfile(state: widget.state),
  );
}

class AccountProfile extends StatefulWidget {
  const AccountProfile({super.key, required this.state});
  final AppState state;
  @override
  State<AccountProfile> createState() => _AccountProfileState();
}

class _AccountProfileState extends State<AccountProfile> {
  List<Map<String, dynamic>> owned = [], joined = [];
  bool loading = true;
  int membershipVersion = -1;
  String? failure, loadedUser;
  AppState get state => widget.state;
  @override
  void initState() {
    super.initState();
    state.addListener(changed);
    load();
  }

  void changed() {
    if (loadedUser != state.db.auth.currentUser?.id ||
        membershipVersion != state.membershipRevision) {
      load();
    }
  }

  Future<void> load() async {
    final id = state.db.auth.currentUser?.id;
    loadedUser = id;
    membershipVersion = state.membershipRevision;
    if (state.guest || id == null) {
      if (mounted) {
        setState(() {
          owned = [];
          joined = [];
          loading = false;
          failure = null;
        });
      }
      return;
    }
    try {
      final mine = await state.db
          .from('channels')
          .select()
          .eq('created_by', id)
          .order('created_at', ascending: false);
      final memberships = await state.db
          .from('channel_members')
          .select('channel_id')
          .eq('user_id', id);
      final ids = memberships.map((m) => m['channel_id'] as String).toList();
      final others = ids.isEmpty
          ? <Map<String, dynamic>>[]
          : await state.db
                .from('channels')
                .select()
                .inFilter('id', ids)
                .order('name');
      if (mounted && id == state.db.auth.currentUser?.id) {
        setState(() {
          owned = mine;
          joined = others.where((c) => c['created_by'] != id).toList();
          loading = false;
          failure = null;
        });
      }
    } on Object {
      if (mounted && id == state.db.auth.currentUser?.id) {
        setState(() {
          failure = 'Could not load your channels.';
          loading = false;
        });
      }
    }
  }

  Future<void> refresh() async {
    await state.refreshStatus();
    await load();
  }

  @override
  void dispose() {
    state.removeListener(changed);
    super.dispose();
  }

  Future<void> createChannel() async {
    if (!await accountLoginDialog(context, state, channel: true) || !mounted) {
      return;
    }
    if (!await loginGate(context, state) || !mounted) return;
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(builder: (_) => ChannelEditor(state: state)),
    );
    if (created == true) await load();
  }

  Future<void> openChannel(Map<String, dynamic> channel) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ChannelDetail(state: state, channel: channel),
      ),
    );
    await load();
  }

  Future<void> upload([Map<String, dynamic>? channel]) async {
    final eligible = owned
        .where(
          (c) =>
              c['review_status'] == 'approved' &&
              ['published', 'active'].contains(c['status']),
        )
        .toList();
    if (eligible.isEmpty) return;
    final chosen =
        channel ??
        await showModalBottomSheet<Map<String, dynamic>>(
          context: context,
          isScrollControlled: true,
          builder: (sheet) => SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: Gap.page,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Upload to which channel?',
                      style: Theme.of(sheet).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: Gap.l),
                    for (final row in eligible)
                      ListTile(
                        leading: ChannelAvatar(channel: row, radius: 22),
                        title: Text(row['name'] as String),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.pop(sheet, row),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
    if (chosen != null && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => NewPost(state: state, channel: chosen),
        ),
      );
    }
  }

  Future<void> editName() async {
    final input = TextEditingController(
      text: profileName(state.status, state.userId),
    );
    final value = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(
          controller: input,
          autofocus: true,
          maxLength: 80,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (input.text.trim().isNotEmpty) {
                Navigator.pop(dialog, input.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // Wait for the route to finish using its controller before disposal.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    input.dispose();
    if (value == null || !mounted) return;
    await runAction(context, () async {
      await state.db
          .from('profiles')
          .update({'display_name': value})
          .eq('id', state.userId)
          .select('id')
          .single();
      await state.refreshStatus();
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) {
      final name = profileName(state.status, state.userId);
      final hasPlan =
          state.paidEnabled &&
          state.premium &&
          state.status['plan_name'] != null;
      final eligible = owned
          .where(
            (c) =>
                c['review_status'] == 'approved' &&
                ['published', 'active'].contains(c['status']),
          )
          .toList();
      return RefreshIndicator(
        onRefresh: refresh,
        child: CustomScrollView(
          key: const PageStorageKey('profile-scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 168,
              automaticallyImplyLeading: false,
              title: const Text('Profile'),
              actions: [
                IconButton(
                  tooltip: 'Edit name',
                  onPressed: editName,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Settings',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => SettingsPage(state: state),
                    ),
                  ),
                  icon: const Icon(Icons.settings_outlined),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    const DecoratedBox(
                      decoration: BoxDecoration(gradient: warmProfileGradient),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, AppColors.background],
                          stops: [.45, 1],
                        ),
                      ),
                    ),
                    SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 64, 16, 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: AppColors.gradient,
                              ),
                              child: CircleAvatar(
                                radius: 34,
                                backgroundColor: AppColors.surfaceHigh,
                                child: Text(
                                  name.characters.first.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  if (hasPlan) ...[
                                    const SizedBox(height: 4),
                                    const PremiumBadge(),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: PageWidth(
                form: true,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (state.guest) ...[
                                const Text("You're using the app as a guest."),
                                const SizedBox(height: 16),
                                GradientButton(
                                  label: 'Log in / Create account',
                                  icon: Icons.login,
                                  onPressed: () async {
                                    await loginGate(context, state);
                                    await load();
                                  },
                                ),
                              ] else ...[
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.mail_outline,
                                      color: AppColors.primary,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        state.db.auth.currentUser?.email ?? '',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    if (hasPlan)
                                      const CrownIcon()
                                    else
                                      const Icon(
                                        Icons.person_outline,
                                        color: AppColors.primary,
                                      ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        hasPlan
                                            ? '${state.status['plan_name']} active'
                                            : !state.paidEnabled &&
                                                  state.adsAccess
                                            ? 'Full access'
                                            : 'Free account',
                                      ),
                                    ),
                                  ],
                                ),
                                if (eligible.isNotEmpty) ...[
                                  const SizedBox(height: 16),
                                  GradientButton(
                                    label: 'Upload content',
                                    icon: Icons.upload_outlined,
                                    onPressed: upload,
                                  ),
                                ],
                                if (state.paidEnabled)
                                  TextButton.icon(
                                    onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute<void>(
                                        builder: (_) => Payments(state: state),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.receipt_long_outlined,
                                    ),
                                    label: const Text('Payment history'),
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (state.paidEnabled) ...[
                        const SizedBox(height: 16),
                        ProfileTile(
                          icon: Icons.workspace_premium_outlined,
                          title: hasPlan ? 'Manage Premium' : 'Explore Premium',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => Plans(state: state),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                            'My Channels',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: createChannel,
                            icon: const Icon(Icons.add),
                            label: const Text('Add Channel'),
                          ),
                        ],
                      ),
                      if (loading)
                        const SkeletonList()
                      else if (failure != null)
                        ErrorRetry(onRetry: load)
                      else if (owned.isEmpty && joined.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Column(
                            children: [
                              Icon(
                                Icons.live_tv_outlined,
                                size: 48,
                                color: AppColors.muted,
                              ),
                              SizedBox(height: 12),
                              Text('No Record Found'),
                            ],
                          ),
                        )
                      else ...[
                        for (final row in owned)
                          profileChannel(row, mine: true),
                        for (final row in joined) profileChannel(row),
                      ],
                      const SizedBox(height: 24),
                      for (final policy in policyLabels.entries)
                        ProfileTile(
                          icon: Icons.description_outlined,
                          title: policy.key,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => Policy(name: policy.value),
                            ),
                          ),
                        ),
                      ProfileTile(
                        icon: Icons.support_agent,
                        title: 'Contact support',
                        subtitle: AppBrand.support,
                        onTap: () => openSupport(context),
                      ),
                      if (state.blocked.isNotEmpty) ...[
                        const SectionTitle('Blocked channels'),
                        for (final id in state.blocked)
                          ListTile(
                            title: const Text('Blocked channel'),
                            trailing: TextButton(
                              onPressed: () =>
                                  runAction(context, () => state.block(id)),
                              child: const Text('Unblock'),
                            ),
                          ),
                      ],
                      if (!state.guest) AccountControls(state: state),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
  Widget profileChannel(Map<String, dynamic> row, {bool mine = false}) {
    final approved =
        row['review_status'] == 'approved' &&
        ['published', 'active'].contains(row['status']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Card(
        child: InkWell(
          borderRadius: Radii.cardRadius,
          onTap: () => openChannel(row),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ChannelAvatar(channel: row, radius: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        row['name'] as String,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (!mine)
                  Text(
                    '${row['members_count'] ?? 0} members',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else if (approved)
                  TextButton.icon(
                    onPressed: () => upload(row),
                    icon: const Icon(Icons.upload_outlined),
                    label: const Text('Upload'),
                  )
                else
                  StatusPill(
                    row['review_status'] == 'pending'
                        ? 'Waiting for approval'
                        : 'Not approved',
                    tone: row['review_status'] == 'pending'
                        ? NoticeTone.warning
                        : NoticeTone.danger,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const policyLabels = {
  'Privacy Policy': 'Privacy',
  'Terms & Conditions': 'Terms',
  'Community Guidelines': 'Community rules',
  'Refund Policy': 'Refund',
};

class ProfileTile extends StatelessWidget {
  const ProfileTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Gap.m),
    child: Card(
      child: ListTile(
        shape: const RoundedRectangleBorder(borderRadius: Radii.cardRadius),
        leading: Icon(icon, color: AppColors.primary),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    ),
  );
}

Future<void> openSupport(BuildContext context) async {
  final uri = Uri(
    scheme: 'mailto',
    path: AppBrand.support,
    queryParameters: {'subject': '${AppBrand.name} support'},
  );
  if (!await launchUrl(uri) && context.mounted) {
    showFeedback(context, 'Email ${AppBrand.support} for help.');
  }
}

class AccountControls extends StatelessWidget {
  const AccountControls({super.key, required this.state});
  final AppState state;
  Future<void> remove(BuildContext context) async {
    final yes =
        await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('Delete account?'),
            content: const Text(
              'Your account, profile, channels and uploaded content will be deleted. Payment records are kept. This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (yes && context.mounted) {
      await runAction(context, () async {
        await state.db.functions.invoke(
          'delete-account',
          body: {'confirm': true},
        );
        await state.logout();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      OutlinedButton.icon(
        onPressed: () async {
          if (await confirmAction(
                context,
                title: 'Logout?',
                message: 'You can log in again at any time.',
                action: 'Logout',
              ) &&
              context.mounted) {
            await runAction(context, state.logout);
          }
        },
        icon: const Icon(Icons.logout),
        label: const Text('Logout'),
      ),
      TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: AppColors.danger),
        onPressed: () => remove(context),
        icon: const Icon(Icons.delete_outline),
        label: const Text('Delete Account'),
      ),
    ],
  );
}

class PoliciesPage extends StatelessWidget {
  const PoliciesPage({super.key});
  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Policies',
    body: ListView(
      padding: Gap.page,
      children: [
        for (final entry in policyLabels.entries)
          ProfileTile(
            icon: Icons.description_outlined,
            title: entry.key,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => Policy(name: entry.value),
              ),
            ),
          ),
      ],
    ),
  );
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, this.state});
  final AppState? state;
  @override
  Widget build(BuildContext context) => AppPage(
    title: 'App Setting',
    body: PageWidth(
      form: true,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const GlowHeader(child: Center(child: BrandMark())),
          const Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.dark_mode_outlined),
                  title: Text('Appearance'),
                  subtitle: Text('Dark theme'),
                ),
                Divider(),
                ListTile(
                  leading: Icon(Icons.text_fields),
                  title: Text('Text size'),
                  subtitle: Text('Follows your phone’s accessibility settings'),
                ),
                Divider(),
                ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text(AppBrand.name),
                  subtitle: Text('Version ${AppBrand.version}'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          for (final entry in policyLabels.entries)
            ProfileTile(
              icon: Icons.description_outlined,
              title: entry.key,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => Policy(name: entry.value),
                ),
              ),
            ),
          ProfileTile(
            icon: Icons.support_agent,
            title: 'Contact support',
            subtitle: AppBrand.support,
            onTap: () => openSupport(context),
          ),
          if (state != null)
            ListenableBuilder(
              listenable: state!,
              builder: (context, _) => state!.guest
                  ? const SizedBox.shrink()
                  : AccountControls(state: state!),
            ),
        ],
      ),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_state.dart';
import '../channel_page.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'channel_detail.dart';
import 'payments.dart';
import 'policies.dart';
import 'premium.dart';

class Profile extends StatelessWidget {
  const Profile({super.key, required this.state});
  final AppState state;
  Future<void> myChannels(BuildContext context) async {
    if (!await loginGate(context, state) || !context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AppPage(
          title: 'My channels',
          body: ChannelList(
            state: state,
            initialMine: true,
            onOpen: (channel) => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => ChannelDetail(state: state, channel: channel),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> createChannel(BuildContext context) async {
    if (!await loginGate(context, state) || !context.mounted) return;
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute<bool>(builder: (_) => ChannelEditor(state: state)),
    );
    if (created == true && context.mounted) {
      showFeedback(context, 'Channel created.');
      await myChannels(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = state.db.auth.currentUser?.email ?? '';
    final metadata = state.db.auth.currentUser?.userMetadata ?? {};
    final name = state.guest
        ? 'Guest'
        : metadata['display_name'] as String? ??
              metadata['full_name'] as String? ??
              email.split('@').first;
    final avatar = {'name': name, 'icon_url': metadata['avatar_url']};
    return RefreshIndicator(
      onRefresh: state.refreshStatus,
      child: PageWidth(
        form: true,
        child: ListView(
          key: const PageStorageKey('profile-scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          padding: Gap.page,
          children: [
            GlowHeader(
              child: Column(
                children: [
                  ChannelAvatar(channel: avatar, radius: AppSizes.avatarLarge),
                  const SizedBox(height: Gap.l),
                  Text(
                    name,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  if (!state.guest) ...[
                    const SizedBox(height: Gap.xs),
                    Text(
                      email,
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: Gap.l),
                  if (state.guest)
                    GradientButton(
                      label: 'Log in',
                      icon: Icons.login,
                      onPressed: () => loginGate(context, state),
                    )
                  else if (!state.paidEnabled)
                    const StatusPill('Free account', tone: NoticeTone.success)
                  else if (state.status['plan_name'] != null)
                    const PremiumBadge()
                  else
                    const StatusPill('Free account'),
                ],
              ),
            ),
            if (state.paidEnabled && !state.premium) ...[
              NoticeCard(
                title: 'A little more Vayora',
                message: 'Explore Premium plans.',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => Plans(state: state)),
                ),
              ),
              const SizedBox(height: Gap.l),
            ],
            if (state.paidEnabled)
              ProfileTile(
                icon: Icons.receipt_long_outlined,
                title: 'Payment history',
                onTap: () async {
                  if (await loginGate(context, state) && context.mounted) {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => Payments(state: state),
                      ),
                    );
                  }
                },
              ),
            ProfileTile(
              icon: Icons.live_tv_outlined,
              title: 'My channels',
              onTap: () => myChannels(context),
            ),
            ProfileTile(
              icon: Icons.add_circle_outline,
              title: 'Create channel',
              onTap: () => createChannel(context),
            ),
            ProfileTile(
              icon: Icons.settings_outlined,
              title: 'Settings',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
              ),
            ),
            ProfileTile(
              icon: Icons.help_outline,
              title: 'Help & support',
              onTap: () => openSupport(context),
            ),
            ProfileTile(
              icon: Icons.policy_outlined,
              title: 'Policies',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const PoliciesPage()),
              ),
            ),
            if (state.blocked.isNotEmpty) ...[
              const SizedBox(height: Gap.l),
              const SectionTitle('Blocked channels'),
              const SizedBox(height: Gap.s),
              for (final id in state.blocked)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.block),
                    title: const Text('Blocked channel'),
                    trailing: TextButton(
                      onPressed: () => runAction(context, () async {
                        await state.block(id);
                        if (context.mounted) {
                          showFeedback(context, 'Channel unblocked.');
                        }
                      }),
                      child: const Text('Unblock'),
                    ),
                  ),
                ),
            ],
            if (!state.guest) ...[
              ProfileTile(
                icon: Icons.logout_rounded,
                title: 'Log out',
                onTap: () async {
                  if (!await confirmAction(
                        context,
                        title: 'Log out?',
                        message: 'You can log in again whenever you’re ready.',
                        action: 'Log out',
                        icon: Icons.logout_rounded,
                      ) ||
                      !context.mounted) {
                    return;
                  }
                  await runAction(context, () async {
                    await state.logout();
                    if (context.mounted) {
                      showFeedback(context, 'You’re logged out.');
                    }
                  });
                },
              ),
              const SizedBox(height: Gap.xl),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete account'),
                onPressed: () async {
                  final yes = await confirmAction(
                    context,
                    title: 'Delete your account?',
                    message:
                        'This permanently deletes your account and uploaded content. Payment records are retained.',
                    action: 'Delete account',
                    icon: Icons.delete_outline,
                    destructive: true,
                  );
                  if (yes && context.mounted) {
                    await runAction(context, () async {
                      await state.db.functions.invoke(
                        'delete-account',
                        body: {'confirm': true},
                      );
                      await state.logout();
                      if (context.mounted) {
                        showFeedback(context, 'Your account was deleted.');
                      }
                    });
                  }
                },
              ),
            ],
            const SizedBox(height: Gap.xl),
          ],
        ),
      ),
    );
  }
}

class ProfileTile extends StatelessWidget {
  const ProfileTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Gap.m),
    child: PressScale(
      onTap: onTap,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Gap.l),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primary),
              const SizedBox(width: Gap.l),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> openSupport(BuildContext context) async {
  if (!await launchUrl(Uri(scheme: 'mailto', path: AppBrand.support)) &&
      context.mounted) {
    showFeedback(context, 'Email ${AppBrand.support} for help.');
  }
}

class PoliciesPage extends StatelessWidget {
  const PoliciesPage({super.key});
  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Policies',
    body: PageWidth(
      form: true,
      child: ListView(
        padding: Gap.page,
        children: [
          const SectionTitle('A good place for everyone'),
          const SizedBox(height: Gap.l),
          for (final name in const [
            'Privacy',
            'Terms',
            'Refund',
            'Community rules',
          ])
            ProfileTile(
              icon: Icons.description_outlined,
              title: name,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => Policy(name: name)),
              ),
            ),
        ],
      ),
    ),
  );
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Settings',
    body: PageWidth(
      form: true,
      child: ListView(
        padding: Gap.page,
        children: [
          const GlowHeader(child: Center(child: BrandMark())),
          const SectionTitle('Made for your screen'),
          const SizedBox(height: Gap.l),
          const Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.dark_mode_outlined),
                  title: Text('Appearance'),
                  subtitle: Text('Cinematic dark'),
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
          const SizedBox(height: Gap.xl),
          OutlinedButton.icon(
            onPressed: () => openSupport(context),
            icon: const Icon(Icons.help_outline),
            label: const Text('Help & support'),
          ),
        ],
      ),
    ),
  );
}

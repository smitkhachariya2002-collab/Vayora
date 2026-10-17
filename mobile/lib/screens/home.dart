import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../account_page.dart';
import '../app_state.dart';
import '../channel_page.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'channel_detail.dart';
import 'cloud.dart';
import 'content.dart';
import 'policies.dart';
import 'premium.dart';
import 'profile.dart';

class Home extends StatefulWidget {
  const Home({super.key, required this.state});
  final AppState state;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  int selected = 2;
  final visited = <int>{2};
  final storage = PageStorageBucket();
  bool showingRecovery = false, searching = false;
  String search = '';
  late final StreamSubscription<AuthState> auth;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.state.addListener(checkRecovery);
    auth = widget.state.db.auth.onAuthStateChange.listen((event) {
      if (!mounted) return;
      if (event.event == AuthChangeEvent.signedIn ||
          event.event == AuthChangeEvent.userUpdated ||
          event.event == AuthChangeEvent.passwordRecovery) {
        unawaited(runAction(context, widget.state.afterLogin));
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.state.prefs.getBool('consent_v1') != true) consent();
      checkRecovery();
    });
  }

  void checkRecovery() {
    if (!mounted || showingRecovery || !widget.state.recoveringPassword) return;
    showingRecovery = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ResetPassword(state: widget.state),
        ),
      );
      showingRecovery = false;
    });
  }

  Future<void> consent() async {
    var agreed = false, busy = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => PopScope(
        canPop: false,
        child: StatefulBuilder(
          builder: (dialog, update) => AlertDialog(
            title: const Center(child: BrandMark()),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Welcome to ${AppBrand.name}',
                    style: Theme.of(dialog).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Gap.m),
                  const Text(
                    'A space to explore, share and connect. Please review our policies before continuing.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Gap.m),
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      for (final name in const [
                        'Privacy',
                        'Terms',
                        'Refund',
                        'Community rules',
                      ])
                        TextButton(
                          onPressed: () => Navigator.push(
                            dialog,
                            MaterialPageRoute<void>(
                              builder: (_) => Policy(name: name),
                            ),
                          ),
                          child: Text(name),
                        ),
                    ],
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('I agree'),
                    value: agreed,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (value) => update(() => agreed = value == true),
                  ),
                ],
              ),
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: GradientButton(
                  label: 'Continue',
                  busy: busy,
                  onPressed: agreed && !busy
                      ? () async {
                          update(() => busy = true);
                          await runAction(dialog, () async {
                            await widget.state.acceptConsent();
                            if (dialog.mounted) Navigator.pop(dialog);
                          });
                          if (dialog.mounted) update(() => busy = false);
                        }
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    if (value == AppLifecycleState.resumed) {
      unawaited(runAction(context, widget.state.afterLogin));
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(checkRecovery);
    auth.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void tab(int index) => setState(() {
    selected = index;
    visited.add(index);
  });
  Widget page(int index) {
    final state = widget.state;
    return switch (index) {
      0 => CloudView(key: const PageStorageKey('cloud'), state: state),
      1 => ContentList(
        key: const PageStorageKey('feed'),
        state: state,
        feed: true,
        onExploreChannels: () => tab(3),
      ),
      2 => Column(
        children: [
          if (searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.s, Gap.xl, Gap.s),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search stories and channels',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => search = value),
              ),
            ),
          Expanded(
            child: ContentList(
              key: const PageStorageKey('explore'),
              state: state,
              search: search,
              onExploreChannels: () => tab(3),
            ),
          ),
        ],
      ),
      3 => ChannelList(
        key: const PageStorageKey('channels'),
        state: state,
        onOpen: (channel) => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => ChannelDetail(state: state, channel: channel),
          ),
        ),
      ),
      _ => Profile(key: const PageStorageKey('profile'), state: state),
    };
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) {
      final state = widget.state;
      return AppPage(
        title: const [
          'Cloud',
          'Feed',
          AppBrand.name,
          'Channels',
          'Profile',
        ][selected],
        actions: [
          if (selected == 2)
            IconButton(
              tooltip: searching ? 'Close search' : 'Search',
              icon: Icon(searching ? Icons.close : Icons.search),
              onPressed: () => setState(() {
                searching = !searching;
                if (!searching) search = '';
              }),
            ),
          CrownButton(
            visible: state.paidEnabled,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => Plans(state: state)),
            ),
          ),
        ],
        body: PageStorage(
          bucket: storage,
          child: IndexedStack(
            index: selected,
            children: List.generate(
              5,
              (index) => visited.contains(index)
                  ? TickerMode(enabled: index == selected, child: page(index))
                  : const SizedBox.shrink(),
            ),
          ),
        ),
        fab: selected == 0
            ? FloatingActionButton(
                tooltip: 'Cloud options',
                onPressed: () => showCloudActions(context, state),
                child: const Icon(Icons.add),
              )
            : null,
        navigation: DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.navigation,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: NavigationBar(
            height:
                MediaQuery.textScalerOf(context).scale(AppSizes.body) >
                    AppSizes.title
                ? AppSizes.navAccessible
                : AppSizes.nav,
            selectedIndex: selected,
            onDestinationSelected: tab,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.cloud_upload_outlined),
                selectedIcon: Icon(Icons.cloud_upload),
                label: 'Cloud',
              ),
              NavigationDestination(
                icon: Icon(Icons.public_outlined),
                selectedIcon: Icon(Icons.public),
                label: 'Feed',
              ),
              NavigationDestination(icon: Icon(Icons.search), label: 'Explore'),
              NavigationDestination(
                icon: Icon(Icons.live_tv_outlined),
                selectedIcon: Icon(Icons.live_tv),
                label: 'Channels',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          ),
        ),
      );
    },
  );
}

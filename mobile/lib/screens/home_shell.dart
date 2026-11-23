import 'package:flutter/material.dart';

import '../services/app_scope.dart';
import '../services/measurement.dart';
import '../services/push_notifications.dart';
import 'channels_screen.dart';
import 'cloud_screen.dart';
import 'explore_screen.dart';
import 'feed_screen.dart';
import 'profile_screen.dart';
import '../widgets/vayora_nav_bar.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _i = 2;
  void _tab(int index){setState(()=>_i=index);Measurement.instance.track('ScreenView',{'screen':['Cloud','Feed','Explore','Channels','Profile'][index]});}

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_)=>PushNotifications.instance.drainPending());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // Retry queued payment results on every resume.
    if (s == AppLifecycleState.resumed) {
      final app = AppScope.of(context);
      Measurement.instance.resumed();
      PushNotifications.instance.refreshRegistration();
      app.flushPending();
      app.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (!app.loaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    // Explore is the default tab; profile retains the existing account and Premium actions.
    final pages = [
      const CloudScreen(),
      const FeedScreen(),
      const ExploreScreen(),
      const ChannelsScreen(),
      const ProfileScreen(),
    ];
    return Scaffold(
      body: SafeArea(bottom: false, child: IndexedStack(index: _i, children: pages)),
      bottomNavigationBar: VayoraNavBar(
        index: _i,
        onTap: _tab,
        items: [
          const NavItem(Icons.cloud_outlined, 'Cloud', Icons.cloud),
          const NavItem(Icons.grid_view_outlined, 'Feed', Icons.grid_view_rounded),
          const NavItem(Icons.explore_outlined, 'Explore', Icons.explore),
          const NavItem(Icons.live_tv_outlined, 'Channels', Icons.live_tv),
          const NavItem(Icons.person_outline, 'Profile', Icons.person),
        ],
      ),
    );
  }
}


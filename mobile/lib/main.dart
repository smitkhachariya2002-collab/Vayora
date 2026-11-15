import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'screens/consent_gate.dart';
import 'screens/home_shell.dart';
import 'services/app_scope.dart';
import 'services/app_state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: Config.supabaseUrl, publishableKey: Config.supabaseKey);
  final state = AppState();
  runApp(VayoraApp(state: state));
  state.start();
}

class VayoraApp extends StatelessWidget {
  const VayoraApp({super.key, required this.state});
  final AppState state;

  // AppScope must sit ABOVE MaterialApp so every pushed route (payment status, history, upgrade...) can find it.
  @override
  Widget build(BuildContext context) => AppScope(
      state: state,
      child: MaterialApp(
        title: Config.appName,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: MediaQuery.textScalerOf(context).clamp(minScaleFactor: .9, maxScaleFactor: 1.1)),
          child: child!,
        ),
        home: const ConsentGate(child: HomeShell()),
      ));
}

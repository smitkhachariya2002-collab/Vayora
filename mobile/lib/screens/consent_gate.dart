import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../services/measurement.dart';
import 'measurement_preferences.dart';
import '../theme.dart';

const consentPrefKey = 'terms_accepted_v1';

Future<void> _askNotifications() async {
  try {
    await Permission.notification.request();
  } catch (_) {/* not available: ignore */}
}

/// Shows "Terms of Service and Privacy Policy" once, on first open. The app is blocked until the
/// user agrees; afterwards the system notification permission prompt is shown.
class ConsentGate extends StatefulWidget {
  const ConsentGate({super.key, required this.child, this.requestNotifications = _askNotifications});
  final Widget child;
  final Future<void> Function() requestNotifications;
  @override
  State<ConsentGate> createState() => _ConsentGateState();
}

class _ConsentGateState extends State<ConsentGate> {
  bool _termsReady=false, _shown=false;
  void _ready(){if(_termsReady)_measurement();}
  @override
  void initState() {
    super.initState();
    Measurement.instance.addListener(_ready);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    if(p.getBool(consentPrefKey)==true){_termsReady=true;await _measurement();return;}
    final agreed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: .75),
      builder: (_) => const PopScope(canPop: false, child: ConsentDialog()),
    );
    if (agreed == true) {
      await p.setBool(consentPrefKey, true);
      await widget.requestNotifications();
      _termsReady=true;
      await _measurement();
    }
  }

  Future<void> _measurement() async {
    if(!mounted||_shown||!Measurement.instance.ready||Measurement.instance.hasChoice)return;
    _shown=true;
    await Navigator.push(context,MaterialPageRoute(builder:(_)=>const MeasurementPreferences()));
  }

  @override
  void dispose(){Measurement.instance.removeListener(_ready);super.dispose();}

  @override
  Widget build(BuildContext context) => widget.child;
}

class ConsentDialog extends StatefulWidget {
  const ConsentDialog({super.key});
  @override
  State<ConsentDialog> createState() => _ConsentDialogState();
}

class _ConsentDialogState extends State<ConsentDialog> {
  late final TapGestureRecognizer _privacy;
  late final TapGestureRecognizer _terms;

  Future<void> _open(String path) => launchUrl(Uri.parse('${Config.websiteUrl}$path'), mode: LaunchMode.externalApplication);

  @override
  void initState() {
    super.initState();
    _privacy = TapGestureRecognizer()..onTap = () => _open('/privacy');
    _terms = TapGestureRecognizer()..onTap = () => _open('/terms');
  }

  @override
  void dispose() {
    _privacy.dispose();
    _terms.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const link = TextStyle(color: Tokens.accent, decoration: TextDecoration.underline, decorationColor: Tokens.accent);
    return Dialog(
      backgroundColor: Tokens.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28), side: BorderSide(color: Tokens.primary.withValues(alpha: .35))),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(borderRadius: BorderRadius.circular(22), child: Image.asset('assets/icon.png', width: 76, height: 76, errorBuilder: (_, __, ___) => const SizedBox(width: 76, height: 76))),
          const SizedBox(height: 20),
          const Text('Terms of Service and Privacy Policy', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Text.rich(
            TextSpan(style: const TextStyle(color: Tokens.muted, height: 1.5), children: [
              const TextSpan(text: 'Welcome to ${Config.appName}. By using this app, you acknowledge that you understand how we collect, use and protect your personal data, as well as your rights and responsibilities as a user. Please review and accept our '),
              TextSpan(text: 'Privacy Policy', style: link, recognizer: _privacy),
              const TextSpan(text: ' and '),
              TextSpan(text: 'Terms & Conditions', style: link, recognizer: _terms),
              const TextSpan(text: '. Optional advertising and analytics choices are separate and are off by default.'),
            ]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 22),
          SizedBox(width: double.infinity, child: GradientButton(label: 'Agree and continue', onPressed: () => Navigator.pop(context, true))),
        ]),
      ),
    );
  }
}


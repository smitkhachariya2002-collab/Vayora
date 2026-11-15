import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../services/measurement.dart';
import '../theme.dart';

const consentPrefKey = Config.consentPrefKey;
class ConsentChoice {
  const ConsentChoice(this.analytics,this.advertising);
  final bool analytics,advertising;
}

/// One first-open dialog holds required terms and separate optional sharing choices.
class ConsentGate extends StatefulWidget {
  const ConsentGate({super.key, required this.child});
  final Widget child;
  @override
  State<ConsentGate> createState() => _ConsentGateState();
}

class _ConsentGateState extends State<ConsentGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    if(p.getBool(consentPrefKey)==true)return;
    final choice = await showDialog<ConsentChoice>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: .75),
      builder: (_) => const PopScope(canPop: false, child: ConsentDialog()),
    );
    if (choice != null) {
      await Measurement.instance.saveInitialChoice(choice.analytics,choice.advertising);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class ConsentDialog extends StatefulWidget {
  const ConsentDialog({super.key});
  @override
  State<ConsentDialog> createState() => _ConsentDialogState();
}

class _ConsentDialogState extends State<ConsentDialog> {
  bool accepted=false,analytics=false,advertising=false;
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
          const Text('Welcome to Vayora', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Text.rich(
            TextSpan(style: const TextStyle(color: Tokens.muted, height: 1.5), children: [
              const TextSpan(text: 'We process account details, uploaded files, purchases and security information to provide Vayora. Read how we use and retain data, who receives it, and how to delete your account in our '),
              TextSpan(text: 'Privacy Policy', style: link, recognizer: _privacy),
              const TextSpan(text: ' and '),
              TextSpan(text: 'Terms & Conditions', style: link, recognizer: _terms),
              const TextSpan(text: '. Choose below. Optional sharing is off unless you enable it. Google Ads is not used.'),
            ]),
            textAlign: TextAlign.center,
          ),
          CheckboxListTile(key:const Key('accept_terms'),contentPadding:EdgeInsets.zero,value:accepted,onChanged:(v)=>setState(()=>accepted=v??false),title:const Text('I am 18 or older and accept the Terms & Conditions and Privacy Policy.')),
          SwitchListTile(key:const Key('consent_analytics'),contentPadding:EdgeInsets.zero,value:analytics,onChanged:(v)=>setState(()=>analytics=v),title:const Text('Optional app analytics'),subtitle:const Text('Share app activity and session information with Vayora to understand usage and improve the service.')),
          SwitchListTile(key:const Key('consent_meta'),contentPadding:EdgeInsets.zero,value:advertising,onChanged:(v)=>setState(()=>advertising=v),title:const Text('Optional Meta/Facebook measurement'),subtitle:const Text('Send app activity, video-use milestones and verified purchase value/currency to Meta for ad measurement and optimisation. Includes hashed account/email identifiers, an install ID, IP address, browser/device information and available ad-click identifiers. Meta can match this with its own data. Passwords, UPI credentials, UTRs and private files are never sent.')),
          const Text('Both optional choices can stay off. They do not change your plan, storage or content access. Change them anytime in Profile → Measurement preferences. Withdrawal stops future sharing and cancels unsent events; it cannot recall data Meta already received.',style:TextStyle(color:Tokens.muted,fontSize:12,height:1.5)),
          const SizedBox(height: 18),
          SizedBox(width: double.infinity, child: FilledButton(key:const Key('consent_continue'),onPressed:accepted?()=>Navigator.pop(context,ConsentChoice(analytics,advertising)):null,child:const Text('Accept terms and save choices'))),
        ]),
      ),
    );
  }
}


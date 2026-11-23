import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../services/app_scope.dart';
import '../services/app_state.dart';
import '../services/measurement.dart';
import '../theme.dart';

/// Returns true when the user ended up with a real account.
Future<bool> requireAccount(BuildContext context) async {
  final app = AppScope.of(context);
  if (!app.status.isGuest) return true;
  // A guest who already bought a plan adds an email to this same account (keeps the plan).
  final save = app.status.isPremium;
  return showLoginSheet(context, signup: save, saveMode: save);
}

/// [signup] opens on "Sign up". [saveMode] = a guest who already has a plan is adding an email to keep it.
Future<bool> showLoginSheet(BuildContext context, {bool signup = false, bool saveMode = false}) async {
  final app = AppScope.of(context);
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Tokens.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => LoginSheet(startSignup: signup, saveMode: saveMode),
  );
  await app.refresh();
  return ok == true;
}

class LoginSheet extends StatefulWidget {
  const LoginSheet({super.key, this.startSignup = false, this.saveMode = false});
  final bool startSignup, saveMode;
  @override
  State<LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends State<LoginSheet> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  late bool _signup = widget.startSignup;
  bool _busy = false, _hide = true;
  String? _err, _info;
  StreamSubscription<AuthState>? _googleSubscription;
  bool _googleFallback=false;
  Future<void> _recoverGoogle(Object error) async {
    if(!mounted)return;
    final code=error is AuthException?error.code:null;
    if(!['identity_already_exists','identity_already_linked','email_exists'].contains(code)||_googleFallback){setState(()=>_err="Google login didn't finish. Please try again.");return;}
    _googleFallback=true;
    if(AppScope.of(context).status.isPremium&&sb.auth.currentUser?.isAnonymous==true){
      final proceed=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Use your existing Google account?'),content:const Text('This Google account already has a Vayora account. Logging in restores that account. The plan on this guest session is not automatically merged; contact support before switching if you need to retain it.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Keep this guest session')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Log in to existing account'))]));
      if(proceed!=true){_googleFallback=false;return;}
    }
    try{await sb.auth.signInWithOAuth(OAuthProvider.google,redirectTo:'${Config.authScheme}://login-callback',authScreenLaunchMode:LaunchMode.externalApplication,queryParams:{'prompt':'select_account'});if(mounted)setState(()=>_info='Choose your existing Google account to restore it.');}
    catch(_){if(mounted)setState(()=>_err="Google login didn't finish. Please try again.");}
  }

  Future<void> _google() async {
    _googleFallback=false;
    setState(() { _busy = true; _err = null; _info = null; });
    await _googleSubscription?.cancel();
    if (!mounted) { return; }
    // Linking upgrades the guest UUID instead of abandoning its purchases/files.
    final linkGuest = sb.auth.currentUser?.isAnonymous == true &&
        (_signup || widget.saveMode || AppScope.of(context).status.isPremium);
    _googleSubscription = sb.auth.onAuthStateChange.listen((state) {
      if (!mounted || state.session?.user.isAnonymous != false ||
          (state.event != AuthChangeEvent.signedIn && state.event != AuthChangeEvent.userUpdated)) { return; }
      unawaited(_googleSubscription?.cancel());
      _googleSubscription = null;
      Navigator.pop(context, true);
    }, onError: (Object error) {
      unawaited(_recoverGoogle(error));
    });
    try {
      final launched = linkGuest
          ? await sb.auth.linkIdentity(OAuthProvider.google,
              redirectTo: '${Config.authScheme}://login-callback',
              authScreenLaunchMode: LaunchMode.externalApplication,
              queryParams: {'prompt': 'select_account'})
          : await sb.auth.signInWithOAuth(OAuthProvider.google,
              redirectTo: '${Config.authScheme}://login-callback',
              authScreenLaunchMode: LaunchMode.externalApplication,
              queryParams: {'prompt': 'select_account'});
      if (!launched) { throw const AuthException('Could not open your browser. Please try again.'); }
      if (mounted) setState(() => _info = 'Finish signing in with Google in your browser. If you cancelled, tap Google again to retry.');
    } on AuthException catch (e) {
      if(['identity_already_exists','identity_already_linked','email_exists'].contains(e.code)){await _recoverGoogle(e);return;}
      await _googleSubscription?.cancel();
      _googleSubscription = null;
      if (mounted) setState(() => _err = e.code == 'identity_already_exists'
          ? 'This Google account already belongs to another Vayora account. Your guest plan is unchanged. Contact support to keep both accounts safe.'
          : e.message);
    } catch (_) {
      await _googleSubscription?.cancel();
      _googleSubscription = null;
      if (mounted) setState(() => _err = 'Could not start Google sign-in. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    unawaited(_googleSubscription?.cancel());
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  void _mode(bool signup) {
    unawaited(_googleSubscription?.cancel());
    _googleSubscription = null;
    setState(() { _signup = signup; _err = null; _info = null; });
  }

  String? _validate(String email) {
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) return 'Enter a valid email address.';
    if (_pass.text.length < 6) return 'Password must be at least 6 characters.';
    return null;
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final bad = _validate(email);
    if (bad != null) return setState(() { _err = bad; _info = null; });
    // A browser sign-in retry must not also close an email login's route.
    await _googleSubscription?.cancel();
    _googleSubscription = null;
    if (!mounted) { return; }
    setState(() { _busy = true; _err = null; _info = null; });
    try {
      if (_signup) {
        if (sb.auth.currentSession == null) {
          final r = await sb.auth.signUp(email: email, password: _pass.text, emailRedirectTo: '${Config.authScheme}://login-callback');
          if (r.session != null) {
            await Measurement.instance.start();await Measurement.instance.track('CompleteRegistration');
            if (mounted) Navigator.pop(context, true);
          } else {
            setState(() => _info = 'We sent a confirmation link to $email. Open it, then come back and log in.');
          }
          return;
        }
        // Guest -> member upgrade keeps the same user id (so a guest purchase stays on this account).
        await sb.auth.updateUser(
          UserAttributes(email: email, password: _pass.text),
          emailRedirectTo: '${Config.authScheme}://login-callback',
        );
        if (sb.auth.currentUser?.isAnonymous == false) {
          await Measurement.instance.start();await Measurement.instance.track('CompleteRegistration');
          if (mounted) Navigator.pop(context, true);
        } else {
          setState(() => _info = 'We sent a confirmation link to $email. Tap it to finish saving your account.');
        }
      } else {
        await sb.auth.signInWithPassword(email: email, password: _pass.text);
        await Measurement.instance.start();await Measurement.instance.track('Login');
        if (mounted) Navigator.pop(context, true);
      }
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      setState(() {
        if (m.contains('already') || m.contains('registered') || m.contains('exists')) {
          _err = 'This email already has an account. Tap "Log in" above to use it.';
        } else if (m.contains('invalid login') || m.contains('invalid credentials')) {
          _err = 'Wrong email or password.';
        } else if (m.contains('not confirmed')) {
          _err = 'Please confirm your email first. Check your inbox for our link.';
        } else {
          _err = e.message;
        }
      });
    } catch (_) {
      setState(() => _err = 'Something went wrong. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (email.isEmpty) return setState(() { _err = 'Enter your email above first.'; _info = null; });
    try {
      await sb.auth.resetPasswordForEmail(email, redirectTo: '${Config.authScheme}://login-callback');
      setState(() { _err = null; _info = 'Password reset link sent to $email.'; });
    } catch (_) {
      setState(() => _err = 'Could not send the reset email. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.saveMode ? 'Save your plan' : (_signup ? 'Create your account' : 'Welcome back');
    final sub = widget.saveMode
        ? 'Add an email and password. Your plan stays on this account and works on any phone.'
        : (_signup ? 'Create your account with email and password.' : 'Log in to your Vayora account.');
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 10, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Tokens.border, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          if (!widget.saveMode) _Tabs(signup: _signup, onChange: _mode),
          if (!widget.saveMode) const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(sub, style: const TextStyle(color: Tokens.muted, fontSize: 13)),
          const SizedBox(height: 16),
          TextField(
            key: const Key('login_email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline, size: 20)),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('login_password'),
            controller: _pass,
            obscureText: _hide,
            autofillHints: [_signup ? AutofillHints.newPassword : AutofillHints.password],
            onSubmitted: (_) => _busy ? null : _submit(),
            decoration: InputDecoration(
              labelText: 'Password',
              helperText: _signup ? 'At least 6 characters' : null,
              prefixIcon: const Icon(Icons.lock_outline, size: 20),
              suffixIcon: IconButton(tooltip: _hide ? 'Show password' : 'Hide password', icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20), onPressed: () => setState(() => _hide = !_hide)),
            ),
          ),
          if (!_signup)
            Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _forgot, child: const Text('Forgot password?'))),
          if (_err != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_err!, style: const TextStyle(color: Tokens.danger, fontSize: 13))),
          if (_info != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_info!, style: const TextStyle(color: Tokens.success, fontSize: 13))),
          const SizedBox(height: 12),
          GradientButton(label: _busy ? 'Please wait…' : (widget.saveMode ? 'Save account' : (_signup ? 'Create account' : 'Log in')), onPressed: _busy ? null : _submit),
          ...[
            const SizedBox(height: 14),
            const Row(children: [
              Expanded(child: Divider(color: Tokens.border)),
              Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('or', style: TextStyle(color: Tokens.muted, fontSize: 12))),
              Expanded(child: Divider(color: Tokens.border)),
            ]),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('google_login'),
              onPressed: _busy ? null : _google,
              icon: const Icon(Icons.g_mobiledata, size: 26),
              label: const Text('Continue with Google', maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(widget.saveMode ? 'Not now' : 'Maybe later')),
        ]),
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.signup, required this.onChange});
  final bool signup;
  final ValueChanged<bool> onChange;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: Tokens.background, borderRadius: BorderRadius.circular(14), border: Border.all(color: Tokens.border)),
        child: Row(children: [
          for (final e in {'Log in': false, 'Sign up': true}.entries)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChange(e.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(gradient: signup == e.value ? Tokens.gradient : null, borderRadius: BorderRadius.circular(10)),
                  child: Text(e.key, style: TextStyle(fontWeight: FontWeight.w600, color: signup == e.value ? Colors.white : Tokens.muted)),
                ),
              ),
            ),
        ]),
      );
}

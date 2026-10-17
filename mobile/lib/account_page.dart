import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_state.dart';

Future<bool> ensureSignedIn(BuildContext context, AppState state) async {
  if (!state.guest) return true;
  await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => Login(state: state)));
  return !state.guest;
}

class Login extends StatefulWidget {
  const Login({super.key, required this.state});
  final AppState state;
  @override
  State<Login> createState() => _LoginState();
}
class _LoginState extends State<Login> {
  final email = TextEditingController(), password = TextEditingController();
  final form = GlobalKey<FormState>();
  bool create = false, busy = false, hidden = true;
  String? failure, notice;
  @override
  void initState() { super.initState(); widget.state.addListener(accountChanged); }
  void accountChanged() {
    if (mounted && !widget.state.guest && ModalRoute.of(context)?.isCurrent == true) Navigator.pop(context);
  }
  @override
  void dispose() {
    widget.state.removeListener(accountChanged);
    email.dispose(); password.dispose(); super.dispose();
  }
  String? validateEmail(String? value) => RegExp(r'^[^ @]+@[^ @]+[.][^ @]+$').hasMatch(value?.trim() ?? '')
      ? null : 'Enter a valid email address';
  Future<void> perform(Future<void> Function() action) async {
    if (busy) return;
    setState(() { busy = true; failure = null; notice = null; });
    try { await action(); }
    on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.code == 'email_exists' || e.code == 'user_already_exists') {
          create = false;
          failure = 'This email already has an account. Log in or reset your password.';
        } else if (e.code == 'invalid_credentials') {
          failure = 'The email or password is incorrect. Try again or reset your password.';
        } else if (e.code == 'email_not_confirmed') {
          failure = 'Please confirm your email before logging in.';
        } else {
          failure = 'Could not complete this request. Please try again.';
        }
      });
    } on Object {
      if (mounted) setState(() => failure = 'Could not connect. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Your Vayora account')),
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520),
      child: Form(key: form, child: ListView(padding: const EdgeInsets.all(24), children: [
        Text(create ? 'Join Vayora' : 'Welcome back', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(create ? 'Create your account to start sharing and exploring.' : 'Log in to continue where you left off.'),
        const SizedBox(height: 24),
        SegmentedButton<bool>(
          segments: const [ButtonSegment(value: false, label: Text('Log in')), ButtonSegment(value: true, label: Text('Sign up'))],
          selected: {create}, showSelectedIcon: false,
          onSelectionChanged: busy ? null : (values) => setState(() { create = values.single; failure = null; notice = null; form.currentState?.reset(); }),
        ),
        const SizedBox(height: 24),
        TextFormField(key: const ValueKey('login-email'), controller: email, enabled: !busy,
          keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(labelText: 'Email address', prefixIcon: Icon(Icons.mail_outline)),
          validator: validateEmail),
        const SizedBox(height: 16),
        TextFormField(key: const ValueKey('login-password'), controller: password, enabled: !busy, obscureText: hidden,
          autofillHints: create ? const [AutofillHints.newPassword] : const [AutofillHints.password],
          decoration: InputDecoration(labelText: 'Password', helperText: create ? 'Use at least 8 characters' : null,
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(tooltip: hidden ? 'Show password' : 'Hide password',
              onPressed: () => setState(() => hidden = !hidden), icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined))),
          validator: (value) => value == null || value.isEmpty ? 'Enter your password' :
            create && value.length < 8 ? 'Use at least 8 characters' : null),
        if (failure != null) Padding(padding: const EdgeInsets.only(top: 16),
          child: Text(failure!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        if (notice != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(notice!)),
        const SizedBox(height: 24),
        FilledButton(key: const ValueKey('account-submit'), onPressed: busy ? null : () {
          if (form.currentState?.validate() != true) return;
          perform(() async {
            await widget.state.login(email.text.trim(), password.text, create: create);
            if (mounted && create && widget.state.guest) setState(() => notice = 'Check your email to confirm your account.');
          });
        }, child: Padding(padding: const EdgeInsets.all(12), child: Text(busy ? 'Please wait…' : create ? 'Sign up' : 'Log in'))),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: busy ? null : () => perform(() => widget.state.google(linkGuest: create)),
          child: const Padding(padding: EdgeInsets.all(12), child: Text('Continue with Google'))),
        if (!create) TextButton(onPressed: busy ? null : () {
          if (validateEmail(email.text) != null) { setState(() => failure = 'Enter your email address first.'); return; }
          perform(() async {
            await widget.state.sendPasswordReset(email.text.trim());
            if (mounted) setState(() => notice = 'Check your email for the password reset link.');
          });
        }, child: const Text('Forgot password?')),
        if (create) const Padding(padding: EdgeInsets.only(top: 16),
          child: Text('We’ll send you an email to confirm your address.')),
      ])),
    )),
  );
}

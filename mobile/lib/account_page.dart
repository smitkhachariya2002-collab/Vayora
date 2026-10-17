import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_state.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'screens/policies.dart';

Future<bool> ensureSignedIn(BuildContext context, AppState state) async {
  if (!state.guest) return true;
  final continueToLogin = await confirmAction(
    context,
    title: 'Please log in',
    message: 'Log in to continue. You’ll come back to this screen.',
    action: 'Log in',
    icon: Icons.lock_outline,
  );
  if (!continueToLogin || !context.mounted) return false;
  await Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => Login(state: state)),
  );
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
  void initState() {
    super.initState();
    widget.state.addListener(accountChanged);
  }

  void accountChanged() {
    if (mounted &&
        !widget.state.guest &&
        ModalRoute.of(context)?.isCurrent == true) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(accountChanged);
    email.dispose();
    password.dispose();
    super.dispose();
  }

  String? validateEmail(String? value) =>
      RegExp(r'^[^ @]+@[^ @]+[.][^ @]+$').hasMatch(value?.trim() ?? '')
      ? null
      : 'Enter a valid email address';
  Future<void> perform(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      failure = null;
      notice = null;
    });
    try {
      await action();
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.code == 'provider_disabled') {
          failure = 'Google sign-in is coming soon. Please log in with email.';
        } else if (e.code == 'email_exists' || e.code == 'user_already_exists') {
          create = false;
          failure =
              'This email already has an account. Log in or reset your password.';
        } else if (e.code == 'invalid_credentials') {
          failure =
              'The email or password is incorrect. Try again or reset your password.';
        } else if (e.code == 'email_not_confirmed') {
          failure = 'Please confirm your email before logging in.';
        } else {
          failure = 'Could not complete this request. Please try again.';
        }
      });
    } on Object {
      if (mounted) {
        setState(
          () => failure =
              'Could not connect. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Account',
    body: PageWidth(
      form: true,
      child: Form(
        key: form,
        child: ListView(
          padding: Gap.page,
          children: [
            GlowHeader(
              child: Column(
                children: [
                  const BrandMark(),
                  const SizedBox(height: Gap.l),
                  Text(
                    'Welcome to ${AppBrand.name}',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: Gap.xs),
                  Text(
                    create
                        ? 'Your next favourite story starts here.'
                        : 'Good to see you again.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                backgroundColor: AppColors.white,
                foregroundColor: AppColors.ink,
              ),
              onPressed: busy
                  ? null
                  : () => perform(() => widget.state.google(linkGuest: create)),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GoogleMark(),
                  SizedBox(width: Gap.m),
                  Flexible(child: Text('Continue with Google')),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: Gap.l),
              child: Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: Gap.l),
                    child: Text('or'),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
            ),
            TextFormField(
              key: const ValueKey('login-email'),
              controller: email,
              enabled: !busy,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Email address',
                prefixIcon: Icon(Icons.mail_outline),
              ),
              validator: validateEmail,
            ),
            const SizedBox(height: Gap.l),
            TextFormField(
              key: const ValueKey('login-password'),
              controller: password,
              enabled: !busy,
              obscureText: hidden,
              autofillHints: create
                  ? const [AutofillHints.newPassword]
                  : const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: create ? 'Use at least 8 characters' : null,
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: hidden ? 'Show password' : 'Hide password',
                  onPressed: busy
                      ? null
                      : () => setState(() => hidden = !hidden),
                  icon: Icon(
                    hidden
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (value) => value == null || value.isEmpty
                  ? 'Enter your password'
                  : create && value.length < 8
                  ? 'Use at least 8 characters'
                  : null,
            ),
            if (failure != null) ...[
              const SizedBox(height: Gap.l),
              NoticeCard(
                title: 'Please try again',
                message: failure!,
                tone: NoticeTone.danger,
              ),
            ],
            if (notice != null) ...[
              const SizedBox(height: Gap.l),
              NoticeCard(
                title: 'Check your email',
                message: notice!,
                tone: NoticeTone.success,
              ),
            ],
            const SizedBox(height: Gap.xl),
            GradientButton(
              key: const ValueKey('account-submit'),
              label: create ? 'Create account' : 'Log in',
              busy: busy,
              onPressed: busy
                  ? null
                  : () {
                      if (form.currentState?.validate() != true) return;
                      perform(() async {
                        await widget.state.login(
                          email.text.trim(),
                          password.text,
                          create: create,
                        );
                        if (mounted && create && widget.state.guest) {
                          setState(
                            () => notice =
                                'Check your email to confirm your account.',
                          );
                        }
                      });
                    },
            ),
            const SizedBox(height: Gap.s),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          create = !create;
                          failure = null;
                          notice = null;
                          form.currentState?.reset();
                        }),
                  child: Text(create ? 'Log in instead' : 'Create account'),
                ),
                if (!create)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () {
                            if (validateEmail(email.text) != null) {
                              setState(
                                () =>
                                    failure = 'Enter your email address first.',
                              );
                              return;
                            }
                            perform(() async {
                              await widget.state.sendPasswordReset(
                                email.text.trim(),
                              );
                              if (mounted) {
                                setState(
                                  () => notice =
                                      'Check your email for the password reset link.',
                                );
                              }
                            });
                          },
                    child: const Text('Forgot password?'),
                  ),
              ],
            ),
            const SizedBox(height: Gap.s),
            Text(
              'By continuing, you agree to our Terms and Privacy Policy.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                for (final policy in const ['Terms', 'Privacy'])
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => Policy(name: policy),
                      ),
                    ),
                    child: Text(policy),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class ResetPassword extends StatefulWidget {
  const ResetPassword({super.key, required this.state});
  final AppState state;
  @override
  State<ResetPassword> createState() => _ResetPasswordState();
}

class _ResetPasswordState extends State<ResetPassword> {
  final password = TextEditingController(), confirm = TextEditingController();
  final form = GlobalKey<FormState>();
  bool busy = false, hidden = true;
  String? failure;
  @override
  void dispose() {
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (form.currentState?.validate() != true) return;
    setState(() {
      busy = true;
      failure = null;
    });
    try {
      await widget.state.saveRecoveredPassword(password.text);
      if (mounted) {
        showFeedback(context, 'Password updated.');
        Navigator.pop(context);
      }
    } on Object {
      if (mounted) {
        setState(
          () => failure =
              'Could not update your password. Open the latest reset email and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AppPage(
    title: 'Reset password',
    body: PageWidth(
      form: true,
      child: Form(
        key: form,
        child: ListView(
          padding: Gap.page,
          children: [
            const GlowHeader(
              child: Center(
                child: Icon(
                  Icons.lock_reset_rounded,
                  size: AppSizes.emptyIcon,
                  color: AppColors.primary,
                ),
              ),
            ),
            Text(
              'A fresh start',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: Gap.s),
            const Text('Choose a strong password for your Vayora account.'),
            const SizedBox(height: Gap.xl),
            TextFormField(
              controller: password,
              obscureText: hidden,
              enabled: !busy,
              decoration: InputDecoration(
                labelText: 'New password',
                suffixIcon: IconButton(
                  tooltip: hidden ? 'Show password' : 'Hide password',
                  onPressed: () => setState(() => hidden = !hidden),
                  icon: Icon(
                    hidden
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
              validator: (value) =>
                  (value?.length ?? 0) < 8 ? 'Use at least 8 characters' : null,
            ),
            const SizedBox(height: Gap.l),
            TextFormField(
              controller: confirm,
              obscureText: hidden,
              enabled: !busy,
              decoration: const InputDecoration(labelText: 'Confirm password'),
              validator: (value) =>
                  value != password.text ? 'Passwords do not match' : null,
            ),
            if (failure != null) ...[
              const SizedBox(height: Gap.l),
              NoticeCard(
                title: 'Please try again',
                message: failure!,
                tone: NoticeTone.danger,
              ),
            ],
            const SizedBox(height: Gap.xl),
            GradientButton(
              label: 'Save password',
              busy: busy,
              onPressed: busy ? null : save,
            ),
          ],
        ),
      ),
    ),
  );
}

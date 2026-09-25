import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import 'auth_repository.dart';
import 'email_validator.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _emailError;
  String? _passwordError;
  String? _error;
  String? _info;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// On success the auth stream flips and the router redirects.
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await action();
    } on AuthFailure catch (f) {
      if (mounted) setState(() => _error = _messageFor(f.kind));
    } catch (_) {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).genericError);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _messageFor(AuthFailureKind kind) {
    final l10n = AppLocalizations.of(context);
    return switch (kind) {
      AuthFailureKind.invalidCredentials => l10n.wrongEmailOrPassword,
      AuthFailureKind.emailTaken => l10n.emailTaken,
      AuthFailureKind.weakPassword => l10n.invalidPassword,
      AuthFailureKind.other => l10n.genericError,
    };
  }

  bool _validate() {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _emailError = isValidEmail(_email.text) ? null : l10n.invalidEmail;
      _passwordError = isValidPassword(_password.text)
          ? null
          : l10n.invalidPassword;
    });
    return _emailError == null && _passwordError == null;
  }

  Future<void> _signIn() async {
    if (!_validate()) return;
    await _run(
      () => ref
          .read(authRepositoryProvider)
          .signInWithPassword(email: _email.text, password: _password.text),
    );
  }

  Future<void> _createAccount() async {
    if (!_validate()) return;
    await _run(() async {
      final signedIn = await ref
          .read(authRepositoryProvider)
          .signUpWithPassword(email: _email.text, password: _password.text);
      if (!signedIn && mounted) {
        setState(
          () => _info = AppLocalizations.of(context).checkEmailToConfirm,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 32),
            Text(
              l10n.appTitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: AppColors.navy,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(l10n.tagline, textAlign: TextAlign.center),
            const SizedBox(height: 48),
            Text(
              l10n.signInTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run(
                      () => ref.read(authRepositoryProvider).signInWithGoogle(),
                    ),
              icon: const Icon(Icons.account_circle_outlined),
              label: Text(l10n.continueWithGoogle),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: const StadiumBorder(),
              ),
            ),
            const SizedBox(height: 24),
            Text(l10n.orUseEmail, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(
                labelText: l10n.emailLabel,
                errorText: _emailError,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: l10n.passwordLabel,
                errorText: _passwordError,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_info != null) ...[const SizedBox(height: 12), Text(_info!)],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _signIn,
              child: Text(l10n.signInButton),
            ),
            TextButton(
              onPressed: _busy ? null : _createAccount,
              child: Text(l10n.createAccount),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import 'auth_repository.dart';
import 'email_validator.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key, required this.onCodeSent});

  /// Called with the email once an OTP was sent (router pushes the OTP screen).
  final ValueChanged<String> onCodeSent;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).genericError);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() async {
    final l10n = AppLocalizations.of(context);
    final email = _email.text.trim();
    if (!isValidEmail(email)) {
      setState(() => _error = l10n.invalidEmail);
      return;
    }
    setState(() => _error = null);
    await _run(() async {
      await ref.read(authRepositoryProvider).sendEmailOtp(email);
      widget.onCodeSent(email);
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
            Text(l10n.appTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: AppColors.navy, fontWeight: FontWeight.w700)),
            Text(l10n.tagline, textAlign: TextAlign.center),
            const SizedBox(height: 48),
            Text(l10n.signInTitle,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run(
                      () => ref.read(authRepositoryProvider).signInWithGoogle()),
              icon: const Icon(Icons.account_circle_outlined),
              label: Text(l10n.continueWithGoogle),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: const StadiumBorder()),
            ),
            const SizedBox(height: 24),
            Text(l10n.orUseEmail, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(
                  labelText: l10n.emailLabel, errorText: _error),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _sendCode,
              child: Text(l10n.sendCode),
            ),
          ],
        ),
      ),
    );
  }
}

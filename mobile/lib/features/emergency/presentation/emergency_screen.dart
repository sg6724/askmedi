import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/gen/app_localizations.dart';
import '../../../core/platform/location_service.dart';
import '../../../core/platform/url_opener.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/source.dart';

/// Why the Emergency screen was opened (null fields: opened from Home).
class EmergencyArgs {
  const EmergencyArgs({this.reason, this.source});
  final String? reason;
  final Source? source;
}

/// Full-screen red alert. Renders without any network call: the numbers and
/// texts are built in, the reason comes from the caller.
class EmergencyScreen extends ConsumerStatefulWidget {
  const EmergencyScreen({super.key, this.args = const EmergencyArgs()});
  final EmergencyArgs args;

  @override
  ConsumerState<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends ConsumerState<EmergencyScreen> {
  bool _locating = false;
  String? _mapsUrl;
  String? _locationError;

  void _call(String number) =>
      ref.read(urlOpenerProvider)(Uri(scheme: 'tel', path: number));

  Future<void> _locate() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _locating = true;
      _locationError = null;
    });
    try {
      final p = await ref.read(locationServiceProvider).current();
      if (!mounted) return;
      setState(
        () => _mapsUrl =
            'https://www.google.com/maps/search/?api=1&query=${p.lat.toStringAsFixed(6)},${p.lng.toStringAsFixed(6)}',
      );
    } on LocationException catch (e) {
      if (!mounted) return;
      setState(
        () => _locationError = switch (e.failure) {
          LocationFailure.denied => l10n.locationDenied,
          LocationFailure.serviceOff => l10n.locationServiceOff,
          LocationFailure.unavailable => l10n.locationUnavailable,
        },
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _share({required bool whatsapp}) {
    final text = AppLocalizations.of(context).shareLocationMessage(_mapsUrl!);
    final uri = whatsapp
        ? Uri.https('wa.me', '/', {'text': text})
        : Uri(scheme: 'sms', query: 'body=${Uri.encodeComponent(text)}');
    ref.read(urlOpenerProvider)(uri);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reason = widget.args.reason;
    final source = widget.args.source;
    return Scaffold(
      backgroundColor: AppColors.danger,
      appBar: AppBar(
        backgroundColor: AppColors.danger,
        foregroundColor: Colors.white,
        title: Text(l10n.emergencyTitle),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.white,
              size: 64,
            ),
            const SizedBox(height: 12),
            Text(
              (reason == null || reason.isEmpty)
                  ? l10n.emergencyGeneric
                  : reason,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (source != null && source.title.isNotEmpty) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: source.url.isEmpty
                    ? null
                    : () => ref.read(urlOpenerProvider)(Uri.parse(source.url)),
                child: Text(
                  l10n.emergencySource(source.title),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            _CallButton(label: l10n.call112, onTap: () => _call('112')),
            _CallButton(label: l10n.call108, onTap: () => _call('108')),
            _CallButton(
              label: l10n.call102,
              onTap: () => _call('102'),
              small: true,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white),
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: _locating ? null : _locate,
              icon: _locating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.my_location),
              label: Text(l10n.shareLocation),
            ),
            if (_locationError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _locationError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            if (_mapsUrl != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.danger,
                      ),
                      onPressed: () => _share(whatsapp: true),
                      icon: const Icon(Icons.chat),
                      label: Text(l10n.shareViaWhatsApp),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.danger,
                      ),
                      onPressed: () => _share(whatsapp: false),
                      icon: const Icon(Icons.sms),
                      label: Text(l10n.shareViaSms),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            Text(
              l10n.emergencyNote,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.label,
    required this.onTap,
    this.small = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool small;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.danger,
        minimumSize: Size.fromHeight(small ? 52 : 68),
        textStyle: TextStyle(
          fontSize: small ? 16 : 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      onPressed: onTap,
      icon: const Icon(Icons.call),
      label: Text(label),
    ),
  );
}

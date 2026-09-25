import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/gen/app_localizations.dart';
import '../core/network/api_client.dart';
import '../core/platform/url_opener.dart';
import '../core/theme/app_theme.dart';
import 'source.dart';

/// The user-facing message for a failed API call.
String apiErrorMessage(AppLocalizations l10n, Object error) {
  if (error is! ApiException) return l10n.genericError;
  return switch ((error.statusCode, error.code)) {
    (null, _) => l10n.networkError,
    (503, _) => l10n.serviceBusy,
    (413, _) => l10n.fileTooLarge,
    (415, _) => l10n.unsupportedFile,
    (_, 'unreadable_image') => l10n.unreadableImage,
    (_, 'location_not_found') => l10n.locationNotFound,
    (_, 'directory_unavailable') => l10n.directoryUnavailable,
    _ => l10n.genericError,
  };
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700, color: AppColors.navy)),
      );
}

class BulletList extends StatelessWidget {
  const BulletList(this.items, {super.key});
  final List<String> items;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final i in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('•  '),
                Expanded(child: Text(i)),
              ]),
            ),
        ],
      );
}

/// Cited sources as tappable links.
class SourcesList extends ConsumerWidget {
  const SourcesList(this.sources, {super.key});
  final List<Source> sources;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (sources.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(l10n.sourcesTitle),
        for (final s in sources)
          InkWell(
            onTap: s.url.isEmpty
                ? null
                : () => ref.read(urlOpenerProvider)(Uri.parse(s.url)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                const Icon(Icons.link, size: 16, color: AppColors.teal),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    s.title.isEmpty ? s.url : s.title,
                    style: const TextStyle(
                        color: AppColors.navy, decoration: TextDecoration.underline),
                  ),
                ),
              ]),
            ),
          ),
      ],
    );
  }
}

class DisclaimerText extends StatelessWidget {
  const DisclaimerText(this.text, {super.key});
  final String? text;

  @override
  Widget build(BuildContext context) {
    final t = (text == null || text!.isEmpty)
        ? AppLocalizations.of(context).disclaimerDefault
        : text!;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(t,
          style: const TextStyle(
              fontSize: 12, color: AppColors.textSecondary, fontStyle: FontStyle.italic)),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Card(
        color: AppColors.blush,
        child: ListTile(
          leading: const Icon(Icons.error_outline, color: AppColors.danger),
          title: Text(message),
          trailing: onRetry == null
              ? null
              : TextButton(
                  onPressed: onRetry,
                  child: Text(AppLocalizations.of(context).retry)),
        ),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.message, {super.key, this.icon = Icons.inbox_outlined});
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary)),
          ]),
        ),
      );
}

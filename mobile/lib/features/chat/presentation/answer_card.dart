import 'package:flutter/material.dart';

import '../../../core/l10n/gen/app_localizations.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets.dart';
import '../domain/chat_models.dart';
import 'chat_screen.dart';

Color urgencyColor(Urgency? u) => switch (u) {
      Urgency.emergency => AppColors.danger,
      Urgency.seeDoctorToday => const Color(0xFFE67E22),
      Urgency.seeDoctorSoon => const Color(0xFFC99A06),
      Urgency.selfCare => AppColors.teal,
      null => AppColors.navy,
    };

String urgencyLabel(AppLocalizations l10n, Urgency? u) => switch (u) {
      Urgency.emergency => l10n.urgencyEmergency,
      Urgency.seeDoctorToday => l10n.urgencySeeDoctorToday,
      Urgency.seeDoctorSoon => l10n.urgencySeeDoctorSoon,
      Urgency.selfCare || null => l10n.urgencySelfCare,
    };

String likelihoodLabel(AppLocalizations l10n, Likelihood l) => switch (l) {
      Likelihood.moreLikely => l10n.likelihoodMoreLikely,
      Likelihood.possible => l10n.likelihoodPossible,
      Likelihood.lessLikely => l10n.likelihoodLessLikely,
    };

/// The result of a symptom check: urgency, causes grouped by likelihood band
/// (never percentages), what to do, when to seek care, sources, disclaimer.
class AnswerCard extends StatelessWidget {
  const AnswerCard({super.key, required this.reply});
  final ChatReply reply;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final a = reply.answer!;
    final color = urgencyColor(a.urgency);
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration:
                  BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
              child: Text(urgencyLabel(l10n, a.urgency),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 8),
            if (a.summary.isNotEmpty) Text(a.summary),
            if (reply.message.isNotEmpty && reply.message != a.summary)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(reply.message),
              ),
            if (a.causes.isNotEmpty) ...[
              SectionTitle(l10n.possibleCauses),
              for (final band in Likelihood.values)
                if (a.causes.any((c) => c.likelihood == band)) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(likelihoodLabel(l10n, band),
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                  ),
                  for (final c in a.causes.where((c) => c.likelihood == band))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title:
                          Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: c.explanation.isEmpty ? null : Text(c.explanation),
                    ),
                ],
            ],
            if (a.doNow.isNotEmpty) ...[
              SectionTitle(l10n.doNow),
              BulletList(a.doNow),
            ],
            if (a.seekCareIf.isNotEmpty) ...[
              SectionTitle(l10n.seekCareIf),
              BulletList(a.seekCareIf),
            ],
            SourcesList(reply.sources),
            const FindHospitalButton(),
            DisclaimerText(reply.disclaimer),
          ],
        ),
      ),
    );
  }
}

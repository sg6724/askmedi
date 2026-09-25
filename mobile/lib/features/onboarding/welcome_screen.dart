import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/gen/app_localizations.dart';
import '../../core/theme/app_theme.dart';
import 'intro_controller.dart';

class _Slide {
  const _Slide(
    this.icon,
    this.color,
    this.accent,
    this.title,
    this.body,
    this.chips,
  );

  final IconData icon;
  final Color color;
  final Color accent;
  final String title;
  final String body;
  final List<(IconData, String)> chips;
}

/// First-run slides that explain what AskMedi does before sign-in.
/// Swipe or tap Next; Skip or Get started marks them seen and the router moves on.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  List<_Slide> _slides(AppLocalizations l10n) => [
    _Slide(
      Icons.health_and_safety_outlined,
      AppColors.sky,
      AppColors.navy,
      l10n.welcome1Title,
      l10n.welcome1Body,
      [
        (Icons.translate, 'English · हिंदी · मराठी'),
        (Icons.mic_none, l10n.welcomeChipVoice),
      ],
    ),
    _Slide(
      Icons.chat_bubble_outline,
      AppColors.tealLight,
      AppColors.teal,
      l10n.welcome2Title,
      l10n.welcome2Body,
      [
        (Icons.quiz_outlined, l10n.welcomeChipQuestions),
        (Icons.link, l10n.welcomeChipSources),
      ],
    ),
    _Slide(
      Icons.medication_outlined,
      AppColors.peach,
      Color(0xFFB8621B),
      l10n.welcome3Title,
      l10n.welcome3Body,
      [
        (Icons.photo_camera_outlined, l10n.homeScanMedicine),
        (Icons.description_outlined, l10n.homeUploadReport),
        (Icons.local_hospital_outlined, l10n.homeFindHospital),
      ],
    ),
    _Slide(
      Icons.verified_user_outlined,
      AppColors.blush,
      AppColors.danger,
      l10n.welcome4Title,
      l10n.welcome4Body,
      [
        (Icons.call, '112 · 108'),
        (Icons.lock_outline, l10n.welcomeChipPrivate),
      ],
    ),
  ];

  Future<void> _finish() => ref.read(introSeenProvider.notifier).markSeen();

  void _next(int count) {
    if (_index == count - 1) {
      _finish();
    } else {
      _pages.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final slides = _slides(l10n);
    final last = _index == slides.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: AnimatedOpacity(
                opacity: last ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: TextButton(
                  onPressed: last ? null : _finish,
                  child: Text(l10n.welcomeSkip),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: slides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) =>
                    _SlideView(slide: slides[i], active: i == _index),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < slides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 8,
                    width: i == _index ? 24 : 8,
                    decoration: BoxDecoration(
                      color: i == _index
                          ? AppColors.navy
                          : AppColors.navy.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: FilledButton(
                onPressed: () => _next(slides.length),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    last ? l10n.welcomeGetStarted : l10n.welcomeNext,
                    key: ValueKey(last),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide, required this.active});

  final _Slide slide;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Scrolls so large text scales and short screens never overflow.
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
      children: [
        const SizedBox(height: 12),
        Center(
          child: AnimatedScale(
            scale: active ? 1 : 0.7,
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutBack,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                color: slide.color,
                shape: BoxShape.circle,
              ),
              child: Icon(slide.icon, size: 88, color: slide.accent),
            ),
          ),
        ),
        const SizedBox(height: 32),
        Text(
          slide.title,
          textAlign: TextAlign.center,
          style: text.headlineSmall?.copyWith(
            color: AppColors.navy,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          slide.body,
          textAlign: TextAlign.center,
          style: text.bodyLarge?.copyWith(
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (icon, label) in slide.chips)
              Chip(
                avatar: Icon(icon, size: 18, color: slide.accent),
                label: Text(label),
                backgroundColor: slide.color,
                side: BorderSide.none,
              ),
          ],
        ),
      ],
    );
  }
}

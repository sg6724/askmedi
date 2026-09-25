import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/gen/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../emergency/presentation/emergency_screen.dart';
import '../domain/chat_models.dart';
import '../domain/spoken_text.dart';
import 'answer_card.dart';
import 'chat_controller.dart';

enum _Mode { idle, listening, thinking, speaking }

/// Voice-first conversation: one big mic, what you said, and the spoken reply.
/// Same safety pipeline as the text chat (it shares [chatControllerProvider]).
class TalkScreen extends ConsumerStatefulWidget {
  const TalkScreen({super.key});

  @override
  ConsumerState<TalkScreen> createState() => _TalkScreenState();
}

class _TalkScreenState extends ConsumerState<TalkScreen>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  _Mode _mode(ChatState s) => switch (s.voice) {
    VoiceStatus.recording => _Mode.listening,
    VoiceStatus.transcribing => _Mode.thinking,
    VoiceStatus.speaking => _Mode.speaking,
    VoiceStatus.idle => s.busy ? _Mode.thinking : _Mode.idle,
  };

  void _onOrb(ChatState s) {
    final c = ref.read(chatControllerProvider.notifier);
    switch (_mode(s)) {
      case _Mode.idle:
      case _Mode.speaking:
        c.startRecording();
      case _Mode.listening:
        c.stopRecording();
      case _Mode.thinking:
        break;
    }
  }

  void _openEmergency(ChatReply reply) {
    final e = reply.emergency;
    context.push(
      Routes.emergency,
      extra: EmergencyArgs(
        reason: (e != null && e.reason.isNotEmpty) ? e.reason : reply.message,
        source: e?.source,
      ),
    );
  }

  void _showAnswer(ChatReply reply) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.all(16),
          children: [AnswerCard(reply: reply)],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(chatControllerProvider);
    final controller = ref.read(chatControllerProvider.notifier);
    ref.listen(chatControllerProvider, (prev, next) {
      final last = next.entries.lastOrNull;
      if (last is BotEntry &&
          !identical(last, prev?.entries.lastOrNull) &&
          last.reply.type == ChatReplyType.emergency) {
        _openEmergency(last.reply);
      }
    });

    final mode = _mode(state);
    // Animate only while listening, thinking or speaking (idle stays still).
    if (mode != _Mode.idle && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (mode == _Mode.idle && _pulse.isAnimating) {
      _pulse.stop();
    }
    final lastUser = state.entries.whereType<UserEntry>().lastOrNull?.text;
    final lastBot = state.entries.whereType<BotEntry>().lastOrNull?.reply;
    final status = switch (mode) {
      _Mode.idle =>
        lastBot == null ? l10n.talkTapToSpeak : l10n.talkTapToAnswer,
      _Mode.listening => l10n.talkListening,
      _Mode.thinking => l10n.talkThinking,
      _Mode.speaking => l10n.talkSpeaking,
    };
    final notice = switch (state.voiceNotice) {
      VoiceNotice.unavailable => l10n.voiceUnavailable,
      VoiceNotice.micDenied => l10n.micDenied,
      VoiceNotice.notHeard => l10n.voiceNotHeard,
      null => null,
    };

    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        title: Text(l10n.homeTalk),
        actions: [
          IconButton(
            tooltip: l10n.newChat,
            icon: const Icon(Icons.refresh),
            onPressed: state.busy ? null : controller.newConversation,
          ),
          IconButton(
            tooltip: l10n.emergencyButton,
            icon: const Icon(Icons.emergency, color: Color(0xFFFF8A80)),
            onPressed: () => context.push(Routes.emergency),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                children: [
                  if (lastBot == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        l10n.aiDisclosure,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  if (lastUser != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      '“$lastUser”',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  if (lastBot != null) ...[
                    const SizedBox(height: 20),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        spokenText(lastBot),
                        key: ValueKey(lastBot),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (lastBot.type == ChatReplyType.followup &&
                        lastBot.followup != null)
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final option in lastBot.followup!.options)
                            ActionChip(
                              label: Text(
                                option,
                                style: const TextStyle(fontSize: 16),
                              ),
                              backgroundColor: Colors.white,
                              onPressed: state.busy
                                  ? null
                                  : () => controller.send(
                                      option,
                                      speakReply: true,
                                    ),
                            ),
                        ],
                      ),
                    if (lastBot.type == ChatReplyType.answer)
                      Center(
                        child: FilledButton.tonalIcon(
                          onPressed: () => _showAnswer(lastBot),
                          icon: const Icon(Icons.article_outlined),
                          label: Text(l10n.talkSeeFullAnswer),
                        ),
                      ),
                    if (lastBot.type == ChatReplyType.answer ||
                        lastBot.type == ChatReplyType.repeat)
                      Center(
                        child: TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () => context.go(Routes.hospitals),
                          icon: const Icon(Icons.local_hospital_outlined),
                          label: Text(l10n.homeFindHospital),
                        ),
                      ),
                  ],
                  if (state.error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      l10n.serviceBusy,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFFFCDD2)),
                    ),
                  ],
                  if (notice != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      notice,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFFFCDD2)),
                    ),
                  ],
                ],
              ),
            ),
            _Orb(
              mode: mode,
              pulse: _pulse,
              onTap: () => _onOrb(state),
              label: status,
            ),
            const SizedBox(height: 12),
            Text(
              status,
              key: const Key('talk-status'),
              style: const TextStyle(color: Colors.white, fontSize: 17),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              onPressed: () => context.pushReplacement(Routes.chat),
              child: Text(l10n.talkTypeInstead),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Orb extends StatelessWidget {
  const _Orb({
    required this.mode,
    required this.pulse,
    required this.onTap,
    required this.label,
  });

  final _Mode mode;
  final Animation<double> pulse;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (mode) {
      _Mode.idle => (AppColors.teal, Icons.mic),
      _Mode.listening => (const Color(0xFFE57373), Icons.stop_rounded),
      _Mode.thinking => (const Color(0xFF7986CB), Icons.more_horiz),
      _Mode.speaking => (AppColors.teal, Icons.graphic_eq),
    };
    final animate = mode != _Mode.idle;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 220,
          height: 220,
          child: AnimatedBuilder(
            animation: pulse,
            builder: (context, _) {
              final t = animate ? pulse.value : 0.0;
              return Stack(
                alignment: Alignment.center,
                children: [
                  for (final phase in const [0.0, 0.5])
                    if (animate)
                      Builder(
                        builder: (_) {
                          final p = (t + phase) % 1.0;
                          return Container(
                            width: 130 + 90 * p,
                            height: 130 + 90 * p,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color.withValues(alpha: 0.35 * (1 - p)),
                            ),
                          );
                        },
                      ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width:
                        130 +
                        (mode == _Mode.thinking
                            ? 6 * math.sin(t * 2 * math.pi)
                            : 0),
                    height:
                        130 +
                        (mode == _Mode.thinking
                            ? 6 * math.sin(t * 2 * math.pi)
                            : 0),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.5),
                          blurRadius: 24,
                        ),
                      ],
                    ),
                    child: Icon(icon, size: 56, color: Colors.white),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/gen/app_localizations.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets.dart';
import '../../emergency/presentation/emergency_screen.dart';
import '../domain/chat_models.dart';
import 'answer_card.dart';
import 'chat_controller.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, this.voice = false});

  /// Opened from "Talk": replies are read aloud and the mic is the main action.
  final bool voice;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send([String? text]) {
    final t = text ?? _input.text;
    if (t.trim().isEmpty) return;
    if (text == null) _input.clear();
    ref.read(chatControllerProvider.notifier).send(t, speakReply: widget.voice);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(chatControllerProvider);
    final controller = ref.read(chatControllerProvider.notifier);

    ref.listen(chatControllerProvider, (prev, next) {
      if (next.entries.length != prev?.entries.length) _scrollToEnd();
      final last = next.entries.lastOrNull;
      if (last is BotEntry &&
          !identical(last, prev?.entries.lastOrNull) &&
          last.reply.type == ChatReplyType.emergency) {
        _openEmergency(last.reply);
      }
    });

    final lastIndex = state.entries.length - 1;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.chatTitle),
        actions: [
          IconButton(
            tooltip: l10n.newChat,
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: state.busy ? null : controller.newConversation,
          ),
          IconButton(
            tooltip: l10n.emergencyButton,
            icon: const Icon(Icons.emergency, color: AppColors.danger),
            onPressed: () => context.push(Routes.emergency),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              children: [
                _DisclosureBanner(text: l10n.aiDisclosure),
                _Bubble(text: l10n.chatWelcome, fromUser: false),
                for (final (i, entry) in state.entries.indexed)
                  switch (entry) {
                    UserEntry(:final text) => _Bubble(
                      text: text,
                      fromUser: true,
                    ),
                    BotEntry(:final reply) => _BotReply(
                      reply: reply,
                      // Only the latest follow-up's options can be tapped.
                      onOption: i == lastIndex && !state.busy ? _send : null,
                      onEmergency: () => _openEmergency(reply),
                    ),
                  },
                if (state.busy)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(l10n.thinking),
                      ],
                    ),
                  ),
                if (state.error != null)
                  ErrorBanner(
                    apiErrorMessage(l10n, state.error!.$1),
                    onRetry: controller.retry,
                  ),
              ],
            ),
          ),
          if (state.voiceNotice != null)
            Container(
              width: double.infinity,
              color: AppColors.peach,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(switch (state.voiceNotice!) {
                VoiceNotice.unavailable => l10n.voiceUnavailable,
                VoiceNotice.micDenied => l10n.micDenied,
                VoiceNotice.notHeard => l10n.voiceNotHeard,
              }),
            ),
          if (state.voice != VoiceStatus.idle)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                state.voice == VoiceStatus.recording
                    ? l10n.listening
                    : l10n.transcribing,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  _MicButton(
                    status: state.voice,
                    large: widget.voice,
                    onStart: state.busy ? null : controller.startRecording,
                    onStop: controller.stopRecording,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: l10n.chatHint,
                        counterText: '',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    tooltip: l10n.send,
                    onPressed: state.busy ? null : () => _send(),
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DisclosureBanner extends StatelessWidget {
  const _DisclosureBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.lavender,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(Icons.smart_toy_outlined, color: AppColors.navy),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.fromUser});
  final String text;
  final bool fromUser;

  @override
  Widget build(BuildContext context) => Align(
    alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 520),
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: fromUser ? AppColors.navy : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: fromUser ? null : Border.all(color: AppColors.sky),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fromUser ? Colors.white : AppColors.textPrimary,
        ),
      ),
    ),
  );
}

class _BotReply extends StatelessWidget {
  const _BotReply({
    required this.reply,
    required this.onOption,
    required this.onEmergency,
  });

  final ChatReply reply;
  final void Function(String)? onOption;
  final VoidCallback onEmergency;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final followup = reply.followup;
    final onOption = this.onOption;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (reply.readback.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  l10n.readbackLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                for (final r in reply.readback)
                  Chip(
                    label: Text(r),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: AppColors.tealLight,
                  ),
              ],
            ),
          ),
        if (reply.type != ChatReplyType.answer && reply.message.isNotEmpty)
          _Bubble(text: reply.message, fromUser: false),
        if (followup != null) ...[
          if (followup.question.isNotEmpty &&
              followup.question != reply.message)
            _Bubble(text: followup.question, fromUser: false),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final o in followup.options)
                ActionChip(
                  label: Text(o),
                  onPressed: onOption == null ? null : () => onOption(o),
                ),
            ],
          ),
        ],
        if (reply.type == ChatReplyType.answer && reply.answer != null)
          AnswerCard(reply: reply),
        if (reply.type == ChatReplyType.emergency)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: onEmergency,
              icon: const Icon(Icons.emergency),
              label: Text(l10n.openEmergency),
            ),
          ),
        if (reply.type == ChatReplyType.repeat) ...[
          const FindHospitalButton(),
          DisclaimerText(reply.disclaimer),
        ],
      ],
    );
  }
}

/// Switches to the Hospitals tab.
class FindHospitalButton extends StatelessWidget {
  const FindHospitalButton({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: FilledButton.icon(
      onPressed: () => context.go(Routes.hospitals),
      icon: const Icon(Icons.local_hospital),
      label: Text(AppLocalizations.of(context).findHospital),
    ),
  );
}

class _MicButton extends StatelessWidget {
  const _MicButton({
    required this.status,
    required this.large,
    required this.onStart,
    required this.onStop,
  });

  final VoiceStatus status;
  final bool large;
  final VoidCallback? onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final recording = status == VoiceStatus.recording;
    final size = large ? 56.0 : 44.0;
    return SizedBox(
      width: size,
      height: size,
      child: IconButton.filled(
        tooltip: recording ? l10n.listening : l10n.speak,
        style: IconButton.styleFrom(
          backgroundColor: recording ? AppColors.danger : AppColors.teal,
        ),
        onPressed: status == VoiceStatus.transcribing
            ? null
            : recording
            ? onStop
            : onStart,
        icon: status == VoiceStatus.transcribing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(recording ? Icons.stop : Icons.mic),
      ),
    );
  }
}

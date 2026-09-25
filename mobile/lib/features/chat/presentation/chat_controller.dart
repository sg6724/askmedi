import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/platform/audio.dart';
import '../../onboarding/locale_controller.dart';
import '../data/chat_repository.dart';
import '../data/voice_repository.dart';
import '../domain/chat_models.dart';
import '../domain/spoken_text.dart';

sealed class ChatEntry {
  const ChatEntry();
}

class UserEntry extends ChatEntry {
  const UserEntry(this.text);
  final String text;
}

class BotEntry extends ChatEntry {
  const BotEntry(this.reply);
  final ChatReply reply;
}

enum VoiceStatus { idle, recording, transcribing }

enum VoiceNotice { unavailable, micDenied, notHeard }

class ChatState {
  const ChatState({
    this.episodeId,
    this.entries = const [],
    this.busy = false,
    this.error,
    this.voice = VoiceStatus.idle,
    this.voiceNotice,
  });

  final String? episodeId;
  final List<ChatEntry> entries;
  final bool busy;

  /// The last failed send (an [ApiException] or other error), with the text to retry.
  final (Object, String)? error;
  final VoiceStatus voice;
  final VoiceNotice? voiceNotice;

  ChatState copyWith({
    String? episodeId,
    List<ChatEntry>? entries,
    bool? busy,
    (Object, String)? Function()? error,
    VoiceStatus? voice,
    VoiceNotice? Function()? voiceNotice,
  }) => ChatState(
    episodeId: episodeId ?? this.episodeId,
    entries: entries ?? this.entries,
    busy: busy ?? this.busy,
    error: error == null ? this.error : error(),
    voice: voice ?? this.voice,
    voiceNotice: voiceNotice == null ? this.voiceNotice : voiceNotice(),
  );
}

class ChatController extends Notifier<ChatState> {
  late VoiceRecorder _recorder;
  late AudioOutput _audio;

  @override
  ChatState build() {
    // Watched (not just read) so the recorder and player live as long as the chat.
    _recorder = ref.watch(voiceRecorderProvider);
    _audio = ref.watch(audioOutputProvider);
    return const ChatState();
  }

  /// Sends [text]; when [speakReply] the reply's message is read aloud.
  Future<void> send(String text, {bool speakReply = false}) async {
    final message = text.trim();
    if (message.isEmpty || state.busy) return;
    state = state.copyWith(
      entries: [...state.entries, UserEntry(message)],
      busy: true,
      error: () => null,
    );
    await _request(message, speakReply: speakReply);
  }

  /// Retries the last failed message without adding it to the thread again.
  Future<void> retry() async {
    final failed = state.error;
    if (failed == null || state.busy) return;
    state = state.copyWith(busy: true, error: () => null);
    await _request(failed.$2, speakReply: false);
  }

  Future<void> _request(String message, {required bool speakReply}) async {
    try {
      final reply = await ref
          .read(chatRepositoryProvider)
          .send(
            episodeId: state.episodeId,
            message: message,
            language: ref.read(appLanguageProvider),
          );
      if (!ref.mounted) return;
      state = state.copyWith(
        episodeId: reply.episodeId,
        entries: [...state.entries, BotEntry(reply)],
        busy: false,
      );
      final spoken = spokenText(reply);
      if (speakReply && spoken.isNotEmpty) await _speak(spoken);
    } catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(busy: false, error: () => (e, message));
    }
  }

  Future<void> _speak(String text) async {
    try {
      final audio = await ref
          .read(voiceRepositoryProvider)
          .speak(text, language: ref.read(appLanguageProvider));
      if (!ref.mounted) return;
      await _audio.playMp3(audio);
    } on ApiException catch (e) {
      if (ref.mounted && e.isBusy) {
        state = state.copyWith(voiceNotice: () => VoiceNotice.unavailable);
      }
    } catch (_) {
      // Playback problems must never break the text conversation.
    }
  }

  Future<void> startRecording() async {
    if (state.voice != VoiceStatus.idle || state.busy) return;
    await _audio.stop();
    final ok = await _recorder.start();
    if (!ref.mounted) return;
    state = ok
        ? state.copyWith(voice: VoiceStatus.recording, voiceNotice: () => null)
        : state.copyWith(voiceNotice: () => VoiceNotice.micDenied);
  }

  Future<void> stopRecording() async {
    if (state.voice != VoiceStatus.recording) return;
    state = state.copyWith(voice: VoiceStatus.transcribing);
    try {
      final wav = await _recorder.stop();
      if (wav == null) {
        state = state.copyWith(
          voice: VoiceStatus.idle,
          voiceNotice: () => VoiceNotice.notHeard,
        );
        return;
      }
      final text = await ref.read(voiceRepositoryProvider).transcribe(wav);
      if (!ref.mounted) return;
      state = state.copyWith(voice: VoiceStatus.idle);
      if (text.isEmpty) {
        state = state.copyWith(voiceNotice: () => VoiceNotice.notHeard);
        return;
      }
      await send(text, speakReply: true);
    } on ApiException catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        voice: VoiceStatus.idle,
        voiceNotice: () =>
            e.isBusy ? VoiceNotice.unavailable : VoiceNotice.notHeard,
      );
    } catch (_) {
      if (!ref.mounted) return;
      state = state.copyWith(
        voice: VoiceStatus.idle,
        voiceNotice: () => VoiceNotice.notHeard,
      );
    }
  }

  void newConversation() {
    _audio.stop();
    state = const ChatState();
  }
}

final chatControllerProvider =
    NotifierProvider.autoDispose<ChatController, ChatState>(ChatController.new);

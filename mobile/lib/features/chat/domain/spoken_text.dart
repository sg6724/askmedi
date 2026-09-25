import 'chat_models.dart';

/// Upper bound for what is read aloud. Speech time grows with length, and the full
/// reply (causes, links, lists) stays on screen anyway.
const maxSpokenChars = 350;

/// The short version of [reply] to read aloud in voice mode.
String spokenText(ChatReply reply) {
  final text = switch (reply.type) {
    ChatReplyType.followup when reply.followup != null =>
      '${reply.followup!.question} ${reply.followup!.options.join(', ')}.',
    ChatReplyType.answer when (reply.answer?.summary ?? '').isNotEmpty =>
      reply.answer!.summary,
    _ => reply.message,
  };
  return _clip(text.trim());
}

final _sentenceEnd = RegExp(r'[.!?।॥]');

String _clip(String text) {
  if (text.length <= maxSpokenChars) return text;
  final head = text.substring(0, maxSpokenChars);
  final ends = _sentenceEnd.allMatches(head).toList();
  return ends.isEmpty ? head.trim() : head.substring(0, ends.last.end).trim();
}

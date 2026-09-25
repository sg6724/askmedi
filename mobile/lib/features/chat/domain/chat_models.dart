import '../../../shared/source.dart';

enum ChatReplyType { followup, answer, emergency, repeat }

enum Urgency {
  emergency('emergency'),
  seeDoctorToday('see_doctor_today'),
  seeDoctorSoon('see_doctor_soon'),
  selfCare('self_care');

  const Urgency(this.wire);
  final String wire;

  static Urgency? fromWire(String? w) =>
      Urgency.values.where((u) => u.wire == w).firstOrNull;
}

enum Likelihood {
  moreLikely('more_likely'),
  possible('possible'),
  lessLikely('less_likely');

  const Likelihood(this.wire);
  final String wire;

  static Likelihood fromWire(String? w) =>
      Likelihood.values.where((l) => l.wire == w).firstOrNull ?? Likelihood.possible;
}

class Followup {
  const Followup({required this.question, required this.options});
  final String question;
  final List<String> options;
}

class Cause {
  const Cause({required this.name, required this.likelihood, required this.explanation});
  final String name;
  final Likelihood likelihood;
  final String explanation;
}

class Answer {
  const Answer({
    required this.urgency,
    required this.summary,
    required this.causes,
    required this.doNow,
    required this.seekCareIf,
  });

  final Urgency? urgency;
  final String summary;
  final List<Cause> causes;
  final List<String> doNow;
  final List<String> seekCareIf;
}

class EmergencyInfo {
  const EmergencyInfo({
    required this.ruleId,
    required this.reason,
    required this.call,
    this.source,
  });

  final String ruleId;
  final String reason;
  final List<String> call;
  final Source? source;
}

class ChatReply {
  const ChatReply({
    required this.episodeId,
    required this.type,
    required this.message,
    this.readback = const [],
    this.followup,
    this.answer,
    this.emergency,
    this.sources = const [],
    this.disclaimer = '',
  });

  factory ChatReply.fromJson(Map<String, dynamic> j) {
    final f = j['followup'] as Map?;
    final a = j['answer'] as Map?;
    final e = j['emergency'] as Map?;
    return ChatReply(
      episodeId: j['episode_id'] as String,
      type: ChatReplyType.values.where((t) => t.name == j['type']).firstOrNull ??
          ChatReplyType.followup,
      message: (j['message'] as String?) ?? '',
      readback: stringList(j['readback']),
      followup: f == null
          ? null
          : Followup(
              question: (f['question'] as String?) ?? '',
              options: stringList(f['options']),
            ),
      answer: a == null
          ? null
          : Answer(
              urgency: Urgency.fromWire(a['urgency'] as String?),
              summary: (a['summary'] as String?) ?? '',
              causes: [
                for (final c in (a['causes'] as List?) ?? const [])
                  Cause(
                    name: ((c as Map)['name'] as String?) ?? '',
                    likelihood: Likelihood.fromWire(c['likelihood'] as String?),
                    explanation: (c['explanation'] as String?) ?? '',
                  ),
              ],
              doNow: stringList(a['do_now']),
              seekCareIf: stringList(a['seek_care_if']),
            ),
      emergency: e == null
          ? null
          : EmergencyInfo(
              ruleId: (e['rule_id'] as String?) ?? '',
              reason: (e['reason'] as String?) ?? '',
              call: stringList(e['call']),
              source: e['source'] is Map
                  ? Source.fromJson(Map<String, dynamic>.from(e['source'] as Map))
                  : null,
            ),
      sources: Source.listFrom(j['sources']),
      disclaimer: (j['disclaimer'] as String?) ?? '',
    );
  }

  final String episodeId;
  final ChatReplyType type;
  final String message;
  final List<String> readback;
  final Followup? followup;
  final Answer? answer;
  final EmergencyInfo? emergency;
  final List<Source> sources;
  final String disclaimer;
}

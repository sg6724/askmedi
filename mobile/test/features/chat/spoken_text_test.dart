import 'package:askmedi/features/chat/domain/chat_models.dart';
import 'package:askmedi/features/chat/domain/spoken_text.dart';
import 'package:flutter_test/flutter_test.dart';

ChatReply reply(Map<String, dynamic> extra) => ChatReply.fromJson({
  'episode_id': 'e1',
  'readback': <String>[],
  'sources': <Map<String, dynamic>>[],
  'disclaimer': 'd',
  'followup': null,
  'answer': null,
  'emergency': null,
  ...extra,
});

void main() {
  test('follow-up: the question and its options', () {
    final r = reply({
      'type': 'followup',
      'message': 'How high is the fever?',
      'followup': {
        'question': 'How high is the fever?',
        'options': ['Mild', 'High'],
      },
    });
    expect(spokenText(r), 'How high is the fever? Mild, High.');
  });

  test('answer: only the summary, not the whole card', () {
    final r = reply({
      'type': 'answer',
      'message':
          'A very long message that repeats every cause and every source link. ' *
          10,
      'answer': {
        'urgency': 'see_doctor_soon',
        'summary':
            'This is most likely a viral infection. See a doctor if it lasts.',
        'causes': [],
        'do_now': ['Rest'],
        'seek_care_if': [],
      },
    });
    expect(
      spokenText(r),
      'This is most likely a viral infection. See a doctor if it lasts.',
    );
  });

  test('emergency and repeat: the message', () {
    final r = reply({'type': 'emergency', 'message': 'Call 112 now.'});
    expect(spokenText(r), 'Call 112 now.');
  });

  test('long text is cut at a sentence end, within the limit', () {
    final long = List.filled(30, 'यह एक वाक्य है।').join(' ');
    final spoken = spokenText(reply({'type': 'repeat', 'message': long}));
    expect(spoken.length, lessThanOrEqualTo(maxSpokenChars));
    expect(spoken.endsWith('।'), isTrue);
  });
}

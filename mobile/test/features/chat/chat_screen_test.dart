import 'dart:typed_data';

import 'package:askmedi/core/network/api_client.dart';
import 'package:askmedi/core/platform/audio.dart';
import 'package:askmedi/features/chat/data/chat_repository.dart';
import 'package:askmedi/features/chat/data/voice_repository.dart';
import 'package:askmedi/features/chat/domain/chat_models.dart';
import 'package:askmedi/features/chat/presentation/chat_screen.dart';
import 'package:askmedi/features/emergency/presentation/emergency_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_router.dart';

class FakeChatRepository implements ChatRepository {
  FakeChatRepository(this.replies);

  /// Returned in order; an Exception entry is thrown instead.
  final List<Object> replies;
  final sent = <({String? episodeId, String message, String language})>[];

  @override
  Future<ChatReply> send({
    required String? episodeId,
    required String message,
    required String language,
  }) async {
    sent.add((episodeId: episodeId, message: message, language: language));
    final next = replies.removeAt(0);
    if (next is Exception) throw next;
    return ChatReply.fromJson(next as Map<String, dynamic>);
  }
}

class FakeVoiceRepository implements VoiceRepository {
  FakeVoiceRepository({this.text = 'mujhe fever hai', this.error});
  final String text;
  final Exception? error;
  final spoken = <String>[];

  @override
  Future<String> transcribe(Uint8List wav) async {
    if (error != null) throw error!;
    return text;
  }

  @override
  Future<Uint8List> speak(String text, {required String language}) async {
    if (error != null) throw error!;
    spoken.add(text);
    return Uint8List.fromList([1, 2, 3]);
  }
}

class FakeRecorder implements VoiceRecorder {
  bool started = false;

  @override
  Future<bool> start() async => started = true;

  @override
  Future<Uint8List?> stop() async => Uint8List.fromList([0, 1]);

  @override
  Future<void> cancel() async {}
}

class FakeAudioOutput implements AudioOutput {
  int plays = 0;

  @override
  Future<void> playMp3(Uint8List bytes) async => plays++;

  @override
  Future<void> stop() async {}
}

Map<String, dynamic> followup() => {
  'episode_id': 'ep-1',
  'type': 'followup',
  'readback': ['Fever', '1 day'],
  'followup': {
    'question': 'How high is the fever?',
    'options': ['Below 100°F', 'Above 102°F'],
  },
  'answer': null,
  'emergency': null,
  'message': 'How high is the fever?',
  'sources': [],
  'disclaimer': 'Not a diagnosis.',
};

Map<String, dynamic> answer() => {
  'episode_id': 'ep-1',
  'type': 'answer',
  'readback': ['Fever'],
  'followup': null,
  'answer': {
    'urgency': 'see_doctor_soon',
    'summary': 'Likely a viral fever.',
    'causes': [
      {
        'name': 'Viral fever',
        'likelihood': 'more_likely',
        'explanation': 'Common.',
      },
      {
        'name': 'Dengue',
        'likelihood': 'less_likely',
        'explanation': 'Check if rash.',
      },
    ],
    'do_now': ['Drink fluids'],
    'seek_care_if': ['Fever lasts over 3 days'],
  },
  'emergency': null,
  'message': 'Likely a viral fever.',
  'sources': [
    {
      'title': 'MedlinePlus: Fever',
      'url': 'https://medlineplus.gov/fever.html',
    },
  ],
  'disclaimer': 'AskMedi gives health information, not a diagnosis.',
};

Map<String, dynamic> emergency() => {
  'episode_id': 'ep-2',
  'type': 'emergency',
  'readback': [],
  'followup': null,
  'answer': null,
  'emergency': {
    'rule_id': 'chest_pain',
    'reason': 'Chest pain can be a heart attack.',
    'call': ['112', '108'],
    'source': {'title': 'WHO ETAT', 'url': 'https://who.int/etat'},
  },
  'message': 'Call 112 now.',
  'sources': [],
  'disclaimer': '',
};

void main() {
  late FakeRecorder recorder;
  late FakeAudioOutput output;

  setUp(() {
    recorder = FakeRecorder();
    output = FakeAudioOutput();
  });

  Future<void> pump(
    WidgetTester tester,
    FakeChatRepository chat, {
    FakeVoiceRepository? voice,
    RecordingOpener? opener,
    bool talk = false,
  }) => pumpRouted(
    tester,
    ChatScreen(voice: talk),
    opener: opener,
    overrides: [
      chatRepositoryProvider.overrideWithValue(chat),
      voiceRepositoryProvider.overrideWithValue(voice ?? FakeVoiceRepository()),
      voiceRecorderProvider.overrideWithValue(recorder),
      audioOutputProvider.overrideWithValue(output),
    ],
  );

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'disclosure, follow-up chips, then an answer card with bands and sources',
    (tester) async {
      final chat = FakeChatRepository([followup(), answer()]);
      final opener = RecordingOpener();
      await pump(tester, chat, opener: opener);

      expect(find.textContaining('AI assistant'), findsOneWidget);

      await type(tester, 'I have fever');
      expect(chat.sent.single.episodeId, isNull);
      expect(chat.sent.single.language, 'en');
      expect(find.text('I have fever'), findsOneWidget);
      expect(find.text('Fever'), findsOneWidget); // read-back chip
      expect(find.text('How high is the fever?'), findsOneWidget);

      await tester.tap(find.widgetWithText(ActionChip, 'Above 102°F'));
      await tester.pumpAndSettle();
      expect(chat.sent.last.message, 'Above 102°F');
      expect(chat.sent.last.episodeId, 'ep-1');

      expect(find.text('See a doctor in the next few days'), findsOneWidget);
      expect(find.text('More likely'), findsOneWidget);
      expect(find.text('Less likely'), findsOneWidget);
      expect(find.text('Possible'), findsNothing); // no causes in that band
      expect(find.text('Viral fever'), findsOneWidget);
      expect(find.text('Drink fluids'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);

      await tester.ensureVisible(find.text('MedlinePlus: Fever'));
      await tester.tap(find.text('MedlinePlus: Fever'));
      expect(
        opener.opened.single.toString(),
        'https://medlineplus.gov/fever.html',
      );

      await tester.ensureVisible(find.text('Find a hospital'));
      await tester.tap(find.text('Find a hospital'));
      await tester.pumpAndSettle();
      expect(find.text('HOSPITALS TAB'), findsOneWidget);
    },
  );

  testWidgets(
    'emergency reply opens the Emergency screen with reason and source',
    (tester) async {
      await pump(tester, FakeChatRepository([emergency()]));

      await type(tester, 'seene mein dard');

      expect(find.byType(EmergencyScreen), findsOneWidget);
      expect(find.text('Chest pain can be a heart attack.'), findsOneWidget);
      expect(find.text('Source: WHO ETAT'), findsOneWidget);
      expect(find.text('Call 112 — Emergency'), findsOneWidget);
    },
  );

  testWidgets('repeat reply shows the message and Find a hospital', (
    tester,
  ) async {
    await pump(
      tester,
      FakeChatRepository([
        {
          'episode_id': 'ep-3',
          'type': 'repeat',
          'readback': [],
          'message':
              'You asked about headache several times. Please see a doctor.',
          'sources': [],
          'disclaimer': '',
        },
      ]),
    );

    await type(tester, 'headache again');

    expect(find.textContaining('Please see a doctor.'), findsOneWidget);
    expect(find.text('Find a hospital'), findsOneWidget);
  });

  testWidgets('503 shows "service is busy"; Retry resends the same message', (
    tester,
  ) async {
    final chat = FakeChatRepository([
      const ApiException(statusCode: 503, code: 'llm_unavailable'),
      followup(),
    ]);
    await pump(tester, chat);

    await type(tester, 'fever');
    expect(
      find.text('The service is busy. Please try again in a minute.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(chat.sent.map((s) => s.message), ['fever', 'fever']);
    expect(
      find.text('The service is busy. Please try again in a minute.'),
      findsNothing,
    );
    expect(find.text('How high is the fever?'), findsOneWidget);
    expect(find.text('fever'), findsOneWidget); // not duplicated in the thread
  });

  testWidgets('voice: record -> transcribe -> chat -> reply is spoken', (
    tester,
  ) async {
    final chat = FakeChatRepository([followup()]);
    final voice = FakeVoiceRepository(text: 'mujhe fever hai');
    await pump(tester, chat, voice: voice);

    await tester.tap(find.byTooltip('Speak'));
    await tester.pumpAndSettle();
    expect(recorder.started, isTrue);
    expect(find.text('Listening… tap to stop'), findsWidgets);

    await tester.tap(find.byIcon(Icons.stop));
    await tester.pumpAndSettle();

    expect(find.text('mujhe fever hai'), findsOneWidget);
    expect(chat.sent.single.message, 'mujhe fever hai');
    expect(voice.spoken, ['How high is the fever?']);
    expect(output.plays, 1);
  });

  testWidgets(
    'voice unavailable (503) shows a friendly note; typing still works',
    (tester) async {
      final chat = FakeChatRepository([followup()]);
      await pump(
        tester,
        chat,
        voice: FakeVoiceRepository(
          error: const ApiException(statusCode: 503, code: 'voice_unavailable'),
        ),
      );

      await tester.tap(find.byTooltip('Speak'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.stop));
      await tester.pumpAndSettle();

      expect(
        find.text('Voice is not available right now. You can still type.'),
        findsOneWidget,
      );
      expect(chat.sent, isEmpty);

      await type(tester, 'fever');
      expect(find.text('How high is the fever?'), findsOneWidget);
    },
  );
}

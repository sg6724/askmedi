import 'package:askmedi/core/platform/audio.dart';
import 'package:askmedi/features/chat/data/chat_repository.dart';
import 'package:askmedi/features/chat/data/voice_repository.dart';
import 'package:askmedi/features/chat/presentation/talk_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_router.dart';
import 'chat_screen_test.dart'
    show
        FakeAudioOutput,
        FakeChatRepository,
        FakeRecorder,
        FakeVoiceRepository,
        answer,
        followup;

void main() {
  late FakeRecorder recorder;
  late FakeAudioOutput output;

  setUp(() {
    recorder = FakeRecorder();
    output = FakeAudioOutput();
  });

  Future<void> pump(
    WidgetTester tester,
    FakeChatRepository chat,
    FakeVoiceRepository voice,
  ) => pumpRouted(
    tester,
    const TalkScreen(),
    overrides: [
      chatRepositoryProvider.overrideWithValue(chat),
      voiceRepositoryProvider.overrideWithValue(voice),
      voiceRecorderProvider.overrideWithValue(recorder),
      audioOutputProvider.overrideWithValue(output),
    ],
  );

  testWidgets(
    'voice-first: tap the orb, speak, hear the question with big options',
    (tester) async {
      final chat = FakeChatRepository([followup(), answer()]);
      final voice = FakeVoiceRepository(text: 'mujhe fever hai');
      await pump(tester, chat, voice);

      expect(find.text('Tap the mic and tell me how you feel'), findsOneWidget);
      expect(
        find.byType(TextField),
        findsNothing,
        reason: 'no typing on the Talk screen',
      );

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pump();
      expect(recorder.started, isTrue);
      expect(find.text('Listening… tap to send'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.stop_rounded));
      await tester.pumpAndSettle();

      expect(find.text('“mujhe fever hai”'), findsOneWidget);
      expect(chat.sent.single.message, 'mujhe fever hai');
      const spoken = 'How high is the fever? Below 100°F, Above 102°F.';
      expect(find.text(spoken), findsOneWidget);
      expect(voice.spoken, [spoken]);
      expect(output.plays, 1);

      // Tapping an option answers by voice too; the answer has a full-answer sheet.
      await tester.tap(find.widgetWithText(ActionChip, 'Above 102°F'));
      await tester.pumpAndSettle();
      expect(chat.sent.last.message, 'Above 102°F');
      expect(find.text('Likely a viral fever.'), findsOneWidget);
      expect(voice.spoken.last, 'Likely a viral fever.');

      await tester.tap(find.text('See full answer'));
      await tester.pumpAndSettle();
      expect(find.text('Viral fever'), findsOneWidget);
    },
  );
}

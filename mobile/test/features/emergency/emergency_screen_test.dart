import 'package:askmedi/core/platform/location_service.dart';
import 'package:askmedi/features/emergency/presentation/emergency_screen.dart';
import 'package:askmedi/shared/source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_router.dart';

class FakeLocation implements LocationService {
  FakeLocation({this.failure});
  final LocationFailure? failure;

  @override
  Future<LatLng> current() async {
    if (failure != null) throw LocationException(failure!);
    return const LatLng(18.5204, 73.8567);
  }
}

void main() {
  testWidgets('generic message from Home; one-tap 112 / 108 / 102', (
    tester,
  ) async {
    final opener = RecordingOpener();
    await pumpRouted(tester, const EmergencyScreen(), opener: opener);

    expect(
      find.text('If you or someone near you is in danger, call for help now.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Call 112 — Emergency'));
    await tester.tap(find.text('Call 108 — Ambulance'));
    await tester.tap(find.text('Call 102 — Mother & child ambulance'));
    expect(opener.opened.map((u) => u.toString()), [
      'tel:112',
      'tel:108',
      'tel:102',
    ]);
  });

  testWidgets('shows the reason and its source', (tester) async {
    await pumpRouted(
      tester,
      const EmergencyScreen(
        args: EmergencyArgs(
          reason: 'Stroke signs need care within minutes.',
          source: Source(
            title: 'MedlinePlus: Stroke',
            url: 'https://medlineplus.gov/stroke',
          ),
        ),
      ),
    );

    expect(find.text('Stroke signs need care within minutes.'), findsOneWidget);
    expect(find.text('Source: MedlinePlus: Stroke'), findsOneWidget);
  });

  testWidgets('share my location -> WhatsApp link with a Google Maps URL', (
    tester,
  ) async {
    final opener = RecordingOpener();
    await pumpRouted(
      tester,
      const EmergencyScreen(),
      opener: opener,
      overrides: [locationServiceProvider.overrideWithValue(FakeLocation())],
    );

    await tester.tap(find.text('Share my location'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send on WhatsApp'));

    final uri = opener.opened.single;
    expect(uri.host, 'wa.me');
    expect(
      uri.queryParameters['text'],
      contains(
        'https://www.google.com/maps/search/?api=1&query=18.520400,73.856700',
      ),
    );

    await tester.tap(find.text('Send as SMS'));
    expect(opener.opened.last.scheme, 'sms');
  });

  testWidgets('location denied shows a message, calls still work', (
    tester,
  ) async {
    await pumpRouted(
      tester,
      const EmergencyScreen(),
      overrides: [
        locationServiceProvider.overrideWithValue(
          FakeLocation(failure: LocationFailure.denied),
        ),
      ],
    );

    await tester.tap(find.text('Share my location'));
    await tester.pumpAndSettle();

    expect(find.text('Location permission was denied.'), findsOneWidget);
    expect(find.text('Send on WhatsApp'), findsNothing);
    expect(find.text('Call 112 — Emergency'), findsOneWidget);
  });
}

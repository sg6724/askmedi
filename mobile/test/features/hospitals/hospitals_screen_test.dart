import 'package:askmedi/core/network/api_client.dart';
import 'package:askmedi/core/platform/location_service.dart';
import 'package:askmedi/features/hospitals/data/hospitals_repository.dart';
import 'package:askmedi/features/hospitals/domain/hospital.dart';
import 'package:askmedi/features/hospitals/presentation/hospitals_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_router.dart';

class FakeHospitals implements HospitalsRepository {
  FakeHospitals({this.error});
  final Exception? error;
  final queries = <HospitalQuery>[];

  @override
  Future<HospitalSearchResult> search(HospitalQuery query) async {
    queries.add(query);
    if (error != null) throw error!;
    return HospitalSearchResult.fromJson({
      'location': {'lat': 18.52, 'lng': 73.86, 'label': 'Pune 411001'},
      'hospitals': [
        {
          'name': 'Ruby Hall Clinic',
          'lat': 18.53,
          'lng': 73.87,
          'distance_km': 1.24,
          'address': 'Sassoon Road',
          'phone': '+91 20 6645 5100',
          'emergency': true,
          'maps_url':
              'https://www.google.com/maps/search/?api=1&query=18.53,73.87',
        },
        {
          'name': 'Small Clinic',
          'lat': 18.54,
          'lng': 73.88,
          'distance_km': 2.0,
          'address': null,
          'phone': null,
          'emergency': null,
          'maps_url':
              'https://www.google.com/maps/search/?api=1&query=18.54,73.88',
        },
      ],
    });
  }
}

class FakeLocation implements LocationService {
  @override
  Future<LatLng> current() async => const LatLng(18.52, 73.86);
}

void main() {
  test('6 digits is a PIN code, anything else an area', () {
    expect(HospitalQuery.fromText('411001').toParams(), {'pincode': '411001'});
    expect(HospitalQuery.fromText('Kothrud').toParams(), {'q': 'Kothrud'});
  });

  testWidgets(
    'PIN code search lists hospitals; call and directions open links',
    (tester) async {
      final repo = FakeHospitals();
      final opener = RecordingOpener();
      await pumpRouted(
        tester,
        const HospitalsScreen(),
        opener: opener,
        overrides: [hospitalsRepositoryProvider.overrideWithValue(repo)],
      );

      await tester.enterText(find.byType(TextField), '411001');
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();

      expect(repo.queries.single, isA<PincodeQuery>());
      expect(find.text('Near Pune 411001'), findsOneWidget);
      expect(find.text('Ruby Hall Clinic'), findsOneWidget);
      expect(find.text('1.2 km'), findsOneWidget);
      expect(find.text('Emergency care'), findsOneWidget);
      // Only the hospital with a phone number gets a Call button.
      expect(find.text('Call'), findsOneWidget);

      await tester.tap(find.text('Call'));
      expect(opener.opened.last.toString(), 'tel:+912066455100');
      await tester.tap(find.text('Directions').first);
      expect(
        opener.opened.last.toString(),
        'https://www.google.com/maps/search/?api=1&query=18.53,73.87',
      );
    },
  );

  testWidgets('Use my location searches by coordinates', (tester) async {
    final repo = FakeHospitals();
    await pumpRouted(
      tester,
      const HospitalsScreen(),
      overrides: [
        hospitalsRepositoryProvider.overrideWithValue(repo),
        locationServiceProvider.overrideWithValue(FakeLocation()),
      ],
    );

    await tester.tap(find.text('Use my location'));
    await tester.pumpAndSettle();

    expect(repo.queries.single.toParams(), {'lat': 18.52, 'lng': 73.86});
    expect(find.text('Ruby Hall Clinic'), findsOneWidget);
  });

  testWidgets('unknown place shows location_not_found message', (tester) async {
    await pumpRouted(
      tester,
      const HospitalsScreen(),
      overrides: [
        hospitalsRepositoryProvider.overrideWithValue(
          FakeHospitals(
            error: const ApiException(
              statusCode: 404,
              code: 'location_not_found',
            ),
          ),
        ),
      ],
    );

    await tester.enterText(find.byType(TextField), 'Nowhereville');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(
      find.text("We couldn't find that place. Check the PIN code or area."),
      findsOneWidget,
    );
  });
}

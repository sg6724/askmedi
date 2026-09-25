import 'dart:typed_data';

import 'package:askmedi/core/network/api_client.dart';
import 'package:askmedi/core/platform/file_pickers.dart';
import 'package:askmedi/features/medicine/data/medicine_repository.dart';
import 'package:askmedi/features/medicine/domain/medicine_models.dart';
import 'package:askmedi/features/medicine/presentation/medicine_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_router.dart';

class FakePickers implements FilePickers {
  final photo = UploadFile(
    bytes: Uint8List.fromList([1, 2, 3]),
    name: 'strip.jpg',
    mimeType: 'image/jpeg',
  );
  PhotoSource? lastSource;

  @override
  Future<UploadFile?> pickPhoto(PhotoSource source) async {
    lastSource = source;
    return photo;
  }

  @override
  Future<UploadFile?> pickImageOrPdf() async => photo;
}

class FakeMedicineRepository implements MedicineRepository {
  FakeMedicineRepository({this.candidates = const [], this.scanError});
  final List<MedicineCandidate> candidates;
  final Exception? scanError;
  final lookups = <({String name, String? brand})>[];

  @override
  Future<List<MedicineCandidate>> scan(UploadFile image) async {
    if (scanError != null) throw scanError!;
    return candidates;
  }

  @override
  Future<MedicineInfo> lookup({
    required String name,
    String? brand,
    required String language,
  }) async {
    lookups.add((name: name, brand: brand));
    return MedicineInfo.fromJson({
      'name': name,
      'brand': brand,
      'salts': [
        {'name': 'Paracetamol', 'strength': '500 mg'},
      ],
      'uses': ['Fever', 'Mild pain'],
      'warnings': ['Avoid alcohol'],
      'pharmacist_flags': [
        {
          'reason':
              'Check with your pharmacist because you listed liver disease.',
        },
      ],
      'summary': 'Paracetamol lowers fever.',
      'sources': [
        {'title': 'openFDA label', 'url': 'https://open.fda.gov/'},
      ],
      'disclaimer': 'Not a diagnosis.',
    });
  }
}

void main() {
  final crocin = MedicineCandidate.fromJson({
    'brand': 'Crocin 500',
    'salts': [
      {'name': 'Paracetamol', 'strength': '500 mg'},
    ],
    'form': 'tablet',
    'manufacturer': 'GSK',
    'confidence': 0.9,
  });
  final dolo = MedicineCandidate.fromJson({
    'brand': 'Dolo 650',
    'salts': [
      {'name': 'Paracetamol', 'strength': '650 mg'},
    ],
  });

  testWidgets('photo -> confirm "Is this…?" -> result with pharmacist flags', (
    tester,
  ) async {
    final pickers = FakePickers();
    final repo = FakeMedicineRepository(candidates: [crocin, dolo]);
    await pumpRouted(
      tester,
      const MedicineScreen(),
      overrides: [
        filePickersProvider.overrideWithValue(pickers),
        medicineRepositoryProvider.overrideWithValue(repo),
      ],
    );

    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();
    expect(pickers.lastSource, PhotoSource.camera);
    expect(
      find.text('Is this Crocin 500 (Paracetamol 500 mg)?'),
      findsOneWidget,
    );
    expect(find.text('Dolo 650'), findsOneWidget); // alternative

    await tester.tap(find.text("Yes, that's it"));
    await tester.pumpAndSettle();

    expect(repo.lookups.single, (name: 'Paracetamol', brand: 'Crocin 500'));
    expect(find.text('Check with your pharmacist'), findsOneWidget);
    expect(
      find.text('Check with your pharmacist because you listed liver disease.'),
      findsOneWidget,
    );
    expect(find.text('Mild pain'), findsOneWidget);
    expect(find.text('Avoid alcohol'), findsOneWidget);
    expect(find.text('openFDA label'), findsOneWidget);
    expect(find.text('Not a diagnosis.'), findsOneWidget);
  });

  testWidgets(
    'unreadable photo (422) -> message and a name field to type into',
    (tester) async {
      final repo = FakeMedicineRepository(
        scanError: const ApiException(
          statusCode: 422,
          code: 'unreadable_image',
        ),
      );
      await pumpRouted(
        tester,
        const MedicineScreen(),
        overrides: [
          filePickersProvider.overrideWithValue(FakePickers()),
          medicineRepositoryProvider.overrideWithValue(repo),
        ],
      );

      await tester.tap(find.text('Choose photo'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining("Couldn't read the medicine name"),
        findsOneWidget,
      );

      expect(
        find.text('Type the name instead'),
        findsNothing,
      ); // field already open
      await tester.enterText(
        find.widgetWithText(TextField, 'Medicine name'),
        'Cetirizine',
      );
      await tester.tap(find.text('Look up'));
      await tester.pumpAndSettle();

      expect(repo.lookups.single, (name: 'Cetirizine', brand: null));
      expect(find.text('Uses'), findsOneWidget);
    },
  );
}

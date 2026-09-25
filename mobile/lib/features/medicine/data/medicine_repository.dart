import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/medicine_models.dart';

abstract interface class MedicineRepository {
  /// `POST /medicine/scan`: candidates read from a photo of the strip or box.
  Future<List<MedicineCandidate>> scan(UploadFile image);

  /// `POST /medicine/lookup`.
  Future<MedicineInfo> lookup({
    required String name,
    String? brand,
    required String language,
  });
}

class ApiMedicineRepository implements MedicineRepository {
  ApiMedicineRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<MedicineCandidate>> scan(UploadFile image) async {
    final json = await _api.postFile('/medicine/scan', 'image', image);
    return [
      for (final c in (json['candidates'] as List?) ?? const [])
        MedicineCandidate.fromJson(Map<String, dynamic>.from(c as Map)),
    ];
  }

  @override
  Future<MedicineInfo> lookup({
    required String name,
    String? brand,
    required String language,
  }) async => MedicineInfo.fromJson(
    await _api.postJson('/medicine/lookup', {
      'name': name,
      'brand': brand,
      'language': language,
    }),
  );
}

final medicineRepositoryProvider = Provider<MedicineRepository>(
  (ref) => ApiMedicineRepository(ref.watch(apiClientProvider)),
);

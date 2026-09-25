import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/hospital.dart';

abstract interface class HospitalsRepository {
  /// `GET /hospitals`.
  Future<HospitalSearchResult> search(HospitalQuery query);
}

class ApiHospitalsRepository implements HospitalsRepository {
  ApiHospitalsRepository(this._api);
  final ApiClient _api;

  @override
  Future<HospitalSearchResult> search(HospitalQuery query) async =>
      HospitalSearchResult.fromJson(
          await _api.getJson('/hospitals', query: query.toParams()));
}

final hospitalsRepositoryProvider = Provider<HospitalsRepository>(
    (ref) => ApiHospitalsRepository(ref.watch(apiClientProvider)));

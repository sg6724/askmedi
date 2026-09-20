import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_repository.dart';
import '../config/app_config.dart';

class MeResponse {
  const MeResponse({required this.userId, this.email});

  factory MeResponse.fromJson(Map<String, dynamic> json) =>
      MeResponse(userId: json['user_id'] as String, email: json['email'] as String?);

  final String userId;
  final String? email;
}

class ApiClient {
  ApiClient({
    required String baseUrl,
    required Future<String?> Function() tokenProvider,
    Dio? dio,
  }) : _dio = dio ?? Dio() {
    _dio.options
      ..baseUrl = baseUrl
      ..connectTimeout = const Duration(seconds: 10)
      ..receiveTimeout = const Duration(seconds: 60);
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await tokenProvider();
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        handler.next(options);
      },
    ));
  }

  final Dio _dio;

  Future<MeResponse> getMe() async {
    final response = await _dio.get<Map<String, dynamic>>('/me');
    return MeResponse.fromJson(response.data!);
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final auth = ref.watch(authRepositoryProvider);
  return ApiClient(baseUrl: AppConfig.apiBaseUrl, tokenProvider: auth.accessToken);
});

/// Verifies the app -> Vercel -> JWT path end-to-end (shown on Home).
///
/// autoDispose: per-session data, dropped with Home on sign-out so the next
/// account re-checks the server. `retry` is off: Riverpod 3's default (10
/// attempts, ~38 s of backoff) would hide the "server unreachable" tile and
/// its Retry button for minutes and hammer the backend.
final meProvider = FutureProvider.autoDispose<MeResponse>(
  (ref) => ref.watch(apiClientProvider).getMe(),
  retry: (_, _) => null,
);

import 'dart:typed_data';

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

/// A failed API call. [statusCode] is null when the server was not reached;
/// [code] is the backend's `{"detail": "<code>"}` when it sent one.
class ApiException implements Exception {
  const ApiException({this.statusCode, this.code});

  factory ApiException.fromDio(DioException e) {
    final data = e.response?.data;
    final detail = data is Map ? data['detail'] : null;
    return ApiException(
      statusCode: e.response?.statusCode,
      code: detail is String ? detail : null,
    );
  }

  final int? statusCode;
  final String? code;

  bool get isBusy => statusCode == 503;

  @override
  String toString() => 'ApiException($statusCode, $code)';
}

/// A file picked by the user, held in memory so uploads work on the web too.
class UploadFile {
  const UploadFile({required this.bytes, required this.name, required this.mimeType});

  final Uint8List bytes;
  final String name;
  final String mimeType;
}

/// Guesses a MIME type from a file name (image pickers on the web may not
/// report one).
String mimeTypeFor(String name) {
  final ext = name.split('.').last.toLowerCase();
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'pdf' => 'application/pdf',
    'wav' => 'audio/wav',
    'webm' => 'audio/webm',
    'm4a' => 'audio/mp4',
    'mp3' => 'audio/mpeg',
    _ => 'application/octet-stream',
  };
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
      ..receiveTimeout = const Duration(seconds: 90);
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

  Future<Map<String, dynamic>> getJson(String path, {Map<String, dynamic>? query}) =>
      _call(() => _dio.get<Map<String, dynamic>>(path, queryParameters: query));

  Future<Map<String, dynamic>> postJson(String path, Map<String, dynamic> body) =>
      _call(() => _dio.post<Map<String, dynamic>>(path, data: body));

  /// Sends [file] as multipart field [field]; bytes-based so it works on web.
  Future<Map<String, dynamic>> postFile(String path, String field, UploadFile file) =>
      _call(() => _dio.post<Map<String, dynamic>>(
            path,
            data: FormData.fromMap({
              field: MultipartFile.fromBytes(
                file.bytes,
                filename: file.name,
                contentType: DioMediaType.parse(file.mimeType),
              ),
            }),
          ));

  /// POSTs JSON and returns the raw response body (e.g. audio).
  Future<Uint8List> postForBytes(String path, Map<String, dynamic> body) async {
    try {
      final response = await _dio.post<List<int>>(
        path,
        data: body,
        options: Options(responseType: ResponseType.bytes),
      );
      return Uint8List.fromList(response.data ?? const []);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Map<String, dynamic>> _call(
      Future<Response<Map<String, dynamic>>> Function() request) async {
    try {
      final response = await request();
      return response.data ?? const {};
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
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

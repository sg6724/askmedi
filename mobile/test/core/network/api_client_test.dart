import 'dart:convert';
import 'dart:typed_data';

import 'package:askmedi/core/network/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingAdapter implements HttpClientAdapter {
  RecordingAdapter({this.status = 200, this.body});
  final int status;
  final Map<String, dynamic>? body;
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    last = options;
    return ResponseBody.fromString(
      jsonEncode(body ?? {'user_id': 'u-1', 'email': 'a@test.dev'}),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('getMe sends bearer token and parses response', () async {
    final adapter = RecordingAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final client = ApiClient(
      baseUrl: 'https://api.test',
      tokenProvider: () async => 'tok-123',
      dio: dio,
    );

    final me = await client.getMe();

    expect(adapter.last!.uri.toString(), 'https://api.test/me');
    expect(adapter.last!.headers['Authorization'], 'Bearer tok-123');
    expect(me.userId, 'u-1');
    expect(me.email, 'a@test.dev');
  });

  test('no token -> no Authorization header', () async {
    final adapter = RecordingAdapter();
    final client = ApiClient(
      baseUrl: 'https://api.test',
      tokenProvider: () async => null,
      dio: Dio()..httpClientAdapter = adapter,
    );
    await client.getMe();
    expect(adapter.last!.headers.containsKey('Authorization'), isFalse);
  });

  ApiClient client(RecordingAdapter adapter) => ApiClient(
        baseUrl: 'https://api.test',
        tokenProvider: () async => 'tok',
        dio: Dio()..httpClientAdapter = adapter,
      );

  test('postJson sends JSON and returns the body', () async {
    final adapter = RecordingAdapter(body: {'episode_id': 'e-1'});
    final json = await client(adapter).postJson('/chat', {'message': 'hi'});
    expect(adapter.last!.uri.toString(), 'https://api.test/chat');
    expect(adapter.last!.data, {'message': 'hi'});
    expect(json['episode_id'], 'e-1');
  });

  test('error responses become ApiException with the detail code', () async {
    final adapter = RecordingAdapter(status: 503, body: {'detail': 'llm_unavailable'});
    await expectLater(
      client(adapter).postJson('/chat', {}),
      throwsA(isA<ApiException>()
          .having((e) => e.statusCode, 'statusCode', 503)
          .having((e) => e.code, 'code', 'llm_unavailable')
          .having((e) => e.isBusy, 'isBusy', true)),
    );
  });

  test('postFile sends multipart bytes under the given field', () async {
    final adapter = RecordingAdapter(body: {'candidates': []});
    await client(adapter).postFile(
      '/medicine/scan',
      'image',
      UploadFile(bytes: Uint8List.fromList([1, 2]), name: 'a.jpg', mimeType: 'image/jpeg'),
    );
    final form = adapter.last!.data as FormData;
    expect(form.files.single.key, 'image');
    expect(form.files.single.value.filename, 'a.jpg');
    expect(form.files.single.value.contentType.toString(), 'image/jpeg');
  });

  test('getJson sends query parameters', () async {
    final adapter = RecordingAdapter(body: {'hospitals': []});
    await client(adapter).getJson('/hospitals', query: {'pincode': '411001'});
    expect(adapter.last!.uri.toString(), 'https://api.test/hospitals?pincode=411001');
  });

  test('mimeTypeFor guesses from the extension', () {
    expect(mimeTypeFor('scan.PDF'), 'application/pdf');
    expect(mimeTypeFor('x.jpeg'), 'image/jpeg');
    expect(mimeTypeFor('noext'), 'application/octet-stream');
  });
}

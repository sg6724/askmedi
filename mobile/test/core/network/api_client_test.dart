import 'dart:convert';
import 'dart:typed_data';

import 'package:askmedi/core/network/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingAdapter implements HttpClientAdapter {
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    last = options;
    return ResponseBody.fromString(
      jsonEncode({'user_id': 'u-1', 'email': 'a@test.dev'}),
      200,
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
}

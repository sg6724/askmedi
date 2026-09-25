import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

abstract interface class VoiceRepository {
  /// `POST /voice/transcribe` with a WAV recording. Returns the text.
  Future<String> transcribe(Uint8List wav);

  /// `POST /voice/speak`. Returns MP3 bytes.
  Future<Uint8List> speak(String text, {required String language});
}

class ApiVoiceRepository implements VoiceRepository {
  ApiVoiceRepository(this._api);
  final ApiClient _api;

  @override
  Future<String> transcribe(Uint8List wav) async {
    final json = await _api.postFile(
      '/voice/transcribe',
      'audio',
      UploadFile(bytes: wav, name: 'voice.wav', mimeType: 'audio/wav'),
    );
    return ((json['text'] as String?) ?? '').trim();
  }

  @override
  Future<Uint8List> speak(String text, {required String language}) {
    // The endpoint accepts at most 1500 characters.
    final clipped = text.length > 1500 ? text.substring(0, 1500) : text;
    return _api.postForBytes('/voice/speak', {'text': clipped, 'language': language});
  }
}

final voiceRepositoryProvider =
    Provider<VoiceRepository>((ref) => ApiVoiceRepository(ref.watch(apiClientProvider)));

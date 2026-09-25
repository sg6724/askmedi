import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/chat_models.dart';

abstract interface class ChatRepository {
  /// `POST /chat`. A null [episodeId] starts a new episode.
  Future<ChatReply> send({
    required String? episodeId,
    required String message,
    required String language,
  });
}

class ApiChatRepository implements ChatRepository {
  ApiChatRepository(this._api);
  final ApiClient _api;

  @override
  Future<ChatReply> send({
    required String? episodeId,
    required String message,
    required String language,
  }) async =>
      ChatReply.fromJson(await _api.postJson('/chat', {
        'episode_id': episodeId,
        'message': message,
        'language': language,
      }));
}

final chatRepositoryProvider =
    Provider<ChatRepository>((ref) => ApiChatRepository(ref.watch(apiClientProvider)));

import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/chats/data/chat_repository.dart';
import 'package:travibe/features/home/data/post_model.dart';

class SharePostResult {
  SharePostResult({
    required List<PublicUserModel> sent,
    required Map<String, String> failed,
  }) : sent = List.unmodifiable(sent),
       failed = Map.unmodifiable(failed);

  final List<PublicUserModel> sent;

  /// User ID → user-facing failure message.
  final Map<String, String> failed;
}

/// Sends a post to people as chat messages.
///
/// The chat API (`StoreMessageRequest.type`) only supports text/image/voice/
/// video, so the post is sent as a `text` message with an excerpt. Once the
/// backend adds a `post` message type (with `post_id`), replace [_sendOne]'s
/// `sendText` call with that payload; the sheet and cubit need no changes.
class SharePostMessenger {
  SharePostMessenger({ChatRepository? chat})
    : _chat = chat ?? LaravelChatRepository();

  final ChatRepository _chat;

  static const excerptLength = 280;
  static const maxMessageLength = 5000;

  Future<SharePostResult> send({
    required PostModel post,
    required List<PublicUserModel> to,
    String? note,
  }) async {
    final text = composeText(post, note);
    final outcomes = await Future.wait(to.map((user) => _sendOne(user, text)));
    final sent = <PublicUserModel>[];
    final failed = <String, String>{};
    for (var i = 0; i < to.length; i++) {
      final error = outcomes[i];
      if (error == null) {
        sent.add(to[i]);
      } else {
        failed[to[i].id] = error;
      }
    }
    return SharePostResult(sent: sent, failed: failed);
  }

  /// Returns null on success, otherwise a message for this recipient.
  Future<String?> _sendOne(PublicUserModel user, String text) async {
    try {
      final conversation = await _chat.create(user.id);
      await _chat.sendText(conversation.id, text);
      return null;
    } on ChatUnconfirmedSend {
      return 'May not have been sent to ${user.name}.';
    } on ApiError catch (error) {
      if (error.statusCode == 403) return "You can't message ${user.name}.";
      return error.message;
    } catch (_) {
      return 'Unable to send. Please try again.';
    }
  }

  static String composeText(PostModel post, String? note) {
    final author = post.user.name.trim().isEmpty
        ? 'a Travibe member'
        : post.user.name.trim();
    final content = (post.content ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    final shared = content.isEmpty
        ? 'Shared a post by $author.'
        : 'Shared a post by $author: “${_clip(content, excerptLength)}”';
    final message = (note ?? '').trim();
    return _clip(
      message.isEmpty ? shared : '$message\n\n$shared',
      maxMessageLength,
    );
  }

  static String _clip(String value, int max) {
    final runes = value.runes;
    if (runes.length <= max) return value;
    return '${String.fromCharCodes(runes.take(max - 1)).trimRight()}…';
  }
}

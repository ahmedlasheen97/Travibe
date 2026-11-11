import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/chats/data/chat_repository.dart';
import 'package:travibe/features/home/data/post_model.dart';

class SharePostResult {
  SharePostResult({
    required List<PublicUserModel> sent,
    required Map<String, String> failed,
    List<PublicUserModel> noteFailed = const [],
  }) : sent = List.unmodifiable(sent),
       failed = Map.unmodifiable(failed),
       noteFailed = List.unmodifiable(noteFailed);

  final List<PublicUserModel> sent;

  /// User ID → user-facing failure message.
  final Map<String, String> failed;

  /// People who got the post but not the typed note. They count as [sent] so
  /// a retry never shares the post twice.
  final List<PublicUserModel> noteFailed;
}

/// Sends a post to people as a `type: post` chat message, followed by the
/// optional note as a separate text message.
class SharePostMessenger {
  SharePostMessenger({ChatRepository? chat})
    : _chat = chat ?? LaravelChatRepository();

  final ChatRepository _chat;

  Future<SharePostResult> send({
    required PostModel post,
    required List<PublicUserModel> to,
    String? note,
  }) async {
    final postId = int.tryParse(post.id);
    final text = (note ?? '').trim();
    final outcomes = await Future.wait(
      to.map((user) => _sendOne(user, postId, text)),
    );
    final sent = <PublicUserModel>[];
    final noteFailed = <PublicUserModel>[];
    final failed = <String, String>{};
    for (var i = 0; i < to.length; i++) {
      switch (outcomes[i]) {
        case _Sent():
          sent.add(to[i]);
        case _NoteFailed():
          sent.add(to[i]);
          noteFailed.add(to[i]);
        case _Failed(:final message):
          failed[to[i].id] = message;
      }
    }
    return SharePostResult(sent: sent, failed: failed, noteFailed: noteFailed);
  }

  Future<_Outcome> _sendOne(
    PublicUserModel user,
    int? postId,
    String note,
  ) async {
    final chat = _chat;
    if (postId == null || postId < 1 || chat is! ChatOperationsRepository) {
      return const _Failed('This post cannot be shared.');
    }
    final String conversationId;
    try {
      conversationId = (await chat.create(user.id)).id;
      await (chat as ChatOperationsRepository).sendPost(conversationId, postId);
    } on ChatUnconfirmedSend {
      return _Failed('May not have been sent to ${user.name}.');
    } on ApiError catch (error) {
      return _Failed(switch (error.statusCode) {
        403 => "You can't message ${user.name}.",
        422 => "${user.name} can't see this post.",
        _ => error.message,
      });
    } catch (_) {
      return const _Failed('Unable to send. Please try again.');
    }
    if (note.isEmpty) return const _Sent();
    try {
      await chat.sendText(conversationId, note);
      return const _Sent();
    } catch (_) {
      return const _NoteFailed();
    }
  }
}

sealed class _Outcome {
  const _Outcome();
}

class _Sent extends _Outcome {
  const _Sent();
}

class _NoteFailed extends _Outcome {
  const _NoteFailed();
}

class _Failed extends _Outcome {
  const _Failed(this.message);
  final String message;
}

import 'dart:async';
import 'package:travibe/core/datasource/remotedata/api_error.dart';
import 'package:travibe/core/models/public_user_model.dart';
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/data/chat_repository.dart';
import 'package:travibe/features/home/data/post_model.dart';
import 'package:travibe/features/search/data/users_page_model.dart';
import 'package:travibe/features/shares/data/send_post_repo.dart';

PublicUserModel person(String id, {bool blocked = false}) =>
    PublicUserModel.fromJson({
      'id': id,
      'name': 'Traveller $id',
      'is_blocked': blocked,
    });
UsersPageModel peoplePage(
  List<PublicUserModel> users, {
  int page = 1,
  int last = 1,
}) => UsersPageModel(
  users: users,
  currentPage: page,
  lastPage: last,
  total: users.length,
);

class PeopleRead {
  PeopleRead(this.query, this.page);
  final String query;
  final int page;
  final result = Completer<UsersPageModel>();
}

class SendPeopleRepo extends SendPostRepo {
  final calls = <PeopleRead>[];
  bool hold = false;
  ApiError? error;
  UsersPageModel result = peoplePage([person('2'), person('3')]);
  @override
  Future<UsersPageModel> users(String query, {int page = 1}) async {
    final read = PeopleRead(query, page);
    calls.add(read);
    if (hold) return read.result.future;
    if (error != null) throw error!;
    return result;
  }
}

PostModel sharedPost({
  String? content = 'Sunset over Petra',
  String visibility = 'public',
}) => PostModel.fromJson({
  'id': 10,
  'url': 'https://travibeapp.com/p/10',
  'user_id': 2,
  'user': {'id': 2, 'name': 'Sara'},
  'content': content,
  'visibility': visibility,
  'likes_count': 0,
  'comments_count': 0,
});

/// Records `create`, `sendPost` and `sendText` in call order.
/// [failures] (participant ID) fail `create`; [postFailures] and
/// [noteFailures] (conversation ID) fail the post or the note.
class RecordingChatRepository
    implements ChatRepository, ChatOperationsRepository {
  final created = <String>[];
  final sent = <({String conversationId, String text})>[];
  final posts = <({String conversationId, int postId})>[];
  final calls = <String>[];
  final failures = <String, Object>{};
  final postFailures = <String, Object>{};
  final noteFailures = <String, Object>{};
  Completer<void>? gate;

  @override
  ChatCapabilities get capabilities =>
      const ChatCapabilities(create: true, sendText: true);

  @override
  Future<ChatConversation> create(String participantId) async {
    created.add(participantId);
    if (gate != null) await gate!.future;
    final failure = failures[participantId];
    if (failure != null) throw failure;
    return ChatConversation(
      id: 'c-$participantId',
      participant: ChatParticipant(id: participantId, name: participantId),
      canSend: true,
    );
  }

  @override
  Future<ChatMessage> sendPost(String id, int postId) async {
    calls.add('post:$id');
    final failure = postFailures[id];
    if (failure != null) throw failure;
    posts.add((conversationId: id, postId: postId));
    return ChatMessage(
      id: 'p-$id',
      senderId: 'self',
      kind: ChatMessageKind.post,
      postId: '$postId',
    );
  }

  @override
  Future<ChatMessage> sendText(String id, String text) async {
    calls.add('text:$id');
    final failure = noteFailures[id];
    if (failure != null) throw failure;
    sent.add((conversationId: id, text: text));
    return ChatMessage(
      id: 'm-$id',
      senderId: 'self',
      kind: ChatMessageKind.text,
      text: text,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

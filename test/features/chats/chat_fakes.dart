import 'dart:async';
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/data/chat_repository.dart';

const participant = ChatParticipant(id: 'other', name: 'Test Person');
const conversation = ChatConversation(
  id: 'conversation-1',
  participant: participant,
  canSend: true,
);
const message = ChatMessage(
  id: 'message-1',
  senderId: 'self',
  kind: ChatMessageKind.text,
  text: 'Test message',
);

class FakeChatRepository
    implements ChatRepository, ConversationRequestRepository {
  @override
  ChatCapabilities capabilities = const ChatCapabilities(
    list: true,
    messages: true,
    create: true,
    sendText: true,
    requests: true,
    requestActions: true,
    read: true,
  );
  List<ChatConversation> items = [conversation];
  List<ChatMessage> messageItems = [message];
  int loads = 0,
      sends = 0,
      cancellations = 0,
      reads = 0,
      accepts = 0,
      declines = 0;
  Completer<ChatMessage>? sending;
  Completer<ChatPage<ChatConversation>>? loading;
  Object? failure;
  @override
  Future<ChatPage<ChatConversation>> conversations({
    String? continuation,
    bool requests = false,
  }) async {
    loads++;
    if (failure != null) throw failure!;
    return loading?.future ?? Future.value(ChatPage(items));
  }

  @override
  Future<ChatPage<ChatMessage>> messages(
    String id, {
    String? continuation,
  }) async => ChatPage(messageItems);
  @override
  Future<ChatConversation> create(String participantId) async => conversation;
  @override
  Future<ChatMessage> sendText(String id, String text) async {
    sends++;
    if (failure != null) throw failure!;
    return sending?.future ?? Future.value(message);
  }

  @override
  Future<void> markRead(String id) async {
    reads++;
  }

  @override
  Future<void> resolveRequest(String id, {required bool accept}) async {
    accept ? accepts++ : declines++;
    items = [];
  }

  @override
  Future<ChatConversation> acceptRequest(String id) async {
    await resolveRequest(id, accept: true);
    return ChatConversation(
      id: id,
      participant: participant,
      canSend: true,
      isAccepted: true,
      isBlocked: false,
    );
  }

  @override
  Future<void> declineRequest(String id) => resolveRequest(id, accept: false);
  @override
  Future<void> remove(String id) async {}
  @override
  void cancel() {
    cancellations++;
  }
}

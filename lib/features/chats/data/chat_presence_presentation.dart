import 'chat_models.dart';
import 'package:travibe/core/utils/formatters.dart';

String? chatPresenceLabel(
  ChatConversation conversation, {
  required bool typing,
  required bool memberOnline,
  bool blocked = false,
}) {
  if (blocked ||
      conversation.participant.isBlocked == true ||
      conversation.isBlocked != false ||
      !(conversation.isAccepted == true || conversation.canSend)) {
    return null;
  }
  if (typing) return 'Typing…';
  final peer = conversation.participant;
  // Missing/withheld REST presence fields are not permission to expose presence.
  final available =
      peer.online != null ||
      peer.onlineStatus != null ||
      peer.lastSeenAt != null;
  if (!available) return null;
  if (memberOnline || peer.online == true) return 'Online';
  final seen = peer.lastSeenAt;
  if (seen == null) return null;
  final relative = timeAgo(seen);
  return relative == 'now' ? 'Last seen just now' : 'Last seen $relative ago';
}

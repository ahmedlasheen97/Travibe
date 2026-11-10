import 'dart:math';
import 'package:travibe/features/chats/data/chat_models.dart';
import 'package:travibe/features/chats/data/reverb_readiness.dart';
import 'chat_e2e_actor.dart';
import 'reverb_test_peer.dart';

class ChatE2eResult {
  ChatE2eResult(this.stages, {this.message});
  final Map<String, bool> stages;
  final ChatMessage? message;
  @override
  String toString() => 'ChatE2eResult(redacted)';
}

/// No production entrypoint invokes this. Caller must supply two approved
/// test-only principals; no automatic login, cleanup, follow or block operations.
Future<ChatE2eResult> runChatE2e({
  required ChatE2eHttpActor a,
  required ChatE2eHttpActor b,
  required ReverbDeployment deployment,
  bool realtime = false,
  bool decline = false,
  Future<ChatE2ePeer> Function()? peerFactory,
}) async {
  if (!a.permit.writes || !b.permit.writes) {
    throw const ChatE2eFailure('write_permission_required');
  }
  if (a.id == b.id || a.other != b.id || b.other != a.id) {
    throw const ChatE2eFailure('test_pair_mismatch');
  }
  if (decline && (!a.permit.decline || !b.permit.decline)) {
    throw const ChatE2eFailure('decline_permission_required');
  }
  final stages = <String, bool>{};
  ChatE2ePeer? sender, receiver;
  final connect = peerFactory ?? () => ReverbTestPeer.connect(deployment);
  final nonce = List.generate(
    12,
    (_) => Random.secure().nextInt(16).toRadixString(16),
  ).join();
  final marker = 'Travibe approved E2E $nonce';
  void check(bool ok, String stage) {
    if (!ok) throw ChatE2eFailure(stage);
    stages[stage] = true;
  }

  try {
    await a.verify();
    await b.verify();
    stages['account_identity'] = true;
    final created = await a.create();
    check(created.isNew, 'fresh_test_conversation_required');
    final conversation = created.conversation.id;
    final recipient = await b.detail(conversation);
    stages['create_conversation'] = true;
    if (recipient.isAccepted != true) {
      // A pending request is not listed to B until its first message exists.
      await a.send(conversation, '$marker request');
      final requests = await b.inbox(requests: true);
      check(requests.items.any((c) => c.id == conversation), 'request_visible');
      if (decline) {
        await b.decline(conversation, createdByThisRun: created.isNew);
        bool removed = false;
        try {
          await a.detail(conversation);
        } on ChatE2eFailure catch (error) {
          removed = error.status == 404;
        }
        bool removedForRecipient = false;
        try {
          await b.detail(conversation);
        } on ChatE2eFailure catch (error) {
          removedForRecipient = error.status == 404;
        }
        check(removed && removedForRecipient, 'request_declined');
        return ChatE2eResult(stages);
      }
      await b.accept(conversation);
      check(
        (await a.detail(conversation)).isAccepted == true,
        'request_accepted',
      );
    } else if (decline) {
      throw const ChatE2eFailure(
        'decline_requires_pending_request_no_relationship_changes',
      );
    }
    if (realtime) {
      sender = await connect();
      receiver = await connect();
      stages['websocket_connection_ack'] = true;
      await sender.subscribe(a, 'private-users.${a.id}');
      await receiver.subscribe(b, 'private-users.${b.id}');
      stages['private_subscription_ack'] = true;
      await sender.subscribe(a, 'presence-conversations.$conversation');
      await receiver.subscribe(b, 'presence-conversations.$conversation');
      stages['presence_subscription_ack'] = true;
    }
    final sent = await a.send(conversation, '$marker text');
    stages['send_text'] = true;
    if (realtime) {
      final event = await receiver!.message(sent.id);
      check(
        event.id == sent.id &&
            event.conversationId == conversation &&
            event.senderId == a.id &&
            event.text == sent.text,
        'message_event_delivery',
      );
    }
    final received = await b.messages(conversation);
    final rendered = received.items.where((m) => m.id == sent.id).firstOrNull;
    check(
      rendered != null &&
          rendered.text == sent.text &&
          rendered.senderId == a.id,
      'rest_receive',
    );
    final inbox = await b.inbox();
    check(inbox.items.any((c) => c.id == conversation), 'inbox_refresh');
    await b.read(conversation);
    stages['mark_read'] = true;
    final changed = await a.messages(
      conversation,
      updatedSince: sent.updatedAt ?? sent.createdAt,
    );
    check(
      changed.items.any((m) => m.id == sent.id && m.readAt != null),
      'server_read_timestamp',
    );
    if (realtime) {
      await sender!.readReceipt(conversation, b.id, sent.id);
      stages['read_event_delivery'] = true;
    }
    if (realtime) {
      DateTime? watermark;
      for (final m in received.items) {
        final date = m.updatedAt ?? m.createdAt;
        if (date != null && (watermark == null || date.isAfter(watermark))) {
          watermark = date;
        }
      }
      check(watermark != null, 'server_reconciliation_watermark');
      await receiver!.close();
      receiver = null;
      final missed = await a.send(conversation, '$marker reconnect');
      receiver = await connect();
      await receiver.subscribe(b, 'private-users.${b.id}');
      await receiver.subscribe(b, 'presence-conversations.$conversation');
      final merged = {for (final m in received.items) m.id: m};
      String? next;
      final seen = <String>{};
      do {
        final page = await b.messages(
          conversation,
          updatedSince: watermark,
          next: next,
        );
        for (final m in page.items) {
          merged[m.id] = m;
        }
        next = page.continuation;
        if (next != null && (!seen.add(next) || seen.length > 10)) {
          throw const ChatE2eFailure('reconciliation_pagination');
        }
      } while (next != null);
      check(
        merged[missed.id]?.text == missed.text &&
            merged[sent.id]?.readAt != null,
        'reconnect_rest_reconciliation',
      );
    }
    return ChatE2eResult(stages, message: rendered);
  } finally {
    await sender?.close();
    await receiver?.close();
  }
}

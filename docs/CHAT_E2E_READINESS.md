# Chat end-to-end and Reverb readiness — 2026-11-08

## Verified deployment, with separate stages

Supplied public configuration:
- Base: `wss://travibeapp.com/reverb` (TLS, effective port 443).
- Public application key: `e18855d51128bfdb7f62e5c6df983dfe` (not a server secret).
- Authorization: `POST https://travibeapp.com/api/v1/broadcasting/auth`.
- Documented channels: `private-users.{id}`, `presence-conversations.{id}`.

| Stage | Development host | iPhone 17 Simulator |
| --- | --- | --- |
| TLS chain/hostname verification | Passed, default trust, no certificate bypass | Passed |
| Literal `/reverb` WebSocket upgrade | Not upgraded; separate HTTPS GET returned 404 | Not upgraded |
| Pusher-protocol `/reverb/app/{publicKey}?protocol=7&client=flutter-travibe-readiness&version=1.0&flash=false` | Upgrade and exact `pusher:connection_established` acknowledged | Same acknowledgement |
| Server activity timeout | 30 seconds | 30 seconds |
| Anonymous POST to broadcasting auth | HTTP 401 | HTTP 401 |
| Positive bearer/channel authorization | Not tested — approved test principals absent | Not tested |
| Private/presence subscription acknowledgement | Not tested | Not tested |
| Actual message/read/typing/presence events | Not tested | Not tested |

The base is a path prefix, not a complete protocol handshake URL. Appending
`/app/{key}` and protocol parameters follows the official
[Pusher wire protocol](https://pusher.com/docs/channels/library_auth_reference/pusher-websockets-protocol/).
[Laravel Reverb](https://laravel.com/framework/docs/12.x/reverb) is Pusher-compatible.
A connected socket does not prove a signed channel, membership or event delivery.
The certificate expiry observed was 2027-01-12 06:33:14 UTC. These are point-in-time
network results, not a guarantee of future reachability, queue health or publishing.

No bearer token, account ID, signed authorization response, private channel,
message endpoint, presence heartbeat or server-record mutation was used in these
live probes. The auth POST was deliberately anonymous and changed no records.
Production Root/UI still does not enable this test transport.

## Contract audit

- `docs/openapi.json` and `API_REFERENCE.md` are the older 53-path audit and do not
  establish Chat behavior. They were preserved.
- `docs/chat-openapi.json` is the authorized 93-path snapshot used by the app.
- The authorized docs were fetched again with HTTP 200, without storing the
  documentation password. The current export still has 93 paths; Conversation,
  Message, broadcasting operations, MessageResource and the Chat introduction
  are unchanged. Latest downloaded/normalized JSON SHA-256:
  `93f192bdc55c348a982ff8ca4e12f9150cec6f40b5d515f74af6a9e93ff50270`.
- The difference is Notification `preview` metadata and its description. That
  unrelated UI/contract is not changed by this task. The existing snapshot is
  retained instead of silently rewriting references to its old checksum.

Confirmed Chat events (schemas already parsed by ChatBroadcastEvent):
- `message.sent`: full MessageResource on the conversation presence channel and
  sender's own private user channel. Match/deduplicate server message IDs.
- `typing.updated`: conversation_id, user_id, is_typing; ephemeral.
- `messages.read`: conversation_id, reader_id, last_read_message_id, read_at;
  apply only to own messages at/below cursor, ignoring own read echoes.
- User-channel notifications include notification.created/read/read_all/
  read_conversation as documented. Notification/FCM data is not a routing string
  or a substitute for authoritative message resources.

Authorization is form-encoded socket_id/channel_name. A recipient's pending
request and a block cannot join conversation presence; the initiator may.
`channel_data` for presence is protocol JSON with user_id; the harness checks
it against the signed actor. Subscription requires the exact raw wire event
`pusher_internal:subscription_succeeded` for the requested channel. Presence
membership data is validated separately. Backend prose names SDK-level
`pusher:member_added/removed`; the raw protocol names `pusher_internal:*`.
Protected wire traffic must still be observed before enabling member UI.

Message types remain text/image/voice/video. Sent requires HTTP 201; delivered_at
and read_at are authoritative. GET messages itself marks delivery, so it is
blocked by the harness's default read-only policy. No editing endpoint exists.
Reconnect uses inclusive highest server updated_at, with pagination and ID merge;
after_id alone does not recover edits, deletions and receipts.

## Prepared two-account test, not executed live

`test/live/chats_two_account_e2e_test.dart` is an external Flutter test driver.
It uses two isolated, fixed-origin HTTP clients with runtime-only test bearer
tokens and the existing typed LaravelConversationContract. It does not replace
or change production repositories, authentication, PreferencesManager or UI.
The received newly generated test message is rendered using ChatMessageBubble.
This is backend/socket/display integration, not yet a two-installed-device UI test.

Ordinary `flutter test` always skips the live scenario, even if secrets happen
to exist in the shell. Two gates are mandatory:
1. Non-secret compile-time `TRAVIBE_CHAT_E2E_ENABLE=true`.
2. Runtime `TRAVIBE_CHAT_E2E_WRITE_APPROVAL=approved-test-accounts-only`.

Only after the user explicitly authorizes disposable test accounts and the write
operations, supply via a secret manager or securely entered runtime environment:
- TRAVIBE_CHAT_E2E_ACCOUNT_A_ID and TRAVIBE_CHAT_E2E_ACCOUNT_B_ID (distinct).
- TRAVIBE_CHAT_E2E_TOKEN_A and TRAVIBE_CHAT_E2E_TOKEN_B (verified/full-access).
- TRAVIBE_CHAT_E2E_REALTIME=true to require actual socket events.
- TRAVIBE_CHAT_E2E_SCENARIO=accept (default), or decline for a separate fresh run.
- Decline additionally requires
  TRAVIBE_CHAT_E2E_DECLINE_APPROVAL=delete-only-new-test-thread.

Do not put tokens into Dart source, dart-define, command arguments, committed
environment files, screenshots, reports or logs. No credentials are supplied now.
After approval and runtime secret setup, the explicit command is:

```sh
flutter test --no-pub --dart-define=TRAVIBE_CHAT_E2E_ENABLE=true \
  test/live/chats_two_account_e2e_test.dart --reporter expanded
```

This command is documented, **not run**. Default execution without the define was
run and skipped the live test. No credentials or write authorization were inferred
from the previously restored ordinary Simulator session.

## Scenario and safeguards

1. GET user for each actor; exact allowlisted identity and verified email must
   match. Bearers never move between clients or redirects.
2. A creates the pair using documented user_id. A 200 existing thread stops before
   sending/deleting; 201 is required. Note that the authorized POST can restore a
   hidden existing pair before returning 200: use disposable accounts and approve
   this possibility. No preexisting content is deleted.
3. If pending, send one generated bootstrap message so the request becomes
   visible; B verifies its request and accepts. No follow/block change is used to
   force a particular acceptance state.
4. Connect sockets, authorize each own user/conversation channel, then await
   private and presence subscription acknowledgements separately.
5. A sends generated text. B must receive the matching actual message.sent event
   when real-time is required; a successful HTTP send or REST fetch cannot pass
   this stage. Then fetch/parse/display the test message and refresh the inbox.
6. B marks read; A must see server read_at and, when enabled, the matching
   messages.read event. No receipt is synthesized from send/navigation success.
7. Disconnect B, send a bounded offline test message, reconnect with a new socket
   ID, reauthorize/resubscribe, and reconcile updated_since pages by server ID.
   Inclusive overlaps must preserve prior receipts and not duplicate rows.
8. Decline is a separate explicitly approved scenario: only a newly created pending
   thread can be declined. Both actors must subsequently receive detail 404.
   An auto-accepted pair is not reset or changed to make this test applicable.
9. At most one create and three sends per actor/run; no automatic mutation retry,
   message DELETE, conversation DELETE, registration, logout, media upload or
   account creation. Failures may leave only approved test artifacts for review.
   No automated destructive cleanup is performed.

HTTP errors are redacted to stage/status, no response/request dumps. Timeouts,
wrong identities, unknown channels, non-matching resources and closed clients fail
closed. Sockets, subscriptions, caches and auth headers are disposed at completion.
Presence authorization/membership is opt-in and never run in the anonymous probe.

## Commands executed without writes

```sh
dart run tool/reverb_readiness.dart
flutter test --no-pub test/features/chats/chat_e2e_readiness_test.dart \
  test/live/chats_two_account_e2e_test.dart --reporter expanded
flutter test --no-pub integration_test/chat_reverb_readiness_test.dart \
  -d E648DA3C-7301-4B73-B7EF-1CF0463BE844 --reporter expanded
```

The native test initializes no app session or Firebase service. It verifies only
anonymous TLS/connection/auth-gate stages and explicitly expects subscription and
message-delivery verification to remain false. Further regression/build results
are recorded in CHAT_FEATURE_IMPLEMENTATION.md.

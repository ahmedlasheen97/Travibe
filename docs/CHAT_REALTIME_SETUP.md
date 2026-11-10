# Chat real-time setup

## Current status

**Reverb using the Pusher protocol is confirmed**, including channel names,
message/typing/read payloads and reconnect rules. Laravel Echo is not used.
The OpenAPI introduction (`info.description` in `docs/chat-openapi.json`) is the
source of these details, in addition to the broadcasting-auth operation.

**Deployment verified in stages on 2026-11-08:** the supplied TLS prefix
`wss://travibeapp.com/reverb` and public key
`e18855d51128bfdb7f62e5c6df983dfe` produce a successful Pusher protocol connection
at `/reverb/app/{key}` on port 443. Host and iPhone 17 Simulator both verified TLS
and received pusher:connection_established (30-second activity timeout). The
literal prefix is not a complete WebSocket handshake URL. Anonymous auth returns
401. Positive auth, private/presence subscription and delivery remain unverified.

Production lifecycle wiring now uses `dart_pusher_channels` 1.3.1 (pure Dart
Pusher protocol), with no Echo or native dependency-manager changes. It starts
only for a verified Laravel account after Root attaches, and pauses/disconnects
on background or session changes. The new client itself connected successfully
in an anonymous iPhone 17 integration test. This does not establish private
subscription or message delivery.

The default-off two-account harness and previous point-in-time results remain
in [CHAT_E2E_READINESS.md](CHAT_E2E_READINESS.md). No write test has been run and
no credentials were inferred from an existing app session. `travibe-api.json`
is available at project root and is semantically identical to the 93-path
`docs/chat-openapi.json`; the old 53-path spec/reference does not define Chat.

## Authorization and eligibility

POST `/api/v1/broadcasting/auth`, authenticated full-access verified-email bearer:
form fields `socket_id`, `channel_name`. Socket IDs match `^\d+\.\d+$`.
Response: `auth` string and optional `channel_data` JSON string. The repository
uses documented form encoding and a redacted authorization-result toString.

- `private-users.{userId}`: own user only.
- `presence-conversations.{conversationId}`: conversation participant only.
- Blocked pairs cannot join the conversation channel. A pending recipient also
  gets 403 until accepting; an initiator may join. Existing subscriptions remain
  open until the client disconnects, so eligibility changes require disconnect.
- One socket may carry the own user channel and open conversation channel.
- The service observes raw `pusher_internal:subscription_succeeded`, not merely
  successful authorization, before processing channel events.
- OpenAPI's operation declares JSON, but its explicit prose requires form data.
  The repository sends application/x-www-form-urlencoded with existing bearer
  authentication. Live successful authorization still needs an approved account.
- Auth completion checks session/generation/channel eligibility both before and
  after awaiting Dio; old sockets are closed on block/pending/route changes.

## Confirmed events

| Event | Channel / payload |
| --- | --- |
| `message.sent` | Conversation presence channel and sender's own user channel; full MessageResource. Append new IDs, reconcile duplicates |
| `typing.updated` | Conversation presence; conversation_id, user_id, is_typing; ephemeral/not stored |
| `messages.read` | Conversation presence; conversation_id, reader_id, last_read_message_id, read_at. Apply to own messages through cursor; ignore own read echoes |
| `notification.created` | Own user; NotificationResource plus unread_count. message_received data has conversation_id, message_id, message_type, preview, is_request |
| `notification.read` | notification_id, unread_count |
| `notifications.read_all` | marked_count, unread_count (0) |
| `notifications.read_conversation` | conversation_id, marked_count, unread_count |
| Standard Pusher presence events | subscription_succeeded member list and member_added/member_removed |

The app now has a strict ChatBroadcastEvent parser for message.sent,
typing.updated and messages.read, including guarded read-cursor application.
Message keys use authoritative IDs; read keys include cursor/time. Typing has no
permanent deduplication key because repeated true events renew ephemeral state.
Fake-payload tests do not establish live delivery.

## REST fallback and reconnection

REST is authoritative for history, sending, counters and reconnection. The socket
does not replay missed events. On reconnect, fetch notification pages newest
first until a known ID, then unread-count. For the open conversation, use highest
known server updated_at as updated_since. Timestamps have one-second precision
and the filter is inclusive: replace known IDs, including tombstones/read ticks
and quotes whose targets were deleted. after_id alone misses updates to old rows.

Current route/app-resume, manual Refresh messages and authenticated generic FCM
hints refresh REST data. Cached history is retained, requests coalesce, cursor
pages are cycle-checked, and stale sessions/lifecycle transitions stop work.
There is no background polling loop or arbitrary push-payload navigation.
Notification socket events invalidate the existing NotificationActivity and
NotificationsCubit. The count is fetched from REST; an open inbox fetches pages
through the oldest cached ID and merges read/new records without resetting its
pagination cursor. No separate notification state or payload-driven routes were
introduced. A closed inbox has no private list cache and loads REST on opening.

Outgoing typing POST is implemented with required is_typing, a two-second client
throttle and three-second idle stop. These are client policy, not a claimed server
TTL. A best-effort false is sent on pause/exit with still-current credentials.
Receiving typing renews a four-second client expiry and only uses the active
conversation peer's authenticated channel event. Presence subscription membership
and member additions/removals drive proven online state. Raw protocol internal
member event names and the documented Pusher SDK aliases are handled exactly.

Presence HTTP is documented: heartbeat every 30–45 seconds while active;
last_seen_at changes at most once per minute. DELETE or logout marks offline.
ChatPresenceRepo now issues a bodyless heartbeat every 35 seconds while Root is
attached, account verified and app foregrounded. Offline DELETE is serialized on
pause/detach, with 10-second network/12-second overall bounds. Session changes
cancel pending requests; no replacement account's credentials clean up an old
account. Backend logout/TTL cover cases where credentials expire before cleanup.
Other users' REST is_online string enum remains unspecified. Live membership can
supply presence; show_active_status hides REST fields, not channel membership.
No member list or online indicator is fabricated.

## Next verification

Provide two explicitly authorized disposable test accounts and permission for
specific write operations, then run the default-off harness described in
CHAT_E2E_READINESS.md. Validate auth responses, exact subscription acknowledgement,
message/read events and reconnect reconciliation separately. Production binding
is implemented and fake-stream tested, but these positive live checks remain
required before claiming authenticated end-to-end operation. Deployment values
are now known;
positive account authorization and actual event delivery are the remaining proof.
Never ship Reverb app secrets, Firebase server keys, documentation passwords or
service accounts. Existing UI, Cubits, REST repositories and session management
are not replaced by the external test driver.


## Production implementation and verification — 2026-11-08

- `reverb_socket.dart`: Pusher protocol adapter using the supplied TLS URL and
  public app key, with package logging disabled and redacted auth exceptions.
- `chat_reverb_service.dart`: one socket per active account, private user channel
  plus only the visible eligible conversation; acknowledgement-gated events,
  ID deduplication bounded to 512 entries, monotonic receipts/tombstones, typing
  expiry and confirmed membership. No arbitrary payload route is accepted.
- `chat_reverb_host.dart`, main/Root and existing screens: current-user, block,
  lifecycle and route visibility integration; asynchronous startup.
- Bounded retry delays 1/2/4/8/16 seconds and 20-second acknowledgement deadline.
  A 401/403 stops automatic retry without clearing Laravel credentials. A later
  resume/account or eligibility action can retry. REST remains available.
- On successful own-channel acknowledgement, reconcile the active conversation
  through inclusive updated_since REST pages and invalidate notifications/counts.
  Updated IDs replace old records; late snapshots cannot erase new stream rows
  or downgrade authoritative read receipts/deletion. Hidden routes refresh on
  return/resume; they do not retain an active presence subscription.
- Two anonymous iPhone 17 integration tests passed, including the actual new
  Pusher client connection. Host TLS/connection probe passed; anonymous auth=401.
  Positive auth/subscription and message delivery are **not verified**.
- Combined focused mocked regression suite: **510 passed**. Final targeted
  analysis: **No issues found**. Normal Simulator Debug build: **succeeded**
  (74.6-second Xcode build). Formatting check: 19 Dart files, no changes needed.
  Full changed-file list and commands are in CHAT_FEATURE_IMPLEMENTATION.md.
- No live messages, conversations, media uploads or request mutations occurred.
  The two-account write harness is still default-off. No Firebase pins, SwiftPM,
  Bundle ID or authentication changes.

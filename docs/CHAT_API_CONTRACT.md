# Verified Chat API contract

Source: authorized `https://travibeapp.com/docs/api`, downloaded 2026-11-07 UTC.
The page embeds OpenAPI 3.1.0 JSON; the extracted specification is saved as
[`chat-openapi.json`](chat-openapi.json): **93 paths**, API version 1.0.0.
SHA-256: `d0af5e2af16afcd9e62a5ba199ac80db4442b01ad5300ae27a67d2703929bd2a`.
Documentation authentication was supplied transiently to curl, not saved in
Flutter source, configuration, or the specification. No credentials are included here.
The older general `docs/openapi.json` was preserved for existing references.

User-supplied `travibe-api.json` is now available at the project root. SHA-256:
`2ce0218dd68fb892f96f014d77070b47cb9b04f8ee70b7e3e87d5168789d1878`.
Its parsed JSON is identical to `docs/chat-openapi.json` (93 paths); differing
file hashes reflect serialization only. No new endpoint, schema, or Chat intro
contract was introduced by this copy. The legacy 53-path `docs/openapi.json` and
`API_REFERENCE.md` are historical and are not used to infer Chat contracts.

Base URL: `https://travibeapp.com/api/v1/`. Chat endpoints require the existing
bearer token and verified email. Broadcasting/presence explicitly require full
access. Laravel remains authoritative for authorization and account eligibility.

## Changes from the previous audit

Documentation access is no longer blocked. Conversation mutations and Message
schemas are confirmed; the presign envelope inconsistency is resolved by the new
201 schema. The production contract now enables all documented REST operations.
Message editing is absent. Deployment is not embedded in the specification; the
user-supplied Reverb configuration was separately checked on 2026-11-08 (below).

## Conversation operations

| Method/path | Body | Success and semantics |
| --- | --- | --- |
| GET `/conversations` | none; `page`, optional `per_page` 1–100 and `search` max 100 | 200 paginated ConversationResource. Accepted threads plus pending requests started by caller; hidden threads excluded |
| POST `/conversations` | integer `user_id` | 201 new / 200 existing `data` resource. Restores caller's hidden thread. Accepted immediately if recipient follows caller; otherwise pending. Own/unavailable user 422, blocked pair 403 |
| GET `/conversations/requests` | same list query options | 200 paginated pending requests received by caller |
| GET `/conversations/{id}` | none | 200 `data` resource; non-participant 404 |
| PATCH `/conversations/{id}` | required boolean `is_muted` | 200 `data` resource; only caller's participant row changes |
| DELETE `/conversations/{id}` | none | 200 `{message: string}`. Hides for caller; when both remove, thread/messages/media are permanently deleted. New messages can restore a surviving hidden thread |
| POST `/conversations/{id}/read` | none | 200 updated `data` resource. Marks incoming messages read, resets unread counter, advances cursor and marks corresponding message notifications read |
| POST `/conversations/{id}/typing` | required boolean `is_typing` | 200 `{message: string}`. Ephemeral event, not stored; pending recipient cannot type, initiator can; blocked pair 403 |
| POST `/conversations/{id}/accept` | none | 200 updated `data` resource. Pending recipient only; already accepted/caller-started thread 403 |
| POST `/conversations/{id}/decline` | none | 200 `{message: string}`. Pending recipient only. Permanently deletes thread, messages, media and both participant rows |

Inbox and message lists use Laravel page metadata, not cursor-page envelopes.
Continuation is computed from `current_page` / `last_page`; server link URLs are
never followed with bearer credentials. Requests count uses `meta.total`.
Server search is a name/username prefix search, never a message-body search.
The production Inbox uses server search, debounced by 350ms. Older in-flight
queries are invalidated before the next request. The compact Requests screen
intentionally has no search field; the repository still supports documented
request search. Fake/legacy Inbox adapters retain loaded-row filtering.

Accept exposes the returned resource through `acceptRequest`, validating the
conversation ID and `is_accepted == true` before enabling the composer. The older
`resolveRequest` entry point remains compatible. Decline requires the documented
200 confirmation envelope; neither operation is optimistic.

ConversationResource contains `id`, `other_user`, `last_message`,
`last_message_at`, `unread_count`, `is_muted`, `is_blocked`, `accepted_at`,
`is_accepted`, `last_read_message_id`, `created_at`, `updated_at`.

PublicUserResource documents `is_online` as a string **without an enum**.
It remains unclassified; online/offline values are not guessed. Optional
last-seen/presence fields may be omitted for privacy. Required stable IDs are
normalized internally without inferring ownership from absent IDs.

Sending eligibility follows documented route context: a pending inbox/create
thread was initiated by the caller; a pending received request cannot send.
Accepted, unblocked threads can send. Detail refresh rechecks block/acceptance
state and preserves known initiator context; Laravel enforces every mutation.

## Messages

| Operation | Contract |
| --- | --- |
| GET `/conversations/{id}/messages` | 200 page envelope. Initial latest page is ascending within that page (newest last); page 2 loads older history. `after_id` selects newer IDs ascending. `updated_since` selects created/changed rows ascending by ID, including deleted placeholders. These two cursors are mutually exclusive. `per_page` 1–100, default 15 |
| POST `/conversations/{id}/messages` | 201 `{data: MessageResource}`. Pending recipient cannot send; initiator can. Blocked pair 403 |
| DELETE `/messages/{id}` | Sender only; 200 `{message: string}`. Placeholder visible to both; attached media released and preview/unread counter adjusted. Already deleted 404; non-sender 403 |
| Editing | No PATCH/PUT/edit endpoint in this specification; not implemented |

StoreMessageRequest:

- `type`: `text`, `image`, `voice`, `video`.
- Text: required `body`, max 5000 characters; no `media_id`.
- Image: required ready `media_id`, optional `body` caption max 1000.
- Voice: required `media_id` and `duration_ms`; no body.
- Video: required `media_id`, optional `poster_media_id` and `duration_ms`; no body
  per the StoreMessageRequest body rule (despite broader enum summary wording).
- `duration_ms`: 1–86400000 when supplied.
- `reply_to_id`: optional positive ID in the same conversation.
- Media must be owned by sender, ready and unattached. No client idempotency key
  is documented; uncertain sends are not automatically retried.

MessageResource includes IDs/type, nullable body, `media` PublicMediaResource
array, optional/empty poster, nullable/empty reply quote, duration, deletion flag,
`delivered_at`, `read_at`, created/updated/deleted timestamps. Deleted rows use a
reduced placeholder shape; the client removes body/media and hides stale quotes.
Unknown future types have a neutral unsupported presentation, not raw enum text.

GET messages itself marks incoming messages delivered unless pending/blocked.
HTTP 201 is only Sent. Delivered/Seen derive from the resource timestamps.
REST refresh and `updated_since` reconcile receipts/deletions on cached history;
no receipt is synthesized from opening a route. Read mutation must succeed before
local notification count refresh. Pending/blocked receipt suppression is server-owned.

## Media upload

`POST /media/presign` returns **201**, top-level:
`media`, `upload_url`, `upload_method` (`PUT`), `upload_headers`, `expires_at`.
Request: filename ≤255, allowed MIME `content_type`, positive byte `size`.
Leave `mediable_type`/`mediable_id` unset so chat can claim the ready media later.

Upload bytes to the returned HTTPS URL with its exact signed headers using a
separate transport with no API interceptors/bearer header. Then POST
`/media/{id}/finalize` (200 `data` resource), and poll GET `/media/{id}` until
ready/failed. Finalize 409 is reconciled by GET; ambiguous writes are not repeated
blindly. Finalize 503 preserves the record; backend performs actual MIME/size checks.

Allowed backend types: JPEG/PNG/GIF/WebP; audio MPEG/MP4/x-M4A/AAC/WAV/x-WAV/OGG/
WebM; video MP4/QuickTime/WebM. Backend limits: 20 MB image/audio, 100 MB video.
Chat picker deliberately caps selected files at 20 MiB to bound in-memory uploads;
this stricter UI limit does not alter the API's video limit.

The client supports camera images, mixed Gallery images/videos, and native AAC-LC
M4A voice recording (`audio/mp4`). Voice duration comes from the recording clock;
playback progress comes from the player. No fake waveform/progress is generated.
Temporary recordings are removed after conversion to a memory draft or disposal.
No unclaimed-media cleanup endpoint is documented; none is invented on discard.

## Broadcasting and remaining contracts

POST `/broadcasting/auth` requires `socket_id` (`digits.digits`) and `channel_name`.
The prose explicitly requires form encoding, which the repository uses despite
OpenAPI's generic JSON content declaration. 200 returns required `auth` and
optional JSON-string `channel_data`; this does not establish subscription success.

The OpenAPI introduction explicitly confirms **Reverb using the Pusher protocol**;
Laravel Echo is not used. Channels are `private-users.{userId}` and
`presence-conversations.{conversationId}`. A blocked pair or pending recipient
cannot join the conversation channel; already-open subscriptions must disconnect
when eligibility changes.

Documented events:

- `message.sent`: full MessageResource on the conversation channel and sender's
  own user channel; deduplicate by server message ID.
- `typing.updated`: conversation_id, user_id, is_typing. Ephemeral; repeated true
  events must not be permanently deduplicated by value.
- `messages.read`: conversation_id, reader_id, last_read_message_id, read_at;
  update only own messages through the cursor and ignore own read echoes.
- `notification.created`: NotificationResource plus unread_count. message_received
  data contains conversation_id, message_id, message_type, preview, is_request.
- `notification.read`, `notifications.read_all`,
  `notifications.read_conversation`: IDs/counts described in the intro.
- Standard presence subscription/member-added/member-removed events.

Typed parsing for the three Chat events and read-cursor application are implemented
and mock-tested in `chat_broadcast_event.dart`. The production transport is now
`dart_pusher_channels` 1.3.1, using the supplied public deployment configuration.
TLS and anonymous connection are verified; positive auth, subscription and live
message delivery still require approved disposable accounts. No secret belongs
in Flutter. See `CHAT_REALTIME_SETUP.md`.

## Readiness revalidation — 2026-11-08

Authorized docs were fetched again (HTTP 200). Chat/broadcast operations,
MessageResource and Chat event descriptions remain unchanged. Only Notification
preview documentation changed; the snapshot and unrelated implementation are
preserved. Supplied deployment configuration now passes TLS and anonymous Reverb
connection acknowledgement on host and iPhone 17 Simulator. Positive channel auth,
subscription and message delivery are not yet verified. See
[CHAT_E2E_READINESS.md](CHAT_E2E_READINESS.md) for public configuration, stage results,
source fingerprint and the write-disabled two-account test plan.

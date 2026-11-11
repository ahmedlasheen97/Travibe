# Chat feature implementation — authorized API integration

Latest update: see **Bottom offline banner, safe bubble retry and emoji picker — 2026-11-10** below.
The preceding **Final Inbox loading, image placeholders and numeric unread badge — 2026-11-10**
section records the completed Inbox/image/badge work.
The preceding **Conversation cache and loading investigation — 2026-11-10** section
records the original conversation-cache work.
The latest visual update is **Home Chat badge and image sending — 2026-11-09**.
The preceding **Chat UI enhancements and edge states — 2026-11-09** section covers
options/deletion, conversation details, shared media, long messages, offline
feedback, loading and the original empty-state illustration. Earlier sections
retain the implementation history and their original verification boundaries.

## Current delivery

The existing Chat screens now use the verified OpenAPI contracts in
`docs/chat-openapi.json`. All ten Conversation endpoints and the three documented
Message endpoints are integrated. Text, replies, images, voice and video payloads,
message deletion, mute/read/request actions, and receipt parsing are implemented.
Existing screens/themes/navigation were retained; composer/media controls were
extracted into reusable widgets to connect the newly confirmed capabilities.

**Live sending/receiving and WebSocket delivery are not verified.** No live account
mutations were performed. API tests use mocks; native builds prove compilation,
not microphone permission, camera/gallery behavior or successful media playback.

## Reference and architecture

All ten images in `docs/chat-references/` were inspected during the original UI
implementation. Dark surfaces, orange controls, shared glass back button,
centered Chats title, flat rows and the conversation layout remain. No production
fixture users/messages, invented routes, or backend fields were introduced.

Repositories reuse DioClient, token interceptors and sessionRevision. Cubits keep
in-memory account-scoped lists/drafts and coalesce requests. Existing Root, Home,
Notifications, authentication, onboarding and Firebase lifecycle are preserved.
No .vscode, signing, bundle identifier, Firebase project or authentication changes.

## Conversation flow

- Inbox and requests parse nullable nested resources and page metadata. Requests
  count uses `meta.total`; cached content remains on refresh/errors. Search in the
  existing inbox is local to loaded names/previews, while the API also documents
  an optional server prefix-search field. No misleading server-search claim.
- Existing user discovery creates with integer `user_id`; 200 existing and 201
  new resources both open the returned conversation. Duplicate taps are blocked.
- Detail loads current metadata and sending eligibility. Pending inbox/create
  threads may send as initiator; pending received requests cannot until accepted.
  Blocked threads stay visible with disabled sending. Unknown online strings do
  not produce false presence indicators.
- Menu supports mute/unmute, manual message refresh and conversation removal.
  Removal explains potential permanent deletion after both participants remove.
- Requests accept/decline refresh authoritative lists. Decline requires a warning
  because it permanently deletes the thread and media for both participants.
- Successful read synchronizes header/cursor and refreshes the existing Laravel
  notification count, since the API marks associated notifications read too.
  The read mutation is guarded by route/app visibility. No local fake Seen state.

## Messaging and reconciliation

Messages preserve chronological server-ID order. Older pages prepend with a
reversed scroll view; refresh merges cached history. Server IDs deduplicate
send responses, REST results and future event invalidations. A confirmed send is
shown immediately, without waiting for a slow refresh or overwriting newer ticks.

Latest-page refresh plus paginated `updated_since` reconciliation updates older
cached read/deleted rows. Cursors use server timestamps, not client wall-clock
receipts; cyclic pagination is rejected. Session/lifecycle checks stop stale work.

Text bodies are limited to 5000 Unicode codepoints. Reply actions use only the
confirmed `reply_to_id`; quotes render deleted placeholders when known targets
are deleted. Sender-only deletion is offered when the stable current-user ID is
known; Laravel is authoritative. Private deleted body/media is removed from the
presentation. Message editing is absent from OpenAPI and is not implemented.

Sending/failed states are client state. Sent is confirmed by HTTP 201. Delivered
and Seen are shown only from server `delivered_at` / `read_at`. Fetching messages
itself marks delivery per the contract; live fetches were therefore not used as
read-only tests on real accounts. Pending/blocked receipt policy is server-owned.
No idempotency key is documented: uncertain text sends retain the draft and ask
the user to check before deliberately retrying; no automatic POST retries.

## Attachments, audio and video

The existing media pipeline is reused: presign 201 → raw PUT with exact signed
headers → finalize → bounded status polling → ready media ID → message 201.
API bearer credentials never enter the storage transport. Signed headers/URLs
and user bytes are never logged. Ambiguous uploads reconcile the same record;
a ready ID is retained after an uncertain send rather than uploading duplicates.
After confirmed send, the upload recovery instance is released so intentionally
sending the same file later gets a fresh unattached record.

Camera selects photos. Gallery uses the existing image_picker mixed-media API.
Supported formats are validated before upload; the UI caps selections at 20 MiB
for memory use (backend video supports 100 MB). Image captions max 1000 are
validated before upload. Images have full-screen zoom; videos play inline only
after a user tap. There is no autoplay or fake thumbnail.

Native voice uses record (AAC-LC, 64 kbps, 44.1 kHz, M4A/audio/mp4). Permission is
requested only on Record. Stop retains a memory draft for Send/Discard; failed
upload/send retains it. Temporary files are removed after reading/disposal.
App background stops recording into a draft; logout clears it. Navigation warns
before discarding and blocks accidental departure during upload.

just_audio provides one player per conversation. Voice/video players coordinate
so they do not overlap, pause on background, and dispose on logout/exit. Progress
is real player position; no synthetic waveform is generated. Video uses Flutter's
video_player, with lazy URL loading and account-change cleanup. Actual supported
codecs remain platform-dependent and need device QA.

Composer has bounded scrolling for optional reply/error/voice controls above the
keyboard. It preserves text/focus, supports RTL/emoji and reduces its multiline
limit in short landscape viewports. Tests use real MediaQuery viewport data;
long message tests use the actual conversation scrollable, not a bounded card.

Default shared MediaUploadService still allows only image MIME types for existing
Profile flows. Chat opts into audio/video. Parser projections validate the expected
media type and accept the newly documented nullable thumbnail. API media calls
now carry captured sessionRevision as well; this prevents cross-account uploads.

## Real time and remaining verification

Channel authorization is implemented with documented form fields and safe
response parsing. Deployment values were subsequently supplied and anonymous
TLS/connection checks passed on 2026-11-08; see the readiness section below.
Positive channel authorization and actual event delivery still need test accounts. Reverb and event payloads are confirmed in
the OpenAPI introduction; typed Chat event parsing is covered by fake-payload
tests. Production now uses the Pusher-protocol client described in the latest
implementation section below and `CHAT_REALTIME_SETUP.md`.

Foreground heartbeat and authenticated channel membership are integrated.
Public REST online-status string values remain unconfirmed and are not coerced.
Typing POST remains throttled/idle-stopped; incoming typing now expires locally
four seconds after its last true event. FCM remains an invalidation hint.

Still needed: two authorized test accounts, controlled live conversation/message/
attachment tests, device microphone/camera/gallery/playback QA, and actual
subscription/event-delivery verification. Unclaimed-media
cleanup is backend-owned; no undocumented DELETE is invented on draft discard.

## Packages/platform configuration

Added official packages just_audio 0.10.6, record 7.1.2 and video_player 2.14.1
(with their locked transitive dependencies). Their iOS implementations have SwiftPM
manifests and compiled successfully. Existing package manager is preserved.
FlutterFire pins remain firebase_core 4.15.2 / firebase_messaging 16.7.1;
native pins remain Firebase 12.19.3 / Google Sign-In 9.2.0.

Added iOS microphone usage text and Android RECORD_AUDIO permission. Existing
camera/gallery usage descriptions were reused. No new signing capability,
background audio mode, ATS exception or Firebase configuration was introduced.

## Files changed

- `docs/chat-openapi.json` (new authorized specification)
- `lib/features/chats/data/chat_models.dart`
- `lib/features/chats/data/chat_repository.dart`
- `lib/features/chats/data/laravel_conversation_contract.dart`
- `lib/features/chats/data/chat_broadcast_event.dart` (new verified event parser)
- `lib/features/chats/cubit/chat_cubit.dart`
- `lib/features/chats/cubit/chat_audio_controller.dart` (new)
- `lib/features/chats/screens/chats_screen.dart`
- `lib/features/chats/screens/conversation_screen.dart`
- `lib/features/chats/widgets/chat_widgets.dart`
- `lib/features/chats/widgets/chat_composer.dart` (new extracted controls)
- `lib/features/chats/widgets/chat_video_message.dart` (new)
- `lib/core/media/media_upload_model.dart`
- `lib/core/media/media_upload_service.dart`
- `lib/core/datasource/remotedata/api_service.dart`
- `pubspec.yaml`, `pubspec.lock`
- `ios/Runner/Info.plist`
- `android/app/src/main/AndroidManifest.xml`
- `test/features/chats/conversation_contract_test.dart`
- `test/features/chats/chat_repository_test.dart`
- `test/features/chats/chat_widgets_test.dart`
- `test/features/chats/authorized_messaging_test.dart` (new)
- `test/features/chats/chat_voice_upload_test.dart` (new)
- `test/features/chats/chat_broadcast_event_test.dart` (new)
- `docs/CHAT_API_CONTRACT.md`, this file, `docs/CHAT_REALTIME_SETUP.md`

Flutter-generated plugin registrations/local package metadata were refreshed by
pub/build. No third-party SDK sources were edited. Git status is unavailable in
this workspace, so this inventory records deliberate edits rather than a Git diff.

## Verification

Verified on 2026-11-08 with Flutter 3.44.9 / Dart 3.12.2:

- Dependency resolution and Dart formatting completed. Targeted analysis of Chat,
  shared media, ApiService and their tests: **no issues**.
- Full analysis: **three unchanged findings** outside this implementation:
  missing widget key in `custom_bottom_nav.dart`, unnecessary underscores in
  `trending_destinations_section.dart`, and an unused import in
  `discard_changes_dialog_widget.dart`. No application diagnostics were suppressed.
- Focused Chat/media/Profile/Notifications/push/auth/onboarding/Home/story-upload
  regressions: **637 passed, zero failed**. This includes seven typed broadcast
  event tests and responsive/RTL/keyboard cases. Following the final playback
  lifecycle guard, the complete Chat subset passed again: **141 tests**.
- Full suite: **1654 passed, five existing failures**. This run preceded the seven
  additional broadcast-parser tests, which passed in the focused run. Two Search
  failures concern small-screen overflow and SVG sizing; three
  `story_other_viewer_test.dart` failures concern reply-composer row, typing and
  keyboard-dismiss behavior. These unrelated tests were not changed.
- Final Simulator Debug build completed successfully in **47.8 seconds** with
  the new audio/video plugins. Bundle ID
  remains `com.travibe.app`; resolved native Firebase 12.19.3 and Google Sign-In
  9.2.0 remain unchanged.

No app launch, real-account send/receive, microphone/camera/gallery/playback QA,
or WebSocket subscription/event delivery was verified during this update. Only
documentation credentials were supplied, not authorized chat test accounts.
Documentation credentials were used transiently and are not stored in the project.

## Chat screenshot alignment — 2026-11-08

All ten images in `docs/chat-references/` were listed and opened visually before
UI edits. This directory contains **no Other User Profile references**. The
separate limitation in `OTHER_USER_PROFILE.md` remains; these Chat screenshots
are the primary design authority for this pass. No Figma node IDs were guessed.

| Screenshot suffix (all `Screenshot 2026-11-07 at … .png`) | Observed reference |
| --- | --- |
| `12.44.23` | Chats initial skeleton: heading bars, circular avatars, name/preview/time bars |
| `12.44.30` | Loaded Chats: Messages/Requests, unread badge, avatars, timestamps |
| `12.44.41` | Conversation: incoming/outgoing text and voice, empty composer |
| `12.45.00` | Draft composer with Send action |
| `12.45.08` | Newly sending message and receipt presentation |
| `12.45.15` | Compact Camera/Gallery menu above composer with dark barrier |
| `12.45.26` | Receipt-state design examples; these are alternatives, not simultaneous states |
| `12.45.43` | Portrait image messages and expanded multiline composer |
| `12.45.53` | Filtered Chats search results |
| `12.46.00` | Empty search with clear action and no Messages/Requests heading |

### Corrections made

- Chats header controls are balanced 44px circles; the search uses the existing
  search SVG, dark fill, stable hint and reference clearance below the header.
- Initial loading replaces live Messages/Requests with skeleton heading bars.
  Skeleton and loaded avatar/row rhythms match (52px reference avatar target).
  Unread badges have a compact 32px minimum width and preserve 99+ semantics.
- Requests is aligned to the right edge. Search results use a Chats section
  heading; empty search has no section heading or Requests action. Filtering is
  still local to loaded data, including confirmed username/name/preview fields.
- The global input theme sets `fillColor: white`. Its inherited fill was visible
  inside the Chat composer. The composer now opts out of that fill locally, and
  New Conversation explicitly sets its dark search fill. Global theme unchanged.
- Reused the existing send, emoji, camera/gallery and search SVG artwork. Emoji
  focuses the existing keyboard; it does not pretend to provide a custom picker.
- Short histories align below the header instead of floating just above the
  composer. The bounded reverse list, controller, server ordering and older-page
  pagination remain. Date labels use Today/Yesterday only for actual timestamps.
- Conversation options use the reference circular control. Voice messages use
  capsule bubbles and an orange circular play/pause affordance. Existing text
  bubble colors and directional corners were already close and are retained.
- Camera/Gallery now open a compact, clipped dark menu above the actual attachment
  button, respecting SafeArea, text scale, RTL direction and keyboard height.
  Barrier/Back dismiss it without clearing text. Unsupported actions stay disabled.
  Media upload and message APIs are unchanged.

### Visual verification artifacts

Representative **mocked widget renders**, not screenshots of real messages/users:
[inbox](chat-verification/inbox-mocked.png),
[loading](chat-verification/loading-mocked.png),
[search](chat-verification/search-mocked.png),
[empty search](chat-verification/empty-search-mocked.png),
[conversation](chat-verification/conversation-mocked.png),
[attachments](chat-verification/attachments-mocked.png).
These were rendered with the real dark theme, Plus Jakarta Sans and Material/SVG
assets and visually inspected against the references. Mock users exist only in
`test/`; these PNGs are documentation artifacts, not production assets.

Intentional functional differences remain: real server receipt state is displayed
one state at a time; unknown online-status strings do not produce fake green
presence dots; voice uses actual playback progress instead of fabricated waveform
amplitudes; attachment access remains while a caption is being composed. Reference
sample users, messages, online flags, images and receipt values are never seeded
into production. Full media/voice playback requires device/backend QA.

### Navigation checks

- Chats → New Conversation: widget test checks one route despite repeated action,
  borrows the same FollowCubit/BlockCubit and returns to the inbox.
- New Conversation → user search → selected conversation: existing discovery tests
  cover minimum length, 350ms debounce, stale responses, own/block filtering,
  errors/retry, pagination and single create/navigation with mocked repositories.
- Chats → existing conversation → Back: widget test preserves local query and
  scroll offset across a refreshed inbox.
- Conversation header → Profile uses existing ProfileScreen.open and its duplicate
  guard. Post author and comment links were source-audited and their existing
  profile/comment regressions run; no second profile route was introduced.
- Profile → Message and old-session response prevention remain covered by the
  existing Other User Profile widget tests with mocked repositories.

### Verification for this pass

- Dart formatting completed on changed Dart files only.
- Targeted analysis (Chat, new reference tests and updated integration test):
  **no issues**.
- Focused Chat/discovery/Profile/post-author/comments/Home regressions:
  **295 passed, zero failed**. This includes all existing Chat lifecycle,
  pagination, error/retry, account-switch and keyboard tests.
- Screenshot/layout/navigation suite: **9 passed**, including four phone widths
  (320/375/393/430) with 1.6 text scaling and a visible keyboard. Captures are
  opt-in with `--dart-define=CHAT_CAPTURE=true`; ordinary tests do not write PNGs.
- iOS Simulator Debug build: **successful, 42.3s**. `flutter run` also built in
  83.2s and launched successfully on the booted iPhone 17 (iOS 26.5). Its visible
  normal-app Home screen was inspected with a simulator screenshot.
- Existing native integration smoke test was updated to accept empty or populated
  real inboxes rather than hardcoding an empty account. It passed: **1 test**.
  The restored authenticated session reached Home; live GET conversations and
  requests both returned HTTP 200 with `data:[]` and `meta.total:0`. Pull-to-refresh,
  Requests, New Conversation, a valid `trav` user query and Back navigation were
  exercised. Discovery completed loaded with zero matches and no error, confirming
  a legitimate empty result in this run rather than a parsing/network failure.
- No live conversation POST, message GET/POST, typing/read mutations, account
  relationship mutations, camera/gallery uploads or audio playback were exercised.
  Nonempty history/rendering, selection/create and Profile → Message remain
  mocked-test verification. No real-time transport or delivery was verified.
- No simulator reset, credential extraction or real-user messages. The normal
  production entry point is restored after the integration runner; final launch
  result is recorded below.
Production source edits are limited to the three Chat screens, ChatComposer,
chat_widgets and the extracted chat_attachment_menu. Added the reference widget
capture/tests, updated the existing safe simulator smoke test, and added the six
mock-render documentation images. No Firebase, SwiftPM, Bundle ID, authentication,
Profile implementation, Home implementation or backend contracts were changed.

Final normal-app relaunch after the integration runner: **successful** on iPhone
17, Debug rebuild **37.0s**, file sync complete and process exit 0. The app is left
on its normal entry point. No full-suite rerun was performed in this visual pass;
the previously recorded unrelated Search/Story Viewer failures were not reclassified.

Files changed in this pass:
- `lib/features/chats/screens/chats_screen.dart`
- `lib/features/chats/screens/conversation_screen.dart`
- `lib/features/chats/screens/new_conversation_screen.dart`
- `lib/features/chats/widgets/chat_composer.dart`
- `lib/features/chats/widgets/chat_widgets.dart`
- `lib/features/chats/widgets/chat_attachment_menu.dart` (new extracted popup)
- `test/features/chats/chat_reference_ui_test.dart` (new, nine tests)
- `integration_test/chats_simulator_test.dart` (read-only, handles populated/empty APIs)
- `docs/chat-verification/*-mocked.png` (six documented test renders)
- `docs/CHAT_FEATURE_IMPLEMENTATION.md`

Historical status at the visual-alignment pass: Reverb deployment configuration
had not yet been supplied. It is now supplied and connected anonymously; see the
latest implementation section below.
Nonempty history, live conversation creation, sending/receipts and media/voice
need explicitly authorized controlled test accounts and actual delivery/playback
verification. Profile reference images are still absent from this directory.


## Historical end-to-end / Reverb readiness — 2026-11-08 (before production binding)

The current delivery and UI above are preserved. This pass prepares tests and
readiness probes; it does not activate a production socket transport or modify
Cubits/repositories/authentication. Detailed gates, commands and exact contracts:
[CHAT_E2E_READINESS.md](CHAT_E2E_READINESS.md).

### Sources and observed network results

The older 53-path docs/openapi.json and API_REFERENCE.md were audited alongside
the newer authorized 93-path snapshot. Authorized docs were refreshed (HTTP 200):
Chat operations, MessageResource and Chat event descriptions are unchanged;
only out-of-scope Notification preview documentation changed. Existing specs and
Notifications implementation were retained. No documentation credentials persisted.

The supplied Reverb base, public key and channel patterns are now recorded.
The complete protocol URI is the prefix plus `/app/{publicKey}` and protocol-7
query parameters. The base `/reverb` alone is not upgraded; a plain HTTPS GET to
it returned 404. Host and iPhone 17 Simulator both verified TLS and received
`pusher:connection_established`, activity timeout 30 seconds. The anonymous
broadcasting-auth request returned HTTP 401 in both environments.

**Positive auth, private/presence subscription and real message/receipt delivery
are NOT verified.** No account IDs/bearers were used in live probes; no presence
join, message history GET, conversation creation, message send, read, typing,
accept/decline or other server-record mutation was performed. The ordinary
restored Simulator account was not used as a test principal.

### Prepared two-account harness

An external, test-only driver uses runtime-secret bearer credentials and the
existing typed Laravel contract; production repositories/PreferencesManager are
not duplicated or changed. The generated test message is rendered with the real
ChatMessageBubble. It requires a compile-time enable flag plus explicit runtime
write approval and two distinct verified account IDs. Default live execution is
skipped, regardless of secrets in a shell. Decline has an additional separate gate.

Stages are independently asserted: identity → fresh conversation → request
acceptance when needed → socket connection → signed authorization → exact private
and presence subscription acknowledgement → text send → actual message.sent event
→ REST/display/list refresh → read timestamp and actual messages.read → reconnect
with a new socket and paginated inclusive updated_since reconciliation. Decline
is a separate fresh pending-thread scenario, verified deleted for both actors.

The harness blocks GET messages in read-only mode because that GET affects
delivery state, limits create/send counts, rejects unknown pairs/channels, never
automatically retries a mutation and performs no destructive cleanup. Only
stage/status diagnostics are logged; no tokens, signatures, text, URLs or IDs.

### Verification

- Dart formatting completed on changed Dart files.
- Targeted analysis: **no issues**.
- Chat/Profile-message/auth/session/push/onboarding regressions and readiness
  tests: **305 passed, zero failed; one live-write test skipped by default**.
- Readiness-specific unit/mock tests: **15 passed** (included above). They verify
  safety gates, actor isolation, conditional request decisions, receipt provenance,
  independent event proof, missing-event failure and reconnect reconciliation.
- Native iPhone 17 anonymous readiness integration: **1 passed**. Native Debug
  test build **46.7s**; no Firebase/session initialization or private subscription.
- Full suite was not rerun; prior unrelated failures were not reclassified.
- Normal app Simulator Debug build: **successful, 125.9s**. Its binary was
  restored on iPhone 17 after the test without launching account-bound startup
  services. Simulator data was not reset. No ordinary account was used for probes.

Files added: lib/features/chats/data/reverb_readiness.dart;
tool/reverb_readiness.dart; test/support/chat_e2e/chat_e2e_actor.dart,
chat_e2e_scenario.dart and reverb_test_peer.dart;
test/live/chats_two_account_e2e_test.dart;
test/features/chats/chat_e2e_readiness_test.dart;
integration_test/chat_reverb_readiness_test.dart; docs/CHAT_E2E_READINESS.md;
docs/chat-realtime-readiness.json (sanitized point-in-time probe results).
Existing ChatRealtimeCoordinator received a comment correction only. Updated
CHAT_REALTIME_SETUP.md, CHAT_API_CONTRACT.md, this report and the legacy
API_REFERENCE.md cross-reference. No UI, native configuration, Firebase versions,
SwiftPM, Bundle ID or authentication behavior changed. Git metadata remains
unavailable; no reset, revert or commit occurred.

Remaining blockers: two explicitly authorized disposable test accounts, secure
runtime credential provisioning and permission for the selected write scenarios;
then positive authorization/subscription/event tests and production lifecycle
binding. WebSocket host/key/TLS are no longer unknown. This is readiness progress,
not a claim that production real-time messaging is operational.


## Updated specification and production Reverb binding — 2026-11-08

This section supersedes historical statements above that transport/presence or
server search is disabled. Existing screenshot-aligned screens were retained.

### Source comparison

`travibe-api.json` was located in Downloads and copied into the project root
before implementation. Its parsed OpenAPI is identical to the authorized
`docs/chat-openapi.json`: 93 paths, same schemas and introductory event contracts.
The SHA-256 is `2ce0218dd68fb892f96f014d77070b47cb9b04f8ee70b7e3e87d5168789d1878`.
The 53-path legacy docs remain historical; they do not override this source.

### Implemented production behavior

- Added pure Dart `dart_pusher_channels` 1.3.1, not Echo. Transitive additions:
  pinenacl 0.6.0, web_socket 1.0.1, web_socket_channel 3.0.3. Existing Firebase,
  Google Sign-In and native SwiftPM versions/configuration were preserved.
- App-scoped ChatReverbHost observes the authoritative current user and app
  lifecycle. Root attachment gates startup behind existing routing; splash,
  onboarding and authentication never wait for WebSockets or presence.
- Private user subscription plus the visible eligible conversation presence
  subscription. Authorization uses existing Dio, captured sessionRevision and
  documented form fields; OpenAPI's declared JSON content type conflicts with
  its explicit form-encoding prose, which the implementation follows.
- Socket subscription acknowledgement gates event processing. Pending recipients,
  blocked users and block actions in flight cannot join presence. Eligibility
  changes disconnect the old socket so a delayed authorization cannot rejoin.
- Bounded reconnect delays 1/2/4/8/16 seconds, 20-second connection/subscription
  acknowledgement deadline, no credential deletion on errors. 401/403 stop
  reconnect attempts until a fresh lifecycle/account/eligibility action.
- Exact message.sent/typing.updated/messages.read parsing, channel checks,
  bounded ID-based deduplication, ephemeral typing expiry and membership-derived
  online state. No invented REST is_online string enum or push route interpretation.
- Reconnect triggers open-thread REST updated_since synchronization (inclusive,
  page-by-page replacement by server ID, retaining older cached history).
  Concurrent REST snapshots cannot erase a later event. Receipt merging is
  monotonic and deleted messages cannot be resurrected by late snapshots.
- Notification events are coalesced into existing REST inbox/count invalidation.
  Open inbox reconciliation refreshes through its oldest cached ID, replaces read
  states and preserves the existing pagination cursor. With no open inbox there
  is no private inbox cache; it loads from REST when opened. Broadcast counts and
  descriptions are not rendered as authoritative inbox data.
- Bodyless presence heartbeat every 35 seconds only while a verified account is
  attached to Root in foreground. Offline DELETE is serialized on pause/detach.
  Account changes cancel pending requests/timers/sockets; queued old-session
  operations are skipped. Logout itself also marks offline per contract; TTL
  handles credentials expiring before explicit cleanup. No bearer retention.
- Inbox and request search now send documented search/page parameters; 350ms
  debounce and immediate query invalidation prevent stale-result replacement.
- Existing conversation creation, request accept/decline, text/reply/delete,
  image/voice/video sends, receipt parsing and presign → PUT → finalize → send
  pipeline were reused. Media requires finalized owned IDs and existing MIME/size
  validation (20MiB image/voice, 100MiB video); no new upload endpoint was invented.
  Editing remains unsupported because no editing operation is documented.

### Files changed in this pass

- `travibe-api.json`, `pubspec.yaml`, `pubspec.lock`
- `lib/main.dart`, `lib/root.dart`
- `lib/features/chats/data/reverb_socket.dart` (new protocol adapter)
- `lib/features/chats/data/chat_reverb_service.dart` (new session/event lifecycle)
- `lib/features/chats/data/chat_presence_repo.dart` (new existing-Dio presence API)
- `lib/features/chats/widgets/chat_reverb_host.dart` (new app scope)
- `lib/features/chats/data/chat_repository.dart`, `chat_models.dart`
- `lib/features/chats/cubit/chat_cubit.dart`
- `lib/features/chats/screens/chats_screen.dart`, `conversation_screen.dart`
- `lib/core/cubit/cursor_list_cubit.dart` (opt-in cached reconciliation method)
- `lib/features/notifications/cubit/notification_activity.dart`, `notifications_cubit.dart`
- `test/features/chats/chat_reverb_service_test.dart` (new)
- `test/features/chats/chat_server_search_test.dart` (new)
- `test/features/chats/authorized_messaging_test.dart`
- `test/features/notifications/notification_reverb_reconcile_test.dart` (new)
- `integration_test/chat_reverb_readiness_test.dart`
- `docs/CHAT_API_CONTRACT.md`, `docs/CHAT_REALTIME_SETUP.md`, this report

### Verification

- Combined focused suite: **510 passed**, covering Chat UI/contracts/requests,
  Reverb session races/events/reconnects, server search debounce, media validation,
  Notifications, Firebase push lifecycle, pagination, authentication/onboarding,
  follow/block and other-user profile regression tests.
- iPhone 17 anonymous integration tests: **2 passed**. Native TLS/Pusher handshake
  plus actual production Pusher client connection were observed. No session was
  loaded, no channel was authorized and no message was sent.
- Final targeted `flutter analyze --no-pub` across Chat, changed notification/core
  files, main/Root, focused tests and the native probe: **No issues found**.
- `dart format --output=none --set-exit-if-changed` on all 19 changed Dart files:
  **0 formatting changes required**.
- Final `flutter build ios --simulator --debug --no-pub`: **succeeded**, Xcode
  build 74.6 seconds; `build/ios/iphonesimulator/Runner.app` produced after the
  integration run. The anonymous integration runner launched on the iPhone 17;
  no ordinary authenticated app session was launched for live write testing.
- Native lockfile still resolves Firebase iOS SDK **12.19.3** and Google Sign-In
  **9.2.0**. FlutterFire remains **4.15.2 / 16.7.1**.
- Dependency resolution completed successfully through `flutter pub add` when
  adding the Pusher client; no arbitrary overrides or native SDK edits.
- Host read-only probe: trusted TLS, HTTP upgrade plus connection acknowledgement,
  activity_timeout 30 seconds; anonymous broadcasting auth HTTP 401. These are
  connectivity results, not positive authorization/subscription/event delivery.
- No live conversation creation, message sends/deletion, media upload or request
  mutations. No private credentials were inferred from the simulator session.
- No UI redesign, Firebase/package pin changes, SwiftPM/signing changes or commits.

### Remaining verification and limitations

Two explicitly authorized disposable accounts and scoped write permission are
still required for successful private/presence authorization, cross-account
message delivery, receipt/request lifecycle, reconnect recovery, and attachment
playback/upload tests. The existing two-account harness remains default-off.
No actual authenticated sending/receiving or real-time delivery is claimed.
The public REST is_online string enum remains unspecified; online indicators only
use confirmed channel membership. Permission/device media UX still needs QA.
Git metadata is unavailable in this workspace, so no Git diff/commit was possible.

## Chat interactions completion — 2026-11-09

### Implemented behavior

- Microphone access is checked only after tapping Record. Native iOS/Android
  permission adapters distinguish first request, denial and Settings-only states.
  Existing `record` captures real AAC-LC audio; its amplitude stream drives the
  level display. Recording supports elapsed time, pause/resume, cancellation,
  preview through existing `just_audio`, and the existing media upload pipeline.
  Empty/oversize recordings are rejected. Interruption preserves a finished draft;
  cancellation, disposal and account changes release resources and temporary files.
- Header status prioritizes Typing → Online → Last seen, using actual REST fields
  and authorized membership. Blocked/pending and withheld/unknown presence are
  suppressed. An opaque REST status string is never interpreted as a boolean.
- Receipt/timestamp details are collapsed initially. Tapping selects one message;
  outgoing Seen/Delivered use actual timestamps, incoming details show time only.
  Existing monotonic receipt reconciliation remains intact.
- Gallery selection creates an ordered, removable thumbnail tray, without sending.
  Each selection uses a separate documented `media_id` message. Confirmed items
  leave individually; failure preserves the current and later selections. Retry
  reuses finalized media and first reconciles an uncertain send by media ID.
  Pending media remains visibly pending, with upload progress and retry feedback.
- Image bubbles preserve aspect ratio and open a black pinch/pan viewer. Download
  validates actual image data, limits size, uses no bearer interceptor, cancels
  across sessions, and reports success only after native gallery save completes.
  iOS uses Photos add-only access; Android uses MediaStore and requests legacy
  write permission only through API 28. No new package dependencies were added.
- The compact selection tray and bottom-anchored composer viewport keep input
  accessible with the keyboard and increased text size. Existing older-message
  pagination remains; automatic latest-message scrolling is limited to users near
  the bottom.

### Files changed or added for these interactions

- `lib/features/chats/cubit/chat_audio_controller.dart`
- `lib/features/chats/data/chat_device_media.dart`, `chat_image_saver.dart`,
  `chat_media_selection.dart`, `chat_presence_presentation.dart`,
  `chat_models.dart`, `chat_broadcast_event.dart`
- `lib/features/chats/screens/conversation_screen.dart`, `chat_image_viewer.dart`
- `lib/features/chats/widgets/chat_composer.dart`, `chat_widgets.dart`,
  `chat_recording_strip.dart`, `chat_selected_media_tray.dart`,
  `chat_pending_media_bubble.dart`
- `lib/core/media/media_upload_service.dart` (optional progress callback)
- `ios/Runner/AppDelegate.swift`, `ios/Runner/Info.plist`
- `android/app/src/main/kotlin/com/travibe/app/MainActivity.kt`,
  `android/app/src/main/AndroidManifest.xml`
- `test/features/chats/chat_interactions_test.dart`,
  `chat_media_queue_send_test.dart`, `chat_widgets_test.dart`
- `integration_test/chat_media_native_test.dart`
- This report and `docs/chat-verification/*-mocked.png`.

### References and visual checks

Only the original ten `docs/chat-references/` images were available; the five
new interaction screenshots could not be located. Figma metadata was accessible,
but design-context access reached the service plan limit. New behavior follows
the written requirements and existing references; exact fidelity to the missing
five screenshots is not claimed. Saved conversation/attachment renders under
`docs/chat-verification/` contain test fixtures, never production mock messages.

### Verification

- Final focused suite: **534 passed**, including Chat, media, Firebase/Notifications,
  pagination, authentication/session, onboarding, follow/block and profile tests.
  The initial run exposed a compact keyboard layout failure; the corrected layout
  passed the full rerun. Interaction tests cover 320/375/393/430 widths and a small
  keyboard viewport with 1.6 text scaling.
- Additional reference rendering suite: **9 passed**; conversation render inspected.
- Targeted analysis across Chat, media upload, Chat tests and native probe:
  **No issues found**. Dart format: **37 files checked, zero changes required**.
- iOS Simulator Debug build: **succeeded**, Xcode 63.5 seconds in the resumed run.
  After the native test, the ordinary app was rebuilt successfully (67.0 seconds),
  installed and launched on iPhone 17 (`com.travibe.app`). A Simulator screenshot
  confirmed the first onboarding page loaded. No authenticated Chat session was
  available or exercised in this launch; onboarding was not skipped or reset.
- Before interruption, native Simulator checks passed microphone status plus an
  opt-in actual Photos save of a local one-pixel PNG (**2 passed**). Photos add-only
  access was pre-granted; this did not exercise the permission dialog. The fixture
  remains in Simulator Photos. The resumed passive native microphone-status check
  also **passed (1 test)** and launched its native runner on iPhone 17; it did not
  request access or record audio.
- Android compile attempt was blocked by unavailable Maven artifacts from
  `dl.google.com`, `repo.maven.apache.org` and `storage.googleapis.com`, including
  `error_prone_annotations:2.3.2`; Android native compilation is not verified.

No live messages, server mutations or media uploads were performed. Microphone
hardware capture, native permission dialogs, physical-device gallery behavior,
and authenticated cross-account media delivery still require controlled device
QA and explicitly authorized test accounts. Firebase versions, SwiftPM, Bundle ID,
authentication and existing real-time contracts were preserved. No commit made.

## Message Requests UI and confirmed resolution — 2026-11-09

This section supersedes earlier descriptions of inline request actions and the
Requests search field. The five newly referenced Requests images could not be
located in the project. The original ten Chat images remain available and their
previously recorded mappings contain no Requests/pending/decline reference set.
Local filenames were requested. Implementation follows the user's written
requirements and existing Travibe theme; exact reference parity is unverified.

### Requests and pending conversation

- Header is now **Requests**, centered with the existing circular Back control.
  Black background and the existing compact ChatListTile retain avatars, real
  last-message previews, optional relative timestamps and unread badges. Inline
  Accept/Decline controls and the Requests search field were removed. Inbox
  search and repository-level request search remain supported and tested.
- A received pending request opens the existing ConversationScreen with its
  history and date separators. “Accept request to reply” and equal pill buttons
  replace the entire composer; no text field, microphone or attachment controls
  are mounted. Both sending and typing have explicit pending-recipient guards.
  The screen does not bind a conversation presence channel before acceptance.
  Documented pending threads initiated by the current user retain their existing
  sending permission; they are not misclassified as received requests.
- New ChatRequestButton reuses the clipped, moderate-blur GlassSurface, with an
  orange/charcoal base, restrained reflection and border. Pointer position drives
  the highlight; compression is 0.97 with a 240ms release curve. Reduced motion
  disables scaling and highlight motion. Normal minimum height is 50px; controls
  grow for accessibility text. Loading stays inside the active button and all
  competing actions are disabled during mutations. The tint and reflection are
  separate paint layers so the gradient cannot discard the base color.

### Accept and decline

The confirmed OpenAPI contracts remain unchanged: bodyless POST `/accept`
returns a 200 `data: ConversationResource`; bodyless POST `/decline` returns a
200 `{message: string}` confirmation. The latter permanently deletes the thread,
messages/media and participant rows according to the backend contract.

- `ConversationRequestRepository.acceptRequest` retains the server resource
  previously discarded by the void action. Identity mismatch or a response still
  marked pending is rejected. No accepted state is manufactured locally.
- After confirmed acceptance the current screen keeps its message history,
  transitions to the normal composer, updates existing list Cubits and request
  count, rebinds eligible Reverb presence, and refreshes/read-synchronizes REST.
  Read results update the Inbox without decrementing the request count twice.
- Decline opens a clipped glass confirmation using the exact requested title and
  description. Red Decline and white Cancel actions use the same button behavior.
  Cancel makes no request. Confirmed success removes the request, returns to
  Requests and shows **Message request declined**. The declined thread is never
  inserted into Inbox. Failure retains the dialog/request and offers an explicit
  retry via Decline; Cancel remains available after failure.
- All mutations are guarded against repeated taps. Logout/account switching
  invalidates late completions, clears private content and dismisses the dialog.
  No bearer credentials or message bodies are logged or retained by this flow.

### Inbox/Requests synchronization and races

The existing ChatListCubit and route callbacks remain the owners; no parallel
conversation cache, singleton state store or replacement repository was added.
The typed repository interface is implemented by the existing Laravel repository.

- `removeConfirmed` records route/account-scoped removal IDs and filters them
  from pending pages, later stale snapshots and confirmed item events. Query
  changes retain removals; a replacement session clears them.
- Inbox promotion uses existing `appendConfirmed`, so an older in-flight load
  cannot replace the newly confirmed resource. The Requests route removes the
  same ID and forwards updates to the existing Inbox route.
- Count refresh captures a mutation revision. Responses started before a
  confirmed resolution cannot restore an obsolete count. A coalesced refresh
  follows mutations that overlap existing requests. Server `meta.total` remains
  authoritative; partial pages are never treated as the global count.
- Detail/read epochs and accepted-state guards prevent old pending resources
  from replacing a confirmed acceptance. Reconnect reconciliation can promote an
  externally accepted request through REST without issuing another accept POST.
- Fresh routes/relaunch use REST again. Removal markers are memory-only, not a
  replacement for backend persistence. Existing pagination/search/scroll state,
  message reconciliation and session cancellation remain intact.

### Files changed

- `lib/features/chats/data/chat_repository.dart`
- `lib/features/chats/cubit/chat_cubit.dart`
- `lib/features/chats/screens/chats_screen.dart`, `conversation_screen.dart`
- `lib/features/chats/widgets/chat_request_controls.dart` (new)
- `test/features/chats/message_requests_test.dart` (new)
- `test/features/chats/chat_fakes.dart`, `chat_widgets_test.dart`,
  `chat_server_search_test.dart`, `chat_repository_test.dart`,
  `authorized_messaging_test.dart`
- `docs/CHAT_API_CONTRACT.md`, this report, and four mocked renders under
  `docs/chat-verification/requests-*-mocked.png`.

### Verification

- Focused Chat regression run: **228 passed** before the final extra capture case;
  the full suite below covers the final code and all **229** Chat tests.
- Focused Requests tests with font-loaded render capture: **20 passed**. Checks
  cover compact list/no inline actions, pending guards, confirmed acceptance,
  errors/retry, duplicate locks, decline/cancel/navigation, unread/request counts,
  account changes, stale details/pages/counts, REST reconnect promotion, fresh
  route restoration, glass press/release/loading and reduced motion.
- Layout checks: 320/375/393/430 logical pixels, 1.6 text scaling, top/bottom safe
  padding and an inherited keyboard inset. Dialog actions remain reachable by
  scrolling when accessibility text consumes the available height.
- Renders of Requests, pending conversation, decline confirmation and declined
  state were visually inspected with Plus Jakarta Sans and Material icons loaded.
  These contain explicit **test fixtures only**, never production sample users.
  Render capture waits for route transitions before taking the image.
- Final full `flutter test --reporter expanded`: **1786 passed, 0 failed,
  1 existing opt-in skip** in 195 seconds. Includes Profile, Stories, Search,
  navigation, authentication, Notifications/Firebase, Home and follow regressions.
  The sole skip remains the unauthorized/default-off live two-account harness.
  No new skips, deleted tests or weakened assertions.
- Targeted analysis of all Chat source/tests: **No issues found**. Formatting of
  the 11 changed Dart files: **0 changes required**.
- Final `flutter build ios --simulator --debug --no-pub`: **succeeded**, Xcode
  87.7 seconds, producing `build/ios/iphonesimulator/Runner.app`. Native dependency
  pins, SwiftPM, signing settings and Bundle ID were unchanged.
- The final Debug app was installed and launched on the booted iPhone 17 without
  resetting Simulator data. A screenshot confirmed the existing Profile Setup
  gate. No profile fields were changed or gate bypassed; live Requests screens
  were not exercised. The four Requests images above are widget renders, not
  screenshots of authenticated Simulator request flows.

An earlier full-suite attempt was interrupted for the final glass paint-layer
correction and is not counted as verification. The successful 1786-test run
listed above completed afterward on the corrected production code.

No live accept/decline, conversation creation, message send or media upload was
performed. Authorized disposable accounts and permission are still required for
end-to-end Laravel mutations, actual private-channel authorization after accept,
cross-account delivery/read updates and restart verification against live data.
Mocked flows and a successful Simulator build do not establish live API success.

## Chat UI enhancements and edge states — 2026-11-09

### References and scope

The local image inventory contains the original ten images under
`docs/chat-references/` and older mocked verification captures. All ten original
images were visually inspected again: loading, Inbox, conversations/composer,
attachments, receipt examples, image messages, search and no-results. The seven
new options/delete/details/gallery/long-message/offline/empty references were
**not found**. Figma metadata also returned the Starter-plan tool-call limit.
Consequently the new states implement the user's written specification and
existing tokens; pixel-level comparison against the seven new references was
not possible. No Figma content was changed.

### Implemented behavior

- **Loading:** added Flutter-only `skeletonizer: ^3.0.0`, preserving Home's actual
  `#232323`/`#303030` palette and 1800ms effect. Home itself still uses its existing
  shimmer implementation and was not changed. Chats/Requests use avatar, label,
  timestamp and badge bones; history uses incoming/outgoing bubble bones; shared
  media uses tile bones. Reduced motion uses a static solid effect. Cached
  content remains visible during refresh and pagination. Compact actions and
  additional-history loading use Cupertino indicators; Inbox refresh is adaptive.
  No native plugin or SwiftPM dependency was added.
- **Empty Inbox:** exact title/description, retained search/header/Messages/Requests
  controls and the original `assets/images/avatar/image 95.svg`, already covered
  by the registered avatar directory. Only a successful empty result displays
  this state; loading, errors, queries and confirmed offline use their own states.
  The supplied SVG's embedded PNG/pattern produced zero visible pixels with the
  installed SVG rendering stack in a direct diagnostic render. The new
  `ChatEmptyIllustration` reads the original asset's embedded image and original
  objectBoundingBox matrix and paints the same crop. The SVG is untouched; no
  replacement artwork or duplicate raster asset was added. A pixel-level test
  confirms that the original orange artwork is visible.
- **Options:** dark rounded sheet, drag handle, existing profile/trash/flag/remove
  SVGs, four actions and red Block styling. Profile, ReportReasonSheet/ProfileRepo
  and shared BlockCubit/confirmation are reused. No new backend endpoints.
- **Delete:** existing glass mutation dialog generalized with compatible defaults
  for Message Requests. Exact new Delete wording, red/white glass actions,
  Cupertino progress, reduced motion, duplicate locking and retry on failure.
  Only a confirmed DELETE removes the Inbox row and returns to Chats. Pending
  pre-delete snapshots are invalidated; later canonical REST data can legitimately
  restore a hidden thread after new activity. Existing request-decline tombstones
  retain their stronger behavior. Active text sends, uploads, recordings and
  pending attachments must finish or be cancelled before Delete is allowed.
  Opening shared media is also guarded while recording. No claim that Delete
  removes the other copy.
- **Details:** tap the participant name/header to open details; the existing
  avatar-to-profile shortcut remains. Large real avatar, name, optional username,
  SVG Profile/Report/Block actions and media grid. Mute/unmute and manual refresh
  remain available in the details overflow menu. Shared relationship state and
  session guards are borrowed rather than duplicated. Blocking disables local
  sending/retry and releases eligible conversation subscriptions before refresh.
- **Shared media:** uses the open conversation's existing message Cubit and
  repository. Only non-deleted image/video messages with valid media URLs appear;
  video previews use actual thumbnail/poster fields or a Play control, never the
  video URL as an image. The screen says when history is partial and offers
  **Load older media** through existing message pagination. No dedicated media
  endpoint, N+1 lookup, new REST store or unbounded history fetch was added.
- **Viewer:** backward-compatible extension of ChatImageViewer with a centered
  Media title, swipeable pages, image zoom/pan, synchronized thumbnail selection,
  download and shared video playback. Only the selected video mounts; aspect
  ratio/height limits prevent portrait video overflow. Existing lifecycle/player
  cleanup is retained. Image saving uses the existing verified saver. Video saves
  stream bounded downloads (100 MiB) into app-temporary files and reuse the native
  add-only gallery bridge; MIME validation, native save failure and cancellation
  prevent false success. Temporary files are cleaned after success/failure.
- **Long text:** measured at the actual width, direction and text scale; six-line
  collapsed preview, Read More... / Read Less within the bubble, unchanged original
  Unicode/line breaks, selection when expanded and Copy text in the message menu.
  Expansion is keyed by message within the route's PageStorage. Short-message
  taps still control existing receipt details.
- **Offline:** a foreground-only, cancellable five-second native network-route
  check shows the red banner only on an explicit offline result. iOS uses
  NWPathMonitor; Android uses ConnectivityManager with the normal
  ACCESS_NETWORK_STATE permission. No new permission prompt or connectivity plugin.
  Unknown/unsupported status is not offline, and connectivity is not proof of API
  reachability. Reconnection refreshes REST without resending drafts. HTTP/server
  failures keep existing retry UI and cached data.
- **Failed text:** memory-only local outbox rows live in the existing Composer
  Cubit. Failed rows remain visible with the red retry action; retry targets the
  captured original text/reply while preserving any newer draft. Sending locks
  prevent double submissions; confirmed server IDs reconcile into the existing
  history. No Sent/Delivered/Seen is assigned to failed or pending rows. Account
  changes discard local private outbox state and reject late responses. Media
  failures retain their existing selected bytes, ready-media IDs, recovery and
  ordered partial-send behavior separately from text-send errors.

### API and verification limits

The backend still has no client-message idempotency key. An ambiguous timeout can
mean a successful send whose response was lost. Such retries first reconcile
history and require explicit confirmation explaining possible duplication; the
client neither guesses message identity from matching body text nor automatically
resends. Exactly-once retry across that case requires backend idempotency support.
Server-ID deduplication for known responses, Reverb and reconnect remains intact.

Shared media is complete only when all message pages have been loaded. The viewer
contains the currently loaded gallery snapshot; load more history to include older
items. Actual playback/format support and Photos/gallery writes depend on the OS.
Video native saving accepts documented video MIME types but an unsupported OS
codec produces a failure rather than a false success. Android native code was not
device-tested in this iOS-focused run. No live send/upload/delete/report/block or
gallery write was authorized or performed; gallery success/failure tests use
mocked download/native adapters. Actual Reverb delivery is not re-certified here.

### Files changed in this increment

- `pubspec.yaml`, `pubspec.lock` — Skeletonizer only; Firebase pins unchanged.
- `lib/features/chats/cubit/chat_cubit.dart` — local outbox and confirmed hiding.
- `lib/features/chats/data/chat_models.dart`, `chat_broadcast_event.dart` — preserve
  verified thumbnail/poster URLs through receipt/reconnect reconciliation.
- `lib/features/chats/data/chat_device_media.dart`, `chat_image_saver.dart` — bounded
  video saving through the existing native bridge.
- `lib/features/chats/screens/chats_screen.dart`, `conversation_screen.dart`,
  `chat_image_viewer.dart`, `new_conversation_screen.dart`.
- `lib/features/chats/screens/conversation_details_screen.dart` (new).
- `lib/features/chats/widgets/chat_loading.dart`, `chat_options.dart`,
  `chat_expandable_text.dart`, `chat_network_banner.dart`,
  `chat_empty_illustration.dart` (new).
- `lib/features/chats/widgets/chat_widgets.dart`, `chat_request_controls.dart`,
  `chat_composer.dart`, `chat_video_message.dart`, `chat_selected_media_tray.dart`.
- `ios/Runner/AppDelegate.swift` — existing application channel only; network
  status and add-only video saving. No signing/capability/Firebase changes.
- `ios/Runner/Info.plist` — add-only Photos purpose text now mentions videos too;
  Bundle ID, existing permission keys and Firebase configuration are unchanged.
- `android/app/src/main/kotlin/com/travibe/app/MainActivity.kt`,
  `android/app/src/main/AndroidManifest.xml` — same channel and network permission.
- `test/features/chats/chat_edge_states_test.dart` (new),
  `message_requests_test.dart` (expects the requested Cupertino loading control).
- `integration_test/chats_simulator_test.dart` (new empty-state wording),
  `integration_test/chat_media_native_test.dart` (read-only network-status probe).
- This document.

### Verification results

- `flutter pub add skeletonizer:^3.0.0` completed dependency resolution: one
  dependency added. Firebase Core 4.15.2 / Messaging 16.7.1 and native Firebase
  12.19.3 / Google Sign-In 9.2.0 remain unchanged. No dependency override.
- Dart formatting completed. Targeted analysis of Chat source/tests and the two
  relevant integration entry points: **no issues**. Full analysis has **zero
  errors/warnings** and only the two existing Home informational lints (named
  widget key and unnecessary underscores); those widgets were not modified.
- Focused Chat/Profile/Notifications/Firebase lifecycle group: **638 passed**.
  Chat-only regression: **258 passed** before the final additional send/delete
  guard. Final edge-state file: **30 passed**, including the guard and a
  visible-artwork pixel assertion. All are included in the subsequent full run.
- Final full Flutter suite: **1,845 passed, zero failures, one existing intentional
  opt-in live-chat skip**, 1m52s. Includes Search, Stories, Profile, Notifications,
  session/auth, Reverb reconciliation, uploads and message-request regressions.
- iPhone 17 Debug build succeeded (Xcode **69.8s**). Simulator integration:
  **3 passed**: native microphone status without requesting permission, native
  optional network-route status without permission prompts, and guarded app
  startup. Native test build took 63.2s; startup test build took 42.7s.
- The startup probe reported **session=false; OnboardingScreen**. Therefore its
  authenticated navigation branch did not execute; no live Chat API, message
  history, read mutation or new conversation was exercised. No gate was bypassed.
- Native image/video gallery writes stayed disabled. Dart download/save tests
  use controlled HTTP/native adapters. No real push or WebSocket delivery claim.
- Final normal-app Debug build with the complete source: **succeeded**, Xcode
  **54.0s**, output `build/ios/iphonesimulator/Runner.app`. Installed without
  erasing data and launched on iPhone 17 (iOS 26.5,
  E648DA3C-7301-4B73-B7EF-1CF0463BE844). `simctl launch` returned process 72464.
  The initial screenshot showed the existing rotating splash, and a subsequent
  capture visibly confirmed Onboarding. No authentication/profile/onboarding
  gate was bypassed. Authenticated enhanced Chat screens were not manually
  exercised; their seven images are mocked widget renders.

All seven mocked captures were visually inspected with real Travibe fonts/icons.
The empty illustration was additionally inspected after bitmap decode. Captures:
`docs/chat-verification/edge-{empty,options,delete,details,viewer,long,offline}-mocked.png`.
These are fixture renders, not the missing reference screenshots or live
authenticated media. Unavailable-image and empty-media fallback states are visible
where fixtures intentionally have no downloadable production asset.

Logs: `/private/tmp/travibe-chat-edge-{regressions,final-chat-tests,guards-test,
full-suite,targeted-analysis,full-analysis,render-tests,ios-build,ios-launch-build,
simulator-tests}.log`; final startup capture:
`/private/tmp/travibe-chat-edge-final-launch.png`. Original SVGs and all existing uncommitted work were
preserved. No commit was made; Git metadata is absent.

## Home Chat badge and image sending — 2026-11-09

### References

The three newly mentioned screenshots were not found in the project image
inventory. The earlier conversation/composer and image-message references
(`12.45.00` and `12.45.43` under `docs/chat-references/`) were inspected again.
The written requirements govern these targeted changes. Pixel-level comparison
with the new three screenshots was not possible. The previously confirmed Figma
Starter-plan access limit remains a design-verification limitation.

### Home unread dot

`travibe-api.json` has **no Chat unread-total endpoint**. Its only unread-count
endpoint belongs to Notifications, whose read-all state is independent of Chat
message unread state. Home therefore shows a **small orange dot**, not a fabricated
numeric total, based on authoritative `ConversationResource.unread_count > 0`.

The app-scoped `ChatUnreadCubit` reuses `ChatRepository` / LaravelChatRepository
and the existing Dio/session infrastructure. It stores only unread presence,
loading/confirmation/error flags and session revision; it does not add another
conversation/message cache, replace route Cubits or modify message state.

- Eligibility follows existing verified-current-user and authenticated Root
  ownership. Initialization does not block splash, onboarding or authentication.
- Scans interleave Inbox and received-request pages through existing pagination.
  Any positive server unread count proves the dot should show. Clearing requires
  complete successful exhaustion of both lists. No outgoing-message increment,
  unread-notification proxy, first-page total or local optimistic count is used.
- Missing `unread_count` is explicitly unknown (`hasUnreadCount` metadata), not
  zero. Malformed data, errors, cycles and a safety budget of 100 pages retain the
  last confirmed indication instead of falsely confirming zero. A dedicated
  backend aggregate would be needed for an efficient exact numeric total and
  very large accounts beyond that scan budget; no endpoint was invented.
- Opening/tapping Home never calls a Chat read endpoint. Root reattachment keeps
  confirmed state while refreshing. Returning from Chats and confirmed conversation
  reads, decline or deletion request authoritative unread reconciliation.
- Existing Reverb message/read/notification events and reconnect hints coalesce
  over 120ms into REST refreshes. Existing generic FCM activity hints also refresh
  through REST; no private message content or arbitrary push routes are consumed.
- Resume refreshes immediately. A single foreground-only 45-second fallback also
  handles unavailable realtime transport and muted-thread notification suppression.
  It polls conversation metadata only, not message history, and never overlaps an
  in-flight scan. It stops while backgrounded or Root is detached.
- Epoch/session checks discard stale responses; in-flight invalidations trigger
  a subsequent canonical scan. Logout/account changes clear private indication
  and require fresh confirmed identity. Disposal cancels subscriptions, timers
  and owned count requests without cancelling open-conversation repositories.

The Home notification badge retains its existing independent behavior.

### Shared Send control

`ChatSendButton` extracts the existing text control: 48px circular orange surface,
the original `assets/images/interactions/send.svg` at 20px, matching Material
pressed/disabled behavior and an 18px white Cupertino loading indicator. Text and
attachments now use this single implementation.

In a conversation, selected attachments keep their removable preview tray above
the composer. Its separate action is hidden, and the composer's one Send button
submits the existing ordered batch, including its existing caption/reply handling.
Removal is locked during sending. The tray's public API remains compatible for
standalone use, where its optional action also uses ChatSendButton. No separate
Material paper-plane icon remains. The empty composer returns to its existing
microphone behavior. Batch/composer locks continue to prevent repeated submissions.

### Image surfaces and upload feedback

- Confirmed incoming/outgoing images use transparent surfaces and zero bubble
  padding, with 16px clipped corners. Existing image constraints, BoxFit.contain,
  alignment, captions, tap-to-view and error presentation remain.
- Text retains its existing orange/charcoal surfaces. Voice/video pending
  presentation and the microphone workflow are preserved.
- Pending images keep the actual selected image visible under a clipped dark
  translucent overlay and centered **white CupertinoActivityIndicator**. There is
  no horizontal bar or separate Sending text below the image. The selected tray
  does not duplicate that image overlay; the shared Send button keeps its normal
  compact loading feedback.
- Overlay fades use 180ms; reduced motion uses zero transition duration and a
  static Cupertino indicator. Reliable byte progress remains in accessibility
  semantics as upload progress, never as a Sent/Delivered/Seen claim.
- Existing presign/upload/finalize/send callbacks and recovery logic are reused
  without changes. Only confirmed send responses replace pending media with server
  messages/IDs. Failure removes the loading state and retains a retry action and
  selected bytes/ready ID. Ambiguous responses retain the existing reconciliation
  and explicit-retry safeguards; no automatic resends or fake completion.
- Account switches invalidate/cancel owned operations and remove old previews.
  Image paths/temp-file handling and media upload APIs were not rewritten.

### Files changed

- `lib/features/chats/cubit/chat_unread_cubit.dart` (new).
- `lib/features/chats/data/chat_models.dart` (confirmed unread-field metadata).
- `lib/features/chats/widgets/chat_reverb_host.dart` (unread lifecycle/hints/scope).
- `lib/root.dart` (Root ownership and Home-return reconciliation).
- `lib/features/home/widgets/home_top_bar.dart` (dot).
- `lib/features/home/screens/home_screen.dart` (refresh on returning from Chats).
- `lib/features/chats/widgets/chat_send_button.dart` (new).
- `lib/features/chats/widgets/chat_image_upload_overlay.dart` (new).
- `lib/features/chats/widgets/chat_composer.dart`, `chat_selected_media_tray.dart`,
  `chat_pending_media_bubble.dart`, `chat_widgets.dart`.
- `lib/features/chats/screens/conversation_screen.dart` (shared batch action and
  post-confirmation unread synchronization).
- `test/features/chats/chat_badge_images_test.dart` (new).
- This document.

No dependencies, native source/configuration, SwiftPM, Firebase versions, Bundle
ID, authentication or unrelated feature behavior were changed. Existing work was
preserved; Git metadata is absent and no commit was made.

### Verification

- New focused file: **27 passed**, including pending/later pages, unknown counts,
  failures/budget/cycles, stale scans, account changes, confirmed/failed reads,
  Home badge persistence and independent notification badge, Reverb reconciliation,
  duplicate hints, resume/fallback, one shared Send action, attachment removal,
  image overlay/rollback, duplicate upload taps and account-switch cancellation.
- Portrait-image constraints/aspect ratios and Send layouts passed at
  **320/375/393/430px**. Reduced-motion loading and existing fullscreen navigation
  are covered. Existing media retry tests retain their uncertain-response and
  ready-media reuse assertions.
- Chat/Home/Notifications/Firebase lifecycle/Profile regressions: **853 passed**.
- Targeted analysis: **no issues**. Full analysis has the same two pre-existing
  Home informational lints (named widget key and unnecessary underscores), with
  no errors/warnings in this increment.

- Final full Flutter suite: **1,872 passed, zero failures, one existing intentional
  opt-in skip**, 2m06s. No existing tests were removed, skipped or weakened.
- iOS Simulator Debug build: **succeeded**, Xcode **87.2s**,
  output `build/ios/iphonesimulator/Runner.app`. No native integration changes
  were needed. Final formatting: **14 changed Dart files, zero further changes**.
- Installed without erasing data and launched `com.travibe.app` on the booted
  iPhone 17 (iOS 26.5, E648DA3C-7301-4B73-B7EF-1CF0463BE844). `simctl launch`
  returned process 88724. A subsequent screenshot visibly confirmed the restored
  **Home** screen with the existing feed and Stories. No authentication gate was
  bypassed. The absence of a dot in that single capture is not evidence of a
  verified zero count or incoming-message synchronization; the live arrival/read
  flow was not exercised. Startup image remains local at
  `/private/tmp/travibe-chat-badge-launch.png` rather than copying account content
  into the repository.

Logs: `/private/tmp/travibe-chat-badge-{new-tests,regressions,full-suite,analysis,
full-analysis,ios-build,final-format}.log`.

No live send or upload is authorized, and no approved disposable test accounts
were supplied. Actual cross-account incoming delivery,
uploading production media and live realtime/badge latency remain unverified.
Mocked event/HTTP/byte callbacks prove application behavior, not live delivery.
The existing lack of backend idempotency still limits exactly-once retry after
an ambiguous timeout; duplicate known server IDs remain deduplicated.


## Conversation cache and loading investigation — 2026-11-10

### Diagnosed cause and evidence

Repeated conversation navigation constructed a new route-owned ChatListCubit
and LaravelChatRepository every time. Repository messages() made a fresh REST
request without a shared history cache. Closing the route cancelled its requests
and discarded its messages/cursor. The next open therefore rendered the initial
Skeletonizer again. Conversation metadata was awaited before messages were even
requested, adding variable latency. Inbox already retains its route-owned list
while the conversation is above it; the missing cache was conversation history.

The single loading flag also rendered a Cupertino pagination row during ordinary
background refresh. Reverb reconcile/new-message refreshes did not inherently
clear existing messages, but could expose this redundant loading UI. Message
Image.network used Flutter's default URL-keyed decoded cache (no separate
authenticated Chat image-cache service was found). Its loading placeholder was
220px high while its decoded intrinsic height could differ, causing a layout
change independent of REST/Skeletonizer loading. No local screen recording was
found in docs; these causes were established from code and mocked route/request
reproductions, not a claim that every frame of the user's recording was traced.

### Changes

- A session-scoped, memory-only ChatHistoryCache restores messages immediately,
  including successful empty results, cursors and confirmed removal markers.
  Cubits remain route-owned and continue cancelling obsolete requests. Cache
  keys separate injected repositories; production routes share the conversation
  key. No private history is persisted to disk.
- History requests begin concurrently with canonical metadata requests. Sending
  eligibility, pending-request restrictions, read mutations and Reverb channel
  eligibility still use the existing authoritative checks.
- Initial loading is distinct from background refresh and loadingMore. Only
  an uncached empty history gets the initial skeleton; only pagination gets the
  older-page Cupertino row. Cached history survives offline/failed refreshes.
- Reverse-list scroll offsets are remembered within the session. Reopening also
  restores the last successful updated_since watermark, allowing paginated REST
  reconciliation to recover edits/deletions on older cached pages. Existing
  server-ID deduplication, monotonic receipts/tombstones and event-over-REST race
  protections remain active. Late disposed-route/session responses are ignored.
- Failed text outbox rows, reply targets and ambiguity flags survive reopening.
  Interrupted in-flight sends become unconfirmed failed rows; they are never
  automatically resent. The existing confirmation safeguard remains necessary
  because the backend does not guarantee idempotency after ambiguous timeouts.
  Media selection/upload leave guards and explicit cancellation remain intact.
- ChatHistoryImage reuses Flutter's NetworkImage/ImageCache and remembers decoded
  geometry for the same URL/session. Reopening a cached image does not insert a
  loading frame or repeat the network request. A real uncached image displays an
  inline Cupertino loader; already-sent images never acquire an upload overlay.
  Newly decoded images preserve their aspect ratio within 220px width / 360px
  height bounds. Without supplied dimensions, the first-ever image still starts
  with a square placeholder until decoding reveals its actual geometry.
- Signed URLs are not fabricated, rewritten, or retained in place of a new
  canonical URL. A server URL change, cache eviction, or expired URL may require
  another fetch. There is no extra presign/detail lookup in the image widget.
- Logout/account revision changes clear snapshots, outbox and geometry/scroll
  metadata synchronously. No token, bearer credential or image bytes are stored
  in this cache. Existing decoded-image cache behavior remains unchanged.

Temporary diagnostics are opt-in and debug-only:
`flutter run --dart-define=CHAT_LOADING_DIAGNOSTICS=true`.
Fixed stages identify initial_load, cache_hit, background_refresh, pagination,
reverb_reconciliation, image_resolve, image_cache_hit, image_frame_ready and
image_error. Only stage/count values are printed, never conversation content,
identifiers, media URLs, raw errors or authentication credentials. Release builds
cannot emit these diagnostics.

### Files changed

- lib/features/chats/cubit/chat_cubit.dart
- lib/features/chats/data/chat_history_cache.dart (new)
- lib/features/chats/screens/conversation_screen.dart
- lib/features/chats/widgets/chat_history_image.dart (new)
- lib/features/chats/widgets/chat_widgets.dart
- test/features/chats/chat_loading_lifecycle_test.dart (new)
- docs/CHAT_FEATURE_IMPLEMENTATION.md

### Verification

- dart format: all six changed Dart files formatted.
- Focused Chat suite: **298 passed**, including **12 new lifecycle tests**.
  Coverage includes uncached skeleton, immediate reopen, refresh success/failure,
  offline cached history, realtime message merge during refresh, pagination,
  successful empty cache, logout/account isolation, failed outbox restoration,
  rapid mocked route transitions, late disposed-route responses and older-page
  deletion reconciliation via updated_since. A generated valid portrait PNG and
  mocked HTTP client verify one actual image fetch across widget recreation,
  decoded aspect ratio, retained dimensions and no cached-image spinner.
- Full Flutter suite: **1,884 passed, 0 failed, 1 existing intentional opt-in
  skip**, completed in 1m35s. No tests removed, skipped or weakened.
- Targeted analysis of Chat and the new test: **no issues**.
- Full analysis: **0 errors, 0 warnings, 2 existing informational lints** in
  home/widgets/custom_bottom_nav.dart:10 (use_key_in_widget_constructors) and
  home/widgets/trending_destinations_section.dart:54 (unnecessary_underscores).
- iOS Simulator Debug build: **succeeded**, Xcode build 79.7s, using
  `flutter build ios --simulator --debug --no-pub`.
- Installed and launched com.travibe.app on the existing booted iPhone 17,
  iOS 26.5, without resetting data. Launch PID 6974. A captured screenshot
  confirmed authenticated Home. Repeated live Inbox/conversation navigation and
  actual Reverb/network timing were **not manually verified** in this run.
  No live sends, uploads or destructive operations were performed.
- Logs: /private/tmp/travibe-chat-loading-focused.log,
  travibe-chat-loading-full-suite.log, travibe-chat-loading-targeted-analysis.log,
  travibe-chat-loading-full-analysis.log and travibe-chat-loading-ios-build.log.
  Launch capture: /private/tmp/travibe-chat-loading-launch.png. Temporary files
  may not survive a workspace restart.

Firebase versions, SwiftPM, Bundle ID, authentication and unrelated UI/config
were not changed. The workspace still has no .git metadata, so no Git history or
revert/reset was used and no commit was created. Live observation with diagnostics
remains useful to separate any residual server latency, cache eviction or signed
URL changes from the now-covered route lifecycle behavior.


## Final Inbox loading, image placeholders and numeric unread badge — 2026-11-10

### Root causes and changes

**Sent-image indicator.** ChatMessage.fromJson already maps a published image to
Sent/Delivered/Seen; image download did not set an upload state. Stable URL keys
already reuse Flutter's ImageCache. The confusing Cupertino indicator was the
separate cold-image download/decode indicator inside ChatHistoryImage. It is now
a quiet charcoal image-only placeholder, with accessibility label Loading image.
The Sending attachment overlay is additionally guarded by outgoing status and
ChatDelivery.sending. Existing active local upload/send controls retain their
Cupertino overlay; published media cannot acquire it from a cache miss.

PublicMediaResource in travibe-api.json explicitly supplies nullable width and
height. Positive dimensions are parsed into ChatMessage and retained through
REST merges and realtime read receipts. The image viewport uses these dimensions
or previously decoded geometry before loading begins. With neither available,
a stable square viewport is used for that first load; BoxFit.contain preserves
the actual picture's aspect ratio. Decoded geometry is remembered for later
opens. Loading completion removes the placeholder without resizing that viewport.
Broken/expired/private images show Image unavailable. Retry inside the same
bounds. Retry deliberately evicts/retries that image URL, not the message send.
A later canonical response may provide a renewed URL. No URL is fabricated,
no extra presign request is made, and raw failure details/URLs are not logged.

**Inbox Skeletonizer.** Conversation history had shared cache snapshots but
ChatsScreen still created a new empty Inbox Cubit on route recreation. Also,
loading && items.isEmpty treated a previously confirmed empty Inbox as an initial
load, and any nonempty refresh displayed a pagination spinner. ChatsScreen now
uses the existing ChatListCubit/ChatHistoryCache snapshot mechanism for Inbox and
Requests. A loaded snapshot renders immediately while canonical REST refreshes.
Successful empty snapshots are distinct from first load: neither Skeletonizer
nor the empty illustration replaces an in-progress refresh or a failed/offline
request. Only loadingMore displays the compact pagination Cupertino indicator.
Search results do not write over the unfiltered Inbox snapshot.

Inbox/Requests snapshots use a separate LRU cache group capped at eight entries,
with at most 200 retained conversations per snapshot. Request-count snapshots
have a separate eight-entry group. These bounds do not evict conversation drafts
or pending/failed outbox data. If an exceptionally large snapshot is truncated,
its beyond-cache pagination cursor is deliberately not reused; the next normal
first-page refresh restores the authoritative cursor. Offline warm history is
limited to those retained rows. All snapshots clear with sessionRevision on
logout/account switching. Existing disposal, generation/session guards, removal
markers and event-versus-REST reconciliation remain active.

**Requests label.** The old formatter displayed any non-null count, including
zero. It now shows Requests for zero/unknown and Requests (N) only for positive
counts. meta.total is authoritative when present; row counts are used only when
the response represents the entire list without another page. Confirmed
accept/decline, existing refresh/reconnect hints and account changes still
synchronize the label; unknown totals are never invented from a partial page.

**Numeric Home badge.** The prior presence-only unread scan stopped as soon as
one unread conversation was found. travibe-api.json defines
ConversationResource.unread_count as “Messages this viewer has not read.” It is
an unread **message** count per conversation, not a count of conversations.
The controller now sums these server values across every Inbox and received
Requests page, deduplicating conversation IDs across pages/scopes. No outgoing
message/event is locally incremented. Counts 1–99 render exactly, 100+ renders
99+, and zero hides the badge. Accessibility exposes the confirmed total.
The orange badge is positioned toward the Chat control's upper-right edge and
uses fixed compact typography so large text does not cover the icon.

There is no documented Chat unread-total endpoint. A numeric result is published
only after a complete scan (existing 100-page combined safety bound). Missing or
negative counts, conflicting duplicate snapshots, cyclic/incomplete pagination
or network failures retain the last confirmed total, never a partial sum or a
false zero. This means a very large/continually changing Inbox may retain its
previous badge until a successful reconciliation; a backend aggregate unread
message total would avoid scanning, but no unconfirmed endpoint is called.
Existing coalesced Reverb/FCM activity hints, confirmed read actions, resume and
45-second foreground fallback refresh the total. Merely opening Home/Chats does
not clear it. Old-session responses cannot publish into the new account.

### Files changed

- lib/features/chats/data/chat_history_cache.dart
- lib/features/chats/cubit/chat_cubit.dart
- lib/features/chats/screens/chats_screen.dart
- lib/features/chats/cubit/chat_unread_cubit.dart
- lib/features/home/widgets/home_top_bar.dart
- lib/features/chats/widgets/chat_widgets.dart
- lib/features/chats/widgets/chat_history_image.dart
- lib/features/chats/data/chat_models.dart
- lib/features/chats/data/chat_broadcast_event.dart
- test/features/chats/chat_final_loading_badge_test.dart (new)
- test/features/chats/chat_loading_lifecycle_test.dart
- test/features/chats/chat_badge_images_test.dart
- test/features/chats/message_requests_test.dart
- test/features/chats/chat_edge_states_test.dart
- docs/CHAT_FEATURE_IMPLEMENTATION.md

Existing tests expecting Requests (0) now assert Requests. The cold-image cache
test asserts the download placeholder and absence of sending UI. The image-viewer
test now uses actual decoded fixture bytes, so its intended preview tap is tested
on an image rather than on the newly actionable broken-image Retry button.
Reverb tests assert numeric 7 -> 0 reconciliation, duplicate-hint coalescing and
old-session rejection. No tests were skipped, deleted or weakened.

### Verification and limits

- dart format: **14 changed Dart files, zero remaining formatting changes**.
- Focused Chat/Home run: **502 passed**.
- **17 new tests** cover 0/1/9/99/100+/245 badges at 320px with enlarged text,
  complete/deduplicated numeric totals, partial/conflicting snapshots, confirmed
  read-style REST reconciliation, account switching, Requests totals 0/1/7,
  Inbox route recreation, silent/offline refresh, cached empty/error distinction,
  search isolation, LRU/row bounds, cold image success/failure, stable dimensions,
  model parsing and dimension retention through Seen updates. Existing tests
  retain active upload overlay, pagination, rapid navigation, read failure,
  Reverb reconnect/resume and session-race coverage.
- Final full suite after the receipt-metadata correction: **1,901 passed,
  0 failed, 1 existing intentional opt-in skip**, 2m11s.
- Final targeted analysis (Chat, Chat tests, HomeTopBar): **no issues**.
- Full analysis: **0 errors, 0 warnings; 2 existing informational Home lints**:
  custom_bottom_nav.dart:10 use_key_in_widget_constructors and
  trending_destinations_section.dart:54 unnecessary_underscores.
- Final iOS Simulator Debug build: **succeeded**, Xcode 63.6s,
  `flutter build ios --simulator --debug --no-pub`.
- The existing iPhone 17 on iOS 26.5 is booted. This change was build-verified,
  not launched into the restored authenticated session or manually exercised
  against live conversation data. No approved disposable account/write consent
  was supplied. Navigation can mark messages read, and normal authenticated
  lifecycle may register device tokens/presence. No live message, upload, read,
  accept/decline/delete or other server mutation was performed for these checks.
  Actual incoming-message badge latency remains unverified; event/REST tests use
  fake streams and HTTP/repository fixtures.
- Figma canvas metadata was briefly accessible, but the next metadata call hit
  the Starter-plan MCP limit before relevant frame context/screenshots could be
  obtained. Existing controls, typography and theme were reused; no new
  pixel-level Figma comparison is claimed.

Final logs (temporary): /private/tmp/travibe-chat-final-ux-focused-pass.log,
travibe-chat-final-ux-full-suite-final.log,
travibe-chat-final-ux-targeted-final.log,
travibe-chat-final-ux-full-analysis.log and
travibe-chat-final-ux-ios-build-final.log. Earlier exploratory runs exposed two
compiler errors, legacy zero-label/cold-spinner expectations and test fixture
issues; those were corrected before the successful final runs above.

Firebase versions, SwiftPM, Bundle ID, authentication, media upload architecture,
Reverb transport, Notifications and unrelated features/configuration are unchanged.
No dependencies, backend routes or production mock data were added. The workspace
still lacks Git metadata; no reset/revert/discard/commit was performed.


## Bottom offline banner, safe bubble retry and emoji picker — 2026-11-10

### Reference availability and root causes

No distinct new set of four supplied screenshots was found in the local project.
The existing ten docs/chat-references images and earlier mocked verification
captures remain. docs/chat-verification/edge-offline-mocked.png was visually
inspected and shows the former top-positioned banner. The new placement follows
the user's written requirements; no pixel-level comparison to missing references
or new Figma frame inspection is claimed.

ChatNetworkBanner was mounted directly after the conversation header. Its
connectivity polling correctly used native interface status rather than HTTP
errors, but an unknown/null check replaced known offline state and hid it.
The failed-send label alone invoked retry; bubble taps opened details. Unknown
transport outcomes were conservatively treated as ambiguous, with a generic
confirmation and a persistent warning in the composer. The emoji button merely
requested keyboard focus; no emoji picker dependency or picker view existed.

### Offline feedback

The banner is now the top accessory inside the bottom composer viewport, above
attachment selections, reply/input controls and the emoji panel. Pending received
requests show it above Accept/Decline controls. It participates in layout instead
of overlaying messages/input and remains within the existing SafeArea/keyboard
layout. Rounded dark red styling, white text, a compact warning icon and a
180ms size transition are used. Reduced motion bypasses the animation wrapper
entirely (a zero-duration AnimatedSize caused a Flutter layout assertion in a new
test). The message ScrollController is retained; tested older-history offsets
remain unchanged across offline/online transitions.

Native networkStatus is still the source: a failed Laravel request never proves
the device is offline. Unknown/unsupported/time-out status cannot create an
offline state or dismiss a previously confirmed one. Only a confirmed connected
result dismisses it and triggers the existing coalesced history refresh. Existing
5-second foreground polling, 3-second status timeout, lifecycle cancellation and
disposal remain. Reconnection never automatically resends a failed message.

### Retry safety and feedback

- Failed text bubbles and their compact red Failed to send. Tap to retry. label
  both invoke the existing retry path. A small Cupertino indicator appears inside
  an outgoing text bubble while sending/retrying; it is static under reduced
  motion. Existing send locking and the original local message ID/text/reply/draft
  are retained. Confirmed success removes the local failure and reconciles the
  authoritative server ID; another failure restores the same local row.
- HTTP client rejections retain direct retry. Connection-establishment timeout
  and TLS certificate rejection are typed ChatPreSendFailure because they happen
  before request transmission. Receive/send/overall timeouts, connection drops,
  malformed acknowledgements and server errors remain conservatively ambiguous.
  An earlier ambiguity is not erased by a later rejected retry.
- Ambiguous text retry first refreshes supported REST history. A malformed 201
  response may still supply a validated positive message ID for the same
  conversation. That ID is retained as session-only correlation metadata and can
  resolve the local row against canonical history without another send. A known
  accepted record now represented by a deletion placeholder is also reconciled,
  rather than offering to resend its removed contents.
- Text/body/time similarity is never used as proof. An unacknowledged timeout
  generally has no reliable correlation ID. If refreshed history cannot resolve
  it, Delivery unknown explains the duplicate risk and requires explicit consent.
  Cancel preserves the failed draft; rapid repeated taps cannot stack this flow.
- Attachment retries likewise refresh first and resolve by the already-owned
  media ID when present in history. Otherwise only an ambiguous send requires
  explicit consent. Definite rejections reset that attempt's uncertain flag;
  uploaded media IDs and local bytes remain available for deliberate retry.
  Upload is not repeated when readyId is already available. Failed attachment
  previews now respond to body/label taps, not just a separate composer action.
- The long text-send warning is not persistently rendered while its failed row
  already provides feedback. Media uncertainty uses compact contextual text.
  Audio permission errors, attachment errors, disabled-state messages and other
  errors remain visible. A regression specifically prevents a microphone error
  from resurrecting the hidden ambiguous-send warning.

No client idempotency key is documented by the backend. Exactly-once resend after
an unacknowledged timeout cannot be guaranteed. History/acknowledgement/media-ID
reconciliation reduces known duplicates; unresolved ambiguity always remains a
user decision. Old-account responses, outbox snapshots and acknowledgement IDs
remain subject to the existing captured sessionRevision protections.

### Emoji picker

Added pinned emoji_picker_flutter 4.5.4. Its official package requires Dart
3.11.5+/Flutter 3.41.8+, compatible with this project's SDK, and supports iOS
SwiftPM. flutter pub get reported Changed 1 dependency: only the new picker was
added. Existing Firebase/Google Sign-In pins and transitive versions were retained.
Sources: https://pub.dev/packages/emoji_picker_flutter/versions/4.5.4 and
https://pub.dev/packages/emoji_picker_flutter/changelog.

The existing composer now owns only its picker/focus presentation state; the
Cubit, draft controller and send/media architecture remain. The dark category
picker uses system emoji glyphs and an English fallback dataset, with orange
selection styling. Recent-emoji persistence is disabled, so account switches do
not expose a previous account's recently used emoji list. No new preferences or
network service is introduced.

Selecting an emoji replaces the current selected text or inserts at the cursor,
keeping both surrounding substrings. Insertion uses UTF-16 selection offsets and
whole Unicode graphemes, including family/skin-tone/ZWJ sequences, and clears stale
IME composing ranges. The controller and existing Cubit draft are updated together.
Multiple and multiline/Arabic insertions are supported.

The icon toggles between picker and native keyboard. Native keyboard dismissal
is observed through View metrics so the picker is revealed after keyboard insets
clear, without occupying both areas simultaneously. Tapping the input returns to
the keyboard. Attachment selection closes the picker before measuring the
existing anchored menu. Picker height adapts to small/landscape layouts and
attachment/reply controls. Covering/leaving the route, disposal or an account
change hides it; delayed old callbacks cannot insert into a new account's draft.
The existing caller-owned FocusNode/controller are not disposed by the composer.

### Files changed

Application/configuration:
- lib/features/chats/widgets/chat_network_banner.dart
- lib/features/chats/widgets/chat_composer.dart
- lib/features/chats/widgets/chat_emoji_picker.dart (new)
- lib/features/chats/widgets/chat_widgets.dart
- lib/features/chats/widgets/chat_pending_media_bubble.dart
- lib/features/chats/screens/conversation_screen.dart
- lib/features/chats/cubit/chat_cubit.dart
- lib/features/chats/data/chat_repository.dart
- pubspec.yaml
- pubspec.lock

Tests/documentation:
- test/features/chats/chat_offline_retry_emoji_test.dart (new)
- test/features/chats/chat_badge_images_test.dart
- test/features/chats/chat_media_queue_send_test.dart
- docs/CHAT_FEATURE_IMPLEMENTATION.md

Flutter-managed plugin registration additionally includes the new dependency in
GeneratedPluginRegistrant.m (iOS), GeneratedPluginRegistrant.swift (macOS), and
both generated_plugin_registrant.cc/generated_plugins.cmake on Linux/Windows.
Flutter also regenerates its ephemeral SwiftPM plugin package and dependency
metadata. These are automatic registration effects of the new package, not a
manual package-manager migration. No Firebase native source, signing/entitlement,
Bundle ID, Laravel contract, .vscode setting or unrelated UI was edited.

### Verification

- flutter pub get: succeeded; one added dependency, no package upgrades/downgrades.
- dart format: **11 changed Dart files, zero remaining formatting changes**.
- Final focused Chat/Home/core-notification regressions: **556 passed**.
- **15 new tests** cover cursor/selection/complex Unicode, native keyboard/picker
  switching, actual grid taps, route and account isolation, disposal, definite
  retries, retry failure/success/deduplication, known acknowledgement reconciliation,
  conservative timeouts, bottom banner/keyboard/tray layout, reduced motion,
  unknown/online status transitions, retained scroll position, large-text
  landscape sizing and preservation of separate audio-error feedback. Existing
  attachment tests now exercise Cancel/Confirm only when delivery is ambiguous
  and verify no additional upload/send occurs before consent.
- Final full suite: **1,916 passed, 0 failed, 1 existing intentional opt-in skip**,
  2m12s. No test was deleted, skipped or weakened.
- Targeted Chat/test analysis: no issues. Full analysis: **0 errors, 0 warnings,
  2 existing Home informational lints**, custom_bottom_nav.dart:10
  (use_key_in_widget_constructors) and trending_destinations_section.dart:54
  (unnecessary_underscores).
- Final iOS Simulator Debug build: **succeeded**, Xcode 67.7s, including the emoji
  picker's official SwiftPM plugin. Build output remains
  build/ios/iphonesimulator/Runner.app for com.travibe.app.
- All new messaging/network tests use fake repositories/HTTP/native-channel
  adapters. No live messages, uploads or other server mutations were performed.
  No approved write-enabled test accounts were supplied. This run proves mocked
  behavior and native compilation, not real backend retry delivery or manual
  iOS/Android keyboard/picker interaction. Android native build was not run.
  The four new reference screenshots remain unavailable for visual comparison.

Logs (temporary): /private/tmp/travibe-chat-emoji-pub-get.log,
travibe-chat-offline-emoji-focused-final.log,
travibe-chat-offline-emoji-full-final.log,
travibe-chat-offline-emoji-analysis-final.log,
travibe-chat-offline-emoji-targeted-final.log and
travibe-chat-offline-emoji-ios-final.log. Earlier exploratory test failures exposed
outdated retry-label expectations, missing fixture frame pumps and the reduced-
motion assertion; those were corrected before the final successful verification.

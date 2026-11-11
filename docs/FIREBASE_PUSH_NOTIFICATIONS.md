# Firebase push notifications

## Production device-token integration

The confirmed Laravel/Kreait contract is now wired into the existing Flutter
lifecycle. PushNotificationsHost creates LaravelPushTokenRepository for the
production PushNotificationService. The unavailable repository remains an
explicit adapter for isolated/test configurations, not the production default
host. No Kreait client library belongs in Flutter and none was added.

POST `https://travibeapp.com/api/v1/device-tokens` sends only:

```json
{"token":"<FCM registration token>","platform":"ios"}
```

Platforms are normalized to `ios` or `android`; others are rejected before HTTP.
The response's `data.id` must be a positive integer record identifier, with a
matching `data.platform`. `created_at` may be null; no raw token response is
required. The server owns idempotency, account association/reassignment and the
10-most-recent-tokens-per-account policy. Flutter does not prune other devices.

DELETE `device-tokens/{id}` always uses that returned backend record ID. It never
uses the FCM token in a URL. An empty HTTP 204 completes removal without JSON
parsing. Account-scoped 404 means the record is already absent for that principal
and clears only its local cleanup entry. 401/403 and network failures retain
cleanup metadata and never clear Laravel credentials or borrow another account's
credentials. Errors use fixed strings, not validation bodies that may echo a
token. No payload, bearer or FCM-token logging was introduced.

The adapter reuses DioClient. A narrowly scoped device-token request flag keeps
an explicitly captured Authorization header through the existing interceptor,
limited to device-tokens and numeric device record paths. Ordinary app requests
continue using the existing sessionRevision/current-token behavior. Redirects are
disabled; connect/send/receive stages each have a 10-second timeout. The adapter
bypasses generic response observers/error-body mapping for these sensitive calls.

## Lifecycle, verified identity and race protection

- Preferences initialize before runApp; the existing CurrentUserCubit remains the
  identity source. A stored session token alone never triggers registration.
- The host waits for a confirmed profile with a nonempty emailVerifiedAt, then
  passes its stable ID/sessionRevision and existing delivery preference. A
  later verified profile emission activates synchronization. Full-access token
  enforcement remains server-side; limited/expired tokens receive 401/403.
- The host rejects queued Bloc events that no longer match CurrentUserCubit.state,
  preventing a stale profile from acquiring a replacement account's credentials.
- Each operation captures its account, sessionRevision and bearer credential in
  memory for that operation. No additional bearer token persistence exists.
- SDK operations and server mutations have separate serialized queues. Stale
  generations cannot publish the current registration state. Duplicate refresh
  events coalesce token reads and successful/pending registration attempts.
- Stream token values have no session stamp, so refresh events cause a fresh SDK
  token read instead of assigning the event's old value to a replacement user.
- The confirmed PushDeviceRecord is separate from a pending PushRegistration.
  Token refresh registers the replacement first. Previous IDs are removed only
  after confirmation, preserving known valid cleanup state if POST fails.
- Logout/account switches clear pending navigation/retries immediately, retire
  old known FCM tokens, delete/rotate the SDK token and queue captured-account
  cleanup. A POST completing after logout is revoked by its returned record ID
  before the next queued registration. Late results never become active state.
- If old credentials have expired, removal fails safely and retains only the ID.
  The next confirmed session for that same user can retry. Another user's token
  is never used for that cleanup. A moved record returns account-scoped 404.
- SDK/server failures do not block splash, login, onboarding or Home. Retry is
  available on inbox refresh/status checks, app resume and token refresh.
- Normal app shutdown cancels subscriptions/timers/navigation but keeps valid
  registrations for terminated delivery, including a POST completed during
  service disposal. Shutdown after a session change still performs stale cleanup.

## Minimum persisted cleanup state

PushDeviceStore reuses PreferencesManager, with the `push_device_records_v1` key:

```json
{"7":["41","42"]}
```

Only Laravel user IDs and backend record IDs are stored. No FCM token, bearer,
APNs token, notification payload or email is persisted. Writes are serialized.
clearSession preserves this narrowly defined non-secret cleanup key alongside
language/onboarding, while continuing to remove account preferences/currency.
Full clear still clears everything. Metadata is removed after confirmed 204/404.

Successful re-registration after process/session restoration recovers the same
server ID idempotently and cleans older IDs recorded for this installation and
same user. Starting with denied permission also attempts same-user stored-ID
cleanup without requiring FCM retrieval. No metadata for another user is used.

A client cannot guarantee server removal if a session expires before DELETE, or
if a POST commits but its response/ID is lost before persistence. Backend logout/
account-deletion cleanup, invalid-FCM-token pruning and token reassignment remain
necessary. There is no invented device-list or raw-token deletion endpoint.
Network timeout bounds the client request; it cannot prove the remote mutation
was cancelled. Retiring/deleting old SDK tokens and account-scoped server access
remain important safeguards.

## Firebase transport and notifications UI

FirebaseBootstrap still coalesces Core initialization once per isolate, reuses
the default Firebase app and reads native config: the existing iOS plist or the
Android `google-services.json` (applied by the Google Services Gradle plugin). Notification startup
is asynchronous and does not alter the 1500ms splash.

Permission is checked without prompting on startup. The inbox offers an explicit
request; concurrent requests coalesce. AuthorizationStatus.deniedPermanently maps
to PushPermission.denied. Authorized/provisional states permit token retrieval;
unknown/notDetermined/denied do not. Resume rereads OS permission.

iOS waits for APNs before reading FCM. Retries are 1, 2, 4, 8 and 16 seconds,
then stop until resume/manual retry. Session changes cancel the retry timer.
Foreground, token-refresh and background-tap subscriptions are installed once and
cancelled on disposal. The top-level vm:entry-point background handler initializes
Core only; it does not navigate, use BuildContext or invent data-only operations.
The OS handles background notification payload presentation.

getInitialMessage/onMessageOpenedApp queue only a generic inbox intent until the
existing authenticated Root flow and confirmed identity are ready. Cross-session
intents are discarded. Foreground activity uses a generic banner. Remote text,
recipient IDs, post IDs and URI fields never authorize UI content/navigation.
Receive and open dedupe keys are separate (bounded 128-key process-local history).
No local-notification duplication was added.

The Home bell and inbox now use the confirmed Laravel schema:

- NotificationUnreadCount strictly parses data.unread_count as a nonnegative
  integer. Missing, string, fractional or negative values are errors, not zero.
- The app-scoped NotificationActivity keeps the cached count, coalesces requests,
  invalidates count requests predating a read action, and immediately clears
  account data/busy state on sessionRevision changes. Old responses cannot
  restore another user's count or publish a read event.
- HomeTopBar displays the server count, hides zero and caps labels at 99+. It
  refreshes through the coordinator on Root attachment, foreground FCM activity,
  route return, Home tab selection/re-tap and app resume. FCM fields never supply
  the count. The former decorative dot is replaced by the real count badge.
- GET notifications retains opaque cursor pagination. The confirmed response
  can omit meta.path, so the notification repository alone supplies its known
  endpoint path to the existing strict cursor parser. Pagination continues to
  use meta.next_cursor, never links.next, offset pages or guessed cursors.
- InboxNotification/NotificationActor parse actor name/avatar, type, created_at
  and read_at. Default row descriptions now use the six confirmed Laravel enum
  phrases documented in NOTIFICATIONS_UI_REDESIGN.md. Opaque data.title/body/
  message and unknown raw enum names are not displayed or used for navigation.
- Rows show actor avatar/fallback, name, type/available description and relative
  time with the existing timeAgo helper. Unread rows have a subtle orange tint,
  heavier text and a Mark as read action; read rows have a muted check.
- PATCH notifications/{id}/read and PATCH notifications/read-all update only
  after success. Read events patch the known loaded records without resetting
  their cursor/cache, then fetch the authoritative unread count. Read-all records
  the IDs loaded when the action started, avoiding marking later new records
  read locally. Future pages receive their read state from Laravel.
- Session-scoped read overlays keep an older in-flight list/page response from
  restoring unread status for a successfully marked ID. Backend read timestamps
  are retained when present; a local completion timestamp supplies the UI state
  only after confirmed PATCH success. Mark-read actions never navigate.
- Errors preserve cached content/count, and failed read writes leave rows
  unchanged. Inbox loading/empty/retry, pull-to-refresh and pagination remain.
  Inbox pull-to-refresh runs Laravel requests independently of optional FCM retry.
- Initial inbox count refresh is scheduled after its first frame: a shared Home
  badge must not receive synchronous notifications during route construction.
- All notification paths retain the ApiService/Dio sessionRevision guard. A stale
  PATCH/count/list response cannot affect a replacement account. No bearer or
  notification content logging was introduced.

The original OpenAPI file is historical and lacks these routes. The user's
confirmed production schema is authoritative for this increment. HTTP tests use
mock adapters; live production inbox access/read actions require a valid session.
Figma metadata was accessible, but relevant design context/screenshots hit the
Starter tool-call limit. Existing dark components/tokens were reused; pixel parity
with Figma is not claimed.

## Versions and platform setup

No dependency versions/configuration were changed: firebase_core 4.15.2,
firebase_messaging 16.7.1, native Firebase 12.19.3, Google Sign-In 9.2.0,
AppCheck 11.3.1 and GTMSessionFetcher 3.5.0. SwiftPM, com.travibe.app,
GoogleService-Info.plist, signing and Google/Apple/Laravel authentication remain.

- iOS: project travibe-adc4d/plist Runner membership are retained. Push capability,
  aps-environment entitlement, Background Modes remote-notification and matching
  Apple provisioning still require configuration. Confirm APNs key/certificate
  in Firebase Console for this app. No credentials/entitlement values invented.
- Android: applicationId/namespace is com.travibe.app (matching iOS) and Core is
  enabled. The `com.google.gms.google-services` Gradle plugin reads
  `android/app/google-services.json` (gitignored; download it from Firebase project
  travibe-adc4d for package com.travibe.app). Plugin manifest already supplies
  POST_NOTIFICATIONS and services. FCM uses the default "Miscellaneous" channel
  and launcher icon; a monochrome notification icon and a custom channel remain.
  Android 13 permission/channel/icon/device behavior requires testing.
- Real-device APNs/FCM token retrieval, Laravel/Kreait sends, foreground/background/
  terminated delivery and logout/account-switch delivery remain to be tested.
  A simulator build or mocked transport is not proof of real push delivery.

## Device-token integration files (previous increment)

- lib/features/notifications/data/laravel_push_token_repository.dart (new)
- lib/features/notifications/data/push_device_store.dart (new)
- lib/features/notifications/data/push_token_repository.dart
- lib/features/notifications/data/notifications_repo.dart
- lib/core/notifications/push_notification_service.dart
- lib/core/notifications/push_notifications_host.dart
- lib/core/datasource/localdata/preferences_manager.dart
- lib/core/datasource/remotedata/dio_client.dart
- lib/core/datasource/remotedata/api_service.dart
- test/features/notifications/laravel_push_token_repository_test.dart (new)
- test/features/notifications/notifications_endpoints_test.dart (new)
- test/core/notifications/push_fakes.dart
- test/core/notifications/push_notification_service_test.dart
- test/core/notifications/push_notifications_host_test.dart
- docs/FIREBASE_PUSH_NOTIFICATIONS.md

Git metadata is absent in this checkout. A focused pre-change snapshot was saved
at /private/tmp/travibe-device-token-before. No reset, commit or unrelated UI
change was made.

## Verification

- dart format completed on changed Dart files.
- Targeted flutter analyze --no-pub on notifications, modified datasource files
  and notification tests: **no issues**.
- Full flutter analyze --no-pub: **three existing unrelated findings**:
  custom_bottom_nav.dart missing key; trending_destinations_section.dart multiple
  underscores; discard_changes_dialog_widget.dart unused DarkColors import.
- flutter test --no-pub test/core/notifications test/features/notifications
  test/core/datasource/preferences_manager_test.dart: **64 passed, zero failed**.
  Coverage includes HTTP response parsing/platforms, 204/404/401/403/offline,
  captured credentials, metadata restoration/scope, token refresh/deduplication,
  APNs/permission states, in-flight logout, rapid A/B/C switches, late responses,
  retention after failed refresh/shutdown, stale-cleanup error isolation, inbox
  navigation/loading/empty/error/refresh, and responsive inbox sizes.
- Authentication/onboarding/settings/account-deletion/account-actions, cursor
  pagination and startup widget regression group: **170 passed, zero failed**.
- flutter build ios --simulator --debug --no-pub, bounded to 15 minutes:
  **succeeded**, final Xcode build **34.2s**, exit **0**. The compiled kernel is
  newer than the final service source. SwiftPM native pins remain unchanged.
  Flutter's automatic objectVersion 60→54 format rewrite was restored to the
  exact pre-task project bytes; no dependency-manager/signing change was retained.
- pubspec.lock is byte-for-byte unchanged. No dependency declarations changed.
- No live registration/revocation, real-device receipt or simulator visual
  inspection was performed. The previous separate Story Viewer run had 12 passing
  tests and the same three known reply-composer failures; those unrelated tests
  were not rerun or claimed fixed in this increment. The full test suite was not
  rerun.

Logs are /private/tmp/travibe-device-{final-analysis,full-analysis,final-tests,
repository-tests,regressions,ios-build}.log. No commit was made.


## Notifications completion and simulator verification — 2026-11-06

Files in this increment:

- lib/features/notifications/data/notification_model.dart (new)
- lib/features/notifications/data/notifications_repo.dart
- lib/features/notifications/cubit/notification_activity.dart (new)
- lib/features/notifications/cubit/notifications_cubit.dart
- lib/features/notifications/screens/notifications_screen.dart
- lib/core/notifications/push_notifications_host.dart
- lib/core/notifications/push_notification_service.dart (reject blank SDK tokens)
- lib/features/notifications/data/laravel_push_token_repository.dart (same guard)
- lib/features/home/widgets/home_top_bar.dart
- lib/root.dart (Home tab unread refresh)
- test/features/notifications/notification_activity_test.dart (new)
- test/features/notifications/notifications_screen_test.dart
- test/features/notifications/notifications_endpoints_test.dart
- test/core/notifications/push_fakes.dart
- test/core/notifications/push_notification_service_test.dart
- integration_test/notifications_simulator_test.dart (new)
- docs/FIREBASE_PUSH_NOTIFICATIONS.md

`git status` still reports no Git metadata. The pre-change snapshot is
/private/tmp/travibe-notifications-complete-before; no existing work was reset.

Environment: Flutter 3.44.9/Dart 3.12.2, Xcode 26.6, booted iPhone 17 simulator
E648DA3C-7301-4B73-B7EF-1CF0463BE844 on iOS 26.5. flutter doctor reports unaccepted
Android licenses and missing CocoaPods. SwiftPM remains the iOS dependency manager;
no CocoaPods installation/migration was attempted. Simulator data was not erased.

Simulator-safe behavior is preserved: Core initialization is coalesced and
failure-tolerant, notification startup is unawaited by auth/splash, permissions
are never automatically requested, APNs retry is bounded, and token retrieval
failure/null/blank/whitespace values never cause placeholder registration. Laravel
inbox access is independent of FCM capability. Production device-token POST/DELETE
semantics and account protections remain as documented above.

Verification:

- flutter doctor -v, flutter devices and xcrun simctl list devices available ran.
- flutter pub get succeeded; pinned declarations and lockfile are unchanged.
- dart format completed on all changed Dart files.
- Final targeted tests (notifications, Firebase lifecycle/device-token adapter,
  cursor pagination and onboarding/splash): **156 passed, zero failed**.
- Full flutter test --no-pub --reporter expanded: **1482 passed, 5 failed**.
  These are the same two Search and three Story Viewer reply-composer failures
  recorded in FIREBASE_MESSAGING_AUDIT.md before this increment. They were not
  changed or claimed fixed. The final additional shared badge/route test passed
  in the focused run; broad tests were not repeated after that isolated addition.
- Full analysis reports only the three existing unrelated findings (Home bottom
  nav key, trending destinations underscores, discard dialog unused import).
- iPhone 17 Simulator integration: **2 passed** after fixing a shared-controller
  notify-during-route-build error detected by the first integration attempt.
  Xcode built the final integration app in **48.3 seconds**. The isolated test
  verifies Home bell badge, inbox actor/content, read-one, read-all, badge zero
  and session clearing with Messaging unavailable. These are test-only fixtures,
  not live authenticated backend flows or fake production push registrations.
- Real persisted startup reached Login in the first simulator attempt and
  Onboarding in the final attempt. No test credentials were supplied and no usable
  authenticated session reached Home. Live authenticated inbox/read/logout/login
  flows therefore remain unverified. No disk preferences were explicitly cleared,
  no simulator erase/reset occurred, and no real read or logout mutation was made.
- Manual UI inspection was unavailable: the computer-use tool rejected access to
  Simulator ("Computer Use was not approved to use Simulator"). Functional screen
  checks above used Flutter integration/widget tests, not manual visual inspection.
- No APNs/FCM push delivery or physical-device token retrieval is claimed.

- Final targeted analysis: **no issues**.
- Normal `flutter run -d E648DA3C-7301-4B73-B7EF-1CF0463BE844 --debug --no-pub`
  built **lib/main.dart**, completed Xcode in **32.8s**, synchronized assets,
  launched successfully and exposed the Dart VM service. A subsequent simctl
  launchctl check confirmed the com.travibe.app process remained alive. Debugger detached with
  `d`, leaving the normal app running. No fatal Firebase/APNs errors or repeated
  initialization loop appeared in the observed Flutter run output. This is not
  proof of APNs registration or remote delivery.
- The project/plists/scheme/SwiftPM locks and pubspec files match their pre-task
  snapshots. Only Flutter's automatic objectVersion format rewrite was restored;
  signing, entitlements, Firebase options and native SDK integration were retained.

Logs are
/private/tmp/travibe-notifications-{doctor,devices,simulators,pub-get,analysis,
final-analysis,final-targeted-analysis,full-tests,targeted-tests,
final-targeted-tests,simulator-tests}.log.



## Screenshot redesign

The flat notification row/menu redesign supersedes the earlier tinted-row UI.
See [NOTIFICATIONS_UI_REDESIGN.md](NOTIFICATIONS_UI_REDESIGN.md) for screenshot
references, exact SVG mapping boundary, follow reuse, media requirements and
current verification. The API/FCM/session lifecycle documented above is retained.

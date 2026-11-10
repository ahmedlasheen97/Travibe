# Notifications screenshot redesign

**Current behavior:** see [Notification behavior fixes](NOTIFICATION_BEHAVIOR_FIXES.md)
for the 2026-11-09 eight-type mapping, safe destinations, automatic read-all,
authorized content previews, tests and live verification limits. The sections
below retain the historical visual implementation record.

## Visual references and implementation

Both local references were verified and visually inspected before UI edits:

- docs/Screenshot 2026-11-06 at 23.36.27.png
- docs/Screenshot 2026-11-06 at 23.37.03.png

The existing NotificationsScreen, repository, cursor Cubit, read/count activity,
FCM lifecycle and token repositories were retained. NotificationRow now renders
flat rows on #0B0B0B, without cards, unread background tint, separators or trailing
read-state icons. The circular shared back button and centered title remain.
The toolbar is 80 reference pixels high, with status/bottom insets handled by
AppBar/SafeArea. Existing Plus Jakarta Sans typography and AppSizes scaling are
used throughout the row.

Actors use 52 reference-pixel circular avatars with the existing image/fallback
widget. The unread indicator is 8px in a permanently reserved 12px gutter, so
reading a row does not move its avatar/text. Type SVGs are 20px at the bottom-right
of the avatar, without an extra colored circle or SVG color filter. The nearby
32px artwork is centered in a dark circular avatar when no actor exists.

Actor names are semibold within the white 16px message. Available secondary text
and inline relative timestamps are muted gray. Layout-aware measurement keeps
the timestamp when truncating to three lines. Truncation uses grapheme clusters,
respects text direction/scaling, and exposes full content to accessibility.

Read-one is triggered by tapping a row, using the existing successful-PATCH state
update; no destination is inferred. Read-all and push permission/settings remain
available in the header overflow menu. The menu is a deliberate functional
addition to the supplied references, whose header shows no trailing action.
Permission status was moved out of the notification list into a bottom sheet.
This does not change permission requests, APNs retries or registration behavior.

## Type/icon mappings and confirmation boundary

NotificationPresentationResolver is an exact, case-sensitive allowlist from
verified backend type strings to semantic kinds. It does not guess enum/class
suffixes or classify arbitrary message text.

| Semantic kind | Original asset |
| --- | --- |
| Comment / reply | assets/images/notification/comment.svg |
| Follow | assets/images/notification/followedyou.svg |
| Like | assets/images/notification/liked.svg |
| Message request / accepted request | assets/images/notification/messagerequest.svg |
| Nearby buddy | assets/images/notification/someone in yourcity.svg |
| Unknown | Neutral notifications icon, no raw backend enum text |

The asset directory is now registered in pubspec.yaml. Original SVG names, root
artwork, proportions and colors are unchanged, including the filename with spaces.

The backend has now confirmed the exact `App\Enums\NotificationType` values
returned unchanged by NotificationResource.php, NotificationCreated and FCM:

| Exact enum | Semantic kind / icon | Actor-relative description |
| --- | --- | --- |
| post_liked | Like / liked.svg | liked your post |
| post_commented | Comment / comment.svg | commented on your post |
| comment_replied | Comment / comment.svg | replied to your comment |
| user_followed | Follow / followedyou.svg | followed you |
| message_received | Message / messagerequest.svg | sent you a message |
| user_mentioned | Neutral fallback | mentioned you |

These six are the default production allowlist, matched exactly without case
folding, namespace guessing or substring matching. Unknown values retain neutral
icons and “New notification”. The existing API actor name/username is emphasized;
missing actors do not acquire a fabricated name from opaque data.title. The
semantic `nearby` rendering capability/asset remains available, but no Nearby or
Story enum alias is enabled. The historical message-request asset is used for
message_received without claiming that the event represents a request.

No description or translation field in opaque data has been confirmed. Default
presentation therefore uses the six confirmed phrases and ignores data.body,
data.message and data.title. It does not invent previews, comment copy, mention
targets, grouped counts or mutual followers. Test-only adapters explicitly own
their synthetic text contract when exercising long text/layout.

## Media and text data boundaries

The confirmed notification shape includes type, actor, target_type, target_id,
data, read_at and created_at. InboxNotification now retains target_type/target_id
without inventing a relationship, endpoint or destination. The actor parser
retains its confirmed stable ID, is_following and is_blocked flags.

There is no confirmed notification thumbnail URL, media relation, grouped actor
count, mutual-follower count, secondary caption or translated-description field.
Default UI uses the confirmed enum phrases above; no sample user, comment, image
URL, group count or mutual count is hardcoded. Unknown records use the generic
notification fallback.

A verified presentation adapter may supply NotificationThumbnail and secondary
text. Thumbnail geometry is:

- Post image: 52 × 52 reference pixels, square, radius 10, BoxFit.cover.
- Story preview: 56 × 80, portrait, radius 10, BoxFit.cover.
- No supported preview/text-only post: no image widget, gap or reserved slot.

The default adapter supplies no preview. Existing post detail APIs and
StoriesRepo.getStory can retrieve media for known resources, but they do not
establish the meaning of notification target_type values or which preview to use.
No per-notification network request/N+1 fetch was added. Production previews need
confirmed target relationships plus preview URLs in the notification payload or
an existing preloaded/batched resource cache. An arbitrary FCM URL is never used.

## Follow behavior and account isolation

Root's existing FollowCubit is passed to the imperative notification route using
BlocProvider.value. FollowActionBuilder and FollowPill preserve shared pending,
Following, optimistic/error behavior. Standalone screens use the same Cubit class
with a screen-owned lifetime, replacing it on session changes.

A follow action appears only for an explicitly verified follow kind, a valid
actor ID with known following/unblocked flags, and a confirmed positive current
user ID different from that actor. Shared block/pending-block state also hides
the action. Missing, blocked or own actors do not create a trailing placeholder.
Follow targets the actor ID and preserves duplicate-request protection.

All existing Laravel notification endpoints, cursor caching, read-one/read-all,
unread badge, activity hints and session guards are unchanged. Reading rows keeps
pagination state; full-page refresh retains its established cursor behavior.
No new notification target navigation was introduced.

## Files changed

- pubspec.yaml (asset directory only; dependency versions unchanged)
- lib/features/notifications/data/notification_model.dart
- lib/features/notifications/data/notification_presentation.dart (new)
- lib/features/notifications/widgets/notification_row.dart (new)
- lib/features/notifications/screens/notifications_screen.dart
- lib/core/notifications/push_notifications_host.dart (shared follow route scope)
- lib/root.dart (passes existing FollowCubit)
- test/features/notifications/notification_redesign_test.dart (new)
- test/features/notifications/notifications_screen_test.dart
- test/features/notifications/notification_activity_test.dart
- integration_test/notifications_simulator_test.dart (updated menu/read interactions)
- docs/NOTIFICATIONS_UI_REDESIGN.md
- docs/FIREBASE_PUSH_NOTIFICATIONS.md (links this visual update)

Git metadata is absent. Focused snapshots were saved to
/private/tmp/travibe-notification-redesign-before before editing. No existing work
was reset and no commit was made.

## Verification

- flutter pub get succeeded; pubspec.lock/dependency versions are unchanged.
- dart format completed on changed Dart files.
- Final focused notification, FCM/token, cursor, follow, onboarding, auth and
  account-deletion regression group: **252 passed, zero failed**.
- Targeted flutter analyze: **no issues**.
- Layout checks cover 320/375/393/430px, larger text/Arabic/emoji, icon assets,
  unknown types, aligned unread gutter, post/story geometry, text-only absence,
  shared follow/pending/own/blocked restrictions, and repeat-read suppression.
- iPhone 17 simulator integration: **2 passed**. Xcode Debug build completed in
  **74.4s**. The inbox/settings/menu/read actions ran with isolated fixtures and
  Messaging unavailable; real startup reached Onboarding. No usable authenticated
  session was available for live production notification UI verification.
- The first native attempt failed because Flutter's generated aggregate package
  declared iOS 13 despite Runner's existing iOS 15 deployment target. Serial
  config-only regeneration/build through Flutter aligned the generated artifact
  to 15 and succeeded. No native dependency version, source-project deployment
  target, SwiftPM manager, Firebase plist, signing or Bundle ID was changed.
- The broader full suite was not rerun for this visual increment; prior known
  Search/Story Viewer failures are not claimed fixed.

- Normal flutter run launched lib/main.dart on iPhone 17 successfully; Xcode
  Debug build completed in **59.4s**. Flutter was detached with `d`, leaving the
  app running; simctl launchctl confirmed the com.travibe.app process afterward.
- pubspec.lock, Runner project, Firebase/Info plists and both native Package.resolved
  files match their pre-task snapshots. Only the asset directory was added to
  pubspec.yaml. Firebase/Google Sign-In versions and native configuration remain.
- No manual authenticated visual inspection or real push delivery is claimed.
  Visual inspection used the two supplied images and rendered test artifact;
  simulator notification interactions used isolated fixtures only.

Logs: /private/tmp/travibe-redesign-{pub-get,analysis,tests,final-tests,config,
simulator}.log. No commit was made. A test-only visual
artifact with project fonts/SVGs is rendered to
/private/tmp/travibe-notification-redesign.png and was visually inspected against
the two references. It uses synthetic test content and fallback avatars, not
production notifications or hardcoded screenshot users. Geometry/icon appearance
were checked; live avatar/media parity cannot be established without live data.


## Confirmed enum update — 2026-11-07

Changed files: notification_presentation.dart (exact default enum/description
maps), notification_row.dart (uses the confirmed description and API actor only),
notification_enum_test.dart (new), notification_redesign_test.dart (explicit fixture
text adapter), notifications_screen_test.dart (unknown opaque data stays generic),
integration_test/notifications_simulator_test.dart (confirmed fixture type values),
this document and FIREBASE_PUSH_NOTIFICATIONS.md. No production layout, SVG asset,
repository, read/count, Firebase, auth or native configuration change was required.

Verification:

- dart format completed on changed Dart files.
- Targeted flutter analyze: **no issues**.
- Notification, Firebase lifecycle/device-token, cursor/account-isolation and
  shared-follow tests: **169 passed, zero failed**. Includes all six exact enums,
  SVGs and descriptions, neutral mention/unknown fallback, ignored unverified
  payload text, missing actor, bold actor name, read/unread state, and the default
  user_followed Follow action. Existing nearby artwork renders in an explicit
  fixture adapter only; the default production allowlist contains exactly six keys.
- iPhone 17 Simulator Debug integration: **2 passed**, Xcode **45.0s**. The real
  restored authenticated session reached Home and opened the Laravel inbox.
  No live read/logout/follow mutation was performed. The isolated fixture test
  used user_followed/post_liked and verified inbox/read/count behavior with
  Messaging unavailable.
- All five notification SVGs remain registered, load successfully in widget tests
  and retain their original files/colors. No asset or dependency changes needed.
- pubspec/lockfile, Runner project and both SwiftPM lockfiles match pre-task bytes.

- Normal lib/main.dart Debug build and launch succeeded on iPhone 17 in **31.5s**.
  Flutter was detached with `d`, leaving the app running; simctl confirmed its
  process after detachment. No dependency, native configuration or layout change
  was made for this enum update.

Logs:
/private/tmp/travibe-enum-{analysis,tests,config,simulator}.log.


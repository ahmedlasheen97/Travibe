# Notification behavior fixes — 2026-11-09

This update supersedes the six-type, no-navigation and no-preview limitations in
the historical `NOTIFICATIONS_UI_REDESIGN.md` report. It preserves that screen's
layout, typography, SVG artwork, shared Follow behavior and notification APIs.

## Diagnosis and contract

The current local `travibe-api.json` documents eight exact notification types.
The old production mapper recognized six: `story_liked` and `comment_liked` were
missing and therefore displayed the generic bell and “New notification”.

| Exact type | Actor-relative text | Existing SVG | Destination |
| --- | --- | --- | --- |
| post_liked | liked your post | liked.svg | Authorized Post detail |
| story_liked | liked your story | liked.svg | Existing Story Viewer |
| comment_liked | liked your comment | liked.svg | Post / comment replies |
| post_commented | commented on your post | comment.svg | Post / comments |
| comment_replied | replied to your comment | comment.svg | Post / comment replies |
| user_followed | followed you | followedyou.svg | Existing Other User Profile |
| message_received | sent you a message | messagerequest.svg | Existing Conversation / pending request |
| user_mentioned | mentioned you | Neutral fallback | Documented Post, Story or Comment target |

Mappings are exact and case-sensitive. Unknown types remain safe/generic. Debug
diagnostics deduplicate bounded fingerprints and report only target presence and
payload-key count: no raw payload, names, URLs, content, IDs, credentials or tokens.
All five existing SVG assets remain registered and unchanged; nearby artwork has
no undocumented production type alias.

A sanitized, read-only request using the Simulator's restored session returned
**GET /api/v1/notifications → HTTP 403**. Credentials remained in memory and were
not printed. Consequently, the specific reported notification could not be
inspected. The client mapping gap is confirmed, but the actual record's type and
why the backend created it are **not verified**. Publishing a Story is not assumed
to create a notification; the spec documents likes and mentions, among other
events. No production read/follow/content/message mutation was performed in this
investigation.

## Safe target navigation

Navigation uses only exact resource morphs (`App\\Models\\Post`,
`App\\Models\\Story`, `App\\Models\\Comment`), positive target IDs, and documented
relationships. Likes also establish their documented object kind when the morph
is absent. `message_received` uses `data.conversation_id` and re-fetches the
canonical conversation before opening it. The current accepted/block state,
rather than an FCM flag or an arbitrary route string, controls the existing Chat
composer and pending-request restrictions.

Comment targets require documented `data.post_id`; the authorized nested comment
endpoint validates their relationship to that Post. Mention notifications support
the documented Post/Story/Comment target relationships. No arbitrary URLs or
push-provided route strings are executed. Rapid taps share one navigation lock.
Known blocked targets and missing, expired, forbidden or deleted content remain
in the inbox and show a safe unavailable message. Rows remain tappable after
automatic read-all; reading is independent of successful destination access.

The project had no standalone Post Detail route. `NotificationPostScreen` is a
small destination using the existing shared PostCard, Likes/Saves owners,
comments/replies sheet, author-profile link and sharing sheet. Other existing
screens were reused. Borrowed Root Cubits remain owned by Root. Account changes
invalidate lookups, clear old inbox state, ignore stale mutations/navigation and
hide opened content. Existing Profile/Chat/Story session protections remain.

Comments open the existing Comments or Replies sheet. The current comments UI
does not support scrolling to/highlighting an individual comment; no unsupported
anchor behavior is claimed. A Comment notification lacking `data.post_id` cannot
be resolved safely and is marked read without invented lookup endpoints.

## Read-all and global badge

After a successful inbox load, while visible and foregrounded, the screen calls
the existing PATCH `/notifications/read-all` when unread work exists. The
repository validates the documented `message` and `data.marked_count` confirmation
before committing local state. Rows are retained, their unread dots disappear,
and the shared Home badge becomes zero after confirmation and authoritative count
reconciliation. Loading failures do not trigger read-all.

Read operations are coalesced, session-stamped and retried explicitly on failure.
Failure preserves unread state and offers Retry. Rebuilds, read echoes and normal
back navigation do not repeatedly acknowledge already-read rows. Resume, return,
pull-to-refresh and activity hints can safely discover new unread work.

Reverb `notification.created` forwards only a bounded notification-ID refresh hint,
including when the server reopens an existing notification ID. The host coalesces
hints, REST reloads authoritative rows/counts, and reopened IDs invalidate stale
local read overrides. A create arriving during an in-flight read-all cannot be
incorrectly acknowledged by its late response. Notifications arriving afterward
are acknowledged through a subsequent successful visible-inbox cycle. New IDs
outside an in-flight read-all snapshot are not mistaken for already-read IDs.

## Thumbnails

The notification schema does not supply a confirmed media URL. Visible content
rows resolve authenticated GET `/posts/{post}`, GET `/stories/{story}`, or the
documented nested comment endpoint. The resolver uses the current Dio/session
architecture, at most three concurrent lookups, a bounded 128-entry account-scoped
two-minute cache and in-flight deduplication. Duplicate targets share work;
failed targets are bounded too. Pull-to-refresh clears previews/cache, and tapping
revalidates access. No media requests or payload URL guessing are added for Follow
or Message notifications.

- Posts: first supported image thumbnail/URL from actual ordered media, **56×56**.
- Stories: actual single-photo thumbnail/URL, **56×76**.
- Text-only Posts / unsupported or inaccessible media: no image or reserved slot.
- Existing rounded corners, cached image rendering and BoxFit.cover remain.

Signed/actual detail URLs are used as supplied, never constructed. HTTP(S) URLs
with embedded credentials are rejected. Story thumbnails represent the photo;
the existing Story Viewer also renders its overlay document when opened.

## Files changed for this update

- `lib/features/notifications/data/notification_presentation.dart`
- `lib/features/notifications/data/notification_model.dart`
- `lib/features/notifications/data/notifications_repo.dart`
- `lib/features/notifications/data/notification_diagnostics.dart` (new)
- `lib/features/notifications/data/notification_targets.dart` (new)
- `lib/features/notifications/cubit/notification_activity.dart`
- `lib/features/notifications/cubit/notifications_cubit.dart`
- `lib/features/notifications/widgets/notification_row.dart`
- `lib/features/notifications/screens/notifications_screen.dart`
- `lib/features/notifications/screens/notification_navigation.dart` (new)
- `lib/features/notifications/screens/notification_post_screen.dart` (new)
- `lib/core/notifications/push_notifications_host.dart` (borrow existing route state)
- `lib/features/chats/data/chat_reverb_service.dart` (notification-ID hint only)
- `lib/features/chats/widgets/chat_reverb_host.dart` (coalesce ID hints)
- `lib/features/comments/screens/comments_screen.dart` (optional initial replies parent)
- `test/features/notifications/notification_enum_test.dart`
- `test/features/notifications/notifications_endpoints_test.dart`
- `test/features/notifications/notification_targets_flow_test.dart` (new)
- `test/features/chats/chat_reverb_service_test.dart`
- `docs/NOTIFICATIONS_UI_REDESIGN.md`
- This document.

No dependencies, native configuration, Firebase versions, SwiftPM, authentication
or unrelated features were changed. Existing uncommitted work was retained; Git
metadata is absent and no commit was made.

## Verification

- Dart formatting completed on changed files.
- Targeted analysis, including Notifications, route scope, Reverb forwarding,
  optional comments parent and changed tests: **no issues**.
- Full `flutter analyze --no-pub`: **zero errors/warnings**, two existing Home
  informational lints (`custom_bottom_nav.dart:10` named key,
  `trending_destinations_section.dart:54` unnecessary underscores). These unrelated
  widgets were not changed.
- Notifications + Firebase lifecycle + Chat + Profile + Stories + Comments:
  **934 passed, zero failures**.
- Full `flutter test --no-pub --reporter expanded`: **1,815 passed, zero failures,
  one existing intentional opt-in live-chat skip**, 2m29s. This includes the final
  Reverb notification-ID hint assertion and the Story Viewer regressions.
- `flutter build ios --simulator --debug --no-pub`: **succeeded**, Xcode 139.6s,
  output `build/ios/iphonesimulator/Runner.app`.
- Installed without erasing data and launched `com.travibe.app` on the booted
  iPhone 17 (iOS 26.5, E648DA3C-7301-4B73-B7EF-1CF0463BE844). `simctl launch`
  returned an app process; the captured screen visibly showed authenticated Home.
  Direct Simulator UI control was unavailable: Computer Use reported that its
  permissions are not granted. Live inbox taps and content-return journeys were
  therefore **not manually verified**. No permission, account or profile setup was
  bypassed. Automated mocked tests exercised the actual destination widgets and
  back navigation; those are not live backend verification.

An added account-switch regression initially caught a real lazy-initialization
issue in the inbox session revision, which is now eagerly captured at startup.
Another intermediate test failure was pending cancellation cleanup in the new
test fixture; its resources now drain before teardown. Final focused/full runs
have no failures. No assertions were removed or weakened.

Logs and startup evidence:

- `/private/tmp/travibe-notification-regressions.log`
- `/private/tmp/travibe-notification-full-suite.log`
- `/private/tmp/travibe-notification-targeted-analysis-final.log`
- `/private/tmp/travibe-notification-full-analysis.log`
- `/private/tmp/travibe-notification-ios-build.log`
- `/private/tmp/travibe-notification-launch.png` (local startup screenshot)

The focused tests exercise exact enums, original SVGs, unknown diagnostics,
missing actors, successful/failed read-all, badge reset, new/reopened events during
mutations, REST pagination/reconciliation, cache/dedup/concurrency, target
visibility/expiration, actual shared route widgets and back navigation, accepted
and pending Chats, duplicate taps and account switching. Existing responsive
tests cover 320/375/393/430 logical widths, larger text and RTL.

Live notification navigation/read-all still requires an eligible full-access,
verified session that can access `/notifications`. No live push delivery or
production notification flow is claimed from mocked tests or a Simulator build.

## Figma parity update — 2026-11-10

Supersedes the "Thumbnails" section above and the morph-only target rules.

- **Contract drift fixed:** `docs/openapi.json` documents short `target_type`
  values (`post|comment|story|user|message`). `normalizedTargetKind` accepts
  these and the legacy `App\Models\*` morphs. Previously short values resolved
  to no target, so rows neither navigated nor showed thumbnails.
- **Previews come from the payload:** `preview.thumbnail_url` / `preview.excerpt`
  (parsed as `NotificationPreviewData`). The per-row GET lookups are removed;
  tap-time `resolve(fresh: true)` still validates deleted/expired/blocked content.
  Thumbnails: post 52×52 square, Story 48×72 portrait, none without a preview.
- **Text:** comment/reply/mention rows append the excerpt ("commented: …");
  `message_received` with `data.is_request` reads "sent you a message request";
  text-only liked posts show the excerpt as a secondary line.
- **Taps:** the avatar opens the actor profile for every type; thumbnail = row.
  Comment targets open the post's comments, scroll to and briefly tint the
  comment (`CommentsScreen.highlightCommentId`); replies open the parent thread.
  An unresolvable message request opens `ChatsScreen(requests: true)`.
- **Follow pill:** shown when `actor.is_following == false` (hidden when
  already following); no longer requires a loaded `CurrentUserCubit`.

### Backend requests (not in the API yet; client has graceful fallbacks)

1. `data.post_id` (+ `comment_id`, `parent_comment_id`) on `post_commented` and
   `comment_replied` when they target a comment. Without it the row shows the
   "unavailable" snackbar.
2. `data.others_count` (int) for grouped likes/comments → "X and N others".
3. `data.mutual_followers_count` on `user_followed` → "N mutual followers".
4. New types `message_request_accepted` (`data.conversation_id`) and
   `buddy_nearby` (opens Buddies). Both are already mapped client-side.
5. Optional `preview.media_type` if video posts/stories are ever allowed.

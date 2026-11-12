# Other user profile and Chat discovery

## Contract and root causes

Source: the authorized 93-path `docs/chat-openapi.json` already downloaded for
Chat. No live account requests or mutations were performed in this update.

GET `/search/users?q=...&page=...` searches name/username prefixes with a confirmed
3–100-character minimum/maximum and Laravel page metadata. The prior endpoint
and query were correct. New Conversation lacked result/idle/empty/retry UI,
pagination and authenticated-user exclusion. It also lost Root's follow/block
owners when pushed through Home → Chats. These are verified client gaps; no
claim is made that the production server returned an error or no users.

The existing SearchRepo/ApiService/DioClient remain in use. A route-owned
ChatDiscoveryCubit debounces 350ms, coalesces unchanged queries, excludes the
confirmed current ID and blocked users, deduplicates pages and ignores obsolete
query/session results. Identity uses the shared current user when available,
otherwise GET `/user`; identity failures are retryable, never ownership guesses.
Malformed search entries are errors, not successful empty results. Empty API
pages and pages filtered to no available users have distinct messages. Avatar
opens Profile; selecting a row creates/opens a Conversation via integer user_id.

## Profile and relationships

One existing ProfileScreen handles public GET `/users/{user}`. `data:null` remains
unavailable. Existing PostsCubit/author-post cursor API, post cards/actions,
About tabs, purple chips, statistics and avatar are reused. Added public header,
Follows You badge and Message/Follow actions; public self profiles omit these
actions. Message uses existing Chat repository and conversation screen, locks
repeated taps and discards old-session completions. Profile tabs retain the
existing posts cache. Gender and nationality_code render only when supplied;
no nation labels are derived from sample content. The documented public resource
has no current_location field: the UI accepts existing supplied location values
but does not infer one from country_code or fetch a private profile.

FollowActionBuilder/FollowCubit preserve their established confirmed mutation,
pending lock, conflict reconciliation and rollback behavior. Session changes now
clear shared relationship overrides and invalidate old mutation completions.
PublicUserModel retains follows_you independently of is_following. Badges and
menu conditions use follows_you, never is_following.

Followers/Following reuse the existing screen, independent cached Cubits and
scroll keys. Counts use successful list meta.total ahead of route snapshot
counts. Confirmed relationship changes refresh loaded lists and profile counts;
refresh supersedes stale in-flight pages. Pagination merges by stable ID.

## Options and assets

- Share profile / Copy profile link: share or copy `PublicProfileResource.url`
  as-is (`ProfileModel.url`, https only) via the native `travibe/post_sharing`
  channel. Both rows are hidden when `url` is missing; no link is built in the app.
  Own profile: the "Share Profile" button beside "Edit Profile" shares
  `UserResource.url` and is hidden without it. Links open via
  `travibe://users/{id}` (see `docs/SHARE_POST.md` → Deep links).
- Remove Follower appears only for follows_you=true. Confirmation precedes
  DELETE `/users/{user}/follower`; its 200 message response is validated. The
  shared override changes only on confirmed success; profile/current-user counts
  and affected lists refresh. Errors retain state. No simulated removal.
- Report: existing ReportReasonSheet and confirmed POST `/reports` with type=user,
  integer id and allowed reason. It uses the route's existing profile repository.
- Block User: existing confirmBlockChange/BlockCubit; shared feeds/profile become
  unavailable through their existing subscriptions.

Existing icons registered via `assets/images/icons/`: send-2.svg for sharing,
user-remove.svg (muted) for removal, flag.svg for reporting, user-remove 2.svg
(red) for blocking. Original artwork/colors and filenames are unchanged.

## Navigation and design limits

Home post authors, search results, comments, suggested users, follower/following
rows, Chat discovery and conversation participant avatars use ProfileScreen.open.
Chat routes borrow Root's FollowCubit/BlockCubit/CurrentUserCubit; they do not
create replacement relationship/session owners. No duplicate profile route was
introduced. Per-entry locks prevent repeated navigation.

No profile screenshots were located. Figma metadata access hit its Starter-plan
tool limit. Written requirements and existing dark Travibe components were used;
there is no claimed screenshot comparison or Figma fidelity. Responsive widget
verification covers 320/375/393/430 logical pixels with increased text scale.

## Verification

Verified 2026-11-08 with Flutter 3.44.9 / Dart 3.12.2:

- `flutter pub get` succeeded; no dependency versions were deliberately changed.
- Changed Dart files were formatted.
- Targeted analysis of 22 changed implementation/test paths: no issues. The final
  action refresh adjustment was analyzed separately with no issues.
- Full analysis: three existing findings: missing widget key in
  `custom_bottom_nav.dart`, unnecessary underscores in
  `trending_destinations_section.dart`, unused import in
  `discard_changes_dialog_widget.dart`. No diagnostics were suppressed.
- Final discovery/public-profile/follower UI tests: **43 passed, zero failed**.
- Broader Chat/Profile/follow/block/search/comments/Notifications/push/Home/Buddies
  regressions: **829 passed, two known Search failures** (run before the final two
  additional navigation/race tests).
- Full suite: **1682 passed, five known failures**: Search small-screen overflow,
  Search SVG size expectation, and the three Story Viewer reply-composer tests
  (row controls, typing pause/resume and keyboard dismissal). No new failures.
  The final profile refresh coalescing adjustment was covered by the repeated
  43-test focused run; the full suite preceded that small adjustment.
- Final iOS Simulator Debug build succeeded in **37.9 seconds** with
  `com.travibe.app`. No app launch or manual Simulator interaction was performed.
- Native Firebase remains 12.19.3 and Google Sign-In 9.2.0; FlutterFire remains
  firebase_core 4.15.2 / firebase_messaging 16.7.1.
No authenticated live search, conversation creation, follow/remove/report/block,
or real-time delivery was tested. Documentation credentials do not authorize
mutating real accounts. Firebase versions, SwiftPM, Bundle ID and Laravel auth
are unchanged. No Reverb deployment work was performed.

## Files created and modified

Created:
- `lib/features/chats/cubit/chat_discovery_cubit.dart`
- `lib/features/chats/screens/chat_navigation.dart`
- `lib/core/widgets/user_profile_link.dart`
- `lib/features/profile/widgets/other_profile_actions.dart`
- `test/features/chats/chat_discovery_test.dart`
- `test/features/profile/other_user_profile_test.dart`
- `test/features/profile/other_profile_contract_test.dart`
- `docs/OTHER_USER_PROFILE.md`

Functional integration changes:
- `lib/features/chats/screens/new_conversation_screen.dart`
- `lib/features/chats/screens/chats_screen.dart`
- `lib/features/chats/screens/conversation_screen.dart`
- `lib/features/profile/screens/profile_screen.dart`
- `lib/features/profile/cubit/profile_cubit.dart`
- `lib/features/profile/data/profile_repo.dart`
- `lib/features/follow/cubit/follow_cubit.dart`
- `lib/features/follow/cubit/follow_users_cubit.dart`
- `lib/features/follow/data/follow_repo.dart`
- `lib/features/follow/screens/follow_users_screen.dart`
- `lib/features/follow/widgets/follow_user_tile.dart`
- `lib/features/search/data/search_repo.dart`
- `lib/features/search/data/users_page_model.dart`
- `lib/features/search/screens/search_screen.dart`
- `lib/features/comments/screens/comments_screen.dart`
- `lib/features/comments/widgets/comment_row.dart`
- `lib/features/home/screens/home_screen.dart` (Chat route scope only)
- `lib/features/home/widgets/suggested_user_card.dart` (profile link only)
- `lib/core/widgets/post_card.dart` (author profile links only)
- `lib/core/models/public_user_model.dart`
- `lib/core/datasource/remotedata/api_service.dart` (session revision on user/search/report requests)
- `pubspec.yaml` (existing SVG directory registration; no dependency changes)
- `test/features/profile/profile_followers_account_ui_test.dart` (expect authoritative list total)
- `docs/FIGMA_REFERENCE.md`

A formatting pass also normalized whitespace in these existing profile files,
with no behavior edits: `screens/privacy_policy_screen.dart`,
`screens/terms_of_service_screen.dart`, `widgets/about_section.dart`,
`widgets/discard_changes_dialog_widget.dart`, `widgets/hotel_card.dart`,
`widgets/language_bottom_sheet.dart`, `widgets/profile_avatar.dart`,
`widgets/profile_post_card.dart`, and `widgets/profile_saved_sub_tabs.dart`.
Paths in this paragraph are relative to `lib/features/profile/`.

`git status --short` could not run because this workspace has no Git metadata.
No reset, revert or commit was performed. Existing files were edited in place;
no previous feature implementation was replaced.

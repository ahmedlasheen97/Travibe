# Profile Stage 3 — Saved Posts

## Verified contract and implementation plan

Inspected PostsRepo, PostsCubit, PostModel, shared PostCard, the existing static
bookmark, ProfileScreen/Saved tabs, ProfileCubit, Profile Stage 1/2 documentation,
PreferencesManager/logout/auth token writes, and docs/openapi.json before editing.
There was no existing save mutation controller or Saved-list API implementation
to reuse. The existing post models, repository, authenticated ApiService/DioClient,
ApiError conversion and interaction widgets are reused.

The Stage 3 plan is now implemented with the confirmed endpoints, relative to
https://travibeapp.com/api/v1/:

| Operation | Confirmed contract | Implementation |
| --- | --- | --- |
| Save | POST posts/{integer post}/save, no request fields required. Returns top-level is_saved:true and message:string. Idempotent. | PostsRepo.setSaved(id,true) sends an empty JSON object through existing ApiService.post and requires a boolean true confirmation. |
| Unsave | DELETE posts/{integer post}/save, no request body. Returns top-level is_saved:false and message:string. Idempotent. | PostsRepo.setSaved(id,false) uses existing ApiService.delete and requires a boolean false confirmation. No save-record ID is involved. |
| Saved list | GET users/me/saved, authenticated, visibility/block filtered, most recently saved first. per_page 1–100, default 15. Paginated PostResource data, links and meta. | PostsRepo.getSavedPosts reuses PostModel/PostsPageModel with an isolated validated Saved paginator adapter. |

OpenAPI says these operations require a full-access bearer token and verified
email. Save may return 403 for visibility, 404 for a missing post, and its prose
also describes 422 for a block relationship; 401 applies to authentication.
Unsave also enforces visibility. Existing ApiError status/message handling is
preserved for 401/403/404/422 and network/timeouts. A failed or malformed mutation
never changes the bookmark. The response message is not needed for success UI;
only the authoritative is_saved boolean is consumed. There is no invented data
envelope around mutation responses.

## Saved response mapping and pagination

The checked-in OpenAPI declares:

- data: array of PostResource objects, reused as PostModel.
- links: first, last, prev and next, each string or null.
- meta: integer current_page, last_page and total, plus the documented Laravel
  paginator fields from, to, per_page, links and path.

The adapter validates the envelope and consumed pagination fields, requested page,
positive integer post IDs, user resources, and any supplied is_saved flag. Invalid
responses become ApiError rather than a false empty list. Optional viewer flag
absence does not mean unsaved: membership in this authenticated endpoint itself
confirms saving. A contradictory supplied is_saved:false is rejected.

Pagination uses the same numeric page/per_page mechanism already used by the
existing feed repository. OpenAPI explicitly lists per_page and describes the
paginator, but does not separately list page as an operation parameter. The
paginator convention is reused; deployed next-page behavior still needs a live
check. No arbitrary response URL is followed with the bearer token.

SavedPostsCubit owns independent items, current page, request generation and
errors. Initial loads coalesce; Load more prevents parallel page requests,
deduplicates by post ID while retaining endpoint order, and stops when current
page reaches last page. Pagination failures retain items and retry the same page
explicitly. Refresh replaces membership and invalidates older page requests.
Transient refresh errors retain current-account items; 401/403 clear the list.

## Save synchronization and UI

Root owns one SavesCubit for bookmark truth and one SavedPostsCubit for Saved
membership/pagination. Explore and Following retain separate PostsCubit instances
and accept the shared SavesCubit through an optional dependency. PostModel.isSaved
is preserved, with an additive hasSaveState flag to avoid guessing toggle direction
when viewer state is missing from a feed resource.

SavesCubit permits one mutation per post at a time. The original state remains
visible while pending; the button is disabled. Only a matching confirmed result
changes the value. Per-post mutation revisions prevent older feed/list snapshots
from overriding a confirmed bookmark. Failures show backend-friendly feedback
and release the pending guard for retry. There is no optimistic save or automatic
mutation retry.

The existing PostCard bookmark is now interactive, using the existing outline
archive.svg for unsaved and filled archive 2.svg for saved. Its SVG remains 20px;
semantics/tooltip and a button hit target were added. Like/Comment/Share controls
and their backend implementations are unchanged. The existing LikesCubit is
provided at Root and borrowed by Home and Saved cards so those cards reuse the
same Like state instead of creating a second app-level instance.

Profile's existing Saved > Posts placeholder is replaced with real PostCards,
loading, empty/error/retry states, Load more and the existing pull-to-refresh
gesture. Confirmed Unsave removes the item immediately, then refreshes endpoint
membership/order to reset shifted pagination offsets. A Save elsewhere refreshes
an already loaded Saved list; it never inserts a feed snapshot into Saved. Only
records returned by GET users/me/saved populate the list.

Saved cards reuse existing Likes, CommentsScreen and SendPostSheet entry points.
No Like/Comment/Share endpoints or unrelated Home widgets were changed. Sharing
never creates a repost. Saved counts/content come from the existing post model.

Saved is hidden on all public-profile routes, including a public response with
is_me:true. Root/pushed own-profile routes reuse inherited controllers;
BlocProvider.value does not dispose borrowed instances. Standalone own-profile
screens create local controllers only when none exist above them.

Confirmed block state filters Saved immediately, including blocked original-post
authors, and refreshes membership after block/unblock. Existing FollowCubit and
BlockCubit implementations are unchanged. Hidden-post filtering is deliberately
not applied: OpenAPI explicitly says hiding does not affect Saved membership.

The existing Profile Posts tab still has Stage 1's unloaded placeholder; no
profile-post endpoint is invented in this stage. Any future profile-post
PostsCubit can accept the same shared SavesCubit. Saved Hotels remains unchanged.
Existing dark theme, Plus Jakarta Sans, Profile tabs and layout are preserved.
Figma access remains unverified as documented in FIGMA_REFERENCE.md; no Figma was
modified and no new screen design was invented.

## Account/session safety

PreferencesManager now exposes a token-change revision/listener. init, saveToken,
generic token writes/removal and clear/logout update that session signal. Token
values are never exposed in logs or Cubit state. Dio still uses the existing
bearer interceptor, reading the current session token.

A token change clears bookmark values/pending flags and Saved items/pagination,
and invalidates old reads/mutations. Old completions cannot populate the new
session or clear a new request's pending flag. Existing feed bookmark snapshots
are invalidated as well. The owning Profile loader is keyed to the session, so
its old identity and open Saved tab do not carry into another account. Stage 2
edit routes referencing a disposed old owner cannot submit through it.

No backend mutation is made merely by opening Saved or rendering a bookmark.
No other account's Saved endpoint is used. Closing controllers cancels listeners
and prevents in-flight response emissions.

## Files changed

| File | Change |
| --- | --- |
| lib/core/datasource/localdata/preferences_manager.dart | Token-change/session notifications and current token cache. |
| lib/core/widgets/post_card.dart | Existing bookmark action, confirmed state, pending guard, SVG variants/semantics. |
| lib/features/home/data/posts_repo.dart | Save/Unsave and authenticated Saved GET operations. |
| lib/features/home/data/post_model.dart | Preserve isSaved and add explicit viewer-state presence. |
| lib/features/home/cubit/posts_cubit.dart | Shared save snapshot acceptance, cross-feed updates and session/request guards. |
| lib/features/home/screens/home_screen.dart | Wire bookmark action and borrow shared Saves/Likes controllers. |
| lib/features/profile/screens/profile_screen.dart | Private Saved integration, scoped controllers, refresh and session-aware owner loading. |
| lib/features/saved/data/saved_posts_page.dart | Validated documented Saved paginator adapter. |
| lib/features/saved/cubit/saves_cubit.dart | Confirmed mutation state, duplicate prevention and revisions/session isolation. |
| lib/features/saved/cubit/saved_posts_cubit.dart | Independent Saved list, pagination, refresh, block/session filtering. |
| lib/features/saved/widgets/saved_posts_sliver.dart | Existing PostCards inside the existing Profile scroll view. |
| lib/root.dart | Own and provide shared Saves/Saved-list/Likes controllers. |
| test/features/saved/fixtures.dart | Synthetic documented post/paginator fixtures and controllable repository. |
| test/features/saved/saved_posts_test.dart | Repository, mutations, pagination, synchronization, stale/block/session tests. |
| test/features/saved/saved_posts_widget_test.dart | Bookmark SVG/action, confirmation/errors, actual Saved UI, refresh/privacy/logout tests. |
| docs/PROFILE_STAGE3.md | This implementation report and updated plan. |

No Laravel, Figma, assets, dependencies, native configuration, Profile editing
implementation, Follow/Block implementation, or Likes/Comments/Share source files
were modified. All pre-existing tests remain unchanged.

## Verification — 2026-10-19

- Targeted Dart analysis: no issues found across changed sources, new Saved tests,
  all Profile tests and existing Posts repository/Cubit tests.
- Standard flutter test --no-pub was attempted for Saved/Profile/Posts. The
  sandbox denied localhost socket binding before tests loaded.
- The actual test files were compiled and executed with the existing no-socket
  Flutter frontend-server/flutter_tester harness, VM service disabled:
  123 passed, 0 failed in the completed run. This includes 24 new Saved tests,
  all 42 Profile Stage 1/2 tests and relevant Posts, Home, hidden-post,
  Like/Comment interaction and Share synchronization regressions.
- One pre-existing Home test failed on the first broad attempt: “zero relationship
  state uses SVG without fake story avatars and opens discovery”. It expects an
  SvgPicture, while the unchanged FollowingEmptyState currently uses Image.asset
  (its SVG is commented out). That test alone was excluded from the completed
  harness run; it and its UI were not changed. This is not an all-suite pass.
- Temporary harness and logs: /private/tmp/travibe-stage3-*.

Coverage includes Save/Unsave success/failure, confirmation parsing, HTTP errors,
duplicate prevention, real Saved rendering, empty/error/retry, pagination/refresh,
cross-feed state, stale page/read protection, block/unblock, controller disposal,
logout/account switching, and SVG/pending action behavior.

No live backend requests or physical-device tests were run. Remaining manual
checks: verified-account Save/Unsave persistence, actual next-page behavior,
visibility/block errors, account switching/logout on device, and long Saved lists
with real media. Response envelopes used in tests are synthetic fixtures based
on the documented schemas, not captured production responses.

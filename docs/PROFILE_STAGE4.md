# Profile Stage 4 — Profile Posts

## Implementation and verified API

The existing Profile Posts placeholder now loads server-side author listings:

GET /api/v1/posts?user_id={integer}&page={page}&per_page={perPage}

PostsRepo.getUserPosts validates positive user/page IDs and per_page 1–100
(default 15), uses the existing authenticated/optional-bearer ApiService/DioClient,
and preserves ApiError status/message handling. It requires data/links/meta,
validates the consumed paginator fields and post IDs, and rejects a mismatched
author response instead of constructing a list by filtering another feed.
Existing Explore/Following paths, parameters and repository methods are unchanged.

PostResource objects reuse PostModel and PostsPageModel. Current/last page and
total come from meta. Optional viewer flags keep their existing presence guards:
unknown Like/Save state cannot be used to guess a mutation direction. An additive
hasCommentCount flag prevents absent comment counters from overwriting a known
shared count. No user-post endpoint, sort parameter or mock data was introduced.

## Owner/public scope and lifecycle

PostsCubit gains an optional immutable userId. Null retains existing feed mode;
a supplied author ID selects getUserPosts. Each Profile owns an independent
PostsCubit, with its own items, page, request generation, errors and subscriptions.
ProfilePostsScope keeps that cache alive when switching Posts/About/Saved tabs.

- Owner mode obtains the integer ID from the authenticated ProfileModel returned
  by GET /profile; it does not assume an ID from a separate logged-in-user cache.
- Public mode uses ProfileScreen.userId, never the authenticated owner's ID.
- Author loaders are created only after ProfileLoaded. data:null/unavailable,
  profile failures and confirmed local blocks remove/dispose the loader and UI.
- Switching target profiles or sessions keys a new Profile loader. Old requests
  cannot publish rows or shared interaction snapshots after disposal.
- Session changes clear pending author state without automatically querying the
  former owner's ID as though it belonged to the new account. The new Profile
  response determines the new owner query. Public routes also reload viewer-aware
  profile state when a token changes, including login/logout.
- Confirmed blocks filter authors and recursively blocked original-post authors.
  Author unblocking revalidates membership. Existing Follow/Block classes remain
  unchanged; following the selected author refreshes follower-visible membership.

## Pagination, refresh and errors

Initial loads and repeated ordinary refreshes coalesce. Load more prevents
parallel pagination, requests the next page, merges duplicate post IDs, and stops
at last_page. Refresh replaces membership and invalidates older pagination.
Pagination errors keep rows and retry the same page explicitly. Transient refresh
errors retain current rows with retry feedback; author-list 401/403/404 clears
cached rows into failure. Network exceptions reuse the existing friendly mapper.
Controller closure invalidates generations before awaiting subscription cleanup.

The existing CustomScrollView/RefreshIndicator contains ProfilePostsSliver:
loading, empty/error/retry, existing PostCards and Load more. Pull-to-refresh on
Posts refreshes Profile metadata and that author list. About and Saved retain
their existing refresh behavior. Header, About, Edit Profile, tabs, dark colors
and Plus Jakarta Sans are preserved. Public routes never expose Saved or Edit.

Figma access remains unverified as recorded in FIGMA_REFERENCE.md. Existing
widgets/layout are reused; there was no Figma modification or new screen design.

## Interaction synchronization

Root now provides existing SharesCubit and HiddenPostsCubit alongside shared
LikesCubit/SavesCubit. Home borrows them and registers its existing feed Cubits
with HiddenPostsCubit; standalone/test screens retain owned fallbacks. Route
navigation forwards borrowed controllers with BlocProvider.value. Disposal only
closes owned controllers and unregisters feeds.

Profile cards reuse existing Like toggles, CommentsScreen, SendPostSheet,
FollowActionBuilder, PostOptionsSheet and block confirmation. Native/external
sharing still does not create a backend repost. Own-card delete/restore actions
are not added. Public-profile options expose existing Hide/Block operations only.
Hide updates registered Home feed caches and offers Undo; author listings ignore
hidden-post filtering and keep the card visible, as required by the API.

PostActivityCubit provides session-scoped authoritative comment counts and
publication notices. Existing post creation success in Root emits a publication
notice in addition to its existing Home refresh signal. Only matching author
scopes refresh; unrelated public profiles and Saved membership are not globally
reloaded. The matching Profile metadata refreshes so header counts remain
server-derived rather than incremented locally.

Explore, Following and Profile post Cubits accept shared interaction snapshots
with request revisions and apply later confirmed updates. Shared PostCard receives
a post ID so comment/share counts update consistently. Comment changes in Saved
also publish the same authoritative count. Stale or missing counters cannot
replace a newer confirmed count.

Saved Posts endpoints, membership, parser, loading, pagination and refresh rules
are preserved. Its only integration changes are optional shared Like/Share/comment
snapshot acceptance and passing post identity/comment changes to existing shared
controllers; there is no replacement Saved list or new Saved data source.

Hidden mutation state now supports feed registration and ignores results from a
previous session, so sharing its existing controller does not publish an old
account's hide result into current feeds.

## Delete/restore integration points — deliberately not implemented

No post delete/restore repository methods, buttons, trash UI or mutation feature
were added. Existing Profile owner post options had no working delete/restore
behavior requiring implementation. The following is required when that feature
is authorized:

1. After confirmed DELETE posts/{post}, invalidate affected list request
   generations and remove every cached occurrence from author/feed/Saved lists.
   Use a per-post deletion tombstone so older pages cannot reinsert it. Refresh
   affected author metadata/counts and membership, without reloading unrelated
   profiles. Existing hide state is not a substitute for deletion.
2. Clear the post's shared interaction state and invalidate pending mutations:
   Like state (LikesCubit.reset exists), comment counts, share ownership/counts,
   bookmark state and hidden state. Post-specific invalidation hooks still need
   to be added where absent. Deletion permanently removes these backend records.
3. After confirmed POST posts/{post}/restore, parse its data:PostResource and use
   the returned resource/counts with a new mutation revision. Refresh affected
   author-list membership/order and appropriate feeds. Do not restore removed
   comments, likes, shares, saves or hides from client snapshots; do not insert
   the restored post into Saved without a new confirmed Save.
4. Refresh Profile metadata from its endpoint. Do not derive header counts from
   a public viewer's visibility-filtered list total.

These are documented integration requirements, not claims of working deletion
or restoration synchronization. The restore-window duration, deleted-post listing
and author sort/pinning rules remain unspecified; this stage does not invent them.

## Files changed

| File | Change |
| --- | --- |
| lib/features/home/data/posts_repo.dart | Focused verified getUserPosts query and response guards. |
| lib/features/home/data/post_model.dart | Explicit comment-count presence for safe shared snapshots. |
| lib/features/home/cubit/posts_cubit.dart | Independent optional author mode, shared comments, hidden exclusion, session/disposal guards. |
| lib/features/home/cubit/post_activity_cubit.dart | New focused comment-count/publication synchronization. |
| lib/features/home/cubit/hidden_posts_cubit.dart | Reuse controller across routes with registered Home feeds/session guards. |
| lib/features/home/screens/home_screen.dart | Borrow shared controllers and pass post identity/activity. |
| lib/core/widgets/post_card.dart | Optional post identity/shared comment/share count display; layout retained. |
| lib/root.dart | Shared providers and confirmed publication notification. |
| lib/features/profile/screens/profile_screen.dart | Author scope, Posts content, refresh and viewer/session lifecycle. |
| lib/features/profile/widgets/profile_posts_scope.dart | Scoped cache and existing follow/block/publication subscriptions. |
| lib/features/profile/widgets/profile_posts_sliver.dart | Existing cards/interactions and author pagination UI. |
| lib/features/saved/cubit/saved_posts_cubit.dart | Optional shared interaction snapshot bridge only. |
| lib/features/saved/widgets/saved_posts_sliver.dart | Post identity/shared comments and disposed-callback guard only. |
| test/features/profile/fixtures.dart | Empty author repository for existing isolated Profile tests. |
| test/features/profile/profile_screen_test.dart | Inject author repository and expect real empty Posts state. |
| test/features/saved/saved_posts_widget_test.dart | Isolate new author loading while preserving Saved assertions. |
| test/features/profile/profile_posts_fixtures.dart | Synthetic author resources and controlled profile/author repositories. |
| test/features/profile/profile_posts_test.dart | Author contracts, pagination, errors, stale/session/count synchronization. |
| test/features/profile/profile_posts_widget_test.dart | Owner/public views, target changes, blocks, creation and actual actions. |
| docs/PROFILE_STAGE4.md | This implementation and verification report. |

No Laravel, Figma, assets, dependencies, native code, Profile editing implementation,
Follow/Block implementation, or Likes/Comments/Share backend implementation changed.
The existing Home stories/discovery widgets and unrelated Profile settings are
unchanged. No tests or dependency packages were removed.

## Verification — 2026-10-19

- Targeted Dart analysis of changed sources and Profile/Saved tests: no issues found.
- Standard flutter test --no-pub was attempted for Profile, Saved and PostsCubit.
  The sandbox denied localhost socket binding before tests loaded.
- The actual test files ran through the existing no-socket frontend-server /
  flutter_tester harness, VM service disabled: 144 passed, 0 failed in the
  completed run. This includes all 21 new Profile Posts tests, 42 existing/updated
  Profile Stage 1/2 tests, all 24 Saved tests, and relevant Home/Posts/hidden-post/
  Like/Comment/Share interaction regressions.
- The single known pre-existing Home test expecting an SvgPicture in
  FollowingEmptyState remains excluded, as in Stage 3. That unchanged widget uses
  Image.asset instead. No unrelated UI/test fix was made; this is not a complete
  app-wide test-suite pass.
- Logs/harness: /private/tmp/travibe-stage4-*.

Focused coverage includes correct owner/public author IDs, query serialization,
optional flags, malformed/cross-author responses, independent caches, loading,
pagination/refresh/error/retry, stale requests, profile switching, unavailable/
blocked profiles, logout/account switching, publication targeting, same-post
interaction synchronization across all four list types, and disposal.

No live backend or physical-device validation was run. Fixtures are synthetic
contract-shaped resources, not captured production data. Manual checks remain:
author pagination with real media/reposts, guest/follower/private visibility,
public profile blocks, native share presentation, and profile creation refresh
on iOS/Android. Delete/restore remains a future feature as requested.

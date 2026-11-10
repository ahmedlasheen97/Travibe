# Laravel cursor pagination migration

Implemented 2026-10-29 using the supplied eight-endpoint contract. No live
Laravel verification was performed. Tests use mocked authenticated API responses.

## Endpoint status

All paths below are relative to `/api/v1/`.

| GET endpoint | Status and consumer |
| --- | --- |
| `feed/following` | Migrated: PostsRepo / Following PostsCubit / Home infinite scrolling |
| `feed/explore` | Migrated: PostsRepo / Explore PostsCubit / Home infinite scrolling |
| `posts` | Migrated: listPosts for unscoped reads; getUserPosts preserves user_id; profile PostsCubit |
| `posts/{post}/likes` | Migrated: LikesRepo.list; cursor-scoped LikesUsersCubit adapter |
| `posts/{post}/comments/{comment}/likes` | Migrated: LikesRepo.list with comment target; LikesUsersCubit adapter |
| `stories/{story}/likes` | Added cursor-ready LikesRepo.listStory and LikesUsersCubit.story; no existing Story likes-list consumer was present |
| `posts/{post}/comments` | Migrated: CommentsRepo / CommentsCubit, including existing parent_id reply filtering |
| `notifications` | Added cursor-ready NotificationsRepo / NotificationsCubit; no existing notification list/read-action UI was present |

The notification icon in Home still has its existing placeholder callback.
There was no Notifications repository, model, state manager, mark-as-read flow or
navigation to preserve. Notification fields are retained as immutable outer maps;
IDs may be nonempty strings or positive integers for deduplication. No unread,
mark-as-read or navigation field mapping/mutation endpoint was invented. Those
future UI features require a verified notification resource/action contract and
approved design. Existing like mutations/buttons remain unchanged; the new likes
list state is separate from offset-paginated Follow/Search state.

## Root cause and response contract

Following previously sent `page: 1` and subsequent offset page numbers. Laravel
now rejects any `page` parameter with HTTP 422. Its response also no longer
provides current_page, last_page or total for these eight paths.

Initial reads now send only the existing scope/filter parameters and per_page:

```text
GET feed/following?per_page=15
GET posts?user_id=23&per_page=15
```

Continuation reads add the exact opaque `meta.next_cursor` string:

```text
GET feed/following?per_page=15&cursor={opaque_backend_cursor}
GET posts?user_id=23&per_page=15&cursor={opaque_backend_cursor}
```

Dio performs query encoding. Production code never constructs, decodes, trims,
increments or derives cursors from item IDs/page numbers. Initial reads omit
cursor entirely. None of the eight GET paths sends page.

The typed `CursorPaginationMeta` validates:

```json
{
  "path": "https://travibeapp.com/api/v1/feed/following",
  "per_page": 15,
  "next_cursor": "opaque string or null",
  "prev_cursor": null
}
```

Both cursor keys must be present and contain null or a nonempty string. The path
is metadata only, never a navigation URL or request target. Invalid metadata
(including offset-only meta) is a visible error, not a fabricated exhausted page.
No total/last-page count is inferred. CursorPage parses typed data plus this meta.
Links are not required or used for these migrated paths.

PostsPageModel retains its existing offset fields/factory for compatibility with
Saved posts. Feed and author repositories explicitly use fromCursorJson and their
Cubits use only cursor metadata. CommentsPage and CommentThreadState now use
cursor metadata instead of page numbers. UsersPageModel remains offset-only for
unchanged Follow/Search consumers.

## Cursor lifecycle and isolation

- CursorProgress belongs to one feed, author, comment thread or list target.
  Next cursor becomes null on exhaustion. It tracks successfully consumed cursors
  and stops direct repetition and longer cycles, including empty responses.
- Initial and continuation payloads deduplicate by existing resource ID. Matching
  IDs update in place while new IDs append in server order. Empty pages with a
  new cursor can be continued; repeated cursors stop. No automatic retry loop is
  introduced.
- One initial/refresh request and one continuation request per scope can run.
  Duplicate requests coalesce or are suppressed. Refresh supersedes an in-flight
  continuation by changing the generation; old successes/errors cannot replace
  the refreshed state.
- Refresh always requests without cursor. Progress is replaced on successful
  refresh; a failed refresh retains the old rows/position for explicit retry.
  Successful refresh clears the consumed-cursor history.
- Home activates a tab with a fresh cursorless traversal. Explore/Following still
  own independent PostsCubits and retain separate interaction state. Following's
  existing post-follow-mutation revalidation behavior remains intact.
- Profile author, feed type and likes target are immutable Cubit scopes. A new
  author/target creates a fresh instance. Existing author user_id and comment
  parent_id filters are retained on every continuation and retry.
- Each comment/reply thread has its own progress/history and generation. Replies
  already used GET posts/{post}/comments with parent_id, so that same endpoint is
  migrated. No separate replies endpoint was assumed or changed.
- Failed continuations preserve rows, cursor and page size; pagination stops until
  explicit retry. Cursor advances only on accepted success. Existing refresh,
  error, skeleton and retry presentations are reused without redesign.
- Session listeners clear cached rows/cursors, invalidate old requests and remove
  old request locks. Comment mutation/count synchronization also discards work
  crossing an authentication change. Existing post reactions, follow/block,
  deletion/restore, bookmark and comment-count synchronization are preserved.
- prev_cursor is parsed and retained; no unnecessary backward-navigation UI was
  added. Repositories can accept that exact cursor if a future verified UI needs it.

## Offset APIs deliberately unchanged

The audit found offset pagination in Buddies page/link handling, user Search,
Follow lists, Block lists, post shares, Saved posts, Stories collections and Story
viewers. None is included in the eight-endpoint change, so their wire contracts
remain unchanged. Home's account fallback reads total from following-list, which
is also unrelated and remains intact. Photon and Profile Setup were not modified.

The remaining page/current_page/last_page/total references in PostsRepo and
PostsPageModel are solely the unchanged users/me/saved request and offset model
compatibility. No migrated feed/author/comment/likes/notification consumer reads
offset metadata. No server endpoint, VS Code configuration, bottom navbar or
visual design was changed.

## Verification

- Final focused run: **326 tests passed**, including cursor migration, Home,
  comments/replies/mutations/counts, post/comment likes, profile posts, Saved,
  block/feed synchronization, shares and post creation.
- Broader regression run: **925 passed, 7 failed**. Failures were outside this
  migration: four Edit Profile widget tests fail before rendering because
  ScreenUtil is not initialized; three Story other-user viewer tests have existing
  UI/SVG/composer assertion mismatches. Those production features/tests were left
  unchanged. This broader run preceded the final tab-reset test; the final focused
  run includes and passes that new tab-reset behavior. Counts overlap and must not
  be summed.
- Targeted analysis of the migrated production code and affected tests: **no
  issues found**. Targeted Dart formatting completed.
- A stale Home empty-state regression assertion expected an SVG, while the
  checkout's existing widget renders image 50.png. The test now checks that exact
  existing asset; no empty-state UI was changed.
- No live Following/Explore requests, account mutations or device claims are made.
  An authenticated live test session was not supplied for this migration.

New tests explicitly guard all eight request paths against page (mock HTTP 422),
assert initial cursor omission and exact continuation values (including special
characters), terminal null, empty data, metadata errors, deduplication, retry,
refresh races, concurrent requests, repeated-cursor loops, independent feeds and
authors, reply filters, notification fields and authentication changes. Broad
Buddies/Photon, Follow/Block, navbar, Stories and Saved regressions exercise the
unchanged offset contracts.

Commands (run from the repository root):

```sh
# Format only files listed below, using dart format <affected Dart paths>.
flutter analyze --no-pub lib/core/models/cursor_pagination.dart lib/core/cubit/cursor_list_cubit.dart lib/features/home/data lib/features/home/cubit/posts_cubit.dart lib/features/home/screens/home_screen.dart lib/features/comments lib/features/likes lib/features/notifications test/core/pagination test/helpers/cursor_fixtures.dart test/features/home test/features/comments test/features/likes test/features/profile test/features/block/block_feed_sync_test.dart test/features/saved test/features/shares test/features/create_post
flutter test --no-pub test/core/pagination test/features/home test/features/comments test/features/likes test/features/profile/profile_posts_test.dart test/features/profile/profile_posts_widget_test.dart test/features/saved test/features/block/block_feed_sync_test.dart test/features/shares test/features/create_post --reporter expanded
# Broader run (includes the seven unrelated failures described above):
flutter test --no-pub test/core/pagination test/features/home test/features/comments test/features/likes test/features/profile test/features/saved test/features/block test/features/follow test/features/shares test/features/stories test/features/create_post test/features/buddies test/core/places test/core/widgets/liquid_glass_bottom_nav_test.dart --reporter expanded
```

## Manual verification checklist

1. Use a verified-email authenticated account. Inspect Following and Explore
   requests: first query has per_page without page/cursor; subsequent queries
   contain the exact previous response's next_cursor. Confirm no 422 offset error.
2. Scroll multiple times, confirm ordering/deduplication and stop at null cursor.
   Switch tabs rapidly, revisit each tab and pull to refresh; each activation/
   refresh starts without a cursor and never mixes data from the other feed.
3. Open two different authors. Verify user_id remains attached to initial,
   continuation and retry queries. Exercise visibility restrictions and deletion.
4. Open comments/replies; check parent_id and independent thread continuation.
   Create/edit/delete/restore comments and verify server-backed counts and likes.
5. Toggle post/comment/Story reactions, follow/unfollow and block a user; verify
   state synchronization and filtering are unchanged. Check Saved and Buddies
   continuation still follow their original contracts.
6. Simulate offline/422/5xx continuation errors using mocks or controlled tooling;
   retry must retain cursor/scope. Test logout/account switching during a request.
   A repeated cursor must terminate further pagination without a request loop.
7. When actual likes-list/notification UI is implemented, wire its immutable scope
   to the cursor list adapter. Confirm notification payload/unread/navigation and
   mark-as-read contracts before adding those behaviors. No speculative mutation
   endpoints are included in this migration.

## Files created

- lib/core/models/cursor_pagination.dart
- lib/core/cubit/cursor_list_cubit.dart
- lib/features/likes/cubit/likes_users_cubit.dart
- lib/features/notifications/data/notifications_repo.dart
- lib/features/notifications/cubit/notifications_cubit.dart
- test/core/pagination/cursor_migration_test.dart
- test/helpers/cursor_fixtures.dart
- docs/CURSOR_PAGINATION_MIGRATION.md

## Files modified

Production:

- lib/features/home/data/posts_repo.dart
- lib/features/home/data/posts_page_model.dart
- lib/features/home/cubit/posts_cubit.dart
- lib/features/home/screens/home_screen.dart (tab activation request lifecycle only)
- lib/features/comments/data/comment_model.dart
- lib/features/comments/data/comments_repo.dart
- lib/features/comments/cubit/comments_cubit.dart
- lib/features/comments/cubit/comments_state.dart
- lib/features/likes/data/likes_repo.dart

Tests and dependent fixtures:

- test/features/home/posts_repo_test.dart
- test/features/home/posts_cubit_test.dart
- test/features/home/hidden_posts_cubit_test.dart
- test/features/home/home_experience_test.dart
- test/features/home/home_experience_fixtures.dart
- test/features/home/post_card_follow_style_test.dart
- test/features/comments/comments_repo_test.dart
- test/features/comments/comments_cubit_test.dart
- test/features/comments/fixtures.dart
- test/features/comments/comment_count_sync_test.dart
- test/features/likes/likes_repo_test.dart
- test/features/likes/likes_sync_test.dart
- test/features/profile/profile_posts_test.dart
- test/features/profile/profile_posts_fixtures.dart
- test/features/profile/fixtures.dart
- test/features/saved/fixtures.dart
- test/features/block/block_feed_sync_test.dart
- test/features/shares/shares_sync_test.dart
- test/features/shares/share_post_dialog_test.dart
- test/features/create_post/create_post_screen_test.dart

Fixture ordinal-to-token tables emulate the mock server only; production does
not contain those token values or translate cursors to page numbers.

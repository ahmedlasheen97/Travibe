# Stories Stage 6 — Story Management

2026-10-22. Incremental review and pagination fix; existing Story Viewer design,
Editor/publishing, Profile, Buddies, native and VS Code configuration are unchanged.

## Features already implemented and retained

- Authenticated repository DELETE `stories/{id}`, owner-only glass menu, black
  action sheet and explicit Cancel/Delete confirmation. Ownership requires both
  `is_mine` and the current authenticated integer user ID.
- Playback pauses throughout sheets, confirmation and deletion. Duplicate deletes
  are suppressed. Content remains visible until confirmed backend success; failures
  preserve it and display feedback. Unauthorized/public viewers cannot delete.
- Successful deletion removes the current item, advances to the next remaining
  story/loaded author or finishes the viewer, and calls Home's `confirmedDelete`.
  Home reconciles cached groups, refreshes and retains a deletion tombstone against
  stale responses. Removing the last own story dismisses the popup and restores
  direct Add Story behavior. No optimistic deletion was introduced.
- An ambiguous deletion failure is not treated as success. Explicit retry first
  checks GET detail: 404 reconciles absence without a repeated DELETE; an existing
  story permits the explicitly requested retry. Session/disposal guards prevent
  old account responses from mutating the current screen.
- Owner-scoped viewers list with strict parsing, independent page cursor, deduped
  user IDs, refresh, load more, empty/loading/error/retry and revoked-access clearing.
  Blocked IDs are filtered on block changes and after asynchronous page completion.
- Existing shared FollowCubit, FollowActionBuilder and neutral FollowPill retain
  follow/unfollow synchronization and duplicate guards. Row menus expose only the
  implemented block action with existing confirmation/BlockCubit. API `has_liked`
  alone controls the heart indicator. No synthetic viewer records or actions.
- Existing eye.svg, centered drag handle, left-aligned header/subtitle, gray pills,
  vertical dots, glass controls, playback, overlays and tracking are unchanged.

## Contract verification and limits

The checked local `docs/openapi.json` contains no `/stories` paths. No new sanitized
runtime capture/specification is available, and inaccessible backend URLs were not
retried. Contracts below are from the earlier user-supplied Stage 5B documentation;
this is not a claim of fresh deployed API verification.

| Operation | Supplied contract used by existing code |
| --- | --- |
| DELETE `/api/v1/stories/{story}` | Owner-only; HTTP 200 with string `message`; no request body |
| GET `/api/v1/stories/{story}/viewers` | Owner-only; `page`, `per_page` (existing default 15); HTTP 200 with `data: Viewer[]`, `links`, `meta` |
| Viewer identity/profile | Positive integer `id`, string `name`; nullable string `username`, `country_code`, `avatar_url`; required timestamp `viewed_at` |
| Viewer relationships | Boolean `is_following`, `follows_you`, `has_liked` |
| Pagination | Integer `current_page`, `last_page`, `per_page`, `total`; nullable string `first`, `last`, `prev`, `next` links |

Existing ApiExceptions handles authentication/403/404/timeout/network failures;
repository tests verify error status preservation. Exact endpoint-specific error
body schemas, deployed pagination bounds and **most-recent-view ordering are not
provided**. Preserve server order rather than sorting/inventing an ordering rule.
Backend authorization must still be checked with owner/non-owner credentials on a
device; client ownership guards do not replace server enforcement.

## New change

`StoryViewersCubit.refresh` previously returned early whenever any request was
loading. Pull-to-refresh during pagination therefore did nothing. Refresh now
supersedes a pending page with a new first-page generation, while a dedicated
refresh guard prevents duplicate first-page requests. Old pagination success or
failure cannot append rows, change the cursor or replace the refresh error. The
existing session/ownership/disposal checks remain. UI and repository contracts
were not changed.

## Changed files

- `lib/features/stories/cubit/story_viewers_cubit.dart`
- `test/features/stories/story_management_test.dart`
- `docs/STORIES_STAGE6.md`

## Verification

- Targeted analysis: `lib/features/stories` and `test/features/stories` — **no
  issues found**. Changed Dart files formatted.
- **239 tests passed, 0 failed** in the compiled Flutter test-engine run, including
  all 233 prior focused Story/shared-media/Create Post regressions and six new
  Stage 6 tests. No socket or test-framework production changes were introduced.
- New coverage: refresh superseding in-flight pagination; late success/error
  rejection and cursor recovery; duplicate refresh/load-more suppression; refresh
  retry; account change; disposal; confirmed last deletion through Viewer → Home
  → own-story popup, including no optimistic removal and stale list resurrection.
- Retained suites cover owner-only deletion, confirmation/cancel, success/failure,
  duplicate deletion, multi/last-story transitions, timeout recovery, Home refresh,
  Follow synchronization, viewers pagination/dedup/errors, blocking and sessions.
- Standard `flutter test --no-pub test/features/stories/story_management_test.dart`
  cannot start its localhost server: OS error 1, operation not permitted at
  127.0.0.1. Actual tests ran using the installed frontend compiler and
  `flutter_tester`, without sockets. Temporary runner, compilation/test output and
  standard-runner error: `/private/tmp/travibe-stories-stage6-*`.

## Manual iOS Simulator/device checks

1. Open an own story; verify glass menu, paused playback, cancel and confirm.
   Repeat rapidly and simulate offline/403/timeout; failures must retain content.
2. Delete an intermediate story, then the final own story. Verify safe advancement,
   close, refreshed Home and direct camera/gallery flow on the next own-bubble tap.
3. Open a non-owner story and verify management controls are absent; independently
   verify backend rejects non-owner deletion/viewers requests.
4. Exercise viewers with more than one page: scroll/load more, refresh while a
   page is pending, retry offline, empty state, and no duplicate rows. Confirm
   actual backend ordering and liked/relationship fields.
5. Follow/unfollow and block a viewer; confirm Home synchronization and row removal.
   Switch accounts with requests/sheets open and verify private data disappears.
6. Compare preserved glass/sheet styling, safe areas, large text and scrolling on
   iOS. No new simulator/device or live backend success is claimed by this review.

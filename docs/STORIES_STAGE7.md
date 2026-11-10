# Stories Stage 7 — Story Likes

2026-10-25. Like/Unlike is implemented with body-independent mutation confirmation
and authoritative Story Detail reconciliation. **Not verified end-to-end against
deployed Laravel. GET Likes list integration remains blocked by its contract.**

## Inspection and contract findings

- Existing StoryDetail already strictly parses `id`, `is_mine`, boolean `is_liked`
  and nonnegative integer `likes_count`. Reused without model changes.
- Existing Post/Comment LikesRepo assumes their response/pagination conventions;
  its optimistic LikesCubit also derives counts when confirmation reads fail.
  Those endpoint-specific assumptions cannot be reused for undocumented Story
  responses. Existing shared LikeValue is reused; Post/Comment Likes code is intact.
- StoriesRepo remains the single Story repository and uses authenticated DioClient
  and ApiExceptions. Existing viewer/playback, management, Follow/Block, session,
  and viewers-sheet code was inspected. Stages 5/6 functionality remains intact.
- `docs/openapi.json` has no Story paths. Other local Story documents do not supply
  Like mutation envelopes or a Likes collection schema. No inaccessible deployed
  URL was retried and no fresh deployed capture is claimed.

| Contract | Verified information / implementation |
| --- | --- |
| POST `/api/v1/stories/{story}/like` | Path supplied by user. No invented body fields. Authenticated request; return `Future<void>` on HTTP 2xx, without interpreting body. |
| DELETE `/api/v1/stories/{story}/like` | Path supplied by user. No JSON requirement; empty success is accepted. Same HTTP-only confirmation. |
| GET `/api/v1/stories/{story}` | Existing verified `data: StoryDetail` supplies `is_liked` and `likes_count` after mutations. |
| GET `/api/v1/stories/{story}/likes` | Path only. Collection envelope, stable liker identity fields, relationship fields, page parameters/limits/metadata, ordering and authorization are unverified. Typed repository/list parsing and list state are deferred. |

Mutation options use ResponseType.plain to avoid JSON-decoding unknown/empty
bodies, timeout and optional CancelToken. Neither mutation is assumed to return
Story Detail. HTTP 401/403/404/422/429 have safe messages/status preservation;
network errors reuse ApiExceptions. Exact successful status codes, mutation
response bodies and endpoint-specific error bodies still need backend examples.
Accepting HTTP 2xx is HTTP success handling, not a claim that a particular status
or example response body was documented. Tests using empty 204 or arbitrary JSON
are robustness fixtures, not captured or newly asserted backend schemas.

## State and recovery

- Home owns one StoryLikesCubit alongside its existing StoriesCubit and passes
  it to viewer routes. Standalone viewers own/dispose a fallback instance. No
  widget-local like state or second Story repository is introduced.
- State is keyed by Story ID, initialized from validated detail and retained across
  story/author navigation and viewer reopenings while Home remains mounted.
- No optimistic flag/count changes and no local increments/decrements. A tap
  marks that ID pending, sends the selected mutation, then GETs Story Detail.
  Only that verified detail supplies the next count/flag (including zero).
- A pending ID rejects rapid duplicate requests. Other stories keep their own
  state. Revisions prevent pre-mutation reads from overwriting confirmation or
  rollback; fresh detail reads reconcile later server changes.
- Failed mutations retain the last verified state. A transport/5xx uncertainty or
  a confirmed write followed by failed GET marks the ID as requiring refresh.
  The next tap reads only, never repeats the write. Fresh viewer detail reads can
  also reconcile this status. Another explicit tap may then change the confirmed
  state. No automatic mutation retries or assumptions about idempotency.
- Session changes clear cached flags/counts and cancel mutation CancelTokens;
  disposal cancels owned mutations. Any late confirmation GET is discarded after
  session change/disposal (the existing detail GET itself is not cancellable).
  Already-dispatched server writes cannot be undone by client cancellation.
- Story switching keeps confirmation associated with the original ID; errors are
  shown only if the original viewer request remains current. Existing BlockCubit
  still controls author exclusion/navigation; no blocked stories are introduced.
- Home StorySummary has no like fields. No guessed Home counts are added; reopening
  uses fresh detail plus shared state. Publication, view counts and unseen markers
  remain independent.

## Viewer and viewers sheet

- Non-owner stories have a 48x48 glass heart button at the existing lower-right
  control inset, inside SafeArea. Owners retain their existing views/menu controls
  and have no Like button. An authenticated user's matching numeric ID also hides
  it even if a contradictory `is_mine` value is received.
- Existing `heart2.svg` is the white outlined heart; `heart.svg` is filled red.
  Original 20x20 geometry/colors are preserved with no ColorFilter. Existing asset
  directory registration is sufficient. No SVG or package was added.
- Like/Unlike/Refresh-status tooltips, selected semantics, disabled pending action
  and progress indicator use the existing glass styling. Child hit testing keeps
  heart taps separate from photo tap-to-next/previous gestures. No canvas crop,
  overlay coordinates, progress timing or editor/publication changes.
- Figma design-to-code skill and local FIGMA_REFERENCE were read. Access is recorded
  blocked and no viewer screenshot exists locally; no blocked call was retried.
  Placement reuses existing control insets and follows the user's written request;
  exact screenshot alignment is **pending visual signoff**, not claimed verified.
- Viewers sheet remains unchanged: API `has_liked` alone controls row hearts.
  Existing refresh/pagination retrieves fresh confirmed badges. No GET Likes list
  is assumed to match viewers, and no unverified liker-to-viewer merge is performed.
  No new Likes sheet, fake liker records, likes count UI or reply feature was added.

## Changed files

- `lib/features/stories/data/stories_repo.dart` — authenticated mutation methods.
- `lib/features/stories/cubit/story_likes_cubit.dart` — shared state/reconciliation.
- `lib/features/stories/cubit/story_viewer_cubit.dart` — versioned detail snapshots.
- `lib/features/stories/widgets/story_like_button.dart` — glass SVG control.
- `lib/features/stories/screens/story_viewer_screen.dart` — non-owner placement,
  feedback and fallback state ownership.
- `lib/features/home/screens/home_screen.dart` — Story-only shared Cubit lifecycle
  and route injection; no post/feed behavior changes.
- `test/features/stories/story_likes_test.dart` — focused regression coverage.
- `docs/STORIES_STAGE7.md` — this report.

## Verification

Targeted analysis: Stories production/tests and Home screen — **no issues found**.
Changed Dart files formatted (7 files, no further changes required).
**267 tests passed, 0 failed**: 28 new Story Like tests plus all 239 previous
focused Story/shared-media/Create Post regressions. This is the actual compiled
Flutter engine run, not a standard-runner or live-backend success claim.

Tests cover mutation requests/authentication, empty/unknown bodies, detail-backed
flags/counts, Like/Unlike HTTP 401/403/404/422/429, failure preservation, duplicate
taps, zero count, stale responses, story switching, session/disposal cancellation,
uncertain-write recovery without resubmission, expiry, owner safety, accessible
untinted SVG control, confirmed outline/filled transitions and no tap navigation.
Existing Story Viewer/management/sheet suites cover playback, overlay gestures,
delete/confirmation, pagination, API-backed viewer heart badges, Follow/Block and
Home/popup synchronization. Media and Create Post regressions are also included.

Standard `flutter test --no-pub test/features/stories/story_likes_test.dart`
cannot start its localhost server (OS error 1, 127.0.0.1). Tests are compiled with
the installed Flutter frontend and run on flutter_tester without a VM-service
socket. Temporary runner, compiler/test logs and standard-runner failure are in
`/private/tmp/travibe-story-likes-*`; no project test framework was replaced.

## Missing backend/visual details and manual verification

Provide sanitized successful POST/DELETE responses/statuses and GET Likes
responses (empty and multi-page), documented query parameters/limits, stable liker
IDs, ordering and owner/public authorization. These are required before adding a
typed `getStoryLikes` result or paginated Likes state. Provide the current viewer
Figma screenshot/node for exact heart placement signoff.

On **both iOS and Android** with deployed Laravel:
1. Open another user's public/followers story; Like, Unlike and reopen it. Check
   authoritative flags/counts through detail GET. Confirm your own story has no
   heart action and still exposes its unchanged viewers/delete controls.
2. Rapidly tap, then move between stories while the request is pending. Check one
   mutation per pending ID, correct per-ID state, and no navigation from heart taps.
3. Simulate offline, HTTP 401/403/404/422/429 and a response lost after dispatch.
   Verify retained state, meaningful feedback and read-first recovery. Never log
   bearer credentials or response bodies containing sensitive information.
4. Logout/change account with a mutation/GET pending; verify state resets and late
   completions do not appear in the new account. Block an author during viewing.
5. Verify owner viewers badges after a confirmed like and explicit sheet refresh;
   hearts must follow `has_liked`, not local Like cache or guessed liker records.
6. Regression-check progress, hold-to-pause, tap navigation, overlays, safe areas,
   small screens/large text, deletion, Home popup and publishing. Compare glass
   heart placement with the current Figma screenshot. No device or live backend
   end-to-end success is claimed by these local tests.

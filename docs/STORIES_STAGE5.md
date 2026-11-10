# Viewers sheet header and follow-pill alignment — 2026-10-22

- Header eye/count row and subtitle now use start alignment on the same 24px
  horizontal content grid. The drag handle remains centered; `eye.svg` stays
  native 24×24, untinted, with a dynamic server-derived count.
- Extracted Home SuggestedUserCard's existing button into the presentation-only
  FollowPill. Home keeps its exact original default background `#2F2E2D`, minimum
  height 36, padding 8×6, StadiumBorder, text styling and pending indicator.
- The sheet reuses that same component and the existing FollowActionBuilder /
  shared FollowCubit. Its presentation overrides retain neutral gray while
  disabled/loading, white text and neutral white pressed feedback. There is no
  second follow implementation or orange button background.
- Circular avatars, API-confirmed heart indicators, vertical supported actions,
  row spacing, scrolling and all Story/session/block/API behavior remain intact.

Changed files: `lib/features/follow/widgets/follow_pill.dart`,
`lib/features/home/widgets/suggested_user_card.dart`,
`lib/features/stories/widgets/story_viewers_sheet.dart`,
`test/features/stories/story_viewers_alignment_test.dart`, and this document.
No repository, Cubit, model, Story timing/publishing/tracking/pagination/deletion,
Profile, Buddies, native, dependencies or VS Code configuration changed.

Verification: targeted analysis **clean**; formatting **four changed Dart files
clean**; compiled Flutter test run **233 passed, 0 failed**, including **six new
alignment/follow tests** and all previous Story/media/Create Post regressions.
Tests verify exact header/handle geometry, untinted eye asset, both gray label
states, disabled/loading/pressed presentation, shared Home/sheet follow/unfollow
confirmation and duplicate protection, failures, blocking/session clearing and
scrolling. Home's original button style values are checked during synchronization.
The standard runner is blocked by sandbox localhost socket permissions; tests
ran on the installed Flutter engine without sockets. Logs/runner are under
`/private/tmp/travibe-viewers-alignment-*`.

The referenced Figma screenshot remains unavailable locally. This update follows
its explicit written alignment requirements; exact screenshot measurements beyond
those requirements and final iOS appearance remain pending visual signoff.

---

# Story Viewer glass UI refinement — 2026-10-22

UI-only changes reuse the current viewer, repository, Cubits, overlay renderer and
playback. The user confirms the prior viewer/publishing work runs on iOS Simulator;
this refinement has widget-test verification, not a new simulator/device signoff.

- Added a reusable StoryGlass surface: pill/circle ClipRRect, bounded
  BackdropFilter with the existing app's 10px blur treatment, translucent theme
  dark grey at 60% and a subtle white border. The photo remains visible through
  the component; blur never expands to the full canvas. No new package is used.
- The author avatar/name/actual relative posting time now sit in a compact glass
  pill below the progress bars. The name can ellipsize while the close control
  remains at the right. Plus Jakarta Sans and existing posting-time semantics stay.
- The owner views pill uses the original white `eye.svg` at its native 24×24 with
  no ColorFilter, actual server count, retained down-chevron and glass treatment.
  Very large counts fit bounded layout and retain their full screen-reader label.
- The owner options button has a 48×48 circular glass touch target and vertical
  Material `more_vert` dots. Asset inspection found no matching vertical-dots SVG.
  Existing menu, delete confirmation and owner-only behavior remain unchanged.
- The black rounded-top viewers sheet retains its centered white handle,
  count/subtitle, scroll/refresh/pagination and loading/empty/error/retry behavior.
  Its header now uses the same untinted `eye.svg`; viewer-row options use vertical
  dots only when the existing block capability is supplied.
- Viewer avatars and names come only from returned users. Existing
  FollowActionBuilder/shared FollowCubit determines Follow/Following. A small
  original red 20×20 `heart.svg` appears only for `has_liked == true`; it is an
  indicator, not a like action. No viewer data, follow state or like endpoint was
  invented. Existing owner/session/block guards remain intact.
- `pubspec.yaml` already registers `assets/images/interactions/`; both SVGs exist
  and are nonempty. Asset registration and SVG files required no changes.

## Contract and visual-reference limits

The existing viewers pipeline uses the earlier user-confirmed Stage 5B contract:
`data: Viewer[]`, `links`, pagination `meta`, boolean `is_following`, `follows_you`
and `has_liked`. Its parser, requests and Cubit were not changed. Current local
OpenAPI has no Story paths and no newer deployed viewer-list capture was supplied;
no independent deployed-schema verification is claimed. Malformed/API failures
continue to show errors, with no synthetic rows or guessed relationship flags.

The three screenshots referenced in this task are not accessible in this turn.
Only the older editor reference/current PNGs are available in `docs/figma/stories`;
Figma access is recorded as blocked. The Figma design-to-code skill was read and
no blocked/rate-limited call was retried. The changes follow the explicit written
specification and existing theme. Glass opacity, border, dimensions and spacing
are implementation choices pending the actual screenshots, not extracted Figma
measurements or a claim of exact screenshot parity.

## Changed files and verification

- `lib/features/stories/widgets/story_glass.dart` — new bounded glass surface.
- `lib/features/stories/screens/story_viewer_screen.dart` — glass author/count/menu, SVG eye and vertical dots.
- `lib/features/stories/widgets/story_viewers_sheet.dart` — SVG eye, real-data heart indicator and vertical row actions.
- `test/features/stories/story_viewer_glass_test.dart` — 10 focused widget tests.
- `docs/STORIES_STAGE5.md` — current visual changes and limitations.

Targeted analysis of Stories and Story tests: **no issues found**. Formatting:
**four changed Dart files, no changes required**. Actual compiled Flutter test
run: **227 passed, 0 failed**, including 10 new glass UI tests and all prior Story,
shared-media and Create Post regressions. Cases verify clipped partial glass,
untinted asset/geometry, real counts, vertical menus/touch targets, opening and
pausing sheets, API-supported hearts/follow state, no fake rows or unsupported
actions, loading/empty/error/retry, public owner-control safety and 320/390/430px
layouts with 59px top/34px bottom insets, long names, large counts and 2.5× text.
The standard Flutter test runner cannot bind localhost in this sandbox. The
installed Flutter frontend server and actual flutter_tester engine ran the tests
without sockets; logs/runner are under `/private/tmp/travibe-story-glass-*`.

No repository, Cubit, model, crop, overlay coordinate, timer, publishing, Home,
popup, Profile, Buddies, backend, native, dependency or VS Code files changed.

Manual iOS checks remain: compare against all three actual screenshots; inspect
notch/Dynamic Island and rotation; test bright/dark photos, glass clipping and
contrast, long names/counts, VoiceOver/tap targets, viewer scrolling/Follow/Block,
loading/offline states and smooth blur/playback on Simulator and device. Exact
Figma alignment and live viewer-list schema/heart flags need that visual/runtime
verification; existing application success is not claimed as refinement testing.

---

# Stories Stage 5 — viewer integration review, 2026-10-22

This update describes the current implementation and supersedes conflicting
POST `/view` parsing/count claims in the historical Stage 5A/5B records below.
The existing full-screen viewer and earlier owner-controls implementation were
already present and have been reused. No viewer, publication pipeline, overlay
renderer, Home popup or media service was rebuilt.

## Current viewer and entry points

- Author bubbles and **View my Story** already route into the same full-screen
  StoryViewerScreen. Navigation uses actual integer author/story IDs and Home's
  loaded author order. Add New Story, the camera/gallery sheet, orange plus badge,
  popup dismissal, expiration handling and account-switch guards remain unchanged.
- The initially selected author's **first unseen, non-expired summary** is now
  preferred. When all available stories are seen, playback starts at the first.
  Left can revisit earlier stories; right/automatic progression finishes this
  author before moving through subsequent already-loaded author groups. No
  extra author pages or invented stories are fetched by the viewer.
- Every selected story loads the full documented `GET stories/{id}` resource.
  The image comes from its original `media[0].url`, never the summary thumbnail.
  Existing image loading/error/retry handling is preserved.
- The existing read-only StoryViewerCanvas decodes the versioned text document
  with StoryElements and uses the editor's StoryTextGeometry, BoxFit.cover crop,
  normalized centers, transforms, text styling and stacking order. Photos and text
  are not flattened again. Unsupported documents show an error.
- The author header now includes the actual `created_at` formatted with the
  existing `timeAgo` helper. Missing timestamps are omitted without a placeholder
  date. Avatar, name, close control, dark theme, Plus Jakarta Sans and canvas
  dimensions remain unchanged.
- One scoped timer drives segmented bars and five-second image playback after a
  decoded frame. Left/right, hold/release, lifecycle pause, sheets, retries,
  final close and disposal retain existing behavior. Empty/unknown initial groups
  close safely. Blocked/known-expired entries are skipped; restricted details
  display no photo and offer Retry/Next/Close.

## View tracking without an invented response envelope

`docs/openapi.json` currently has **no Story paths**. The latest supplied contract
confirms request behavior but explicitly leaves the POST `/view` response body
unverified. Earlier local notes and test fixtures containing `data.views_count`
and `data.viewed_at` are not treated as a verified runtime schema for this update.

- `StoriesRepo.recordView` sends `POST stories/{id}/view` **without a request body**
  through the existing authenticated DioClient. It confirms a successful 2xx HTTP
  status and deliberately does not interpret the body. `ResponseType.plain`
  prevents an unknown/empty/non-JSON body from triggering Dio JSON decoding.
- The former strict StoryViewReceipt response parser has been removed. No guessed
  `data`, `media`, count, timestamp or other POST response field is required.
- Tracking starts only after valid details, decoded image, active session and
  unpaused visibility. The Cubit prevents overlapping requests and remembers
  successful IDs. The shared repository additionally deduplicates in-flight
  requests by `(session revision, story ID)` across rapid route reopenings.
  Completed requests are released; later visits can refresh the backend's view
  timestamp. A new account never inherits another account's pending view future.
- A successful POST marks the story seen locally while retaining the last verified
  count. The Cubit then fetches the documented full Story GET resource for the
  authoritative `views_count`, validating story/author identity and expiry.
  **No local `+1` occurs**, including repeat views.
- If the count GET fails, playback and the last verified count remain available;
  a confirmed POST is not repeated merely because reconciliation failed. A 401,
  403 or 404 from tracking/reconciliation clears the current photo, layers and
  timer and provides appropriate feedback. Ordinary tracking network errors do
  not crash playback or mark an unconfirmed POST seen.
- Home updates its seen flag and verified count through the existing callbacks.
  Fresh Home responses may replace older cached counts; reads started before a
  confirmed view cannot overwrite its newer count/seen state. A scoped Stories
  refresh on viewer return reconciles server membership/order/counts. Late same-
  session acknowledgements also refresh Home; unrelated post feeds are untouched.
- Session revisions, request generations and disposal checks discard stale detail
  and tracking replies. Disposing before the POST acknowledgement prevents another
  detail read; an acknowledgement may still update its original Home, never a new
  account. A closed/navigated viewer's pending count GET is discarded; its late
  POST acknowledgement asks Home to refresh instead of applying an old count.
  Signed URLs, credentials and tokens are not logged.

## Scope and design limitations

No likes, replies, viewer-list endpoints/UI, deletion features or owner controls
were added in this update. The earlier owner controls/viewers list already exist
in the workspace and remain intact; only their test doubles were adapted to the
body-independent recordView method. Profile, Buddies, native configuration,
dependencies, publication and editing implementations are unchanged.

The only local Figma images are Story Editor references. A verified Story Viewer
frame/screenshot is still unavailable and `docs/FIGMA_REFERENCE.md` records blocked
access. The Figma design-to-code guidance was read; no blocked/rate-limited call
was retried and no new Figma layout was invented. Current styling is preserved,
with the requested posting time added using existing theme/font conventions.
Exact viewer-frame spacing, time placement and icon parity need a current
screenshot or accessible frame before visual signoff.

## Files changed in this update

- `lib/features/stories/data/stories_repo.dart` — body-independent view POST and session-scoped in-flight guard.
- `lib/features/stories/data/story_model.dart` — removed unverified view receipt parser.
- `lib/features/stories/cubit/story_viewer_cubit.dart` — first-unseen selection, detail count reconciliation and access revocation safety.
- `lib/features/stories/cubit/stories_cubit.dart` — fresh count reconciliation with stale-read protection.
- `lib/features/stories/screens/story_viewer_screen.dart` — actual posting time in existing header.
- `lib/features/home/screens/home_screen.dart` — scoped Stories refresh after viewing, with original-session guards.
- `test/features/stories/story_viewer_test.dart` — updated mocks/read expectations for documented count GET.
- `test/features/stories/story_owner_controls_test.dart` — updated view mocks; preserved owner-feature regressions.
- `test/features/stories/story_viewer_stage5_test.dart` — new focused viewer integration tests.
- `docs/STORIES_STAGE5.md` — current findings, behavior and validation.

`.vscode/launch.json` and `.vscode/settings.json` remain absent and were not
modified. This workspace has no Git metadata, so no repository diff is claimed.

## Verification

- Targeted analysis of `lib/features/stories`, Story tests and the changed Home
  screen: **no issues found**.
- Formatting verification: **nine changed Dart files**, no changes required.
- Actual compiled Flutter test run: **217 passed, 0 failed**, including all
  **184 Story tests** (23 new Stage 5 cases), 27 shared-media tests and six
  Create Post regressions. Existing popup, owner controls, publishing, camera,
  gallery, overlay geometry/gestures, audience selection and export tests passed.
- New cases cover arbitrary successful POST bodies without field parsing,
  no request body, repository/route concurrency, later repeat views without local
  increments, separate-account requests, first unseen/all-seen/expired selection,
  POST → GET count reconciliation, failed count reads without duplicate POSTs,
  401/403/404 clearing, stale sessions, disposal before POST acknowledgement and
  during count GET, fresh/stale Home counts and real
  versus missing posting timestamps. Existing detail/image/navigation/error/
  retry/pause/popup/session/block tests run alongside them.
- The standard `flutter test` runner cannot load here because the sandbox denies
  binding its localhost server (`127.0.0.1`). Tests were compiled using the
  installed Flutter frontend server and executed on the actual `flutter_tester`
  engine with isolated per-file suites and no sockets. No dependencies changed.
  Standard-runner failure, compiled
  runner, compile log, passing test log and analysis log are under
  `/private/tmp/travibe-stage5-*`.
- No all-project or deployed-device pass is claimed. The existing unrelated Home
  Following SVG test is outside these focused suites and was not changed.

## Manual device verification

1. Open another author's bubble and View my Story. Confirm the correct author,
   first unseen story, all-seen fallback, posting time and original-photo crop.
2. Compare versioned text positions/scales with the editor; test left/right,
   hold/release, automatic segments, author transitions and final close.
3. Using two accounts, verify first/repeat view behavior, server counts and Home
   unseen rings after returning. Repeat views must not add a count locally.
4. Exercise offline view POST/count GET, retry, expired 404 and visibility/block
   403. Confirm no inaccessible photo remains visible and no confirmed POST is
   repeated solely because a count refresh failed.
5. Rapidly close/reopen, background/foreground and change accounts during detail,
   view and count requests. Check that timers stop and stale content/counts never
   cross sessions. Verify existing plus badge and Add New Story still work.
6. Check iOS/Android safe areas, large text, slow image loading, memory use and
   the current Figma Viewer screenshot when available. No deployed/device success
   is claimed from isolated tests; the exact POST response body remains unverified.

---

# Historical Stage 5A/5B implementation records

The records below are retained for history. Their strict view-response schema and
older verification counts do not describe the current implementation above.

# Stories Stage 5 — owner controls, viewers and confirmed view tracking

## Stage 5B implementation — 2026-10-21

This section supersedes the Stage 5A statements below about read-only behavior,
absence of view/deletion writes, and the old manual check prohibiting such writes.
Story publishing, editor gestures, media upload, overlays and photo crop are unchanged.

### Owner controls and navigation

- Only a full resource with `is_mine: true` **and** `user_id` matching Home's
  authenticated account ID receives the bottom views pill and circular options
  button. Missing identity, another author's resource or a different session
  cannot open owner sheets or initiate owner requests.
- Home passes the existing shared FollowCubit and BlockCubit through the pushed
  route. Sheets reprovide those exact instances; no duplicate follow/block state
  or new unsupported user action is introduced.
- The dark safe-area views pill shows an eye, the server-returned count and a down
  chevron. Dots open a black rounded-top sheet with the existing white SheetHandle
  and a red trash/Delete story action. A separate confirmation is mandatory.
- Sheets, nested user action sheets, confirmations and pending deletion pause
  playback using independent pause reasons. Dismissal resumes without resetting
  progress or undoing lifecycle/long-press pauses. A guard prevents duplicate
  owner sheets. Account changes close all viewer-owned modal routes and the
  viewer without popping Home.
- The original photo, progress bars, overlay rendering and left/right/hold
  gestures remain intact. There are no story likes, replies or viewers-profile
  navigation invented in this stage.

### Verified API mapping

Contracts are taken from the supplied Stage 5B documentation, not inferred from
old OpenAPI schemas. They have not been exercised against the deployed API here.

| Operation | Request | Required successful response |
| --- | --- | --- |
| Record active view | `POST stories/{id}/view`, **no body** | HTTP 200, `data.views_count` nonnegative integer and parseable `data.viewed_at` |
| Owner viewers | `GET stories/{id}/viewers?page={page}&per_page=15` | HTTP 200, `data: []`, `links`, pagination `meta` |
| Owner deletion | `DELETE stories/{id}`, no body | HTTP 200, string `message` |

`StoryViewerUser` parses integer ID, name, nullable username/country/avatar,
view timestamp and boolean `is_following`, `follows_you`, `has_liked`.
`has_liked` is retained as data only; no like UI/API is implemented. Invalid IDs,
counts, flags, pagination and response envelopes are rejected through ApiError.
All requests use the existing authenticated DioClient and bounded receive timeout.
No credentials or raw request data are logged.

### View recording and Home synchronization

- Tracking begins only when valid details and a decoded photo are actively
  visible, unpaused and unexpired. Loading or backgrounded images do not record.
- An in-flight guard and successful-ID set deduplicate writes in this viewer.
  Repeated backend responses supply the count; the client never adds one locally.
  Failed tracking does not mark Home seen or change the count. Playback continues;
  re-entering an unconfirmed story may retry the repeat-safe backend operation.
- Confirmed views update the displayed count and Home summary/author unseen flag.
  Other unseen stories in the author group remain unseen. Session-scoped seen
  reconciliation prevents already-pending Home pages from restoring old unseen
  flags; no global post refresh occurs.
- Confirmed deletion removes the current snapshot member, loads the next remaining
  story/author or closes at the end, and removes it from Home before refreshing
  the existing Stories collection. Deletion tombstones stop late pages restoring
  the removed ID. Home's author pagination remains independent of viewer lists.
- A confirmed write can update its original Home after viewer disposal, but never
  a later account. Session changes clear Home seen/deleted reconciliation state.

### Viewers pagination, follow and block

- A sheet-scoped StoryViewersCubit owns its page cursor, loading/errors and stale
  request guards. Owner capability is checked before requests and after replies.
- Initial loading, no viewers, error/retry, pull refresh, scroll pagination and
  explicit Load more are supported. Duplicate IDs/pages are prevented. Pagination
  failure retains rows and retries the same cursor; 401/403/404 clears private rows.
- Each row reuses HomeUserAvatar and FollowActionBuilder with the shared FollowCubit;
  follow labels/pending/error behavior stays consistent with the rest of the app.
  The existing PostOptionsSheet is restricted to its Block user action, then calls
  the existing confirmBlockChange behavior. No post-specific/report actions appear.
- Confirmed blocked users are removed immediately and filtered from late pages.
  Disposal and account changes invalidate pending responses. A new account cannot
  inherit the old sheet's rows or make requests using its owner capability.

### Delete failure safety

403/404 return API feedback without claiming deletion succeeded. Transport,
malformed-success and server-error outcomes can be ambiguous: the story remains
available and the UI explicitly says deletion was not confirmed. No automatic
DELETE retry occurs. After another explicit confirmation, recovery first GETs the
same story. A 404 reconciles its absence without another DELETE; a still-existing
resource can be deleted after that explicit user action. Duplicate confirmation
requests cannot overlap; navigation cannot change the selected item mid-deletion.

### Design availability

The three referenced screenshot attachments are not accessible in this session,
and no owner-controls screenshots are present in `docs/figma`. Existing Figma
access is documented as blocked in `docs/FIGMA_REFERENCE.md`; no rate-limited call
was retried. The implementation follows the user's written layout, black/dark
surfaces, rounded sheets, safe areas, white handle and Plus Jakarta Sans theme.
No matching eye/trash/options SVGs were found, so Material glyphs are used in those
slots. Existing popup `story.svg`/`add.svg` and all publication/editor assets remain
unchanged. Exact screenshot dimensions, colors and icon parity need visual signoff.

### Files changed in Stage 5B

- `lib/features/stories/data/story_model.dart`
- `lib/features/stories/data/stories_repo.dart`
- `lib/features/stories/cubit/stories_cubit.dart`
- `lib/features/stories/cubit/story_viewer_cubit.dart`
- `lib/features/stories/cubit/story_viewers_cubit.dart` (new)
- `lib/features/stories/screens/story_viewer_screen.dart`
- `lib/features/stories/widgets/story_viewers_sheet.dart` (new)
- `lib/features/home/screens/home_screen.dart` (Stories route/callback wiring only)
- `test/features/stories/story_viewer_test.dart` (existing fixtures/expectations now allow confirmed view writes)
- `test/features/stories/story_owner_controls_test.dart` (new)
- `docs/STORIES_STAGE5.md`

### Verification and remaining device checks

- Targeted Dart analysis of Stories, Story tests and the changed Home screen:
  **no issues found**.
- Formatting check: **10 changed Dart files, 0 formatting changes required**.
- Actual compiled Flutter test run: **194 passed, 0 failed**. This includes
  **23 new owner-control tests**, the 138 existing Story regressions,
  27 shared-media tests and six Create Post regressions.
- Coverage includes exact endpoints/no view body, strict response parsing,
  401/403/404, active-photo-only tracking, no optimistic counts, write deduplication,
  delete confirmation/cancellation/final-story completion/timeout reconciliation,
  viewer pagination/error retry, blocked late rows, Home stale-page reconciliation,
  session/disposal protection, nested-modal closure, independent playback pauses
  and a 320px screen at 2.5x text scaling. The latter found and fixed a genuine
  overflow: header text now wraps and sheet content can scroll.
- Standard `flutter test --no-pub test/features/stories/story_owner_controls_test.dart`
  cannot load in this sandbox: binding its `127.0.0.1` test server is denied.
  Tests were instead compiled with the installed Flutter frontend server and run
  through the actual `flutter_tester` engine with isolated per-file suites and no
  sockets. Runner, compile log, standard-runner failure and passing test log:
  `/private/tmp/travibe-stories-owner-*`.
- No all-project or deployed API pass is claimed. The previously known unrelated
  Home Following SVG expectation was not changed or included in these suites.

No backend, Profile, Posts, Buddies, dependencies or native configuration files changed.

Device checks still required:

1. Compare all three owner states against the actual screenshots on-device,
   including safe areas, bright photos, large text and small displays.
2. With two real accounts, confirm owner-only viewers/delete authorization,
   repeat-safe tracking counts and Home unseen updates after confirmed viewing.
3. Check viewer pagination, follow/unfollow and existing block confirmations;
   blocked viewers must disappear without changing unrelated follow state.
4. Cancel/confirm deletion, delete the final story, and test 403/404/offline/timeout
   recovery against the backend. Verify Home membership/counts after refresh.
5. Background with sheets open, system Back, rapid taps, logout/account switch
   during sheet/dialog/request, and route disposal during confirmed writes.

The following Stage 5A record is retained for history; its no-write restrictions
and Stage 5A-only test counts describe that earlier stage, not current behavior.

---

# Stories Stage 5A — full-screen read-only viewer

Implemented 2026-10-21. Stage 4B Public/Followers publishing remains unchanged.
The user has confirmed that publication works on-device; the new viewer still
needs the device checks below. No backend or Figma changes were made.

## Entry points and loaded sequence

- Home now passes the existing StoriesRepo and shared BlockCubit into one
  StoryViewerScreen route. A route-opening guard prevents duplicate viewers.
- **View my Story** in the existing own-story popup is enabled when Home supplies
  its viewer callback. Selecting it dismisses the popup and starts that owner's
  returned active stories. Both requested popup SVGs remain unchanged/untinted.
  Standalone embeddings without a navigation callback remain safely unavailable.
- Other authors' bubbles open the same viewer at the selected author's first
  available story. Author ownership/selection uses integer IDs, never names.
- Home passes the displayed order: own group first when loaded, then remaining
  authors in their existing backend order. The viewer snapshots this already
  loaded sequence; it never loads extra author pages or invents subsequent items.
- Right tap advances; left tap goes back within an author and then to the previous
  available author's last story. At the first available story, left restarts it.
  At the end of an author, next advances to the next loaded available group;
  after the final group the viewer closes. Known-expired entries and blocked
  authors are skipped. Unknown summary expiry still requires a full detail GET.

## Full resource and rendering

Each selected item loads **GET /api/v1/stories/{id}** through the existing
StoriesRepo/authenticated DioClient and typed StoryDetail. The summary thumbnail
is never substituted for full details. HTTP/resource IDs and author IDs must
match the selected entry; expired full resources are rejected.

The displayed photo comes from the returned one-item media resource's `url`.
Missing/invalid URLs, malformed resources and image decode/network failures show
an error rather than a blank successful story. No URL is fabricated. Flutter's
image transport does not receive the Laravel API Bearer interceptor or headers.

`StoryElements.decode` validates the existing client-owned v1 text document and
restores stable IDs, text, normalized centers and uniform scale. Unsupported
versions/styles/malformed elements show an explicit error; layers are not silently
omitted. No sticker, drawing, video, audio or location behavior is invented.

StoryViewerCanvas uses the same **StoryTextGeometry** as the editor:

- Full photo viewport below the top safe area, extending to the bottom, with
  centered BoxFit.cover and clipping; no new fixed aspect ratio or flattening.
- Plus Jakarta Sans, 24px at reference width 390, w600 white text/black shadow,
  measured text boxes, centered alignment, LTR and 8px padding.
- Existing fitScale and normalized-center bounds, positions and stacking order.
- Read-only layers; no text editor, drag/resize/delete targets or publish controls.

There is no change to StoryCanvas, StoryEditorCubit, StoryEditorDraft, overlay
serialization, original-photo upload or PNG export.

## Playback and lifecycle

- Segmented progress bars cover the current author's available loaded stories.
  Earlier segments fill locally, the current segment advances and later segments
  remain empty. These are playback indicators, not persisted seen state.
- Default duration is **five seconds per image**, a configurable client playback
  policy, not an API field or claimed Figma duration. No new dependency is added.
- Timing begins only after both valid details and a decoded image frame exist.
  Loading, failed media, invalid overlays and errors cannot auto-progress.
- Long-press pauses and release/cancellation resumes. App inactive/background
  pauses independently; releasing a touch cannot undo a lifecycle pause. Resume
  checks expiry before starting another timer.
- A 50ms scoped timer drives progress; navigation resets it. Request generations
  discard stale GET results and stale image ready/error callbacks.
- Block changes immediately remove the current blocked author's content and
  advance to a loaded unblocked author. Pending reads cannot restore the blocked
  image. Other blocked groups are skipped when reached. No Profile mode or
  optional-field absence is interpreted as a block.
- Account change clears content, cancels playback and closes the viewer. Viewer
  requests are scoped to their original session revision and cannot populate a
  later account's screen. Disposal cancels timers/subscriptions and invalidates
  pending reads; existing repository GET timeouts remain bounded.
- Close and system Back stop playback immediately. A close guard prevents a
  double tap or coincident auto-completion from popping the underlying Home route.

## Loading and errors

The screen provides initial/detail/image loading, centered error feedback,
**Retry**, **Next Story** (skip), and an always-accessible Close control.

- 403: no access; no photo or overlay is displayed.
- 404: expired or no longer available; retry or skip to the next loaded story.
- Other API/network errors retain safe ApiError feedback and permit retry.
- Missing media, mismatched author/ID and unsupported overlay documents cannot
  masquerade as a valid story. Retry re-fetches the current detail resource.

No `POST /stories/{id}/view`, local has_seen/has_unseen override, viewers list,
Story like, deletion, reply, or other Stage 5B functionality is implemented.
Home pagination/unseen flags/block synchronization and all post feeds are preserved.

## Design limitation

No Story Viewer Figma screenshot/frame is available locally; only the existing
editor screenshots are present. The implementation reuses the current Travibe
black/dark surfaces, Plus Jakarta Sans, safe areas, author avatar/header, white
segmented progress and Close control. Figma MCP was not retried while access was
previously limited. This is theme-aligned functional UI, **not a claim of exact
viewer-frame parity**. Supply the current Viewer screenshot/node for visual signoff.

## Files changed

- `lib/features/stories/cubit/story_viewer_cubit.dart` — scoped detail/navigation/playback state.
- `lib/features/stories/screens/story_viewer_screen.dart` — full-screen viewer/lifecycle/controls.
- `lib/features/stories/widgets/story_viewer_canvas.dart` — read-only photo/text rendering.
- `lib/features/stories/widgets/your_story_button.dart` — enabled viewer navigation callback.
- `lib/features/home/widgets/home_stories.dart` — own/other author entry contracts and displayed order.
- `lib/features/home/screens/home_screen.dart` — guarded route with shared repo/block state.
- `test/features/stories/story_viewer_test.dart` — focused viewer tests.
- `test/features/stories/story_popup_test.dart` — safe callback-less fallback expectation update.
- `docs/STORIES_STAGE5.md` — implementation and verification.

No Profile, Posts repository/feed behavior, Buddies, backend, native configuration,
pubspec/dependency, media pipeline or publishing files changed.

## Verification

Targeted analysis of Stories, Story tests and both changed Home files:
**no issues found**. Formatting verification passed for all eight changed Dart
files. The actual frontend-server/flutter_tester no-socket run passed
**171 tests, 0 failed**: 138 Stories tests (including 17 new viewer tests),
27 shared-media tests and six Create Post regressions. Artifacts/logs are under
`/private/tmp/travibe-stories-viewer-*`.

Standard `flutter test --no-pub test/features/stories/story_viewer_test.dart`
could not load because sandbox policy denies its localhost server socket.
No standard-runner, deployed viewer or all-project test pass is claimed.
The known unrelated Following SVG expectation is outside these focused suites;
its production widget and test were not changed.

New cases cover GET detail selection, author/story ordering, segment counts,
left/right/automatic end behavior, waiting for image decode, press/background
pause composition and cancellation, 403/404, retry, missing media, invalid overlays,
expired resources, stale GET/image results, sessions, disposal, blocking, shared
geometry/style, safe/double close and both Home entry paths. Integration checks
use detail image URLs instead of thumbnails and assert all Story requests are GET.
Existing publishing, media, popup, audience, export and editor gesture suites run.

## Manual device checks

1. Open own stories through the popup and other authors through their bubbles.
   Confirm author identity, original-photo orientation/crop and every v1 text
   position/scale/font against the editor on the same device.
2. Check segment bars, left/right taps, cross-author order, long hold, cancelled
   touch, auto progression, final close, system Back and repeated Close taps.
3. Background/foreground and lock/unlock during loading and playback. Verify
   timing remains paused and expired content does not resume as a fresh story.
4. Exercise slow/offline details, failed media download, 403, 404 and malformed
   overlay/media fixtures. Retry and Next must remain usable without thumbnails.
5. Block an author and switch/logout accounts with requests pending and with a
   photo visible. Confirm stale content never returns or crosses sessions.
6. Verify notch/rotation, small screens, large accessibility text, contrast on
   bright photos, memory/performance with many layers and remote avatar failures.
7. Verify no seen/like/delete writes or unseen-state changes. Stage 5B owns those.

Exact Figma Viewer parity and deployed device behavior remain to be verified;
the GET contract is sufficient for this read-only Stage 5A implementation.

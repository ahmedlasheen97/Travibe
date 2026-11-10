# Stories Stages 4 / 4B — export preparation and real publishing

Updated 2026-10-21. Stage 4B uses the Story API documentation supplied by the user,
which supersedes the missing Story contracts in local `docs/openapi.json`.
The local OpenAPI was not overwritten. The user has now confirmed Public and
Followers Story publication working on-device. No deployed requests were made
from this environment. The new own-story popup below still needs device checks.

## Your Story action popup

Implemented 2026-10-21 using the existing GET /stories state. No repository,
Cubit pagination, publication, media upload or Story Viewer behavior changed.

- The existing own bubble is now tappable. When its returned author ID equals
  the authenticated ID and at least one summary has a known future expires_at,
  it opens one anchored floating popup. Ownership never uses names or list index.
- With no known unexpired own stories, tapping goes directly to the existing
  Add Story camera/gallery sheet. Loading without cached own active evidence
  does not block creation. Missing expiry is not treated as proof of activity.
  Existing author pagination is not replaced or automatically expanded.
- The popup has exactly two actions: **View my Story** and **Add New Story**.
  View is visibly disabled, annotated “Available in Stage 5A,” with disabled
  semantics. It never opens a fake viewer, editor or new navigation destination.
  Add dismisses the popup and calls the existing StoryEntry creation callback.
- The orange plus badge still opens Add Story directly. Its transparent padding
  no longer intercepts the bubble center; its artwork, position and surrounding
  semantic target remain unchanged. The existing You label/ring is retained.
- Uses Material MenuAnchor on the root overlay, above Home and bottom navigation.
  Outside taps dismiss and are consumed, so they cannot accidentally activate
  underlying navigation. Repeated anchor taps toggle a single menu.
- Styling follows the supplied written reference: #171717 background, rounded
  24px corners, 8px panel padding/anchor gap, 56px minimum menu-row height,
  Plus Jakarta Sans, white text and subtle elevation. The disabled viewer label
  is visibly muted. No unrelated Home design was changed.
- Popup icons use **SvgPicture.asset** at 24×24 with **no ColorFilter**:
  `assets/images/interactions/story.svg` and
  `assets/images/interactions/add.svg`. Their original appearance/colors remain
  intact. Both files already exist and `assets/images/interactions/` is declared
  in pubspec.yaml, so no asset, dependency or pubspec edits were required.
- Menu layout respects physical window safe insets even when Home's SafeArea has
  consumed local padding. The constrained menu can flip/reposition inside the
  window, with keyboard/notch insets retained. No bottom sheet replaces the popup.
- Session changes close it immediately and invalidate old-session own-story
  evidence; new current-account identity/data can establish activity again.
  Removing/changing the owner data closes a stale menu. While open, a scoped
  timer dismisses it when the last known active story expires; the next tap
  opens Add Story. Timers/listeners/overlay entries are cleaned up on disposal.
- Unseen flags, block filtering, pagination cursors and story data stay owned by
  the existing StoriesCubit. Opening/dismissing this menu performs no API write,
  seen mutation, upload or publication.

### Screenshot limitation

No popup screenshot was attached in this turn or found among local Story design
references (only the existing editor screenshots are present). The written
layout/style and exact requested SVG assets were followed. Exact screenshot
parity is not claimed; a popup screenshot is needed for final visual comparison.
No Figma calls or changes were made.

### Changed files for the popup

- `lib/features/stories/widgets/your_story_button.dart` — own-story menu and lifecycle.
- `lib/features/home/widgets/home_stories.dart` — wrap the existing own bubble;
  preserve badge, other authors and list behavior.
- `test/features/stories/story_popup_test.dart` — 14 focused widget tests.
- `docs/STORIES_STAGE4.md` — behavior, design limits and verification.

### Popup verification

- Targeted analysis of Stories, Story tests and the changed Home widget:
  **no issues found**. Formatting checks cover all three changed Dart files.
- Actual no-socket frontend-server/flutter_tester run: **154 passed, 0 failed**
  (121 Stories including 14 new popup tests, 27 shared media tests, six Create
  Post regressions). Artifacts: `/private/tmp/travibe-stories-popup-*`.
- Tests cover direct Add when empty/loading/expired/unknown expiry, active own
  actions, disabled View, real Add sheet handoff, orange badge behavior, consumed
  outside navigation taps, one menu only, ownership by ID, clearing on account
  change/data removal, timed expiration, original SVG assets/registration and
  root-overlay safe bounds near a bottom/right anchor.
- Existing Public/Followers publishing, safe ready-media retry, block/session
  synchronization, export and gesture suites pass. No backend contract changed.
- Standard `flutter test --no-pub test/features/stories/story_popup_test.dart`
  cannot load because sandbox policy denies its localhost server socket. No
  standard-runner pass is claimed. Unrelated Home suites were not rerun; the
  known historical Following SVG expectation below was not modified.

Manual device checks: tap the bubble with zero and with active stories, add via
popup and badge, dismiss outside/over navigation, test notch/rotation/large text,
account switching and last-story expiration. Verify View remains unavailable
until Stage 5A. Publication remains the user's already verified Stage 4B flow.

## Implemented behavior

- The existing orange Post button publishes **Public and Followers** Stories for a signed-in
  session. Camera/gallery, editor layout, Plus Jakarta Sans, text/keyboard,
  drag/scale/delete and audience selection remain intact.
- Upload the **original selected photo**, using its actual name, byte-derived
  MIME and bytes, through the unchanged `MediaUploadService`. Do not flatten text
  into the image, send a guessed media binding or duplicate the presign pipeline.
- Wait for authoritative ready media; submit one ID and serialized text elements.
  Only confirmed HTTP 201 with a valid matching Story resource is success.
- Refresh Home Stories before success feedback and editor closure. A refresh
  failure keeps Home's retry affordance, but does not turn confirmed creation
  into another POST. Closing the successful editor disposes its local draft;
  the picker does not retain a second draft.
- Upload/processing/publishing progress is visible and announced. Editing,
  additional submits and Back are blocked while publishing. Tapping Post during
  an active canvas gesture or text/audience sheet cannot submit a partial edit.
- Genuine failures retain the photo, text, transforms and audience in the open
  editor. Confirmed validation errors permit explicit retry; the shared service
  checks its existing media ID and reuses ready bytes without another presign,
  PUT or finalize. Failed media/expired authorization follow existing shared
  recovery rules; 401/403/404/422 errors retain their API messages.
- An ambiguous Story POST (e.g. receive timeout, lost connection, server error,
  malformed successful resource) is **not** automatically repeated. The editor
  explains possible creation and disables further submissions. No undocumented
  idempotency key or assumption that a lost response means failure is introduced.
- Publishing is scoped to the session in which the editor opened. Account change
  cancels pending work and requires reopening; late completions cannot refresh
  another account's Home or show success. Disposal closes owned upload transport
  and cancels API publication. No credentials/signed URLs are logged by new code.

## Verified contract and mappings

Paths are relative to `/api/v1/`; the repository reuses authenticated DioClient
and ApiExceptions/ApiError. GET requests have bounded response timeouts; POST has
bounded send/receive timeouts. Storage timeouts/headers/transport are unchanged.

| Operation | Mapping |
| --- | --- |
| POST stories | JSON `media_ids: [positiveInteger]`, `visibility: "public"` or `"followers"` from the selected audience, `location_name: null`, `elements: [...]` |
| Eligibility | Exactly one image owned by the authenticated user, ready and unattached; no guessed mediable_type/id in presign |
| Authentication | Full-access Bearer and verified email required; backend authoritatively enforces this, returning 401/403 when applicable |
| Creation result | HTTP 201 `{data: StoryDetailResource}`; validate resource, submitted media ID, exact selected visibility and is_mine |
| GET stories | `data` author groups, each with user, has_unseen and summaries; `meta.current_page/last_page/per_page/total`, nullable link strings |
| Pagination | Request `page`, paginate by author group. No undocumented per_page/filter parameters added |
| GET stories/{id} | HTTP 200 `{data: StoryDetailResource}`; typed repository method only, no viewer UI |
| Detail projection | id, user_id/user, one media item, visibility, location_name, elements, views_count/likes_count, is_liked/is_mine/has_seen, created_at/expires_at |
| Limits/lifetime | At most 50 elements, maximum 10 active Stories, expiration 24h after creation. Server owns active count and expiration; no client-created timestamps or silent eviction |

Nullable thumbnail/avatar and creation timestamps from the supplied collection
example are supported. Bad IDs, field types, timestamps, envelopes and pagination
are rejected rather than presented as an empty successful collection.

### Audience safety

Public explicitly maps to `public`; Followers explicitly maps to `followers`.
The Story enum has exactly these two choices and Public remains the default.
The sheet uses a globe for Public and users icon for Followers, with descriptions
“Anyone can see your story.” and “Only people who follow you can see your story.”
Both options enable publication. The old unsupported-audience restriction has
been removed from the request, publishing Cubit and editor Post button.

Selection stays in StoryEditorCubit/StoryEditorDraft across text/layer edits,
sheet dismissal, upload, validation failure and safe retry. A rejection does not
change it. The repository rejects a successful resource whose visibility differs
from the selected request, rather than silently accepting a fallback. All
Stage 4B duplicate, upload recovery, session and uncertain-POST guards remain.
No backend, Home feed, Profile, Buddies or Story Viewer code changed for this
subsequent audience update.

## Versioned overlay representation

The server stores `elements` verbatim; these are **client-defined fields**, not
new backend top-level fields or server enum claims. Each existing text layer is:

```json
{
  "version": 1,
  "id": "story-text-1",
  "type": "text",
  "text": "Hello Travibe",
  "position": {"x": 0.5, "y": 0.5},
  "scale": 1.0,
  "style": {
    "font_family": "Plus Jakarta Sans",
    "font_size": 24,
    "reference_width": 390,
    "font_weight": 600,
    "color_argb": 4294967295,
    "shadow_color_argb": 3707764736,
    "shadow_blur": 3,
    "padding": 8,
    "max_width_fraction": 0.8,
    "alignment": "center",
    "direction": "ltr"
  }
}
```

Position is the normalized layer center in the image canvas; scale is the
committed uniform transform. Ordered elements preserve stacking order. V1 uses
existing StoryTextGeometry's fit-to-canvas bounds, scale limits and centered cover
photo. There is no rotation, sticker, drawing or location implementation.
Encoding/decoding preserves IDs, Unicode text, centers and scale, validates finite
numbers/normalized bounds/unique IDs, enforces 50 elements and rejects unsupported
versions/styles. Decoded layers can directly populate the existing immutable
StoryEditorDraft and StoryEditorCubit; new text IDs avoid restored-ID collisions.
Server elements not authored by this codec remain verbatim in StoryDetail rather
than being silently interpreted as v1. No cross-device viewer is claimed.

The exact encoded-elements byte ceiling was **not supplied**. The client does
not invent a limit; backend 422 field errors remain authoritative. A documented
ceiling would permit earlier local byte-size feedback.

## Home Stories integration

Home owns an independent StoriesCubit; no post feed cursor is reused. Static
Story names/assets are removed. The bar always retains the current user's Add
Story entry; a returned own group appears there first using authenticated account
identity. Remaining authors retain backend order. Returned avatars and has_unseen
rings are used, with existing neutral avatar fallbacks and truncated labels.
Owner metadata is hidden during session transitions until the new identity loads.

Loading, empty (Add Story only), error/retry, horizontal pagination and pull to
refresh are supported. Pages merge duplicate author groups and Story IDs; refresh
starts a new generation and cannot be overwritten by an older page. Successful
publication reloads page one. Current shared BlockCubit state filters groups,
invalidates pending reads and refreshes after block changes. Session changes
immediately clear groups, invalidate responses and reload for the next account.

Other authors' story entries are inert and announced as viewer coming soon.
No fake viewer, seen mutation, Story playback, like or delete feature is added.
The existing Following-tab layout, Home post interactions and Root navigation
are preserved.

## PNG export retained

The existing StoryExportController still exports the render-content boundary as
immutable PNG, default long edge 1920 with proportional short edge, excluding all
editor controls and delete target. It retains paint/duplicate/stale/disposal
protection. Stage 4B adds only an interaction-status getter used to avoid
publishing during an unfinished gesture. PNG export is **not invoked** by Post.

## Files changed in Stage 4B

- `lib/features/stories/data/stories_repo.dart` — typed GET/detail/POST repository.
- `lib/features/stories/data/story_model.dart` — requests/resources/author pages.
- `lib/features/stories/data/story_elements.dart` — client v1 text codec.
- `lib/features/stories/data/story_editor_draft.dart` — original-byte MIME detection.
- `lib/features/stories/data/story_audience.dart` — explicit wire-mapping guidance.
- `lib/features/stories/cubit/story_publish_cubit.dart` — scoped upload/publish flow.
- `lib/features/stories/cubit/stories_cubit.dart` — author-group loading/pagination.
- `lib/features/stories/screens/story_editor_screen.dart` — Post/progress/guards.
- `lib/features/stories/widgets/story_entry.dart` — repository/refresh callback.
- `lib/features/stories/widgets/story_audience_sheet.dart` — both audience descriptions/icons.
- `lib/features/stories/widgets/story_canvas_export.dart` — gesture-status getter.
- `lib/features/home/screens/home_screen.dart` — scoped Stories state/refresh.
- `lib/features/home/widgets/home_stories.dart` — real groups/avatars/list states.
- `test/features/stories/story_publishing_test.dart` — API/publishing/Home tests.
- `test/features/stories/story_widgets_test.dart` — remove legacy static-map fixture.
- `docs/STORIES_STAGE4.md` — current implementation/contract/verification.

No Profile, Buddies, Laravel, Figma, dependency, native configuration or shared
media implementation files changed.

## Public / Followers update verification

This focused update preserves the existing visual layout and shared media
infrastructure. Exact changed files:

- `lib/features/stories/data/story_audience.dart`
- `lib/features/stories/data/story_model.dart`
- `lib/features/stories/data/stories_repo.dart`
- `lib/features/stories/cubit/story_publish_cubit.dart`
- `lib/features/stories/screens/story_editor_screen.dart`
- `lib/features/stories/widgets/story_audience_sheet.dart`
- `test/features/stories/story_audience_test.dart`
- `test/features/stories/story_publishing_test.dart`
- `docs/STORIES_STAGE3.md`
- `docs/STORIES_STAGE4.md`

Targeted Stories analysis: **no issues found**. Formatting verification passed
for all eight changed Dart files. The focused frontend-server/flutter_tester
no-socket run passed **140 tests, 0 failed**: 107 Stories (including 28 publishing
suite tests), 27 shared media tests and six Create Post regressions. Logs and
runner artifacts are under `/private/tmp/travibe-stories-followers-*`.
The standard Flutter runner cannot load the targeted audience/publishing suites
because the sandbox denies localhost server-socket binding; no standard-runner
pass is claimed. Related Home suites were not rerun for this audience-only update;
the known pre-existing SVG expectation failure below remains outside scope.
New coverage verifies successful
Followers publication, exact request visibility, draft preservation after a
Followers rejection, safe retry with one upload and response mismatch safety.
Existing Public publication, audience gestures, export and media tests also run.

## Stage 4B verification history (before audience update)

Targeted analysis of Stories, the two changed Home files and Story tests:
**no issues found**. Standard Flutter tests cannot load in this sandbox because
localhost socket binding is denied. Actual tests execute using the temporary
frontend-server/flutter_tester no-socket runner, not simulated test results.

- **138 passed** across Stories (105, including 26 new), shared media (27) and
  Create Post regressions (6).
- Related Home suites: **44 passed, 1 existing failure**. The known
  `zero relationship state uses SVG without fake story avatars and opens discovery`
  test expects an SvgPicture descendant, but unchanged FollowingEmptyState
  currently renders `assets/images/home/image 50.png` with the SVG commented out.
  No unrelated production or test alteration was made to hide this discrepancy.
- Total expanded run: **182 passed, 1 failed**. Logs and temporary runner are
  under `/private/tmp/travibe-stories4b-*`.
- New tests cover exact request/HTTP 201/resource parsing, 401/403/404/422,
  nullable collection fields, exact audience mapping, overlay JSON round trip and
  validation, original raw-byte upload with no storage Bearer, finalize/ready,
  one-tap success/refresh/closure, duplicate guards, ready-media retry after 422,
  upload/processing failure, expired authorization, ambiguous POST, session and
  disposal safety, pagination/dedup/refresh/error/empty, block and stale reads.
- Existing export, camera/gallery, keyboard/text and drag/scale/delete suites pass.

## Device verification / remaining decisions

1. On a verified full-access account, select and capture separate photos. Add,
   move, scale and delete text; keep Public and tap Post once. Confirm progress,
   one upload/finalize/Story POST, success, closure and refreshed own Story group.
2. Confirm original media and v1 elements in sanitized backend responses; do not
   log tokens, signed URLs or upload headers. This stage has no Story Viewer to
   visually replay the server resource yet.
3. Choose Followers: confirm the pill/description, publish with followers
   visibility and verify the backend response. Trigger a rejected request and
   retry: the selection must remain Followers, with no duplicate media upload.
   Repeat the successful flow with Public to confirm its existing behavior.
4. Test offline upload, processing failure and 422 active-story limit. Confirm
   draft retention and safe ready-media reuse on a confirmed retry. Confirm a
   lost Story POST response does not automatically resubmit.
5. Test author pagination, empty/error/retry, blocking/unblocking, logout/account
   switching, remote-image failure, small screens and large text.
6. Backend should document the exact elements byte ceiling and an idempotent
   creation/reconciliation policy for ambiguous POST outcomes. No idempotency
   semantics are invented here.

The user has confirmed Story publication working on-device. The checks above
remain useful regression checks; new popup behavior still needs device signoff.
No deployed success is inferred from unit/widget tests alone.

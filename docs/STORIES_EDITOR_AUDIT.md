# Stories avatar, upload feedback and editor audit

Audited 2026-11-04. This change preserves the existing photo-plus-elements
publication architecture. It does not activate a different export/upload path.

## UI changes

- Home retains the 64px avatar, 72px layout frame and 80px cell at the 390 × 844 reference
  size, its existing AppSizes scaling, horizontal list and name position.
- The orange badge has a fixed **20 logical pixel** diameter on every screen.
  Both axes use the same dimension. Its center now lies on the avatar's
  bottom-right circumference (45-degree diagonal), overlapping the image edge
  with part inside and part outside. The centered plus icon remains 12px.
  This supersedes the earlier fully-inside badge positioning.
- The badge has no competing GestureDetector. The existing full own-story
  bubble is the shared accessible touch target, including the badge area.
- An authenticated, session-current own group with at least one known future
  `expires_at` opens the existing dark rounded MenuAnchor, with **View Story**
  and **Add to Story**. Both avatar and badge use that same path. The menu does
  not require a new bottom sheet or dependency.
- View uses the existing Home viewer callback and original group/story order;
  Add uses StoryEntry's existing camera/gallery selection and editor route.
  Without an active story, both taps open creation directly. Missing expiry,
  another author's matching display name and expired data do not prove an
  active own story. Existing expiry timer, session invalidation, outside-tap
  dismissal, menu toggle and navigation locks remain.
- The editor no longer renders its bottom upload/processing/publishing text.
  A single white radius-10 CupertinoActivityIndicator occupies the existing
  20px Post-button slot. Progress is still an accessibility live-region label.
  No second indicator is added.
- Existing `PopScope`, `AbsorbPointer`, disabled Post state and publisher guards
  prevent Back, editing and duplicate submissions while busy. Confirmed success
  refreshes Home through `onPublished`, then closes the editor. Failure keeps
  the current photo/layers/audience and existing error Snackbar. Definitive
  failures permit explicit Post retry; ambiguous creation still disables repeat
  publication rather than risking a duplicate.

## Latest refinement: segmented edge rings

The latest request supersedes the former separated outer ring. A 64px image and
2px stroke cannot have both a 72px painted outer diameter and zero separation.
To satisfy the explicit transparent-gap/image-edge requirement, **the visible
stroke overlays the image edge**, while the original **72px layout frame** stays
in place. The photo is still exactly 64px; it has not been enlarged. Cell width,
label position, header height, horizontal list identity and touch targets remain.
Earlier documents describing a 72px painted ring with 2px gap are superseded by
this geometry.

At the reference size:

- Image box: 64 × 64, radius 32.
- Ring centerline: radius 31, **fixed 2 logical pixel** stroke, covering image
  radii 30–32. It does not scale up into a thicker stroke on tablets.
- Ring's painted outer diameter: 64px; no padding, fill, background track or
  additional painted circle separates the image and arcs.
- Existing surrounding layout frame: 72 × 72; cell remains 80px wide.
- Badge: 20px, center displaced by `32 / sqrt(2)` (about 22.63px) on each axis
  from the avatar center. Its right/bottom edges remain within the 72px frame.
  Stack clipping remains disabled and the avatar's ClipOval encloses only the
  image, not the badge. Both badge and avatar still share YourStoryButton.

`StoryRing` is a lightweight CustomPaint wrapper with a foreground painter over
HomeUserAvatar. `StoryRingPainter` uses anti-aliased PaintingStyle.stroke and
StrokeCap.butt. One story uses drawCircle for a continuous circumference; two
or more use drawArc with equal `2π / count` sectors and centered **3-degree**
transparent gaps. There is no black/grey track draw beneath the segments.
An empty color list paints nothing. An exceptionally large undocumented count
can reduce the angular gap to keep positive nonoverlapping sweeps; the normal
contract's up-to-10 active stories use exactly 3 degrees. The painter compares
its immutable color list in shouldRepaint.

Counts come exclusively from each real `StoryGroup.stories` collection:
known future `expires_at` values, unique story IDs and original relative order.
Past/equal expiry and unknown expiry are excluded conservatively, matching the
own-menu requirement that a future expiry establish an active story. Loading
placeholders and views_count are never counted. The filter runs when the widget
renders; no new polling, expiry timer or network request is introduced.

The API already exposes individual `StorySummary.hasSeen`. Each segment is
`DarkColors.primaryColor` (#E45C10) when unseen and Colors.white24 when seen.
Fully seen groups are grey. Group-level has_unseen does not override the more
specific individual flags. Deleted stories are removed by the existing
StoriesCubit reconciliation. Publishing continues to refresh through the
existing onPublished callback; confirmed viewing reconciles locally, and deletion
retains its existing canonical refresh. Painting itself never reads the network.

Changed files for this refinement:

- `lib/features/home/widgets/home_stories.dart`
- `lib/features/stories/widgets/story_ring.dart` (new)
- `test/features/home/home_responsive_ui_test.dart`
- `test/features/stories/story_popup_test.dart`
- `test/features/stories/story_ring_test.dart` (new)
- `docs/STORIES_EDITOR_AUDIT.md`

### Refinement verification

- Formatting: all five changed Dart files are clean (zero further changes).
- Targeted `flutter analyze --no-pub` on those five files: **no issues found**.
- Regression command below: **462 passed, 3 failed**. All Home, ring, grouping,
  publishing/upload and pagination checks passed. All **12 new StoryRing tests**
  passed, including pixel-level continuous circle/2px thickness/transparent
  3-degree gaps, photo visibility beneath gaps, mixed viewed colors and no paint
  for zero stories. Actual grouped item counts (including 1, 2, 3, 4 and 10),
  expired/unknown/duplicate/deleted records, publish refresh, local viewed-state
  updates and the existing deletion refresh are covered.
- Badge geometry/menu tests passed at 320, 375, 390, 393 and 430px scaling;
  Home's real responsive layouts passed at 320/375/393/430px widths, landscape
  and tablet at 1×/2× text scaling. Tests retain the 64px reference image,
  72px frame, 20px badge, story scroll identity, centered tabs/Search, refresh
  overlay and cursor pagination behavior.
- The only three failures remain the unchanged Story Viewer reply-composer tests
  listed in the initial audit below. A separate current run reproduced
  **12 passed, the same 3 failed**: composer/control layout, typing/Done, and
  keyboard-dismiss expectations. No viewer/reply implementation or its tests
  were changed or claimed fixed.
- No iOS Simulator visual verification was performed; Simulator access was
  previously denied in this session. Pixel and widget tests are the visual/
  geometry evidence here; no new screenshot parity or device-performance claim.

```sh
flutter test --no-pub test/features/stories test/features/home test/core/media test/core/pagination --reporter expanded
flutter test --no-pub test/features/stories/story_other_viewer_test.dart --reporter expanded
```

Implementation references: `home_stories.dart:33` (badge geometry),
`:131` (72px frame/64px avatar), and `story_ring.dart:9` (active-item filtering),
`:36` (2px painter and transparent angular gaps).

## Initial avatar/upload audit files

- `lib/features/home/widgets/home_stories.dart`
- `lib/features/stories/widgets/your_story_button.dart`
- `lib/features/stories/screens/story_editor_screen.dart`
- `test/features/stories/story_popup_test.dart`
- `test/features/stories/story_management_test.dart`
- `test/features/stories/story_upload_feedback_test.dart` (new)
- `docs/STORIES_EDITOR_AUDIT.md` (new)

Home feed loading/pagination, tabs, Root, Profile, Buddies, startup/splash, API
request models, upload service, repositories, text widgets and dependencies were
not changed by this task.

## Exact editor libraries and responsibilities

The text editor is custom Flutter code, not a third-party image/text editor.
There is no `pro_image_editor`, `image_editor_plus`, `flutter_quill`, screenshot
package or server-side text-rendering integration in this path.

| Layer | Implementation / dependency |
| --- | --- |
| Aa entry point | `StoryEditorScreen._editText`, `screens/story_editor_screen.dart` |
| Text entry | `showStoryTextEntry`, `_StoryTextEntry`, `widgets/story_text_entry.dart`; Flutter Material `showModalBottomSheet`, `TextField`, `TextEditingController` |
| Draft/state | `StoryEditorCubit`, `StoryEditorDraft`, `StoryTextLayer`; `flutter_bloc` (`^9.1.1`) |
| Editable canvas | `StoryCanvas`, `_GestureCanvasState`, `StoryTextGeometry`, `widgets/story_canvas.dart`; Flutter `Stack`, `Positioned`, `Listener`, `GestureDetector`, `Transform.scale`, `RichText`, `TextSpan`, `TextPainter` |
| Optional raster export | `StoryExportController.capture`, `widgets/story_canvas_export.dart` (a `part` of story_canvas.dart); Flutter rendering `RenderRepaintBoundary`, `dart:ui` and `dart:typed_data` |
| Viewer | `StoryViewerCubit`, `StoryViewerCanvas`; same `StoryTextGeometry`, read-only Flutter RichText/Transform.scale |
| Photo selection | `StoryPhotoRepo`, `StoryPickerCubit`, `PostStorySheet`, `StoryEntry`; `image_picker` (`^1.2.3`), `image_picker_android` (`^0.8.13+22`), `image_picker_platform_interface` (`^2.11.1`) |
| Transport | `StoryPublishCubit`, `StoriesRepo`, shared `MediaUploadService`; `dio` (`^5.11.0`) |
| Ancillary UI | `flutter_svg` (`^2.3.0`) for existing menu/tools/assets; `flutter_screenutil` (`^5.9.3`) via AppSizes for Home geometry |

Version strings above are declared pubspec constraints. Flutter framework widgets
and dart:ui are SDK facilities, not additional package dependencies.

## Text editing behavior

1. Aa invokes `_editText()` in StoryEditorScreen. Tapping an existing canvas
   layer invokes the same method with that layer's text/id.
2. `showStoryTextEntry` opens a scroll-controlled, SafeArea-aware dark bottom
   sheet. A multiline TextField autofocuses; its controller is initialized from
   the existing layer. The sheet adds keyboard `viewInsets.bottom` padding and
   scrolls its content. Done returns the string; Cancel/dismiss returns null.
3. `StoryEditorCubit.saveText` ignores empty/whitespace-only submissions,
   replaces text for an existing id or appends a uniquely identified layer.
   Multiple text layers are supported, with 50 enforced by the UI and codec.
   Layer order is paint/z-order; there is no separate reorder control.
4. Layers store **id, text, normalized center (x/y), scale**. Initial center is
   `(0.5, 0.5)` and scale 1. A completed drag/pinch commits one immutable state
   update; transient previews stay in the canvas State. Dragging onto the bottom
   delete target removes that layer. Cancellation and viewport changes do not
   commit a stale gesture.
5. Drag and pinch scale work. **Rotation does not**: no rotation property is
   stored or used, and ScaleUpdateDetails.rotation is not consumed.
6. `StoryTextGeometry` determines line wrapping, padded size, scale limits and
   normalized bounds. `Positioned` converts the normalized center to viewport
   coordinates. `Transform.scale` scales around the layer center. Text stays
   bounded to the canvas; fitScale caps at 4 and can constrain further to fit.
7. Appearance is fixed, not chosen per layer: Plus Jakarta Sans, 24px at a
   390px canvas width, weight 600, white, black87 shadow/blur 3, centered, 8px
   padding and maximum width about 80% of the canvas. There is no text background
   color, color picker, alignment picker or font-size slider. Pinch changes the
   effective size. The text-entry field itself uses a 24px white editing style.
8. StoryEditorScreen uses `resizeToAvoidBottomInset: false`, a top SafeArea,
   overlay controls and a nested control SafeArea. Opening the text sheet does
   not resize/re-crop the image canvas. Delete-target positioning includes
   bottom safe padding. The export boundary excludes all these controls.
9. Closing/reopening the **text sheet** keeps committed text and initializes it
   for editing. Cancel preserves the previous layer. Closing the **whole editor**
   disposes its Cubit: edits are not durably saved or automatically recovered.
   Reopening with an explicitly retained draft could restore that draft, but
   StoryEntry starts from a fresh picked image. Android picker recovery restores
   the pending image selection, not a persisted overlay draft.

### Arabic / RTL

The TextField accepts Arabic/Unicode and uses ambient Directionality. Canvas
TextPainter and RichText, the serialized v1 style and viewer explicitly use
**LTR** direction and center alignment. Flutter still shapes Arabic/bidi runs,
but paragraph direction is not chosen from the text or locale. There is no
per-layer RTL field, RTL editing toggle or guaranteed Arabic-specific font.
Platform font fallback and mixed-script line metrics can affect fidelity.
This audit did not change RTL/text behavior or claim visual Arabic verification.

## Two distinct render/export paths

### Actual Post path: original media plus metadata

`StoryEditorScreen._post()` → `StoryPublishCubit.publish(_editor.state)` →
`MediaUploadService.upload(bytes: draft.image.bytes, filename: draft.image.name,
contentType: draft.image.contentType)` → `StoriesRepo.create(CreateStoryRequest)`.

**The Post path never calls `StoryExportController.capture`.** The original
selected bytes are uploaded with their signature-detected MIME. Text is not
rasterized into the uploaded photo. The export controller supplied to the
canvas is currently consulted only to block Post during an editing gesture.

`StoryElements.encode` supplies versioned text metadata separately. Each element
contains `version: 1`, `id`, `type: text`, `text`, normalized `position`, `scale`
and a full copy of the fixed `style` map (including reference_width 390,
font_family/font_size/font_weight, color/shadow, padding, alignment and direction).
These are client-defined entries inside the existing `elements` array, not new
backend top-level fields. The decoder rejects unsupported versions/styles,
invalid coordinates/scales, duplicate ids and excessive layer counts.

### Existing optional PNG exporter: implemented but not published

`StoryExportController.capture(longestEdge: 1920)` waits for the rendered frame,
captures the `story-render-content` RepaintBoundary with
`RenderRepaintBoundary.toImage`, and uses `ui.Image.toByteData(PNG)` to return
immutable PNG bytes and output dimensions. The pixel ratio is
`longestEdge / max(viewportWidth, viewportHeight)`; accepted longest-edge values
are 64–1920. This is a client policy, not an asserted server image limit.

That boundary includes the cover-cropped photo and all committed text layers in
their rendered order. It excludes toolbar, keyboard, text sheet and delete target.
The controller refuses unready/invalid images, active/cancelled gesture previews,
detached canvases and changed drafts/viewports during capture. Existing pixel
tests exercise text transforms, cropped viewport dimensions, exclusion of chrome
and stale-capture rejection. No claim is made that video, unsupported element
types or unimplemented mention/sticker/drawing/location tools are exported.

## Backend contract and evidence limits

Sources inspected:

- `docs/openapi.json`: shared media presign/finalize/status specification.
- `docs/STORIES_STAGE4.md`, “Verified contract and mappings”: retained summary
  of the user-supplied Story contract, including prior user confirmation of
  Public/Followers publication on-device.
- Current StoriesRepo/CreateStoryRequest, typed parsers, publisher and mocked
  repository/upload tests.

**The local OpenAPI has no `/stories` paths.** Its comment/post restore paths
are unrelated. No backend source or authenticated live response was supplied in
this task, and no live publication was performed. Story-specific requirements
below are documentation-backed and implemented/tested against mocks; current
deployed enforcement and the actual database schema were not independently
re-verified. We do not infer extra fields or video/text endpoints from the UI.

| Operation | Current contract / request |
| --- | --- |
| POST `/api/v1/media/presign` | Required filename (max 255), content_type, size. Image MIME enum: JPEG, PNG, GIF, WebP. Optional mediable_type/id exist in shared spec but Stories does not send them. Spec notes configurable per-type size limits, 20 MB default, not a hardcoded Story limit. |
| Signed storage upload | Server returns upload_url, upload_method (documented PUT), signed upload_headers and expiry/media id. Shared service sends original bytes with exactly the signed headers on an isolated Dio client, without API Bearer/JSON interceptors. |
| POST `/api/v1/media/{id}/finalize` | After confirmed storage success; server verifies stored bytes and queues derived media processing. |
| GET `/api/v1/media/{id}` | Poll pending/processing → ready or failed. Ready media id is required before Story creation. Status/uncertain-write recovery avoids blindly repeating PUT/finalize. |
| POST `/api/v1/stories` | Client sends `media_ids: [oneReadyMediaId]`, selected `visibility: public` or `followers`, `location_name: null`, `elements: [...]`. Exactly one owned, ready, unattached image; full-access Bearer and verified email per retained Story contract. |
| Optional text/caption/location | Text layers are carried in elements. No separate caption/text/body field is sent or verified. Retained contract includes nullable location_name; no editor location action is currently implemented. |
| Creation response | HTTP 201 `{data: StoryDetailResource}`. Client verifies media id, visibility and is_mine before accepting success. Ambiguous outcome disables resubmission. |
| GET `/api/v1/stories?page=N` | Author groups with user, has_unseen, summary ids/view flags/expiry; page-based author pagination and links/meta. |
| GET `/api/v1/stories/{id}` | Detail with one media item and elements, author/audience, views/likes/ownership/seen state and timestamps. Viewer loads the detail rather than painting from a thumbnail alone. |

The retained Story contract documents at most 50 elements, 10 active Stories
and 24-hour expiry. These server-owned limits were not re-probed. The shared
OpenAPI `MediaType` enum is **image only**, and the current picker, MIME detector,
publisher and viewer implement photos. Video and standalone text stories are
not supported by this verified client/spec path; there is no verified video or
text-only creation contract. A valid selected photo is mandatory in the draft.

Per the retained contract the backend stores a media reference plus the elements
document verbatim. The client sends no flattened text media. Actual database
columns, storage layout and any undisclosed server transforms cannot be proven
from this Flutter repository.

## Published viewer fidelity

StoryViewerCubit filters known-expired summaries, requests each detail, decodes
the v1 elements and supplies the media URL to StoryViewerCanvas. The viewer uses
the same StoryTextGeometry, cover image fit, normalized centers, scale bounds,
font/shadow/padding and RichText direction as the editor, without editing chrome.
Unsupported documents show the existing error rather than silently dropping text.
Viewed-state/like callbacks and Home reconciliation are unchanged.

This reproduces supported v1 layers at equivalent viewport geometry. It is not
a flattened, immutable visual: different aspect ratios can change cover crop,
wrapping and bound positions, while platform font fallback can change glyph
metrics. The image downloaded without its elements will not contain the text.

## Recommended next step

First capture an authorized real create/detail round trip and confirm that v1
elements, original media and audience survive unchanged. Add explicit visual
fixtures for Arabic/mixed-direction text and differing viewport aspect ratios.
Agree the required cross-client fidelity and RTL schema before changing text.

Client-side compositing is **already implemented**, but is **not required** for
the current metadata-aware Travibe viewer. For future text-only stories or
cross-client burned-in output, first agree a supported background-image policy
and backend payload semantics. The existing PNG capture could then be connected
to the existing image upload pipeline with an explicit rule to avoid rendering
the same text twice (baked pixels plus elements). Do not invent a `text` media
type or enable a second upload architecture based only on editor UI.

## Initial avatar/upload audit verification

- `dart format --output=none --set-exit-if-changed` on all six changed Dart
  files: clean, zero further changes (initial avatar/upload audit).
- `flutter analyze --no-pub lib/features/home/widgets/home_stories.dart
  lib/features/stories test/features/stories`: **no issues found**.
- Final regression run: **685 passed, 3 failed**. It covered the full Stories
  suite (editor, pixel export, upload/publication, navigation/menu, owner controls,
  viewers and likes), all Home tests, shared media transport/recovery, cursor
  pagination, Profile account actions/UI, Buddies and onboarding/splash.
- New checks cover exact 20px badge dimensions and circular containment at 320,
  375, 390, 393 and 430px widths; reference avatar/ring dimensions; both own-story
  tap paths; expired-story creation; Add → gallery → editor; View → real viewer
  with original story order; one compact Post indicator; no visible bottom
  progress text; blocked Back and duplicate submit; refresh-on-success; retained
  photo/text draft with actionable error and explicit retry.
- The unchanged `story_other_viewer_test.dart` has the same three failures:
  `other-user row has composer and independent heart/options; owner controls unchanged`,
  `typing pauses progress, Done resumes and preserves the current draft without sending`,
  and `dismiss keyboard works; story change clears the ephemeral draft`.
  A separate run reproduced **12 passed, 3 failed**. These remain the previously
  reported emoji asset/send-icon/keyboard-dismiss-control expectation mismatches;
  neither the reply composer nor its tests were modified or claimed fixed.

Commands:

```sh
flutter test --no-pub test/features/stories test/features/home test/core/media test/core/pagination test/features/profile/profile_account_actions_test.dart test/features/profile/profile_ui_polish_test.dart test/features/buddies test/features/onboarding --reporter expanded
flutter test --no-pub test/features/stories/story_other_viewer_test.dart --reporter expanded
```

### Code reference index

| Concern | Reference |
| --- | --- |
| Badge geometry / shared own bubble | `lib/features/home/widgets/home_stories.dart:33`, `:131`, `:193` |
| Active/expired/session menu gate | `lib/features/stories/widgets/your_story_button.dart:37`, `:100` |
| Actual Post / Aa entry | `lib/features/stories/screens/story_editor_screen.dart:46`, `:60` |
| Input field | `lib/features/stories/widgets/story_text_entry.dart:81` |
| Layer model / draft | `lib/features/stories/data/story_editor_draft.dart:58`, `:77` |
| Shared text layout / render boundary / gestures | `lib/features/stories/widgets/story_canvas.dart:13`, `:267`, `:374` |
| PNG capture | `lib/features/stories/widgets/story_canvas_export.dart:35` |
| Fixed serialized style / codec | `lib/features/stories/data/story_elements.dart:8`, `:22`, `:56` |
| Original bytes / create / refresh | `lib/features/stories/cubit/story_publish_cubit.dart:139`, `:155`, `:164` |
| Signed media transport | `lib/core/media/media_upload_service.dart:72` |
| Exact Story request JSON | `lib/features/stories/data/story_model.dart:208` |
| Story POST response validation | `lib/features/stories/data/stories_repo.dart:185` |
| Viewer v1 decoding / text renderer | `lib/features/stories/cubit/story_viewer_cubit.dart:331`, `lib/features/stories/widgets/story_viewer_canvas.dart:51` |

Figma root metadata was accessible on this run; the follow-up metadata request
hit the Starter-plan limit before relevant Story context/screenshots could be
verified. UI changes follow the user's explicit geometry and existing dark menu.
No current Figma screenshot parity is claimed. Simulator Computer Use was denied
earlier in this session; no new Simulator visual verification is claimed here.

# Stories Stage 2A — Text layers and gestures

Implemented 2026-10-20 after reading STORIES_STAGE1.md and the local editor
architecture. This stage activates Text only. Mention, Sticker/Emoji, Draw,
Location, audience selection and Post remain unavailable. There are no Story
API calls, uploads, Laravel changes or new dependencies.

## Interaction

- Aa opens a dark text-entry sheet with an automatically focused multiline
  field, Cancel and Done. The keyboard is requested through TextField autofocus.
- Done with nonblank text adds a layer at the canvas center. Tapping an existing
  layer reopens its text for editing while retaining its ID, center and scale.
- Empty/whitespace-only Done cancels that text operation. It never creates an
  empty overlay or erases existing text. Cancel, sheet dismissal and route Back
  likewise discard only the uncommitted text entry.
- Drag text with one finger; pinch with two fingers to resize. The whole padded
  text box remains within the image canvas, including at its corners. A pinch
  can continue as a one-finger drag without prematurely committing the draft.
- A bottom delete target appears while transforming a layer and turns red when
  the release point is inside it. Only release inside the target deletes text.
  Passing over it, overlapping it with text, dropping outside or cancelling a
  pointer does not delete the layer.
- Gesture previews stay local to the canvas. A completed gesture commits one
  transform after all participating fingers lift. A cancelled gesture restores
  the committed layer. Unrelated disabled-tool taps leave the draft untouched.
- The selected image stays intact. No source bytes are rewritten or resized.

## Architecture

- StoryEditorDraft now supports typed StoryTextLayer values with stable local
  IDs, text, normalized canvas-center coordinates and scale. withLayers creates
  another immutable draft referencing the same original StorySourceImage.
- StoryEditorCubit owns committed text creation, edits, transforms and deletion.
  It has no API, picker, file-writing or image-processing dependency. It ignores
  blank text and nonfinite/invalid transforms. IDs avoid collisions with layers
  already in the supplied draft and remain stable through edits/transforms.
- StoryCanvas owns pointer recognition and transient gesture previews, separate
  from Cubit mutation. It handles pointer-count transitions and final raw pointer
  release because Flutter can end a scale segment before the final finger lifts.
  Cancelled pointers and callbacks from disposed viewports cannot commit changes.
- StoryTextGeometry centralizes text measurement, bounded positioning and scale.
  The current local style is white Plus Jakarta Sans at a base 24px for a 390px
  canvas, with a shadow, centered wrapping and padded touch bounds. Scaling is
  ordinarily 0.5–4, further limited by canvas dimensions; very long paragraphs
  can fit below 0.5 so their complete bounds remain inside the canvas.
- The photo and text are the only content inside story-render-content, a
  RepaintBoundary. Toolbar, Post, profile/audience controls, text-entry UI and the
  delete target are siblings/outside it. This prepares a future renderer without
  implementing composition or export in Stage 2A.
- StoryEditorScreen owns/disposes its editor Cubit. Modal-entry controllers and
  focus remain UI state. Duplicate text-entry openings are guarded.

## Keyboard, safe areas and viewport changes

The editor uses resizeToAvoidBottomInset: false so opening the keyboard does not
change the background crop or normalized overlay geometry. The text sheet uses
keyboard-inset padding, safe-area handling and scrollable content. The delete
target sits above the bottom safe area.

A canvas-size change replaces the transient gesture viewport and cancels an
unfinished gesture. Committed normalized center/scale values remain in the draft;
their visible projection is bounded to the new viewport without rewriting state.
The photo still uses Stage 1's aspect-preserving centered BoxFit.cover behavior.
Authored canvas text uses consistent measurement rather than applying the device
text scale a second time; entry controls retain normal Flutter text behavior.

On an actual device the IME may consume the first Android Back to hide the
keyboard. Route Back dismisses the text sheet without committing; the editor's
Back control then exits the local editor as before. Draft persistence after
leaving the editor or process death during editing is not introduced here.

## Verification

- Targeted analysis: dart analyze lib/features/stories test/features/stories.
- Regression command: flutter test --no-pub test/features/stories
  test/features/create_post/create_post_screen_test.dart, plus the temporary
  text-preview render test. **47 passed, 0 failed**: 40 Story tests, 6 existing
  Create Post regressions and 1 temporary render check.
- Fifteen new Stage 2A tests cover creation/editing, ID/transform preservation,
  empty cancellation, autofocus/keyboard request, local drag previews, normalized
  commits, full-box bounds, pinch resizing/final release, pinch-to-drag transition,
  drag/pinch cancellation, precise delete drops, keyboard/Back behavior, viewport
  changes, long text/safe areas, source-image preservation, zero HTTP creation
  and exclusion of controls/delete target from the renderable content subtree.
- Existing Stage 1 tests still exercise native gallery options, cancellation,
  errors, duplicate taps, invalid images, Android recovery and the actual Home
  entry. The Stage 1 disabled-tool expectation now accounts for active Aa and
  four remaining disabled tools.
- Loaded-font Flutter renders were inspected for text on the image, text entry
  with a simulated keyboard inset and the active delete target:
  /private/tmp/travibe-story-text-canvas.png,
  /private/tmp/travibe-story-text-entry.png,
  /private/tmp/travibe-story-text-delete.png.
  These are widget renders, not real-device screenshots or a native keyboard.
- The final Stage 2A tests and targeted analysis were rerun after cleanup.
  The unrelated known Home Following-empty-state SVG failure documented in
  STORIES_STAGE1.md was not addressed; no all-project test pass is claimed.

## Figma gaps and manual device checks

The current attached screenshots show the editor toolbar but do not show text
entry, text styling choices, selection, pinch feedback or a delete target. The
dark rounded sheet, Cancel/Done placement, white text/shadow, bounds/scale limits
and delete-target presentation are minimal consistent UI decisions. They are
not claimed as exact Figma parity. No older design or invented node ID was used.

Before device signoff, verify on both iOS and Android:

1. Automatic keyboard presentation, multiline typing, emoji/Unicode, IME
   composition, selection/paste and editing existing text. Check long content,
   accessibility text sizes and shorter/landscape displays.
2. Native keyboard dismissal and Android Back order; Cancel/Done should retain
   or discard only the intended text entry. Confirm the photo/canvas stays still
   while the keyboard opens and closes.
3. One/two-finger transitions, repeated pinches, release order, dragging scaled
   text at every edge, precise delete drops and interrupted/cancelled touches.
4. Rotation/window resizing mid-gesture, bottom gesture-navigation insets and
   safe areas. The delete target must remain reachable above system navigation.
5. Multiple overlapping text layers (the last added is visually on top), layer
   editing after movement, unchanged original photo and disabled publication.

## Changed files

- lib/features/stories/data/story_editor_draft.dart
- lib/features/stories/cubit/story_editor_cubit.dart (new)
- lib/features/stories/widgets/story_canvas.dart (new)
- lib/features/stories/widgets/story_text_entry.dart (new)
- lib/features/stories/screens/story_editor_screen.dart
- test/features/stories/story_editor_test.dart (new)
- test/features/stories/story_widgets_test.dart
- docs/STORIES_STAGE2A.md (new)

The Stage 1 picker, Story sheet, Home entry, platform configuration and packages
were not modified in this stage. The old preview-only footer was removed from
the editor to leave the bottom delete-target area clear. Existing header geometry
was retained. Create Post, Profile, Buddies, Follow, Block and Laravel were not
modified.

## Next UI-fix tasks — deferred, before Stage 2B

The user requested these as the next work in the same Codex session. They were
explicitly deferred while completing Stage 2A and are not implemented here:

1. Enable Take a Photo with working native camera capture and the required
   platform configuration, cancellation/error handling and local draft entry.
2. Use assets/images/interactions/camera.svg and
   assets/images/interactions/gallery.svg in the Post a Story sheet.
3. Audit/apply Travibe primary orange and Plus Jakarta Sans consistently.
4. Improve Story Editor alignment against the current Figma design/screenshots,
   preserving the completed text and gesture behavior.

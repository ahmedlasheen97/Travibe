# Stories Stage 3 — audience selection

Updated 2026-10-21 after Stage 4B and the confirmed Public / Followers product
change. This supersedes the original local-only audience choices and publication
gate; real publishing is documented in `STORIES_STAGE4.md`.

## Current audience contract

Exactly two Story-specific choices are available. Public remains the default.
No Post audience enum or account-wide audience preference is reused.

| Editor choice | Icon | Description | POST stories visibility |
| --- | --- | --- | --- |
| Public | Globe (Icons.language) | Anyone can see your story. | public |
| Followers | Users (Icons.people_outline) | Only people who follow you can see your story. | followers |

`StoryAudience` owns the label, description and explicit verified visibility
mapping. `CreateStoryRequest` sends the selected value; the repository requires
the returned Story visibility to match that value. Both choices can publish.
There is no fallback from Followers to Public after an API rejection, and no
obsolete audience-specific publishing restriction.

## Editor behavior

- Tapping the existing audience pill opens the existing modal sheet, with exactly
  two rows, descriptions, icons and selected radio feedback.
- Selecting an option dismisses the sheet and immediately updates the pill via
  StoryEditorCubit. Dismissal, swipe and system Back do not change the selection.
- Audience belongs to immutable StoryEditorDraft. Creating/editing text,
  dragging/resizing/deleting layers and opening/dismissing sheets preserve it.
- Uploading and publication operate on the selected draft snapshot. Failure
  retains the draft and its audience; retry sends the same selected visibility
  and reuses ready media through the unchanged shared service.
- Duplicate sheet openings/contending text entry and late sheet responses after
  disposal remain guarded. Publishing still prevents duplicate requests and
  editing/Back while busy. Authentication/session and uncertain-POST guards apply
  equally to both audiences.

## Visual preservation

The existing dark sheet, rounded shape, SheetHandle, colors, padding, row styles,
Plus Jakarta Sans, editor header/safe areas and control sizes remain unchanged.
Public retains its existing 140 × 44 pill; Followers uses the existing alternate
156 × 44 pill. Only audience content and obsolete restrictions changed.

The current editor screenshot remains
`docs/figma/stories/story_editor_figma.png`. There is still no separately verified
current audience-sheet screenshot locally. No Figma calls or redesign were made
for this label/contract update, and exact sheet design parity is not newly claimed.

## Verification

Focused tests cover default/exact choices, icons/descriptions, Public/Followers
switching, draft/image/layer/transform preservation, dismissal/Back, duplicate
openings, disposal, exact API visibility, Followers creation, rejected Followers
requests without fallback, safe ready-media retry, mismatched response visibility
and Public publication regression. Targeted analysis is clean and the combined
no-socket run passed 140 tests with zero failures (107 Stories, 27 media, six
Create Post regressions). Standard Flutter tests remain blocked by the sandbox
localhost-socket restriction; see Stage 4 for details.

Changed in this update: `story_audience.dart`, `story_model.dart`,
`stories_repo.dart`, `story_publish_cubit.dart`, `story_editor_screen.dart`,
`story_audience_sheet.dart`, `story_audience_test.dart`,
`story_publishing_test.dart`, and Stories Stage 3/4 documentation.

Device confirmation remains: both pill labels, descriptions/icons, small screens,
large text, successful Followers publication and failure/retry preservation.

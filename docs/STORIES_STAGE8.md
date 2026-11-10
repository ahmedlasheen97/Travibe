# Stories Stage 8 — Other-user Story Viewer controls

2026-10-25. UI-only reply preparation plus existing Like/Block integration. No
reply/report request, persistence, publishing, auth, VS Code, native or dependency
changes. No real-device or deployed-backend success is claimed for this stage.

## UI

- Other-user stories now show a bottom horizontal row: flexible glass Send Message
  composer, existing 48×48 glass heart, then 48×48 glass vertical three-dot button.
  Owner identification retains `is_mine` and numeric authenticated-ID guards.
- The row uses 16px outer/8px inner spacing, SafeArea, flexible width and scalable
  text. Existing clipped StoryGlass and Plus Jakarta Sans are reused.
- Opening the keyboard moves the controls above its inset. Scaffold does not
  resize the story canvas, preserving the media crop, overlay coordinates and
  rendering dimensions. No change to progress timing or navigation hit regions.
- Owner views/count/menu, viewers sheet and Delete controls are unchanged.

## Local composer

`StoryReplyComposer` owns/disposes its TextEditingController and FocusNode. The
widget is keyed by story ID, clears on ID/session change and is never persisted.
Draft text survives keyboard dismissal, sheet dismissal and Like rebuilds while
that story remains displayed. Moving to another story/loading/removing the current
composer discards its ephemeral draft. No replies are stored outside this widget.

The field uses a small outlined smiley and white text/subtle placeholder. Keyboard
Done, a keyboard-hide control and outside taps dismiss focus; native keyboard
inset dismissal also releases focus. Active focus pauses playback using a `reply`
pause reason. Leaving/changing stories releases that reason even if a focused
composer is disposed. Existing lifecycle/press/sheet reasons remain independent.

While focused or containing text, the UI explicitly says “Replies are not available
yet.” There is no send action, fake reply response or success notification. A
verified Story Reply endpoint/request/response, authorization and product behavior
are required before implementing actual sending.

## Reused actions

- **Like:** unchanged Stage 7 StoryLikeButton and shared StoryLikesCubit. Existing
  outlined white/filled red SVGs, confirmed mutations/Story Detail reconciliation,
  duplicate guards, read-first offline recovery and session cancellation remain.
  No new Like repository/state or changed mutation semantics.
- **Options:** compact black rounded-top modal with centered SheetHandle, white
  flag/Report, separator and red user-off/Block user. Modal and confirmation pause
  progression using a separate `other-sheet` reason. Duplicate sheet opening is
  guarded. Dismissal releases only that reason.
- **Report:** disabled and explicitly labeled “Reporting is not available yet.”
  Repository/action inspection found no implemented Story Report flow or verified
  contract. The existing post-options Report item is a menu action, not a reusable
  verified reporting integration. Report cannot call Block or any API.
- **Block:** reuses confirmBlockChange, the supplied Root-scoped BlockCubit and
  BlockRepo; the sheet exposes that instance through BlocProvider.value. Existing
  status lookup, confirmation, errors/Retry, pending/disabled state and duplicate
  guards are retained. No second mutation implementation or endpoint added.
- Confirmed block changes flow through existing viewer author exclusion and Home
  Stories block subscription/refresh. The viewer advances to a remaining loaded
  author or closes at the end; the options sheet dismisses after success. Failure
  retains the story and allows retry. Missing BlockCubit disables the capability.
- Session/route guards prevent stale sheet actions; session changes close the
  viewer/its modal stack and clear local text. Late status checks on an unmounted
  sheet cannot present confirmation or submit a block.

## Design-reference limits

The Figma design-to-code skill and docs/FIGMA_REFERENCE.md were read. The two
referenced viewer/options screenshots are not attached/available locally; only
older Story Editor screenshots exist under docs/figma/stories. Figma access is
recorded blocked and no blocked/rate-limited request was retried. This implements
the written layout using existing glass/theme conventions. Exact Figma dimensions,
opacity, icon artwork and spacing require the current screenshots/node references
for visual signoff; no screenshot parity is claimed. The initial implementation used standard outlined smiley/report/block icons;
the custom SVG refinement below supersedes those icon choices.

The shared labeled CustomTextField was inspected; its title/form layout does not
match a compact glass composer. The composer reuses Flutter TextField and
StoryGlass rather than altering shared form styling.

## Changed files

- lib/features/stories/screens/story_viewer_screen.dart
- lib/features/stories/widgets/story_reply_composer.dart
- lib/features/stories/widgets/story_other_options_sheet.dart
- test/features/stories/story_other_viewer_test.dart
- docs/STORIES_STAGE8.md

## Verification

Targeted analysis of Stories production/tests: no issues found. Changed Dart
files formatted (4 files, no further changes). **282 tests passed, 0 failed**:
15 new Stage 8 tests and all 267 previous focused regressions, executed through
the actual compiled Flutter engine. This is not deployed API/device verification.

New tests cover other/owner controls; draft entry, pause/resume, Done/hide keyboard;
no send action; story/session clearing; Report non-operation; modal dismissal;
Block confirmation/success/failure/cancel/duplicate status checks; disposal;
320/390px layouts at 2.5× text with safe insets; unchanged canvas during keyboard
insets/native keyboard dismissal; next-author block navigation; and account
change during a pending Block status check.

All prior focused Stories (including Stage 7 Like/Unlike), shared media and Create
Post regression suites are included in the compiled-engine run. Standard
`flutter test --no-pub test/features/stories/story_other_viewer_test.dart` remains
blocked by localhost server binding permissions (OS error 1 at 127.0.0.1). Tests
run on the installed Flutter frontend/flutter_tester without a VM-service socket;
no project test infrastructure was replaced. Temporary runner/compiler/results:
`/private/tmp/travibe-story-stage8-*`.

## Manual iOS / Android checklist

1. Compare other-user and unchanged owner controls against the actual current
   Figma screenshots; inspect notch/navigation insets, narrow screens and large text.
2. Focus/type, use Done/hide, system keyboard Back and outside taps. Verify paused
   playback, retained current-story text, no send or success message, and unchanged
   photo crop/overlay placement as keyboard appears/disappears.
3. Like/Unlike while editing/dismissing; confirm independent taps, original API
   behavior, duplicate prevention and offline read-first recovery.
4. Open/dismiss options repeatedly and interrupt with app background/foreground.
   Confirm playback resumes only when all pause reasons have cleared.
5. Report must stay non-operational. Block must check status and request explicit
   confirmation; test Cancel, offline/failure/Retry, pending taps and success with
   another author available versus the last group. Verify Home filtering/refresh.
6. Switch account or leave the viewer with keyboard/modal/Block status pending.
   No private draft, stale dialog or mutation may appear in the new session.
7. Regression-check owner viewers/delete, tap/hold/auto progression and publishing.
   Reply and Report backend contracts remain required for their future integration.


## Custom SVG refinement

The exact files `happyemoji 20.svg`, `flag.svg`, `user-remove.svg` and `send.svg`
were verified under `assets/images/interactions/`. All are nonempty valid SVGs;
the existing pubspec directory registration includes them. No renaming, asset,
manifest, dependency or functionality changes were needed.

- Composer emoji: `happyemoji 20.svg`, original white at native 20×20, centered in
  the existing prefix slot; no ColorFilter. Placeholder/glass/focus remain intact.
- Report: `flag.svg`, native 24×24, original #BDBCBB. Report stays disabled.
- Block: `user-remove.svg`, native 24×24, original red #DD312A; no filter. Both
  action icons retain the previous 24px Material-icon geometry and sheet layout.
- `send.svg` is valid XML with native 20×20 dimensions and is registered. There
  is intentionally no existing send control, so none was added. Typing remains local with unavailable
  feedback; the current keyboard-hide action remains unchanged.

Changed files: story_reply_composer.dart, story_other_options_sheet.dart,
story_other_viewer_test.dart and this document. Asset inspection verified XML
and native dimensions for all four files. Tests verify rendered control dimensions
and no filters, removal of replaced Material icons,
no send control and the existing Report/Block and viewer regressions.

Targeted Stories analysis: no issues found. Formatting: three Dart files clean.
**282 tests passed, 0 failed** in the final compiled-engine run, including the
updated SVG assertions and existing behavior regressions. Standard flutter test
is still blocked by sandbox localhost permissions. Logs: /private/tmp/travibe-story-stage8-svg-*.
Exact Figma artwork/spacing signoff and iOS/Android visual checks remain pending
the two unavailable viewer screenshots; no pixel-perfect comparison is claimed.

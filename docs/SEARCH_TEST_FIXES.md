# Search layout and icon fixes — 2026-11-09

## Confirmed failures

Both original tests are in `test/features/search/search_screen_test.dart`:

1. `small screen handles long names, missing avatars and keyboard` —
   `Expected: null; Actual: FlutterError: A RenderFlex overflowed by 13 pixels on the right.`
   Independent reproduction and full rendering diagnostics identified the Row in
   `lib/features/search/widgets/search_tabs.dart` (previously line 20). Its content
   needed 313px inside the 300px remaining after the left inset on a 320px screen.
   Each label had fixed trailing padding, including an unnecessary final gap.
2. `Home search SVG keeps its original colors and tap action` —
   previously `Expected: 20; Actual: 17.0`. The shared Home icon used
   `AppSizes.adaptiveRadius(20)`, whose minimum scale is 0.85. A preceding test's
   320px ScreenUtil configuration therefore yielded 17px. Running only this test
   also exposed a fixture setup error: it never initialized ScreenUtil, causing
   `LateInitializationError: Field '_minTextAdapt' has not been initialized`.

## Implementation

- Search tabs retain their current typography, selected colors, label-width
  underline, left inset and 28px inter-tab spacing. The final trailing gap is
  removed. A horizontal scroll view gives enlarged labels their natural width
  while keeping every tab reachable when the strip exceeds the viewport. No
  errors are hidden and no font scaling is disabled.
- New 200% text tests exposed an additional 18px overflow in `PersonResultTile`:
  the follow action had no maximum width when there was no optional trailing
  action. A LayoutBuilder now constrains it relative to the row's inner width.
  Scaled action text may wrap while author names retain their existing ellipsis.
  Existing compact constraints for optional trailing controls are preserved.
  This widget is also reused by follower lists, covered by the regression run.
- The existing `search-normal.svg` remains unchanged and renders at 20×20 logical
  pixels, consistent with SearchField. Home's 44px touch target, responsive outer
  spacing, full-screen tab centering and callback are unchanged.
- The icon test explicitly initializes ScreenUtil using the app's 390×844 design
  size and resets its viewport afterward. Its original 20px assertion was retained;
  new assertions check actual rendered dimensions, original colors, touch target
  size and callback behavior.

No repositories, Cubits, API schemas, routing, filters, pagination or session
guards were modified. Assets, Firebase versions, SwiftPM, Bundle ID and
authentication were preserved. This workspace has no Git metadata; no history,
reset or commit was assumed. Existing work was retained.

## Tests

Search was tested first, before the feature regressions and full suite. Coverage
now includes 320/375/393/430px widths at 100% and 200% system text sizes, long
names/handles, missing avatars, a 180px keyboard inset in a 480px-high viewport,
reachable Top/Recent/People tabs, RTL, cached results and no extra tab-switch
requests. Icon checks cover those widths plus the 390px reference viewport.
No assertions were weakened and no test skips were added.

| Command | Result |
| --- | --- |
| `flutter test --no-pub test/features/search --reporter expanded` | **33 passed** |
| Independent icon tests with ScreenUtil initialization | **5 passed** |
| Profile, Stories, Chat, shared media, Home and follow regression batch | **961 passed** |
| `flutter test --reporter expanded` | **1765 passed, 0 failed, 1 existing opt-in skip** |
| Targeted Search/HomeTabs/test analysis | **No issues found** |
| `flutter analyze` | **0 errors, 0 warnings, 2 existing informational lints** |
| `dart format --output=none --set-exit-if-changed` on the four changed Dart files | **0 changes required** |

The full default suite completed successfully in 88 seconds. Compared with the
previous 1750 passes and two failures, both failures now pass and 13 additional
responsive checks pass. The sole existing skip remains the disabled-by-default
`test/live/chats_two_account_e2e_test.dart`, which requires explicitly authorized
test accounts and live-write permission. No test was deleted or newly skipped.

Regression command:

```sh
flutter test --no-pub test/features/profile test/features/stories \
  test/features/chats test/core/media test/features/home test/features/follow \
  --reporter expanded
```

The remaining informational lints are unrelated and unchanged:

- `use_key_in_widget_constructors` —
  `lib/features/home/widgets/custom_bottom_nav.dart:10`.
- `unnecessary_underscores` —
  `lib/features/home/widgets/trending_destinations_section.dart:54`.

They cause the full analyzer command to exit nonzero; they are not compiler
errors or warnings. No suppression or analyzer configuration was changed.

## Files changed

- `lib/features/search/widgets/search_tabs.dart`
- `lib/features/search/widgets/person_result_tile.dart`
- `lib/features/home/widgets/home_tabs.dart`
- `test/features/search/search_screen_test.dart`
- This report and the follow-up pointer in `docs/PROFILE_STORIES_TEST_FIXES.md`.

The existing Figma reference/access limitations were reviewed. These are bounded
layout and icon corrections preserving the current design, not a redesign or
new pixel-level Figma signoff. No Simulator build, live account or backend write
was required for this verification.

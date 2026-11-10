# Home loading: floating page-top overlay

Updated 2026-10-29. Initial loading, pull-to-refresh and Home icon re-tap share
one floating orange CupertinoActivityIndicator at the **top of Home**, directly
below the system SafeArea/status bar. It is above the Stories and tab content,
not below For You / Following and not vertically centered in the feed.

## Removed layout reservation

The rejected 48px fixed loading slot below the tabs has been removed, together
with its Column/SizedBox reservation and 16px below-tab loader padding. The tabs
again use their original **48px pinned header extent**. The original intentional
**16px spacing between tabs and the first post** remains unchanged.

The spinner does not add height or padding to the scroll view, header, Stories,
tabs or post list. Loading and non-loading layouts use the exact same elements
and spacing. Tests compare header, Stories, tabs and first-card rectangles before,
during and after refresh and confirm that the original tab-to-post gap is 16px.

## Overlay and appearance

The existing Home Stack remains inside its SafeArea. A non-layout-affecting
`Positioned(top: 0, left: 0, right: 0)` paints the shared indicator last, above the
page content. Center provides horizontal alignment only; the positioned child's
height is its 30px spinner frame, not the viewport height.

- CupertinoActivityIndicator radius: **15 logical pixels**.
- Color: existing Theme.of(context).primaryColor, mapped by the app's dark theme
  to verified `DarkColors.primaryColor`, **0xFFE45C10**.
- One 30px spinner frame; no text, loading card, SVG, separate ring or dimming layer.
- IgnorePointer preserves touch and scrolling interactions.
- Position stays fixed at Home's SafeArea origin as content scrolls underneath;
  it no longer follows the tabs or reads scroll offsets to place the spinner.
- SafeArea protects the status bar; Root's existing Scaffold keeps the body clear
  of bottom navigation. Header and navigation layout are unchanged.
- Existing accessible loading semantics and reduced-motion support remain in the
  shared indicator; Flutter owns its animation and disposal.

## Unchanged loading behavior

| Trigger | Behavior |
| --- | --- |
| Initial Home / initial retry | One page-top spinner until the active feed succeeds or fails |
| Pull-to-refresh | Same spinner and position; cached Stories/posts stay mounted; selection and scroll remain |
| Home icon re-tap while on Home | Refresh only the selected feed; repeated taps coalesce; same spinner and position |
| Home selected from another bottom tab | Normal cached navigation without a forced request; pending initial load keeps its existing request |
| Pagination | Existing compact footer indicator; no page-top spinner |
| Background publication/follow/block refresh | Cached content remains; no page-top spinner solely because isRefreshing is true |

RefreshIndicator.noSpinner continues to provide the native pull gesture without
painting a native RefreshProgressIndicator alongside the custom indicator.
AlwaysScrollableScrollPhysics, scroll controller behavior and native gesture
handling are unchanged. The overlay tracks only the active feed request, so slow
Stories/account/suggestion refreshes do not delay its removal. No artificial delay
or second loading-state coordinator was added.

The existing per-feed explicit-refresh Future tracking, Home re-tap signal,
coalescing, stale-generation/session protection, cache retention, error/retry and
disposal logic were not modified. Fresh feed requests still omit cursor; the
existing Cubit installs the new cursor on success and safely retains cached
progress on failure. No cursor is generated or decoded.

For You still uses GET feed/explore and Following uses GET feed/following.
Labels, white active dots, Stories behavior, post cards and bottom-navigation
behavior are unchanged.

## Verification

**244 focused regression tests passed. Targeted Flutter analysis: no issues.**
Both changed Dart files were formatted. All feed responses were mocked.

Coverage includes:

- One primary-colored, radius-15 indicator for initial, pull and Home re-tap loads.
- Horizontal centering at the top of Home, not the viewport/feed center or below
  tabs; the exact same rectangle for all three triggers with a simulated 44px
  status-bar inset. The indicator remains below that system inset.
- Restored 48px tab header and original 16px tab-to-first-post distance; no loading
  reservation. Header, Stories, tabs and cards do not move as loading starts/ends.
- Spinner removal after success, empty response, failure and retry; no native/custom
  refresh-spinner overlap or independent Stories spinner.
- Cached card elements remain mounted; scroll position and selected feed survive.
- Duplicate Home taps coalesce; return from another tab does not restart a cached
  or still-pending first request.
- Cursorless refresh, stale continuation rejection, correct next cursor, pagination
  without a page-top spinner, session changes and safe disposal/listener removal.
- Existing Home, cursor migration, creation/publication, Follow, Likes, block/feed,
  Home Stories and Liquid Glass navigation regressions.

An additional temporary widget-render test passed. Initial and refreshing Root
previews with app fonts and simulated SafeArea insets were reviewed at:

- /private/tmp/travibe-home-top-initial.png
- /private/tmp/travibe-home-top-refresh.png

Those previews use test fixtures and reduced motion; they are not real feed data
or native-device verification. The temporary test/images are outside the repo.

Commands:

```sh
dart format lib/features/home/screens/home_screen.dart test/features/home/home_loading_polish_test.dart
flutter analyze --no-pub lib/features/home/screens/home_screen.dart test/features/home/home_loading_polish_test.dart
flutter test --no-pub test/core/widgets/travibe_loading_indicator_test.dart test/features/home test/core/pagination test/features/create_post test/features/block/block_feed_sync_test.dart test/features/follow test/features/likes test/features/stories/story_widgets_test.dart test/features/stories/story_home_test.dart test/features/stories/story_audience_test.dart test/core/widgets/liquid_glass_bottom_nav_test.dart --reporter expanded
```

The earlier unrelated Search small-screen 13px overflow remains recorded from a
previous broader run. Search was not changed or rerun for this correction; the
current 244-test focused run has no failures.

## Manual device verification

Manual iOS Simulator, Android Emulator and physical-device verification remain
pending. No live Laravel checks or native gesture/render verification are claimed.

1. Compare initial load, pull refresh and Home icon re-tap on both platforms: one
   orange spinner at the top of Home below the status bar, not below the tabs.
2. Confirm there is no extra gap between tabs and the first post. Header, Stories,
   tabs and cached cards must remain in place while loading starts and finishes.
3. Scroll and re-tap Home; the spinner should remain fixed at the page top without
   resetting the scroll position or changing the active feed. Interactions should
   pass through the overlay.
4. Test repeated Home taps, return from another bottom tab, pagination, refresh
   failure/retry, account changes and navigation away during a request.
5. Check accessibility and reduced motion. No second native or Stories spinner
   should appear for the same refresh.

## Files modified

- lib/features/home/screens/home_screen.dart — remove loading reservation and
  position the existing overlay at the SafeArea's top edge.
- test/features/home/home_loading_polish_test.dart — placement, SafeArea, restored
  spacing and no-layout-shift assertions.
- docs/HOME_UI_LOADING_POLISH.md

Root/navigation logic, shared indicator styling, Feed Cubits/repositories/models,
API contracts, cursor pagination, caching, Stories, tabs, post cards, Photon,
Buddies, Profile Setup, Profile, other screens, dependencies and VS Code settings
were not modified.

# Liquid Glass bottom navigation

A focused Flutter rendering update to Root's existing BottomNavigationBar.
No third-party glass dependency, tab/route/API/Story/auth feature changes.

## Inspection and retained architecture

Root owns the five positions: Home, Explore, Create Post, Buddies, Profile. Its
existing lazy IndexedStack, visited-tab set, TickerMode, shared Cubit instances,
selected index, scroll-driven slide/opacity behavior and composer callback remain.
Center opens CreatePostScreen without selecting index 2; publication retains its
existing Home behavior. No new navigation state or tab controllers were added.

The separate home/widgets/custom_bottom_nav.dart is unused and has different
icon mappings. It was not substituted or modified. Root's exact existing assets
and labels remain, including Compas capitalization and the center SVG/orange glow.

## Rendering

New presentation-only LiquidGlassBottomNav wraps the existing Material bar:
- ClipRRect confines BackdropFilter to the bar, sigma 18 on both axes.
- Translucent charcoal from the existing BottomNavStyle background, a soft diagonal
  white-to-dark gradient and thin translucent white border provide highlights.
- Top corner radius is capped at 32px; bottom remains attached to the screen. No
  floating offsets, external margins or extra shadows are introduced.
- A pointer-ignoring decorative row supplies the selected capsule: translucent
  white fill/border with a 220ms ease-in-out transition. Material continues to own
  labels, accessibility semantics, touch feedback and callbacks. Animation frames
  do not recreate tab state.
- SafeArea handles bottom/side system insets once. The theme height is a minimum
  preference, with at least 64px control space and natural layout expansion for the
  existing 42px center SVG/labels. This avoids clipping it above the home indicator.
  The first test run caught a fixed-height overflow; natural layout resolved it.
- Root's reserved bottom layout and Scaffold keyboard behavior are preserved.
  No extendBody, feed overlay or scroll viewport redesign was introduced.

## Changed files

- lib/root.dart — replace only the old decorative wrapper.
- lib/core/widgets/liquid_glass_bottom_nav.dart — new glass presentation wrapper.
- test/core/widgets/liquid_glass_bottom_nav_test.dart — nine focused widget tests.
- docs/LIQUID_GLASS_NAV.md — this report.

## Verification

Targeted analysis: Root, glass widget and new tests — **no issues found**.
Formatting: three Dart files clean. Full project `flutter analyze --no-pub`
reports **16 findings outside changed files** (existing deprecated/style/import
issues); none were fixed as part of this UI task.

Separate focused compiled-engine run: **9 passed, 0 failed**. Tests cover: five positions/labels, clipped blur and attached
bounds, selected capsule/animation, center callback semantics, 320/390/430px
widths and up to 2.5x text, iOS/Android-style bottom insets, keyboard insets,
actual center SVG fit, and real Root Home/Buddies element/Cubit/scroll retention.
Existing Create Post, Buddies and Story/Home navigation regressions were included.

Broader compiled-engine run: **299 passed, 3 failed**. The failures are isolated
standalone Story Viewer composer assertions, which do not use Root or this bar:
- Expected happyemoji 20.svg; current composer uses happyemoji.svg.
- Expected no send.svg; current composer displays it.
- Expected the Dismiss keyboard tooltip; it is absent in the current composer.
These production/test files were left untouched as explicitly requested. This is
not an all-project test-pass claim.

Standard `flutter test --no-pub test/core/widgets/liquid_glass_bottom_nav_test.dart`
is blocked by sandbox localhost server permissions (OS error 1 at 127.0.0.1).
Tests ran through the installed Flutter compiler/flutter_tester without a
VM-service socket. Temporary runner, compilation, test and full-analysis logs:
/private/tmp/travibe-glass-nav-*.

## Platform and visual limits

This is an iOS-inspired Flutter blur/highlight treatment, not Apple's native
Liquid Glass/refraction renderer. The existing reserved bottom area is retained,
so blur samples whatever is painted behind that area; its visible strength varies
with the background. The feed is not extended beneath the bar just to increase
blur. GPU cost/appearance need device verification, particularly older Android
hardware; no frame-time or native Simulator visual signoff is claimed.

The local FIGMA_REFERENCE access limitation was consulted; no inaccessible Figma
request was retried. This follows the user's written design, not extracted Figma
measurements or a claim of exact Apple/Figma parity.

Manually verify iPhone home-indicator/notch and Android gesture/three-button
insets, landscape/side insets, keyboard appearance, large text/screen-reader tap
areas, selected transitions, scroll-driven hide/show, center Create Post/back,
and all tabs retaining content/scroll position. Compare glass contrast on actual
screen backgrounds and profile GPU/frame timing before device signoff.

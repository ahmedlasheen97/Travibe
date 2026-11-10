# Travibe animated splash

## Assets and scope

The existing SplashScreen, AnimationController, SVG widgets and orange expansion
are reused. `assets/images/onboarding/logo1.svg` (119 × 108 orange T) and
`logo2.svg` (182 × 43 white Travibe wordmark) are unchanged. Native launch files,
routes, authentication, onboarding screens and dependencies are unchanged.

## 1500ms timeline

The finite controller runs for **1500ms** after both SVGs are loaded through
flutter_svg’s shared asset cache. Asset loading/native startup time is separate;
there is no timer, extra navigation delay or indefinite loop.

| Time | Presentation |
| --- | --- |
| 0–600ms | Black background; T starts entirely below the viewport and rises to center with easeOutCubic while rotating exactly once |
| 600–900ms | Upright T shrinks/moves left as the white wordmark fades and slides in with easeInOutCubic; the existing centered horizontal composition is retained |
| 900–1500ms | Existing logo-origin orange expansion grows smoothly to cover every corner; the wordmark and T fade into orange |
| 1500ms | Fully orange frame paints; the existing completion callback navigates once, post-frame |

`RotationTransition` wraps the actual T SVG with `alignment: Alignment.center`.
Its turns animation uses the existing controller through a linear
`Interval(0, .4)`: 0 to exactly 1 turn, then held at 1 (upright) for the remainder.
Translation and proportional scaling remain outside rotation. Reduced motion
uses zero turns. No ring/spinner, SVG modification or layout replacement is used.

LayoutBuilder uses the full viewport without SafeArea clipping. The initial
vertical offset is half the viewport height plus half the fitted T height and
one pixel. Branding scales proportionally on narrow or short screens.

## Orange expansion

The original symbol returns toward the page center while scaling outward.
SplashExpansionPainter paints a circle behind it, following the SVG’s exact
current center. The circle covers its transparent geometry and grows to the
farthest viewport corner plus two pixels. Both SVGs fade out before completion,
leaving solid `DarkColors.primaryColor` (#E45C10) without transparent seams.
The original T fill (#DE5F14) is preserved while visible.

## Routing, accessibility and lifecycle

The app still opens `/splash`. Startup routing is now coordinated with the
onboarding completion flag and authenticated `/user` validation. Skip/completion
opens Sign Up; later launches choose Home, Login, verification or Profile Setup
as documented in [Onboarding API and startup flow](ONBOARDING_API_STARTUP_FLOW.md).
That integration leaves this animation unchanged.

The single controller pauses while inactive and resumes from the same position.
Rebuilds do not restart it. Disposal, mounted checks and the exactly-once guard
are retained. Reduced motion shows static upright full branding and completes
after the first asset-ready frame, without waiting 1500ms. The image semantic
label remains “Travibe”. Existing black iOS and Android native launch backgrounds
and system-overlay styling are unchanged.

## Reference check — 2026-11-03

Figma metadata for `SI9VCqSKenZVSy5mFZQ8eH`, page `0:1`, is now accessible.
The splash section is `2834:40230`; its Splash1–Splash7 frames are
`2834:39797`, `2834:39827`, `2834:39849`, `2834:39871`, `2834:39893`,
`2834:39966` and `2834:40014`. Design context and screenshot were received for
Splash5 (`2834:39893`), showing the orange symbol to the left and white wordmark
entering from the right. Other requested frame contexts were blocked by the
Figma Starter plan tool limit. No Figma content or assets were changed.

The user’s explicit faster timeline and rotation govern this update. The
existing slight wordmark slide and expansion are preserved; full motion fidelity
to a reference video cannot be established because no video was supplied and
remaining Figma contexts were unavailable.

## Files changed

- `lib/features/onboarding/screens/splash_screen.dart`
- `test/features/onboarding/splash_screen_test.dart`
- `docs/SPLASH_ANIMATION.md`

## Verification

- `dart format` on both changed Dart files: clean.
- Targeted `flutter analyze --no-pub` on both changed Dart files: **No issues found**.
- `flutter test --no-pub test/features/onboarding test/features/auth
  test/features/profilesetup test/features/profile/profile_account_actions_test.dart
  --reporter expanded`: **81 passed, 0 failed**, including **11 splash tests**.
- Tests cover the 1500ms boundary, offscreen start, monotonic eased rise, exact
  quarter-turn positions and upright finish, SVG-centered rotation, wordmark
  sequencing, attached expansion, every final orange pixel, safe-area insets,
  narrow/tablet layouts, exactly-once completion, disposal, rotation pause/resume,
  rebuild continuity, reduced motion without rotation, saved-session policy,
  Onboarding Next through all three pages, Get Started to Login, and account
  exit/navigation regressions. No overflow exceptions were reported.
- iOS debug Simulator build succeeded for the booted iPhone 17 / iOS 26.5.
- Recorded `/private/tmp/travibe-splash-1500ms.mov` and inspected frames at
  100ms intervals, including `/private/tmp/travibe-splash-1500ms-detail.png`.
  Frames show the T entering from below at changing angles, finishing upright,
  white wordmark reveal, attached orange expansion, and solid orange covering
  all edges before the destination. No white flash was visible in sampled frames.
- This Simulator already has a saved session and correctly reaches Login under
  the preserved policy. Its session data was not cleared. Session-free Onboarding
  and its complete Next/Get Started flow were verified by widget tests.
- Debug Simulator startup and frame pacing are not release-performance evidence;
  the deterministic widget tests verify the controller’s 1500ms completion.

The recording includes native/engine startup and asset loading; those are not
part of the controller’s 1500ms. Physical-device and Android runtime performance
checks remain pending.

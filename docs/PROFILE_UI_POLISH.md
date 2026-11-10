# Profile UI polish and unified refresh

## Scope and reference

The existing ProfileScreen, Cubits, repositories and navigation are preserved.
No reference screenshot was attached or present in the workspace, and
`docs/FIGMA_REFERENCE.md` records blocked Figma access. Layout follows the written
requirements; exact screenshot alignment has not been verified.

## Loading investigation

Profile and author posts load independently. Saved posts have a third separate
Cubit. Previously Profile rendered a native RefreshIndicator plus its own
LinearProgressIndicator, while author/saved-post slivers independently rendered
initial circular spinners and refresh progress bars. Simultaneous refreshes could
therefore show several loading indicators and insert extra layout height. The
old initial ProfileShimmer also had several independent shimmer animations,
including a settings placeholder rather than an available real header.

### Initial loading and cache

The installed dependency is **shimmer**, not Skeletonizer. This change reuses
that existing skeleton infrastructure without adding a package or production
placeholder users/models. ProfileShimmer now uses one dark shimmer animation
for avatar, name, username, two bio lines, statistics, action buttons, tabs and
initial post shapes. DarkColors tokens provide the base/highlight; bone fills
are dark rather than white. Reduced-motion preferences disable shimmer motion.
Skeleton body interactions/semantics are excluded; the real My Profile header
and Settings button remain outside the skeleton, and root navigation is available.
The initial skeleton retains non-scrolling physics so it does not hide Root's nav.

An own ProfileCubit seeds its state from the existing authoritative CurrentUserCubit
resource, when present. A normal read still revalidates it, but cached content
renders immediately without becoming a skeleton. Public profiles never use that
own-user cache. Existing session invalidation/generation guards remain intact.

When Profile arrives first, actual profile information is shown immediately; the
independent posts request uses ProfilePostSkeleton while awaiting its first data.
It does not hold the profile skeleton or show an initial Cupertino spinner.
Saved initial loading reuses this same post skeleton. Actual failures/empty
responses keep their existing error/retry and empty views.

### Explicit refresh

Pull-to-refresh and Profile nav re-tap share one in-flight UI request coordinator.
It joins an already-running Profile read and starts/joins the active tab's data:

- Posts: Profile read plus existing author PostsCubit.refresh().
- About: Profile read only.
- Saved → Posts: Profile read plus SavedPostsCubit.load(), which joins an existing
  first-page request or fetches a fresh first page when idle.
- Saved → Hotels placeholder: Profile read only; no invented hotel endpoint.

The UI waits for the required Futures and clears its busy presentation on
success/failure. Repeated pulls/re-taps share the same work. Underlying Cubits
still own API errors, generations, session isolation, caching and pagination.
Posts pagination resets through the existing refresh method; no API contracts or
cursor/offset conventions changed.

RefreshIndicator.noSpinner preserves the native pull gesture while suppressing
its visible spinner. A single existing TravibeLoadingIndicator (30px box,
Cupertino radius 15, DarkColors.primaryColor via the dark theme) floats in a Stack
below SafeArea, within the real header's lower clearance and existing avatar gap.
It is horizontally centered, above the avatar/statistics, and ignores pointer
events. It adds no slot, padding, scroll offset change or layout height. The real
header stays visible. Tests compare avatar/stats positions and mounted card
identity before/during/after refresh and verify scroll/tab preservation.

Old Profile/author/saved refresh bars are removed. The top overlay is only for
explicit refresh: background profile/social revalidation and pagination do not
activate it. Pagination retains its existing local progress and error/retry UI;
local indicators are suppressed while the explicit page refresh is active, so
there cannot be a second spinner at the same time.

Root adds the same ValueNotifier re-tap pattern already used by Home and Buddies.
Profile re-tap refreshes only Profile and its selected tab. Returning from another
Root tab preserves the visited Profile widget/cache and does not force a read.
Signal listeners and pending UI callbacks respect disposal/session changes.
Home/Buddies signals and Liquid Glass navigation behavior are unchanged.

## Layout and interactions

- A real centered My Profile title and Settings icon remain available during
  initial loading, content and retry/error states. The settings route reuses the
  existing BlockCubit. Standalone screens lacking that controller keep the icon
  visible but disabled rather than opening a broken settings route.
- Statistics share one rounded rectangular border (radius 20), existing 20px
  horizontal margins, equal-width cells, and two thin vertical dividers. Counts
  retain primary orange and nullable “—” handling; labels use existing grey text.
- Followers/Following now reuse the existing FollowUsersScreen and shared
  FollowCubit/BlockCubit, passing the actual profile ID. No follow repository or
  endpoint changes. Standalone views without those controllers stay read-only.
- Header bio uses white 16px regular Plus Jakarta Sans, natural wrapping, centered
  alignment, maxLines 2 and ellipsis. It is capped at 290px with an additional
  8px horizontal inset inside the existing 32px header margins.
  Blank/whitespace-only bio has no paragraph gap. About's Bio display is also
  capped at two lines. The model and Edit Profile retain the full original value.
- Share Profile / Edit Profile use equal-width grey FilledButton pills with 44px
  minimum height, 12px gap, white text, 20px content margins and StadiumBorder.
  Larger text can grow naturally instead of clipping. Edit navigation and save
  logic are unchanged.
- **Share Profile was not implemented before this task.** It remains disabled,
  with no fake share success, guessed public profile URL or new share behavior.
- Posts/About/Saved selection, post cards, save/like/follow/block behavior, profile
  editing, account deletion, Photon/location integration and APIs are preserved.

## Initial polish files changed

| File | Change |
| --- | --- |
| lib/features/profile/screens/profile_screen.dart | Shared header, coordinated explicit refresh/overlay, signal lifecycle, connection routes and bio presentation |
| lib/features/profile/cubit/profile_cubit.dart | Seed own profile from the existing current-user cache |
| lib/features/profile/widgets/profile_shimmer.dart | One dark skeleton clock and reusable initial post skeleton |
| lib/features/profile/widgets/profile_top_bar.dart | Real centered title and existing Settings navigation |
| lib/features/profile/widgets/profile_stats.dart | Rounded outer border, equal cells, dividers and optional existing-list actions |
| lib/features/profile/widgets/profile_header_info.dart | Explicit natural wrapping/alignment and blank-bio handling |
| lib/features/profile/widgets/profile_action_buttons.dart | Compact grey pills; preserve Edit and disabled Share |
| lib/features/profile/widgets/profile_posts_sliver.dart | Initial post skeleton, remove refresh bar, suppress duplicate local loading |
| lib/features/saved/widgets/saved_posts_sliver.dart | Same loading presentation for Profile's Saved tab |
| lib/root.dart | Profile re-tap notifier; optional ProfileRepo injection matching existing repository injection patterns |
| test/features/profile/profile_ui_polish_test.dart | 17 controlled UI, cache, refresh, layout and navigation regressions |
| test/features/profile/profile_screen_test.dart | Assert the compact FilledButton instead of old CustomButton |
| test/features/saved/saved_posts_widget_test.dart | Expect initial post skeleton instead of circular spinner |
| docs/PROFILE_UI_POLISH.md | Implementation and verification record |

## Verification

- Formatting on all 13 changed Dart files.
- Targeted analysis of all 13 changed Dart files: **No issues found**.
- Latest focused regressions: **663 passed, 0 failed**, including the styling follow-up tests.
- Current controlled Profile UI suite: **19 passed** (17 initial polish tests plus two responsive-bio cases). Covers skeleton/header visibility,
  no initial spinner, cached profile bypass, independent post loading, actual
  pull gesture/native spinner suppression, one top orange indicator, unchanged
  geometry, success/failure cleanup, cached card identity, coalesced requests,
  scroll/selected-tab preservation, Saved coordination, background revalidation,
  pagination, stats/dividers/colors, bio, button size/colors, logout stale
  responses, small screens with larger text, Root cache/re-taps and existing
  Followers/Following navigation. Existing tests retain Edit Profile navigation.
- Broad focused command:
  `flutter test --no-pub test/features/profile test/features/profilesetup
  test/features/buddies test/core/places test/features/home test/core/pagination
  test/features/saved test/features/create_post
  test/core/widgets/liquid_glass_bottom_nav_test.dart
  test/core/widgets/travibe_loading_indicator_test.dart`.
- Uses mocked repositories and deterministic Completers; no live profile mutations.
- An exploratory analysis of the entire Profile widgets directory found an
  existing unrelated unused import in discard_changes_dialog_widget.dart; that
  file was not changed. The final targeted analysis excludes untouched files.

## Manual verification and remaining dependencies

No interactive iOS/Android Profile verification was performed for this change.
No authorized test login or reference screenshot was supplied, so live Profile
rendering and exact visual comparison are still pending. Widget coverage includes
320 × 568 at 1.6 text scale, normal iPhone dimensions and a simulated top SafeArea.
No live backend checks or account/location changes were performed.

Using an authorized test account, check:

1. Initial skeleton, cached return from another tab, and Settings access while loading.
2. Pull/re-tap on Posts, About and Saved: one orange spinner, no native spinner,
   no avatar/post jumps, retained scroll/tab and proper failure cleanup.
3. Statistics border/dividers and actual follower/following routes.
4. Long/empty/emoji bio, grey compact buttons and existing Edit save/navigation.
5. Pagination, saved posts, logout/account switch and bottom navigation.
6. Compare against the actual reference screenshot when available; verify physical
   device dark skeleton contrast, accessible text sizing and touch targets.

Share Profile remains a pre-existing functional dependency, not a completed share
feature. No extra dependencies, API contracts or unrelated feature changes.


## Follow-up — bio, Gender dropdown and 44px actions

### Bio

ProfileHeaderInfo now uses DarkColors.whiteColor, fontSize 16, explicit existing
Plus Jakarta Sans family, regular weight, center alignment, softWrap, maxLines 2
and TextOverflow.ellipsis. A ConstrainedBox caps bio width at 290 logical pixels;
8px additional padding on each side inside the existing 32px header inset lets
it contract naturally to 240px on a 320px screen. Short text keeps its intrinsic
width and centered position. The original string remains untouched in the model,
API and Edit Profile. The Profile skeleton's two bio lines match the larger text.

### Gender root cause and correction

The field already explicitly filled dark grey. However, it inherited the global
InputDecorationTheme.focusColor (`#D1DAD6`, light grey) and default chevron color.
The installed Flutter DropdownButton implementation explicitly replaces the
InputDecorator fill with the effective focusColor while the field has focus.
This explains a light focused field despite its dark fillColor declaration.
The global input theme also supplies light defaults and different border states.

Only the Gender dropdown is corrected: darkgreyColor for its focus/fill/popup,
white selected text, grey hint/chevron, 28px rounded border, borderless enabled /
focused / disabled states, transparent hover tint, 20px horizontal/14px vertical
padding and a 52px minimum field height matching Current City. The menu retains
its dark rounded popup and readable values. The global theme is unchanged.
Existing null, male, female and other values, selected value initialization,
draft change detection and PATCH serialization are unchanged. Save Changes
height and behavior are unchanged.

The tests verify the effective focused InputDecorator fill, retained focus,
actual popup painter pixels (`#1C1C1C`), menu values and successful partial PATCH
with only gender. Clearing to Not specified retains the existing null mapping.

### Profile actions

Share Profile and Edit Profile have a 44px minimum/normal rendered height,
equal widths, existing 12px gap, white text, darkgreyColor backgrounds and pill
corners. Large text can grow if necessary for layout/accessibility. Share remains
disabled; Edit retains its existing route. The matching skeleton action bones
are also 44px. No Edit Profile Save Changes button styling changed.

### Files changed in this follow-up

- lib/features/profile/widgets/profile_header_info.dart
- lib/features/profile/widgets/profile_action_buttons.dart
- lib/features/profile/widgets/profile_shimmer.dart
- lib/features/profile/screens/edit_profile_screen.dart
- test/features/profile/profile_ui_polish_test.dart
- test/features/profile/edit_profile_city_save_test.dart
- docs/PROFILE_UI_POLISH.md

### Verification

- Formatting verification: **6 Dart files, 0 changes required**.
- Targeted analyzer on all six changed Dart files: **No issues found**.
- Focused regression suite: **663 passed, 0 failed**.
- The Profile UI + Edit Profile city/save suites cover **51 tests** in total,
  including four new cases (two responsive bio widths and two Gender cases) and
  the enhanced typography/button assertions.
New assertions cover white 16px typography, unchanged full bio strings, real
ellipsis overflow, responsive width/centering on 390px and 320px screens, normal
44px action heights/equal widths/12px gap, focused dark Gender rendering, dark
popup paint, preserved gender options and Save Changes/PATCH/null mapping.
Existing loading/refresh, Edit navigation, location, Home and Buddies regressions
are included. APIs and production session data were not mutated.

Interactive Simulator verification and screenshot comparison have not been
performed for this follow-up. The Simulator's app was last at unauthenticated
Onboarding; a signed-in authorized test account is needed to verify live Edit
Profile. No reference screenshot was accessible in the workspace. Android and
physical-device checks remain pending. Widget rendering and popup paint checks
are automated checks, not claimed as manual device verification.

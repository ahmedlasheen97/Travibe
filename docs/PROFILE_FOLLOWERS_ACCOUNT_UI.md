# Profile connections, empty states and account UI

## Scope and visual reference

This updates the existing Flutter views, Cubits and navigation. No API endpoint,
request model, deletion transport, dependency, SVG asset, Home loading widget,
Buddies search flow, Photon service or VS Code configuration changed.

No user reference screenshots were accessible in this conversation/workspace.
`docs/FIGMA_REFERENCE.md` records blocked Figma access. The implementation follows
the written screenshot requirements; pixel-level reference matching is unverified.

## Connections card fix and reuse

The oversized orange elements were **production TextButtons**, not debug data:
FollowUserTile rendered PersonResultTile followed by a separate Wrap containing
Block and follower/following count-navigation buttons. Global TextButton styles
made those controls large and orange, outside the rounded card.

The separate Wrap is removed. Block/Unblock and the two relationship-navigation
actions now live in the card's User options overflow menu, using compact readable
text. The relationship fields and their existing routes remain available.

The production BuddiesTravelerCard is a vertical photo-grid presentation, so it
cannot serve the requested horizontal avatar/name/button layout without changing
Buddies. The implementation instead reuses the existing shared **PersonResultTile**
from user search/suggestions. It gains an optional trailing slot; default search
and suggestion presentation is preserved. FollowUserTile supplies the overflow
menu, existing FollowActionBuilder and block-aware follow controls. No second
avatar/image loader or duplicate relationship service was introduced.

Cards retain their existing rounded dark surface, HomeUserAvatar (44px) loading /
error fallback and Flutter image caching, white name, muted username, and dynamic
Follow/Following/Updating state. Identity text has one-line ellipsis; the compact
trailing variant bounds the relationship control on narrow/large-text screens.
Avatar/name taps open ProfileScreen with the actual numeric user ID and preserved
Follow/Block controllers. Optimistic mutation, rollback and duplicate-request
protection still come from FollowCubit/BlockCubit.

## Followers / Following screen

- Centered real username when supplied, automatic route Back button, dark page.
  Missing username falls back to the existing route title, without inventing one.
- Profile passes actual nullable count snapshots. Unknown counts are omitted;
  page length is never presented as a total.
- Followers and Following tabs have white active text/underline and muted inactive
  text. The requested initial type selects the correct list.
- Each visited tab owns its existing FollowUsersCubit, cache, pagination and
  scroll key; switching back reuses that list. Suggested people remains a
  single-list mode.
- Initial loading uses dark shimmer placeholders. Paging preserves cards and
  shows the compact orange Cupertino indicator in the footer.
- Pull refresh uses RefreshIndicator.noSpinner and one non-layout-affecting,
  top-positioned TravibeLoadingIndicator (Cupertino radius 15 / primary orange).
  Per-tab in-flight refresh coordination prevents duplicates. No native spinner
  or refresh progress bar is rendered alongside it.
- Existing page/per_page API pagination, ID deduplication, retry and block filtering
  are preserved. No cursor migration.
- FollowUsersCubit now invalidates its cached/in-flight pages on session changes
  and unregisters its listener on close. Old requests cannot replace new-session
  results or clear a newer in-flight request. The screen clears obsolete refresh
  UI coordination on session change.

## SVG inspection and empty states

The actual SVG XML and embedded artwork were inspected. These SVGs contain
embedded original PNG artwork with SVG pattern transforms selecting crops; they
are rendered directly with flutter_svg without editing or generating substitutes.

| Asset | Verified artwork / use |
| --- | --- |
| assets/images/profile/emptypic.svg | Orange person/community illustration; Followers and Following |
| assets/images/profile/emptypost.svg | Photo/post with plus illustration cropped from the original sprite; Profile Posts |
| assets/images/profile/emptyitems.svg | Saved bookmark/card illustration cropped from the original sprite; Saved posts/items |

A shared ProfileEmptyState preserves original aspect ratio/colors at 121px image
height, centered white heading, muted description and optional orange pill CTA.
It is only selected after successful loading with an empty visible result; initial
loading and failures keep their proper skeleton/error presentations.

- Own Posts: **No posts yet** — “Share your first travel story and inspire other
  travelers.” — **Create Post** opens the existing composer. Root supplies its
  existing creation/publication handler, retaining publication/cache updates and
  duplicate-open protection. A standalone own profile uses CreatePostScreen.open
  and the existing PostActivityCubit. Public non-owner profiles show no creation
  CTA and use traveler-appropriate copy.
- Saved: **No saved items yet** — “Save posts and hotels to find them here.” No CTA.
  The unsupported Saved Hotels placeholder remains unchanged; no hotel endpoint
  or fake empty hotel response was added.
- Followers: **No followers yet** — “Your travel community is just getting started”.
- Following: **You don’t follow anyone yet.** — “Discover travelers and start
  building your travel community” — **Explore People**.

Explore People from Root's Profile connections uses a callback to return to Root
and select its existing Buddies tab/cache. Standalone connection routes can open
the existing BuddiesScreen with shared Follow/Block controllers and Back navigation.
No new GoRouter path or discovery API was invented.

## Delete Account presentation and security

The existing screen already contained the real password flow and red bottom
Delete my Account button. It now uses the consistent dark header/field treatment,
**Current password *** label, lock/visibility controls, explicit dark fill/border,
orange cursor/focus border and the existing destructive red button. SafeArea,
keyboard resizing/scrolling and compact in-button progress remain in place.

Warning copy retains the established semantics: account, profile and associated
account data are permanently deleted. It does not add unverified claims about
message retention or deletion of every server record.

### Reason-field decision

The existing authenticated AccountRepo/ApiService contract accepts only the
required password. No deletion reason field, validation limit or feedback
endpoint is documented, and the previous product flow did not collect a reason.
Therefore **Problem / 0/24 is omitted**. No unsent feedback is collected, stored,
logged or falsely represented as submitted. A future reason field needs an
approved backend/product destination and confirmed validation limit.

### Preserved safeguards

- DELETE `/api/v1/account`, authenticated, password in the required query only.
- Existing query/password redaction, disabled observers/debug logging and no
  destructive retry remain untouched.
- Password is obscured initially; autofill, suggestions and IME learning remain
  disabled. Input is cleared by the existing cancellation/submission/disposal
  lifecycle and never placed in navigation arguments or persistent storage.
- Existing explicit permanence checkbox **and** final “Permanently Delete Account?”
  dialog are preserved. Opening the screen or pressing an unconfirmed action
  cannot delete the account.
- Only HTTP 200 with the documented success response triggers the existing local
  session/cache cleanup and unauthenticated stack replacement. 401/422, timeout,
  server failure and uncertain outcomes retain the existing safe handling.

## Log Out wording and glass dialog

Settings and confirmation now say **Log Out**, **Log Out?**, and “Are you sure you
want to log out of Travibe?”. Internal SignOutCubit/service names remain stable.

The dialog is 320px wide where space permits, constrained by 24px screen insets.
A 24px ClipRRect bounds an 8px BackdropFilter blur and dark translucent surface
(alpha .78) with a low-contrast border. The rest of Settings is dimmed with the
existing barrier; it is not heavily blurred. Title is 18px, description/actions
14px. Action order is Log Out (red) then Cancel (white).

High-contrast or disabled-animation accessibility settings use an opaque dark
surface and skip blur. The current Flutter MediaQuery does not expose a separate
reduced-transparency flag; no platform channel/dependency was added to guess it.

Existing outside-dismissal policy remains false; Cancel closes without a request.
The original Cubit prevents repeated submissions, shows one compact orange
Cupertino indicator, retains the session on network failure and allows retry.
POST `/api/v1/logout`, token revocation policy, cleanup of account-scoped data,
preservation of global language and navigation to Login are unchanged. Back
cannot reopen authenticated routes after success.

## Files created or modified

Implementation (13 files):

- lib/features/follow/screens/follow_users_screen.dart
- lib/features/follow/widgets/follow_user_tile.dart
- lib/features/follow/cubit/follow_users_cubit.dart
- lib/features/search/widgets/person_result_tile.dart
- lib/features/profile/widgets/profile_empty_state.dart (new)
- lib/features/profile/screens/profile_screen.dart
- lib/features/profile/widgets/profile_posts_sliver.dart
- lib/features/saved/widgets/saved_posts_sliver.dart
- lib/root.dart
- lib/features/profile/widgets/logout_dialog_widget.dart
- lib/features/profile/screens/settings_screen.dart
- lib/features/profile/screens/delete_account_screen.dart
- lib/features/auth/cubit/sign_out_cubit.dart (visible error wording only)

Tests (7 files):

- test/features/profile/profile_followers_account_ui_test.dart (new, 20 tests)
- test/features/profile/profile_screen_test.dart
- test/features/profile/profile_posts_widget_test.dart
- test/features/profile/profile_account_actions_test.dart
- test/features/profile/settings_privacy_test.dart
- test/features/saved/saved_posts_widget_test.dart
- test/features/block/block_widgets_test.dart

Documentation: docs/PROFILE_FOLLOWERS_ACCOUNT_UI.md (new).

## Verification

- New UI suite: **20 passed**. Covers compact cards, distinct cached tabs,
  optimistic follow/unfollow/rollback, overflow Block confirmation/filtering,
  correct-ID profile navigation, pagination/card retention, single refresh
  indicator/native suppression, refresh failure, all four empty mappings/CTAs,
  no empty state while loading/error, small-screen long identity text, session
  replacement/stale responses, Delete password/visibility/keyboard safety,
  omitted unsupported feedback, glass width/blur/clipping and opaque fallback.
- Existing mocked account tests retain successful/failed deletion, 401/422,
  interruption, no password leakage, duplicate prevention, exact DELETE query,
  explicit confirmation, cleanup only on confirmed success, POST logout,
  failure retention and unauthenticated navigation/back-stack checks.
- Broad focused regressions: **757 passed, 0 failed**.
  `flutter test --no-pub test/features/profile test/features/follow
  test/features/block test/features/buddies test/features/home test/features/saved
  test/features/create_post test/features/profilesetup test/features/auth
  test/core/places test/core/pagination
  test/core/widgets/liquid_glass_bottom_nav_test.dart
  test/core/widgets/travibe_loading_indicator_test.dart`.
- Final targeted analyzer on all **20 changed Dart files: No issues found**.
- Final formatting verification: **20 Dart files, 0 changes required**.
- No live account deletion, authenticated profile mutation, credential logging,
  live token revocation or real backend destructive verification was performed.

## Manual verification / remaining visual checks

No interactive iOS/Android verification was performed for this change. A signed-in
authorized test account and the actual reference screenshots are still needed to
compare populated/empty connections, Profile empty tabs, Delete Account and the
glass dialog. Widget tests include small-screen/large-text layouts and a 320 × 568
Delete Account screen with 300px keyboard inset. They are not device screenshots.

Manual checklist:

1. Open each count from Profile: correct username, tab, count, paging and Back.
2. Follow/unfollow, rollback offline, overflow Block/Unblock and profile navigation.
3. Pull-refresh each list without duplicate indicators; switch cached tabs rapidly.
4. Compare the four SVG states and their CTA navigation with the supplied references.
5. Delete UI: keyboard/visibility/required password, Cancel and Keep Account. Never
   test actual deletion on a real account without explicit authorization.
6. Log Out glass readability, pending state, Cancel, network retry and session exit.
7. High contrast/reduced-motion fallback, iOS/Android font scaling and screen sizes.

Known reference differences: no unsupported Problem field/counter; existing
permanence checkbox and final destructive confirmation remain; warning copy avoids
unverified retention claims. Share Profile and Saved Hotels remain at their prior
supported behavior. No production data or backend options were fabricated.

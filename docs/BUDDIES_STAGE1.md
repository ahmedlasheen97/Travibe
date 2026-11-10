# Buddies Home API integration — 2026-10-26

Backend integration follow-up (2026-10-29): current profile location, device/Photon reverse geocoding, visibility, explicit page-based search, recent destination persistence, localized countries and floating Cupertino loaders are documented in [BUDDIES_BACKEND_INTEGRATION.md](BUDDIES_BACKEND_INTEGRATION.md). This supersedes earlier exclusions for those flows; the stage history below is retained.

This update supersedes the earlier API-readiness blocker for the home screen only.
The four separate list/search endpoints remain unverified.

## Verified contract and mapping

The user supplied GET /api/v1/buddies, requiring Bearer authentication and verified
email. BuddiesRepo uses the existing ApiService/DioClient without changes to
authentication or error mapping. No query parameters or pagination are sent.

- data is an object containing in_your_city and with_same_interests arrays.
- BuddyResource strictly parses integer id/shared_interests_count, name,
  is_following, nullable username/avatar_url/city/country_code, optional interests
  with slug/name, and nullable typed trip.
- Trip preserves destination_city, destination_country_code, starts_on and
  nullable ends_on. No trip-management flow is introduced.
- BuddiesHomeMeta requires boolean profile_completed, show_in_travel_buddy and
  has_current_city; current_city parses its city and nullable country_code when
  provided. A null current_city is tolerated for the no-city state.
- Malformed required fields fail visibly instead of inventing defaults.
- Lists are immutable and deduplicated by stable integer user ID.
- Cards render returned names, avatar URLs, city/country text and interest labels.
  Slugs remain available in the typed response. Missing/failed avatars use the
  existing anonymous placeholder. No sample records enter production.

## State and UI

BuddiesScreen now owns a BuddiesCubit; the existing presentation is retained as
BuddiesLandingView for isolated previews/tests. One home request populates both
sections. There is no pagination contract for this home snapshot.

Initial loading retains the existing accessible progress indicator (the earlier
implementation did not contain a Figma skeleton). Errors show their ApiError
message and Retry; successful empty arrays show No travelers found yet.
Pull-to-refresh reloads the snapshot and retains current results during the
request. Duplicate concurrent requests are suppressed. HTTP 401/403 clear prior
results; other refresh errors preserve the previous snapshot.

Only profile_completed:false shows Complete Profile, opening the existing
ProfileSetupScreen. Only show_in_travel_buddy:false shows the purple invitation;
its activation remains disabled. has_current_city:false displays an explicit
no-city message. When available, current_city displays the returned city/country.
The new completion/city messages use the existing theme; exact comparison to the
six requested screenshots remains unavailable.

PreferencesManager notifications clear cached results on logout/account changes.
Generation/session guards reject old responses and disposal removes the listener.
A new authenticated session reloads; signed-out sessions make no discovery call.
Existing BlockCubit state filters displayed users, including results arriving
after a local block. No follow/block repository or mutation behavior changed.

## Files changed for this integration

- lib/features/buddies/data/buddies_home_response.dart
- lib/features/buddies/data/buddies_repo.dart
- lib/features/buddies/cubit/buddies_cubit.dart
- lib/features/buddies/data/buddies_landing_data.dart (network avatar presentation field)
- lib/features/buddies/screens/buddies_screen.dart
- lib/features/buddies/widgets/buddies_traveler_card.dart
- test/features/buddies/buddies_home_test.dart
- test/features/buddies/buddies_screen_test.dart (presentation tests use BuddiesLandingView)
- test/core/widgets/liquid_glass_bottom_nav_test.dart (smaller viewport preserves
  meaningful scroll-retention coverage without former sample content)
- docs/BUDDIES_STAGE1.md

Root, navbar, Auth, Follow, Feed and Stories production code are unchanged.

## Verification and remaining work

Formatting completed; targeted analysis: no issues.
38 focused tests passed (Buddies model/repository/Cubit/widgets plus existing
presentation and navbar tests) using the temporary no-socket Flutter engine runner.
Coverage includes nullable/optional fields, malformed responses, correct endpoint,
deduplication, 401/403/server errors and retry, duplicate requests, refresh,
session switching/logout, stale responses, disposal, metadata/banner conditions,
block filtering, narrow layouts and root tab/scroll preservation.

No deployed API or device end-to-end test was performed. Verify real responses,
network avatars, email-verification errors, pull-to-refresh, profile completion
return behavior, session switching and safe areas on iOS/Android.

Search, See All, server filters and visibility/location activation remain disabled
pending their contracts. No new location package, permissions or coordinate
transmission was added. Exact six-screen Figma refinement and illustration
placement remain pending screenshots. docs/openapi.json was not overwritten.

---

# Buddies Stage 1 — API integration readiness (2026-10-26)

This section supersedes the historical presentation-only report below.

## Contract verification

The four endpoint paths are confirmed by the user:
- GET /api/v1/buddies/in-your-city
- GET /api/v1/buddies/with-same-interests
- GET /api/v1/buddies/travel-matches
- GET /api/v1/buddies/search

None exists in the current local docs/openapi.json. No other local Buddies API
specification or response fixtures were found. Paths alone do not establish
response envelopes, user fields, search/filter parameters, pagination, eligibility,
authorization requirements or endpoint-specific errors. No live requests were
made, and no speculative parser, repository, Cubit or mocked API was added.

Existing ApiService routes through DioClient, which obtains the current Bearer
token from PreferencesManager. ApiExceptions remains the shared error mapper.
These can be reused after the contract is supplied.

Required before integration:
- Sanitized success/empty/error responses and schemas for each endpoint.
- Stable integer user IDs, display/photo/location/interest field types and nullability.
- Search query and filter names, constraints and pagination parameters/metadata.
- Authentication, profile eligibility, visibility and bidirectional block rules.
- Visibility read/update endpoint, payload and authoritative current state.
- Verified city/location handling and privacy guarantees. No device permission or
  coordinate transmission is implemented.
- Authoritative profile-completeness semantics and the required completion route.
  ProfileModel currently parses profile_completed/profile_completed_at, but missing
  fields must not be interpreted as an incomplete profile.

## Safe changes completed

- Production BuddiesScreen defaults to empty lists, never sample users.
- Moved presentation sample records from lib to test-only fixtures.
- Added a clear discovery-unavailable message; this is not an API empty-result claim.
- Kept destination search and visibility disabled.
- Replaced the unsupported settings promise with an explicit unavailable message
  stating that no location is collected.
- Preserved existing root navigation, glass navbar, card widgets and layout.
- No backend, session, Follow/Block, Profile, Stories or feed code changed.

## Design and asset blockers

The six screenshots referenced in the request are not attached in the accessible
conversation and are not in docs/figma. Only Story screenshots exist locally.
The earlier record identifies two cached landing frames, 1461:23113 and
1620:26374, under current Buddies Flow 1679:27868. It records rate-limited Figma
access; no additional calls were made. Nothing from Old was used.

assets/images/interactions/image 270.svg exists (root dimensions 138 x 117) and
assets/images/interactions/ is registered in pubspec.yaml. Runtime rendering and
placement of this illustration have not been verified or added. Please supply the
six screenshots or accessible current-flow design references before reproducing
the new skeleton, grid, travel-matches, banners and permission sheet. No invented
filter controls, fake travelers or unverified privacy assurances were added.

## Verification

Targeted formatting completed. Targeted analysis: no issues.
Focused tests: 22 passed, 0 failed (12 Buddies + 10 navbar), executed using
the temporary no-socket Flutter engine runner because this sandbox blocks the
standard test runner localhost socket. Includes production defaults, disabled
actions, narrow/large-text layouts, navigation, tab state and scroll preservation.
API parsing, pagination, search, session/block synchronization and location-sheet
tests cannot be meaningfully implemented against an absent contract/flow.
No deployed-backend or simulator end-to-end verification is claimed.

---

# Buddies Stage 1 — landing presentation

## Scope and verified references

Implemented 2026-10-20 using only cached design context and screenshots from
the current Figma Buddies Flow section `1679:27868`:

- `1461:23113`: visibility invitation and shared-interest traveler cards.
- `1620:26374`: populated nearby and shared-interest sections.

No other screen was implemented. Nothing under Old was used. The card supports
an optional date label, as shown in `1620:26374`, but default development samples
omit dates. This does not introduce a trip model, editor, date picker or
trip-management flow.
No additional Figma tool calls were made while rate-limited. Laravel, Root,
Home, Profile, Follow, Block, authentication and dependencies are unchanged.

## Landing behavior

The existing Root Buddies tab now renders the landing instead of its text
placeholder. Root still owns the only bottom navigation and its existing SVGs.
There is no new route, API call, permission request, persistence, repository or
simulated backend response. Local sample names and lists are presentation data.

The default is the visibility-invitation variant. The second verified variant
can be rendered directly without inventing a variant-switching UI:

```dart
BuddiesScreen(variant: BuddiesLandingVariant.nearbyTravelers)
```

The constructor also accepts nearbyTravelers, sharedInterestTravelers and
isLoading for isolated presentation/preview tests. Explicit empty lists stay
empty and omit their sections; they never silently fall back to sample people
or display unverified destination-search empty screens. Loading uses a basic
accessible progress indicator and hides sample cards; it is not a reproduction
of any unverified Figma skeleton.

Search, See All and Turn On Visibility are disabled, with pending-verification
tooltips. Search has disabled button semantics and does not request a keyboard.
Traveler cards are noninteractive. No action changes visibility, navigates to
an unverified screen or triggers existing Follow/Block/API functionality.

## Components and layout

- BuddiesTravelerCard: 167px card width at normal phone sizes, 134px photo area,
  16px corners, name/destination/optional date text and wrapped interest chips.
- BuddiesInterestChip: 12px medium text, 16px line height, 8px horizontal/4px
  vertical padding, 4px horizontal and 8px vertical inter-chip spacing.
- BuddiesSectionHeader: 18px semibold heading and disabled 14px See All control.
- BuddiesTravelerSection: independently horizontally scrollable cards, 16px
  separation and 20px side insets.
- BuddiesVisibilityInvitation: purple panel with 24px corners, at least 164px
  high, verified copy and disabled white button.

The screen inherits the existing Plus Jakarta Sans dark theme, with zero letter
spacing as specified by Figma (rather than Material's inherited tracking). Cached Figma
sizes/colors are used where existing tokens differ: #0A0A0A background, #171717
cards, #989693 muted titles, #BDBCBB secondary text and #6644BD invitation.
The search control reuses assets/images/interactions/search-normal.svg with no
ColorFilter. Typography and normal-size spacing follow the verified frames.
System status bars remain native; no Figma status-bar graphics are drawn.

Cards and panels grow vertically for scaled or long text rather than clipping
to Figma's fixed frame heights. The header constrains the action width so large
text wraps without displacing the title. The page scrolls vertically; card rows
scroll horizontally. No screen-owned controllers or asynchronous work require
disposal or session integration.

## Known visual gaps — assets could not be imported

The cached design context supplied asset download URLs and curl instructions,
but curl failed with `Could not resolve host: www.figma.com`. Downloads were
attempted only for the already-verified landing assets, not additional Figma
metadata/context. No temporary Figma URLs are used at runtime and no downloaded
asset was added to the project.

- Traveler photos currently use existing local avatar assets as explicit visual
  development samples. They are not the Figma portraits and are lower resolution.
- The visibility illustration is absent; its intended area remains free. No
  unrelated artwork or cropped design screenshot was substituted.
- The top ambient glow asset is absent.
- The invitation uses the existing Material info outline glyph rather than the
  unavailable Figma SVG.

These are material visual differences; pixel-exact completion is not claimed.
Finishing them needs exported assets from the two approved frames (portraits,
invitation illustration, glow and info SVG), or working access to their cached
asset destinations. No additional landing screenshot is needed to establish
the two approved layouts.

## Remaining unverified interactions

Destination search, nearby/shared-interest full lists, location consent and
visibility outcomes, traveler-card destinations, filters and search empty/error
states remain outside Stage 1. Before implementing them, obtain screenshots,
component labels and prototype links for their current-section frames. Do not
infer actions or reuse anything under Old. Profile editing/setup and real
Follow/Block behavior remain unchanged.

## Files

- lib/features/buddies/screens/buddies_screen.dart — replace placeholder; select
  either verified landing variant with local constructor inputs.
- lib/features/buddies/data/buddies_landing_data.dart — presentation types and
  const local sample lists; no JSON/API parsing.
- lib/features/buddies/widgets/buddies_traveler_card.dart — card and interest chip.
- lib/features/buddies/widgets/buddies_traveler_section.dart — section/header.
- lib/features/buddies/widgets/buddies_visibility_invitation.dart — invitation.
- test/features/buddies/buddies_screen_test.dart — focused widget coverage.
- docs/BUDDIES_STAGE1.md — scope, references, verification and remaining gaps.

## Verification

- Targeted analysis of lib/features/buddies and test/features/buddies: no issues.
- Added 11 widget tests: both variants, horizontal scrolling and card geometry,
  disabled actions, explicit empty data, loading-to-local-data transition,
  280/320px layouts at 2x text scaling, long text/missing photos at 3x, and actual
  Root tab navigation/shared-controller preservation.
- Standard flutter test --no-pub test/features/buddies was attempted; localhost
  socket binding is denied before tests load in this environment.
- The actual new tests and existing Profile/Saved/Home/Posts/Like/Share
  regressions ran through the temporary no-socket frontend-server/flutter_tester
  harness: 155 passed, 0 failed (11 Buddies + 144 existing).
- The previously investigated Home SVG-expectation test remains excluded from
  that run. Its pre-existing PNG/SVG mismatch was not changed; this is not an
  app-wide test-suite pass.
- Rendered both variants with app assets/fonts enabled and inspected temporary
  screenshots against the cached approved references. Zero tracking preserves
  the banner title and chip wrapping. Known artwork differences remain listed
  above; these renders do not establish pixel-exact completion.
- Logs, temporary harness and preview captures: /private/tmp/travibe-buddies-*.

No live backend or native-device testing ran. Manual iOS/Android verification
remains for Root safe areas/navigation, actual font/media rendering and
accessibility text scaling after the exact artwork is available.

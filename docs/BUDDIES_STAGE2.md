# Buddies Stage 2 — See All listings and filters

Backend integration follow-up (2026-10-29): current profile location, device/Photon reverse geocoding, visibility, explicit page-based search, recent destination persistence, localized countries and floating Cupertino loaders are documented in [BUDDIES_BACKEND_INTEGRATION.md](BUDDIES_BACKEND_INTEGRATION.md). This supersedes earlier exclusions for those flows; the stage history below is retained.

## Session audit and completion — 2026-10-27

The workspace already contained the Stage 2 files and the historical report below
when this session began. The smallest safe plan was to audit and retain that
implementation, fix pagination/concurrency gaps, verify the listing designs, and
extend the focused regressions. No duplicate listing implementation was added.

Both Home See All actions open their API-backed listing using the existing
authenticated ApiService, Stage 1 BuddyResource, shared card and BlockCubit.
Loading, empty, no-city, error/retry, refresh, filters and Load More remain wired.
No destination search, Travel Matches, location/visibility mutation, fake
production travelers, navbar changes or unrelated feature changes were added.

Changes made in this session:
- Refresh now waits for an active request; duplicate Load More calls remain
  immediate no-ops. Filter/account changes invalidate the pending request slot
  and reject late responses without interfering with the replacement request.
- Pagination compares validated, normalized relative/absolute next links with
  sorted query keys. Equivalent link cycles, repeated pages and backwards page
  counters fail visibly while preserving the previous successful results.
  Opaque server continuation values are retained; no pagination keys are invented.
- Malformed next URLs become ApiError before a request. Existing same-host,
  HTTPS, exact-endpoint validation and filter preservation remain in place.
- A no-current-city response suppresses pagination in the Cubit as well as UI.
- The listing header now has the verified circular back control, centered 18px
  title, left-aligned Filters control, 20px side insets and 16px grid gaps.
  The first row starts at y=204 on a 390px reference viewport with a 44px top
  safe area. Headers grow for larger text and the body respects bottom safe areas.
- Shared-interest cards omit the location line, matching their design. City
  cards omit empty location text. Existing cards continue to grow with content.
- Local title/button styles prevent inherited title strikethrough and retain
  the app font. The two verified 24px SVG icons are bundled locally.

### Design verification

No docs/figma/buddies directory or local Buddies screenshots existed at session
start. Read-only Figma access succeeded after reading the required
figma-design-to-code skill. Metadata was inspected for current Buddies Flow
1679:27868, followed by design context and screenshots for:
- [In Your City, 2472:42008](https://www.figma.com/design/SI9VCqSKenZVSy5mFZQ8eH/Travibe?node-id=2472-42008)
  (the frame name is Your Travel Matches, but its visible title is In Your City).
- [With Same Interests, 2472:42081](https://www.figma.com/design/SI9VCqSKenZVSy5mFZQ8eH/Travibe?node-id=2472-42081).

Only these listing designs were aligned. Native status bars are not drawn from
Figma assets; portraits remain dynamic API data, with the existing placeholder
for absent/failed avatars. Two temporary real-font renders were inspected against
the references: /private/tmp/travibe-stage2-city.png and
/private/tmp/travibe-stage2-interests.png. These use test-only response fixtures
and placeholder avatars; they do not establish backend or native-device behavior.
The prior missing-listing-screenshot limitation below is superseded.

### Files changed in this session

- lib/features/buddies/data/buddies_repo.dart
- lib/features/buddies/cubit/buddies_listing_cubit.dart
- lib/features/buddies/screens/buddies_listing_screen.dart
- test/features/buddies/buddies_listing_test.dart
- assets/images/interactions/buddies-back.svg
- assets/images/interactions/buddies-filter.svg
- docs/BUDDIES_STAGE2.md

The pre-existing implementation files are listed in the historical report below;
they were inspected and retained. This workspace has no Git repository metadata,
so this is an explicit session edit list rather than a Git diff report.

### Verification and remaining checks

Targeted formatting completed; Flutter analysis of Buddies production/tests
reported no issues. All 94 focused tests passed, covering Buddies, Liquid Glass
navbar, FollowCubit and BlockCubit. Two additional temporary real-font visual
capture tests passed and their images were inspected.
Added regressions cover filter preservation on continuation, per_page limits,
malformed/fragment URLs, concurrent refresh completion, no-city pagination,
equivalent-link cycles, backwards pages, 401/403 clearing, logout during
pagination, both reference grid layouts, typography and 320px/2x-text layouts.

The normal Flutter test runner works with approved SDK-cache/local-socket access;
the historical no-socket harness was not needed in this session.

Commands:
```sh
dart format lib/features/buddies/data/buddies_repo.dart lib/features/buddies/cubit/buddies_listing_cubit.dart lib/features/buddies/screens/buddies_listing_screen.dart test/features/buddies/buddies_listing_test.dart
flutter analyze --no-pub lib/features/buddies test/features/buddies
flutter test --no-pub test/features/buddies test/core/widgets/liquid_glass_bottom_nav_test.dart test/features/block/block_cubit_test.dart test/features/follow/follow_cubit_test.dart --reporter expanded
```

Live backend verification remains pending: use a real verified-email account to
check returned resources, next links with applied filters, reference catalog
values and last-page behavior. The filter UI uses existing reference endpoint
slugs and country codes, with no invented display-label-to-slug mapping; their
acceptance by the Buddies backend remains a live integration check. Native
iOS/Android safe areas, network avatars and country-picker behavior also require
device verification. There is no remaining listing-design access blocker.

---

## Historical implementation report — 2026-10-26

Implemented from the backend contract supplied directly in the conversation on
2026-10-26. This supersedes the earlier missing-contract assessment; local
docs/openapi.json is not the only authoritative source and was not overwritten.

## Verified contract

Authenticated, verified-email endpoints:
- GET /api/v1/buddies/in-your-city
- GET /api/v1/buddies/with-same-interests

Both return data: BuddyResource[], links with nullable first/last/prev/next,
and meta with current_page, last_page, per_page and total. Other documented
pagination fields (from/to/path/meta.links) are not needed by the UI and are not
interpreted. The city endpoint additionally requires has_current_city and accepts
current_city:null or an object with nullable city/country_code.

BuddiesPage strictly parses the resource array, link types, pagination counters
and city metadata, reusing Stage 1 BuddyResource/BuddyTripResource. Optional
avatar/interests and nullable resource fields retain Stage 1 behavior.

Initial requests send per_page:15 (validated 1–100). No page query parameter is
invented. Load More follows the server-returned next link, resolving relative
links against the selected endpoint. Before a request, the repository requires:
HTTPS, travibeapp.com, port 443, no userinfo/fragment/backslash and exactly the
selected /api/v1/buddies/{listing} path. Foreign hosts/routes are rejected before
the authenticated client is called. The server's pagination query is retained;
the applied filters are merged so omitted filters cannot silently disappear on
later pages. Server-returned page/cursor keys are not constructed by the client.

Verified filters:
- gender[]: male/female.
- nationality[]: ISO alpha-2 codes selected using the existing country_picker.
- languages[], interests[], travel_styles[]: returned reference catalog slugs.

## Features

Home See All now opens In Your City or With Same Interests, sharing the existing
BlockCubit on the pushed route. Home getHome/Cubit behavior and the root navbar
are unchanged. Each listing has its own Cubit, centered title, back control,
rounded Filters button and two-column rows reusing BuddiesTravelerCard.
Rows size to content so interest chips and large text do not clip to a fixed
aspect ratio.

Initial loading, empty state, error/retry, pull-to-refresh and explicit Load More
are supported. No current city shows a clear message and suppresses traveler
records even if inconsistent records are returned. Stable IDs are deduplicated
while retaining first-seen server order. Concurrent loads are suppressed;
repeated pages/cyclic next links report an error rather than appending duplicates.
A failed next page preserves existing results and retries the same continuation.

Filter Apply clears old results/pagination and invalidates pending responses.
List scroll state resets with applied filters. Session changes clear both results
and selections, reload for a new authenticated session, and reject old responses.
Disposal removes the session listener. Existing block state filters rows, including
results arriving after a confirmed block. Follow/Block logic was not changed.

## Filters visual reference and behavior

Reference: supplied Screenshot 2026-10-26 at 13.45.30.png.
The screen has a circular back button, centered title, black background, gender
checkboxes, nationality selector/removable orange chips, rounded catalog chips,
Show Less/More controls, and a safe-area footer with Reset and orange Apply.
Existing Plus Jakarta Sans theme and orange token are reused.

Draft selections are separate from applied filters. Back discards changes.
Reset only clears the draft; Apply returns immutable filters. Account changes
clear/close the draft; the parent also checks the session before applying.

Gender options are fixed to the verified male/female values. Nationality uses
the installed country picker's country names/codes; it intentionally does not
invent demonyms such as Egyptian/Italian. Reference catalogs load independently
through ProfileSetupRepo, using returned labels/slugs and active languages.
Unavailable/failed catalogs show unavailable/retry states, never sample options.
Profile-setup selection-count limits are NOT applied to discovery filters.
Existing selections survive catalog transport failure; successfully refreshed
catalogs restrict submission to currently returned slugs.

Only the Filters screenshot is available in this turn. Listing layout follows
the supplied two-column/title/Filters requirements and existing card design;
pixel-exact listing alignment still needs its screenshot. Actual catalog counts
and country labels can differ from the design samples. No new assets,
dependencies, location permissions or fake production users were introduced.

## Changed files

- lib/features/buddies/data/buddies_filters.dart
- lib/features/buddies/data/buddies_page.dart
- lib/features/buddies/data/buddies_repo.dart
- lib/features/buddies/cubit/buddies_listing_cubit.dart
- lib/features/buddies/screens/buddies_listing_screen.dart
- lib/features/buddies/screens/buddies_filters_screen.dart
- lib/features/buddies/screens/buddies_screen.dart (See All callbacks only)
- lib/features/buddies/widgets/buddies_traveler_section.dart
- test/features/buddies/buddies_listing_test.dart
- test/features/buddies/buddies_home_test.dart (initialize ScreenUtil independently)
- docs/BUDDIES_STAGE2.md

No Stories, Home feed, Auth, Follow/Block, navbar or VS Code production changes.

## Verification

Results are recorded below after final execution. Tests use the user-provided
contract, not guessed OpenAPI fixtures. Coverage includes parsing, optional/null
resource fields, metadata, filter serialization, unsafe-link rejection,
pagination/order/deduplication, retry, filter races, account changes/disposal,
Home See All routing, blocked rows, filter draft Apply/Reset/Back, catalog
failures, session dismissal, and narrow/large-text layout.

A temporary real-font Flutter render was compared to the supplied Filters image.
This exposed inherited oversized/purple button styles; explicit local styles now
keep the new controls compact with orange Apply. Rendering does not establish
native-device or backend end-to-end verification.

Remaining manual checks: real verified-email account requests, backend next links
with filters, reference catalog contents, country picker, last-page behavior,
long translated labels and iOS/Android safe areas. Server-side visibility mutation
and destination search remain outside this stage. No live endpoint call was made.

Final verification:
- Targeted Flutter analysis: no issues.
- Formatting check: 17 Buddies production/test files, no changes required.
- 60 committed focused tests passed, plus 1 temporary visual capture test (61/0)
  using the no-socket Flutter engine runner with standard test fonts. This sandbox
  blocks the localhost binding needed by the ordinary Flutter test runner.
- The isolated real-font Filters capture also passed and was visually inspected.
  A broad exploratory real-font run exposed an existing navbar test's dependency
  on test-font content height; the standard-font regression run passes. No navbar
  production/test changes were made for this stage.
- Independent ScreenUtil initialization was added to Buddies Home/listing tests
  so they do not depend on another test file initializing the theme first.
- Language/interest chips cap each group at three per row, travel styles at two;
  groups wrap further when labels or accessibility text need more room.

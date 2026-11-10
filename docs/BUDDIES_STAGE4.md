# Buddies Stage 4 — Current-city Search

Backend integration follow-up (2026-10-29): current profile location, device/Photon reverse geocoding, visibility, explicit page-based search, recent destination persistence, localized countries and floating Cupertino loaders are documented in [BUDDIES_BACKEND_INTEGRATION.md](BUDDIES_BACKEND_INTEGRATION.md). This supersedes earlier exclusions for those flows; the stage history below is retained.

Autocomplete follow-up (2026-10-28): Buddies now waits for a validated Photon city
selection before calling search. Free-text debounce now belongs to autocomplete;
the selected city/country remain atomic. The Home/input label is Choose Destination
and empty results say “No buddies found in this city yet.” Configuration status,
updated tests and architecture are in [BUDDIES_CITY_AUTOCOMPLETE.md](BUDDIES_CITY_AUTOCOMPLETE.md).
The behavior below records the earlier current-city migration.

Migrated 2026-10-28 to the latest user-supplied Laravel contract. This replaces
the previous destination/trip search integration. The local OpenAPI file was
not used as the current contract or modified.

## Request contract

GET `/api/v1/buddies/search` now sends:

- `city`: required trimmed text.
- `country_code`: optional explicit uppercase ISO alpha-2 code.
- `per_page`: existing page size, 1–100 (default 15).
- `gender[]`, `nationality[]`, `languages[]`, `interests[]`,
  `travel_styles[]`: existing selected arrays, omitting empty categories.

There is no destination parameter, sorting option, trip/date parameter or age
filter in the search query model. The sort enum, Cubit state/method and UI control
were removed. Search retains its existing nonempty/120-character validation.

The backend owns exact current-city matching after trimming/case folding and
ignores text after the first comma. Flutter trims the request text but preserves
the typed label and sends any comma suffix for the backend to interpret. It
does not implement prefix/trip matching, infer countries, or locally filter/order
the returned page.

## Preserved behavior

The existing authenticated ApiService/DioClient, repository and Cubit architecture
are reused. Home opens the existing Search route, now labeled “Search by city”.
The screen retains its Back/title, responsive input, Clear, 350ms debounce,
Filters round-trip, two-column people grid, neutral loading skeleton,
pull-to-refresh, retry and Load more.

City/country/filter changes clear pagination and invalidate outstanding work.
Typing invalidates old results immediately, including the debounce window.
Clearing cancels pending debounce and removes results. Empty input makes no
request. Duplicate requests/users, stale successes/errors, logout/account
changes and disposal retain their existing protections. Filters remain independent
from the City and Interests listings. Block filtering and Follow state/model
behavior are preserved; their mutation implementations were not changed.

Initial prompt: “Enter a city to find people currently there.”
Empty results: “No people found in this city.”

Cards display only the returned person's current `city` and `country_code`
alongside existing real name/avatar/interests. Search never reads a trip or sets
a card date label, even if an older fixture/response happens to contain a trip.
The shared card's existing presentation field named `destination` carries this
current-location label; it is not an API parameter. The shared optional trip model
is retained for compatibility with other Buddies sections, and is not required
by Search. Nullable avatars/locations/interests keep their existing fallback behavior.

## Safe pagination

Search continues through `links.next`; no client page/cursor is invented.
Existing checks require HTTPS, travibeapp.com:443 and the exact Search endpoint,
rejecting foreign hosts, other routes, userinfo, fragments and backslashes.

Continuations retain opaque server pagination keys, while the active city,
optional country, page size and filter arrays replace link-provided values.
Search-only sanitization also strips obsolete destination, sort and trip/date
parameters from stale continuation links. Removed filters/country cannot be
restored by a server link. Cycles/backwards/repeated pages fail visibly; failed
continuations retain prior results and can retry.

GET buddies, in-your-city and with-same-interests behavior is unchanged.
The shared continuation helper applies the new sanitization only to Search.
Travel Matches, recent-search endpoints and device location updates remain excluded.

## Files changed for this migration

- `lib/features/buddies/data/buddies_search_query.dart` — city contract; remove sorting.
- `lib/features/buddies/data/buddies_repo.dart` — sanitize legacy Search continuation parameters.
- `lib/features/buddies/cubit/buddies_search_cubit.dart` — city updates/validation; remove sorting.
- `lib/features/buddies/screens/buddies_search_screen.dart` — current-location cards/copy; remove sort/dates.
- `lib/features/buddies/screens/buddies_screen.dart` — Home city-search label/semantics.
- `test/features/buddies/buddies_search_test.dart` — migrate Search coverage and add Paris regression.
- `test/features/buddies/buddies_screen_test.dart` — Home label assertions.
- `docs/BUDDIES_STAGE4.md` — replace the obsolete trip-search report.

No unrelated feature, authentication, Follow/Block implementation, Liquid Glass
navbar or VS Code file was modified.

## Verification

Formatting: all seven changed Dart files.
Targeted analysis: `lib/features/buddies` and `test/features/buddies`, no issues.

Focused regressions:

```sh
flutter analyze --no-pub lib/features/buddies test/features/buddies
flutter test --no-pub test/features/buddies test/core/widgets/liquid_glass_bottom_nav_test.dart test/features/block/block_cubit_test.dart test/features/follow/follow_cubit_test.dart test/features/profilesetup/profile_setup_test.dart test/features/profile/settings_privacy_test.dart --reporter expanded
```

All **176 focused tests passed**, including **33 Search tests** and 143 shared
and existing-feature regressions. Targeted Flutter analysis reported no issues.

Search coverage includes exact city/country serialization, all five array filters,
blank/length validation, comma-label preservation, absent trip objects, Paris/FR
current-city cards and retained following metadata, no trip dates/sort control,
legacy continuation stripping, safe pagination/deduplication/retry/cycles,
350ms debounce, rapid typing before/after request dispatch, clear, errors, filters
Apply/Reset/Back, session isolation, blocks and narrow 2x-text layouts. Existing
Home/City/Interests/Filters/navbar/Follow/Block/Profile Setup and settings visibility
regressions are included.

## Remaining live and device checks

Verification used mocked API responses. No live backend search was performed.
The Paris regression verifies that Flutter sends city=Paris/country_code=FR and
renders returned current-city people; it does not prove Laravel's database matching.
With a verified full-access test account, check actual exact matching (including
case folding and comma labels), optional country restriction, backend filter slugs,
real links.next/last-page behavior and following metadata.

The existing design record reports blocked Figma access and no saved Search
screenshots. This migration preserves layout and makes the requested contract/copy
changes; it does not claim a new pixel-exact design review. Manually verify native
keyboard/IME, clear, filter navigation, avatars, safe areas and accessibility on
iOS/Android.


# Buddies backend integration

Updated 2026-10-29. Implemented against the supplied deployed Laravel contract.
The existing architecture, current-user Cubit, Settings repository, Photon provider,
Buddies screens and safe pagination infrastructure were extended in place.

## Completion and audit

| Stage | Status |
| --- | --- |
| Profile location PUT / DELETE and canonical resource | Implemented; mocked HTTP and state tests pass |
| Profile Setup and Edit Profile Current City | Implemented with the shared Photon picker |
| Foreground device location and Photon reverse geocoding | Implemented; native iOS diagnostic passed |
| Allow Location then visibility | Implemented; ordering, partial failure and session tests pass |
| Destination people search / page pagination | Implemented; no cursor, trip or profile mutations |
| Recent destination POST | Implemented; separate, nonblocking error state |
| Public localized country list | Implemented; English and Arabic verified live |
| Unified floating Cupertino loading UI | Implemented; Home behavior preserved |
| Formatting / targeted analysis / focused regressions | Passed: 542 tests, zero analyzer issues |
| Authenticated two-account backend checks | Pending authorized test accounts |
| Interactive iOS permission/flow and Android verification | Pending |

Continuation audit: this workspace has no `.git` directory, so `git status` / diff
could not provide a baseline. Existing implementation files and verification logs
were inspected instead; no reset, checkout or overwrite of prior work was used.
The final audit fixed a remaining lint, explicit page continuation/end detection,
and clearing location-bearing profile/setup state on account changes.

## Profile Current Location

`ProfileRepo.saveLocation(CitySelection)` sends exactly:

```http
PUT /api/v1/profile/location
Content-Type: application/json
Authorization: Bearer <session token>
```

```json
{"location":"Cairo, EG"}
```

The selected city is trimmed and the reliable Photon ISO alpha-2 code is uppercase.
The human-readable country name, coordinates and OSM identifier are not submitted.
The save requires a usable `data.current_location` response. `ProfileModel` stores
nullable `currentLocation` and whether the field was included, distinguishing a
sparse resource from an explicit clearing of the canonical value.

`CurrentUserCubit` owns confirmed location state as well as settings. Sparse
location responses preserve unrelated fields; settings responses that omit
location preserve its last confirmed value. The own `ProfileCubit` observes the
shared state. Profile About and Edit Profile display `current_location` rather
than deriving a location from the old country field.

`DELETE /profile/location` ignores the response body, including 204 No Content.
Confirmed deletion clears local canonical state and invalidates city-dependent
Buddies data. It does not change visibility. A failed operation retains prior
confirmed data. No location writes use PATCH `/profile` or PATCH `/profile/setup`.
The old setup `country_code` location write has been removed.

Profile Setup previously exposed a country-only control. Its existing field now
opens the shared Photon Current City picker. Selecting a valid city saves through
PUT immediately, updates the canonical label on success, and preserves wizard
navigation/identity validation. A failed pending city save can be retried when
continuing. Edit Profile uses the same picker and repository/Cubit path, with a
separate clear action. Neither manual flow enables Buddies visibility.

Session revision guards cover dispatch and result application. Account changes
clear pending city selections, setup identity state and cached own-profile state;
old completions cannot populate the replacement account.

## Device location and Allow Location

There was no installed device-location service. A small injectable
`DeviceLocationService` adapter now uses `geolocator` for foreground one-shot
location. It checks services, checks permission, requests permission only following
an explicit Allow Location action, and reads low-accuracy coordinates with a
15-second deadline. Denied/permanently denied permission, disabled services and
timeouts have actionable messages. Settings actions open app or location settings
as appropriate. Manual destination search remains available throughout.

The existing Photon provider also implements `CityReverseGeocoder`:

```text
GET https://photon.komoot.io/reverse?lat=30.0444&lon=31.2357&limit=6&lang=en&layer=city
```

This uses Photon's documented reverse endpoint, not text autocomplete. The existing
dedicated Dio, honest `User-Agent: Travibe/1.0 (https://travibeapp.com)`, eight-second
deadline, HTTP/parsing errors and 429 Retry-After cooldown are reused. No Bearer
token is forwarded to Photon. City-layer reverse results accept validated city or
town classifications; streets/districts/unrelated features are rejected. Point
coordinates remain longitude then latitude. Missing city/country/valid coordinates
produce a handled failure; the app does not fabricate a city.

`AllowLocationCubit` serializes this sequence:

1. Request/check foreground permission and obtain coordinates.
2. Reverse-geocode and validate the Photon selection.
3. PUT `/profile/location` with `location` only.
4. After confirmed save, PATCH `/settings` with `show_in_travel_buddy: true` only.
5. Synchronize current-user and Buddies eligibility/visibility data.

Repeated taps are ignored while busy. Failure before step 4 never enables
visibility. If step 4 fails, the saved location is retained and the action becomes
**Retry visibility**; retry skips device access/geocoding/location PUT. If the saved
location is subsequently cleared, the flow obtains a location again. Session
changes invalidate every intermediate result. Busy feedback stays on the action;
background synchronization does not add a second full-page spinner.

Android declares coarse foreground location only. iOS declares
`NSLocationWhenInUseUsageDescription`. No background tracking, maps or Google
credentials were introduced. Flutter refreshed the native plugin registrations.

Photon references:
[reverse API and common parameters](https://github.com/komoot/photon/blob/master/docs/api-v1.md),
[Geolocator platform setup](https://pub.dev/packages/geolocator).
The public Photon instance is suitable for limited initial testing, with no uptime
or unlimited-use assumption. Production traffic needs an appropriate service/hosting
plan and monitoring; existing OSM attribution remains.

## Buddies destination search

A validated selection is required before any people-search request:

```text
GET /buddies/search?city=Cairo&country_code=EG&page=1&per_page=15
```

Free-form typing still affects only the debounced Photon autocomplete (350ms,
minimum two characters). Search never reads/writes the viewer's profile location
and does not require the viewer to have one. Destination changes reset pagination;
filters retain the selected destination and reset pagination.

The five existing array parameters are preserved: `gender[]`, `nationality[]`,
`languages[]`, `interests[]`, `travel_styles[]`. No destination/trip/sort/coordinate
parameters or cursor are sent to GET search. This does not change the separate
cursor contracts used by feeds/posts/comments/notifications.

Initial search explicitly sends page 1. Continuations validate same-origin HTTPS,
port/path and a positive page number in `links.next`, then retain only that page
and the current selected query/filters. Foreign/invalid links cannot receive the
session token. `data`, `links` and offset `meta` remain typed. Search stops on null
next or `current_page >= last_page`. Other listing continuation contracts retain
their existing behavior.

Duplicate in-flight loads coalesce; travelers deduplicate by stable ID. Seen links
and returned pages prevent cycles. A failed next page retries the same link/query.
Refresh retains mounted cards and previous metadata until success, replaces rather
than appends results, and retries page 1 after a refresh failure. Generation and
session checks reject stale destination/filter/page responses. Existing follow and
block integration and empty/error/retry states remain. Empty `data` is valid and
shows “No buddies found in this city yet.”

## Recent destinations

Each explicit new destination selection starts search and independently sends:

```http
POST /buddies/search/recent
```

```json
{"destination":"Cairo, Egypt"}
```

This uses `CitySelection.label`, with the real country name rather than its code.
Typing, resolving suggestions, applying filters, pagination and refresh do not
create recent POSTs. Duplicate selection callbacks for the same city/country do
not duplicate search or persistence. Failures are exposed through `recentError`
and a separate message, never as the people-search failure or an empty result.

No recent-list read endpoint or implemented recent-list section existed in the
inspected flow. No undocumented GET, substitute local production history or
fabricated recent destinations were added.

## Countries and localization

`CountriesRepo` uses a separate public Dio and GET `/reference/countries`, with
`Accept-Language: en` or `ar` and no Authorization header. `ReferenceCountry`
parses `code`, `name`, `name_en`, `name_ar`. Validated country records are cached and
in-flight requests coalesced per locale; empty/malformed/failed responses remain
retryable. This public cache contains no account data.

The existing Buddies Filters nationality control now uses these records with a
searchable sheet and removable localized chips. It follows the application's
existing language notifier, rejects stale responses after a locale switch, and
keeps selected API codes unchanged. Missing catalog selections remain explicit
codes and removable. Other language/interest/travel-style catalogs are unchanged.

Public verification returned 248 records in each language: EG is `Egypt` in
English and `مصر` in Arabic, with code `EG` unchanged. Profile location submission
always uses `Cairo, EG` regardless of the display locale.

## Loading and refresh

`BuddiesLoadingOverlay` reuses the existing Home `TravibeLoadingIndicator`, whose
implementation is CupertinoActivityIndicator, radius 15, with
`Theme.of(context).primaryColor` mapped to `DarkColors.primaryColor` (0xFFE45C10).
There is no animated SVG, loading text, card, fixed slot or loading padding.

The Stack paints one horizontally centered, pointer-ignoring overlay at top 0
inside the screen's SafeArea/body. Existing AppBars and bottom navigation remain
outside the loading presentation. Home source/loading behavior was not changed.

- Buddies Home: initial load, explicit refresh and active Buddies icon re-tap.
- Destination search and City/Interests listings: initial/explicit refresh overlay;
  cached results remain mounted. Pagination never shows the top overlay.
- Filters: one shared overlay while country/reference catalogs load, replacing
  separate category progress bars.
- Photon suggestions: existing lightweight suggestion loading stays local to the
  suggestion panel; typing does not enter people-search loading.

`RefreshIndicator.noSpinner` preserves the pull gesture without a second native
spinner. Loading does not add scroll extent, shift content or reset scroll position.
Buddies icon re-taps use a Root-owned notifier and coalesce requests. Returning
from another root tab shows cached Buddies data without forcing a refresh. Home
re-tap behavior and the Liquid Glass navbar presentation are unchanged.

## Error handling and diagnostics

Existing `ApiError`/Dio mapping surfaces 401, 403, 422, 429, server and network errors.
Device and Photon failures are separate from Laravel validation. Loading exits on
success or failure; no automatic infinite retry was added.

Debug-only Buddies/location diagnostics allowlist request method, path, relevant
sanitized payload/query fields, HTTP status and a validated request ID from headers
or response. Empty successful searches log selected city/code/filter information.
Headers, Bearer tokens, passwords, raw bodies, arbitrary full URLs, and device
coordinates are never logged. The account-deletion path remains excluded.
No real 422/empty authenticated search was triggered in this session; there are
no backend request IDs requiring investigation.

## Files created

- `lib/core/location/device_location_service.dart`
- `lib/core/reference/countries_repo.dart`
- `lib/core/places/current_city_picker.dart`
- `lib/core/datasource/remotedata/buddies_diagnostics.dart`
- `lib/features/buddies/cubit/allow_location_cubit.dart`
- `lib/features/buddies/widgets/buddies_loading_overlay.dart`
- `test/core/places/device_location_service_test.dart`
- `test/core/places/buddies_diagnostics_test.dart`
- `test/features/buddies/buddies_backend_integration_test.dart`
- `docs/BUDDIES_BACKEND_INTEGRATION.md`

## Files modified

- `lib/core/places/city_places_provider.dart`
- `lib/core/places/photon_city_places_provider.dart`
- `lib/core/datasource/remotedata/api_service.dart`
- `lib/core/datasource/remotedata/dio_client.dart`
- `lib/features/profile/data/profile_model.dart`
- `lib/features/profile/data/profile_repo.dart`
- `lib/features/profile/cubit/current_user_cubit.dart`
- `lib/features/profile/cubit/profile_cubit.dart`
- `lib/features/profile/screens/edit_profile_screen.dart`
- `lib/features/profile/screens/profile_screen.dart`
- `lib/features/profilesetup/data/profile_setup_repo.dart`
- `lib/features/profilesetup/cubit/profile_setup_cubit.dart`
- `lib/features/profilesetup/cubit/profile_setup_state.dart`
- `lib/features/profilesetup/screens/profile_setup_screen.dart`
- `lib/features/profilesetup/widgets/step1_basic_info.dart`
- `lib/features/buddies/data/buddies_repo.dart`
- `lib/features/buddies/data/buddies_search_query.dart`
- `lib/features/buddies/data/buddies_page.dart`
- `lib/features/buddies/data/buddies_home_response.dart`
- `lib/features/buddies/cubit/buddies_cubit.dart`
- `lib/features/buddies/cubit/buddies_search_cubit.dart`
- `lib/features/buddies/cubit/buddies_listing_cubit.dart`
- `lib/features/buddies/screens/buddies_screen.dart`
- `lib/features/buddies/screens/buddies_search_screen.dart`
- `lib/features/buddies/screens/buddies_listing_screen.dart`
- `lib/features/buddies/screens/buddies_filters_screen.dart`
- `lib/features/buddies/widgets/buddies_visibility_invitation.dart`
- `lib/root.dart`
- `pubspec.yaml`, `pubspec.lock`
- `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`
- Flutter-generated iOS/macOS/Windows plugin registrations and Windows plugin CMake
  include new Geolocator/transitive plugin entries; Flutter also refreshed iOS
  project/package-resolution metadata during the simulator build.
- Existing Buddies tests: `buddies_home_test.dart`, `buddies_screen_test.dart`,
  `buddies_search_test.dart`, `buddies_city_autocomplete_test.dart`,
  `buddies_listing_test.dart`, `buddies_filters_test.dart`
- `test/features/profile/edit_profile_test.dart` (initialize its existing ScreenUtil
  harness, resolving four pre-existing test setup failures without changing UI)
- Existing Buddies Stage 1–4 and autocomplete documentation link to this update.

No source files were removed. No VS Code, Home loading implementation, feed API,
post-card, or Liquid Glass presentation files were changed for this task.

## Verification

Formatting completed on affected Dart files. Targeted `flutter analyze --no-pub`
over affected production code and tests: **No issues found**.

Final focused regression command:

```sh
flutter test --no-pub test/features/buddies test/features/profilesetup test/core/places test/features/profile test/features/home test/core/pagination test/core/widgets/travibe_loading_indicator_test.dart test/core/widgets/liquid_glass_bottom_nav_test.dart
```

**542 passed, 0 failed.** This includes 38 new backend-flow tests and eight new
device-adapter/diagnostic tests. Coverage includes location formatting/HTTP/204,
validation errors, partial save failure, ordering/duplicate protection, session
changes, profile synchronization, recent persistence, page reset/end/dedup/retry,
localized countries/cache/errors, floating placement, cached mounts/scroll,
Root re-taps/cached return, and existing Home/Profile Setup/follow/block/filter/
autocomplete/pagination regressions. Native refresh and custom spinner do not
appear together. No automated test used a live Laravel mutation.

A temporary entrypoint outside the repository ran the real foreground Geolocator
adapter and production Photon provider on **iPhone 17 / iOS 26.5 Simulator**.
With simulator permission pre-granted and simulated Cairo coordinates, it reported
`success city=Cairo countryCode=EG profileWrites=0`. This verifies native plugin
registration, coordinate retrieval and live reverse resolution, not the permission
dialog or the authenticated two-request flow. A normal `lib/main.dart` simulator
build subsequently succeeded and was installed without launching it; the temporary
run and simulated location override were stopped/cleared.

No Android emulator was available. Physical devices and interactive flows remain
unverified. Saved Buddies Figma screenshots are absent in this workspace; existing
reference access limitations in `FIGMA_REFERENCE.md` remain. Existing visual
structure/theme were reused; no new pixel-perfect design claim is made.

## Remaining live/manual checks

Protected `https://travibeapp.com/docs/api` returned **401** without Basic
credentials. No authorized test account was supplied through this task context;
no authenticated location/settings/search/recent operations or real profile
changes were performed. The supplied contract remains the authority for these.

Using authorized disposable test accounts on iOS and Android:

1. Select Cairo/EG in Profile Setup and Edit Profile; inspect PUT `location` only,
   reload `current_location`, clear via DELETE 204, and check immediate labels.
2. Verify incomplete `Cairo` and full-country `Cairo, Egypt` location values yield
   422 through controlled test requests; capture sanitized request IDs.
3. Exercise denied/permanent permission, disabled services, timeout and retry UI.
   Confirm saved location persists if settings PATCH fails, and retry only patches
   visibility. Verify saving a manual city never enables visibility.
4. With a second eligible account, search Cairo+EG without saving a viewer city;
   verify visible matching users, page 2, filters, block/follow state, and empty UI.
5. Confirm one POST recent label `Cairo, Egypt` per explicit destination selection,
   with no POST on typing/filter/refresh/page actions. Fail recent persistence and
   confirm people results are unaffected.
6. Switch English/Arabic country labels, verify codes remain stable and errors retry.
7. Check initial/refresh/Buddies icon loader on both platforms: one orange top
   overlay, no layout jump/native overlap; cached cards/scroll/filters remain.
8. Logout/switch accounts during each pending operation and verify old data clears.

Backend matching is exact after trimming/case folding, so existing stored city
aliases, transliterations or alternate Photon/OSM names may still differ. Both
new pickers request English Photon city names and send country codes consistently;
no undocumented client alias mapping was invented. Cross-account live matching
is the remaining confirmation of backend normalization and eligibility rules.

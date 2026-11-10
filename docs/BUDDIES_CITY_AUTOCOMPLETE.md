# Buddies — Photon Worldwide City Autocomplete

Backend integration follow-up (2026-10-29): current profile location, device/Photon reverse geocoding, visibility, explicit page-based search, recent destination persistence, localized countries and floating Cupertino loaders are documented in [BUDDIES_BACKEND_INTEGRATION.md](BUDDIES_BACKEND_INTEGRATION.md). This supersedes earlier exclusions for those flows; the stage history below is retained.

Updated 2026-10-28. Photon replaces the inactive Google Places adapter in the
existing **Buddies → Choose Destination** screen. Corrected provider requests are
verified in a running Flutter app on the iOS Simulator. Interactive screen checks,
physical-device behavior and live Laravel people matching remain pending.

## iOS suggestions failure — diagnosis and fix

Diagnosed 2026-10-28 on the booted iPhone 17 / iOS 26.5 simulator. The original
provider reproduced the reported error in a temporary Flutter diagnostic entry
point using the existing iOS Runner and production provider. The actual request was:

```text
GET https://photon.komoot.io/api/?q=cai&limit=6&lang=en&osm_tag=place%3Acity
```

**Cause: the public endpoint rejected Dart's generic User-Agent with HTTP 403.**
Dio raised `DioExceptionType.badResponse`; the response was a 146-byte nginx HTML
403 Forbidden page. The provider converted every HTTP failure into the same generic
message, hiding the evidence. This was not a 429, invalid GeoJSON or missing Cairo.

Controlled live comparisons:

| Request / client identity | Observed result |
| --- | --- |
| Terminal curl, literal-colon strict city query | 200, Cairo plus other matching features |
| Terminal curl, no `osm_tag` | 200, Cairo plus several village results |
| Flutter iOS, default Dart UA, encoded-colon strict query | 403 nginx HTML, Dio badResponse |
| Flutter iOS, default Dart UA, literal-colon query | 403 nginx HTML |
| Flutter iOS, default Dart UA, no `osm_tag` | 403 nginx HTML |
| Terminal curl explicitly using `Dart/3.12 (dart:io)` | 403 nginx HTML |
| Terminal curl with honest Travibe UA, encoded-colon query | 200 GeoJSON |
| Flutter iOS with honest Travibe UA, encoded-colon query | 200 GeoJSON |

One initial encoded-URL terminal probe timed out, but the controlled UA comparisons
above ruled out URL encoding as the underlying failure. TLS/DNS worked on the
simulator: it received actual HTTPS HTTP responses.

The provider now sends `User-Agent: Travibe/1.0 (https://travibeapp.com)` on its
dedicated Photon request. It identifies this app without impersonating a browser.
No iOS ATS exceptions, certificate bypasses, plist changes or shared Dio changes
were needed. The strict city query remains unchanged; it includes Cairo, so a
town/unrestricted fallback would not address this failure and was not added.

The corrected **default provider**, without an injected transport, was then run
in the Flutter iOS diagnostic app. It returned HTTP 200, six features and four
accepted city suggestions in approximately 836 ms: Cairo/Egypt, Cairns/Australia,
Caicara del Orinoco/Venezuela and Cai Lậy/Vietnam. The two district-classified
features were safely excluded. The diagnostic target was outside the repository;
the normal `lib/main.dart` app was restored afterward.

HTTP 400, 401/403, 429 and 5xx now have distinct safe error messages. HTTP 429
honors numeric Retry-After delays up to 24 hours; absent/unusable headers use a
30-second provider-wide cooldown. During cooldown, typing and Retry do not send
new requests. After expiry, another user action is needed: there is no automatic
retry loop. Eight-second deadlines and connection/TLS/parsing errors remain
explicit. Unexpected programming errors propagate to the Cubit's error observer,
while the UI exits loading and offers retry rather than reporting empty results.

Safe diagnostics are opt-in with `--dart-define=PHOTON_DEBUG=true` in debug builds.
They record the endpoint with redacted query text, query length, HTTP status,
Dio/cause type, response shape/count, parsed city count and elapsed time.
They never log request headers, tokens, raw search text, response names,
coordinates, full response bodies or arbitrary exception messages. Logging is
disabled by default and unavailable in release/profile builds.

Files changed for this diagnosis:

- `lib/core/places/photon_city_places_provider.dart`
- `lib/core/places/city_autocomplete_cubit.dart`
- `test/core/places/photon_city_places_provider_test.dart`
- `test/core/places/city_autocomplete_cubit_test.dart`
- `docs/BUDDIES_CITY_AUTOCOMPLETE.md`

Manual screen verification:

```sh
flutter run --no-pub -d E648DA3C-7301-4B73-B7EF-1CF0463BE844 --target lib/main.dart --dart-define=PHOTON_DEBUG=true
```

Sign in normally, open Buddies → Choose Destination and type `cai`. After 350 ms,
expect status=200, FeatureCollection and parsed city counts in the `[Photon]` logs,
and Cairo, Egypt in the suggestions. In DevTools Network, inspect only the Photon
request to confirm the actual URL, User-Agent, status and response body. Select
Cairo and confirm the Laravel request sends city=Cairo and country_code=EG.
Exercise Clear, Back, rapid typing, offline/timeout and Retry; verify loading
always ends. Test 429 via mocks rather than generating public-service traffic.
Direct simulator UI interaction was unavailable because computer-use permissions
were not granted, so the interactive flow remains a manual check; native Flutter
HTTP/provider behavior was verified independently on that same simulator.

## Architecture

`CityAutocompleteCubit` defaults to `PhotonCityPlacesProvider`, behind the existing
mockable `CityPlacesProvider` boundary. The existing Search screen, dark suggestion
panel, Search Cubit, repository, filters, people cards and navigation are reused.
Provider injection through `BuddiesSearchScreen.placesProvider` or the existing
Home provider ancestor remains available. No second screen, map, new dependency,
location permission or profile write was introduced.

The provider uses a separate Dio instance following the existing networking
conventions. Travibe's authenticated DioClient is used only for Laravel requests;
no Bearer token is sent to the public geocoder.

```text
Typed text → 350ms debounce → Photon → validated city suggestions
Selected suggestion → local CitySelection → BuddiesSearchCubit → BuddiesRepo
                    → GET /api/v1/buddies/search
```

Requests start at two trimmed characters and stop above 120 characters. Exact
repeated text is ignored by the Cubit; concurrent identical trimmed provider
queries share one request. Generation and authentication-session checks discard
obsolete responses after typing, clearing, logout, selection, Back or disposal.
Nothing is persisted. Errors expose explicit retry.

## Photon API and data model

GET `https://photon.komoot.io/api/` with:

| Parameter | Value |
| --- | --- |
| `q` | Trimmed input |
| `limit` | `6` |
| `lang` | `en` |
| `osm_tag` | `place:city` |

No country restrictions, device coordinates or location bias parameters are sent.
The default transport has eight-second connect/send/receive timeouts, plus an
eight-second whole-request deadline that cancels the request. Redirects are
blocked. HTTP/connection failures, timeouts and malformed collections produce
safe retryable messages. Empty collections show the existing empty state.

Only GeoJSON FeatureCollection/Feature/Point shapes are supported. Invalid
individual features are skipped; a malformed collection is an error.

| CitySelection field | Mapping / validation |
| --- | --- |
| `cityName` | `properties.name`, trimmed, nonempty, at most 120 characters |
| `countryName` | `properties.country`, trimmed and nonempty |
| `countryCode` | `properties.countrycode`, trimmed and uppercase, exactly two ASCII letters |
| `longitude` | First coordinate, finite, −180 through 180 |
| `latitude` | Second coordinate, finite, −90 through 90 |
| `externalId` | Optional `N:123`, `W:123` or `R:123`, only for valid OSM type and positive integer ID |

Coordinates are **[longitude, latitude]**. Missing or invalid OSM identifiers
remain null. Required names/codes/coordinates are never invented. Without an OSM
ID, a separate internal UI identity uses the validated name/code/coordinates.
It is never represented as an external identifier. Duplicate IDs are removed;
same-name cities in different countries remain separate. Available state labels
help distinguish cities further. At most six valid suggestions are displayed.

Explicit non-city classifications (towns, roads, buildings) are rejected even if
returned unexpectedly. Missing optional classification fields are accepted under
the city-filtered request when the required structured fields are valid.
No town fallback is enabled: the real Dubai request returned valid city results,
and insufficient coverage has not been established. Strict city filtering can
omit smaller settlements. Any future fallback needs evaluated coverage and
controlled town classification without admitting addresses or unrelated places.

References: [Photon project](https://github.com/komoot/photon),
[API documentation](https://github.com/komoot/photon/blob/master/docs/api-v1.md).
Upstream also documents category filters and deprecates OSM-tag filtering;
this implementation retains the explicitly requested, live-tested `osm_tag` contract.

## Search integration

Selecting a suggestion resolves locally: Photon already supplied all required
fields. Google Details, credentials, session tokens and attribution were removed
from this feature. The suggestion panel credits OpenStreetMap contributors.
OSM licensing details: <https://www.openstreetmap.org/copyright>.

Only selecting an offered, validated city starts the existing Laravel search:

```text
GET /api/v1/buddies/search?city=Dubai&country_code=AE&per_page=15
```

The five existing `gender[]`, `nationality[]`, `languages[]`, `interests[]` and
`travel_styles[]` filters remain supported. Latitude, longitude, external IDs,
destination, sorting and trip parameters are never sent. Typing, keyboard Search
and filters without a selected city cannot start people search.

Changing city resets pagination. Filter Apply/Reset/Back retain the selected city
and existing draft/applied behavior. Safe `links.next`, duplicate traveler
prevention, block/follow state, session isolation, stale-response protection,
two-column grid, skeleton, retry and people-discovery empty state are preserved.
Selection dismisses the keyboard; Clear removes selection and results.
Profile Setup, Current City, Liquid Glass navbar and unrelated Google
configuration are unchanged. Android's main manifest now declares INTERNET so
release builds can access the network. No native Places setup is needed.

## Public service and production hosting

The public Photon demo is for limited initial testing. The operator permits
reasonable usage, can throttle/ban extensive traffic and provides no availability
guarantee. Debouncing and coalescing do not imply unlimited production capacity.
Before rollout, choose a self-hosted/operated Photon deployment or managed service,
define capacity, monitoring, rate limits and privacy policy, and inject the
corresponding provider/transport. A Laravel proxy needs its own verified contract;
no new backend endpoint was invented. No fixed quotas or SLA are assumed.

Typed city text and the client IP reach the public geocoder. No Travibe token,
account identifier or profile data is attached. No Google Cloud project, keys,
billing setup, SDK or map tiles are required. Existing Sign-In configuration stays.
Review OSM attribution and public-service privacy before distribution.

### Backend normalization concerns

Laravel matches exact trimmed, case-insensitive city names. Photon/OSM names may
differ from saved Current City labels: aliases, transliteration, boroughs,
abbreviations, Munich/München. `lang=en` is best effort and can fall back to local
names. Case folding does not handle aliases. Confirm normalization against actual
backend records; no client aliases or Profile Setup mutations were introduced.
Same-name cities in the same country remain indistinguishable to the existing
city+country API. Coordinates and OSM IDs remain client-side only. Photon ranking
can offer fuzzy city-name matches, so users must select the intended suggestion.

## Verification

**244 focused tests passed. Targeted Flutter analysis: no issues.** Four affected
Dart files were formatted for the diagnosis/fix. Tests use mocked Photon GeoJSON
and Laravel responses. Full-project analysis reports 12 existing warnings and
infos in unrelated files (Auth, Home, Profile and a shared text field); those
files were left unchanged.
Coverage includes exact request shape, timeout/cancellation, coordinate order and
bounds, missing properties/IDs, country normalization, duplicate city names,
strict city classification, empty/error/retry, debounce, rapid typing/stale
responses, selection/clear, exact Laravel query/no profile writes, filters,
pagination and session changes. Existing Buddies Stage 1–3, Follow/Block, navbar,
Profile Setup and Settings regressions are included.

```sh
dart format lib/core/places test/core/places test/features/buddies/buddies_search_test.dart test/features/buddies/buddies_city_autocomplete_test.dart
flutter analyze --no-pub lib/core/places lib/features/buddies test/core/places test/features/buddies
flutter test --no-pub test/core/places test/features/buddies test/core/widgets/liquid_glass_bottom_nav_test.dart test/features/block/block_cubit_test.dart test/features/follow/follow_cubit_test.dart test/features/profilesetup/profile_setup_test.dart test/features/profile/settings_privacy_test.dart --reporter expanded
```

A real read-only GET with `q=dubai&limit=6&lang=en&osm_tag=place:city` returned
HTTP 200 on 2026-10-28: Dubai, United Arab Emirates, `AE`, `N:31248510`, Point
`[55.2924146, 25.2647227]`. This verifies the public endpoint/payload, not native
networking or authenticated people matching. No live Laravel request was made.
Existing layout/assets are preserved; no new pixel-exact Figma claim is made.

Manual verification still required:

1. Test Android release and iOS: type Dub, select Dubai and confirm actual people
   currently in Dubai. Verify the user's saved Current City stays unchanged.
2. Check London UK/Canada, non-Latin names, aliases, short text and settlements
   outside strict city coverage. Compare selected names with backend records.
3. Exercise rapid typing, Clear, Back, keyboard dismissal, offline/timeouts/retry,
   accessibility/large text, and logout/account changes during requests.
4. Apply/reopen filters, change city and continue pages; verify Follow/Block and
   no trip messaging. Review service usage/privacy and attribution before rollout.

## Files changed for Photon migration

Created:

- `lib/core/places/photon_city_places_provider.dart`
- `test/core/places/photon_city_places_provider_test.dart`

Modified:

- `lib/core/places/city_places_provider.dart`
- `lib/core/places/city_autocomplete_cubit.dart`
- `lib/core/places/city_autocomplete_results.dart`
- `android/app/src/main/AndroidManifest.xml`
- `test/core/places/fake_city_places.dart`
- `test/core/places/city_autocomplete_cubit_test.dart`
- `test/features/buddies/buddies_search_test.dart`
- `test/features/buddies/buddies_city_autocomplete_test.dart`
- `docs/BUDDIES_CITY_AUTOCOMPLETE.md`
- `docs/BUDDIES_STAGE4.md`

Removed unused Google adapter/tests:

- `lib/core/places/google_city_places_provider.dart`
- `test/core/places/google_city_places_provider_test.dart`

The existing Buddies Search screen, query, Cubit and repository needed no production
changes: they already gate on structured selection and serialize only the
current-city contract. No dependencies were added or removed.

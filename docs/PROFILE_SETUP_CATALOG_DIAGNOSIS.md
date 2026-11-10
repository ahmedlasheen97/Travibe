# Profile Setup Step 3 and shared reference catalogs — 2026-10-27

## Live diagnosis

Read-only public GET requests verified the exact paths used by Flutter:

| Endpoint | Observed status | Observed response |
| --- | --- | --- |
| https://travibeapp.com/api/v1/reference/languages | 200 | data is an incomplete PHP Collection object |
| https://travibeapp.com/api/v1/reference/interests | 200 | data is an incomplete PHP Collection object |
| https://travibeapp.com/api/v1/reference/travel-styles | 200 | data is an incomplete PHP Collection object |

All three returned this exact JSON:

```json
{"data":{"__PHP_Incomplete_Class_Name":"Illuminate\\Support\\Collection"}}
```

Requests used Accept: application/json, without a Bearer token or mutation. These
reference endpoints are public in the existing API specification. A second
languages request with Cache-Control: no-cache returned the same HTTP 200 body.
Verification took place on 2026-10-27, before 10:44 UTC. No authenticated PATCH or
completion request was made against a live account.

The direct cause of Flutter's error is verified: ReferenceItem.parseCatalog
requires data to be an array, but receives a map. The check fails before item
field parsing even begins. The response contains no option records or usable
slugs. This is not a misspelled Flutter endpoint, an auth response, an empty
catalog, or evidence that the valid item schema should be loosened.

The documented expected shape remains data: [{slug, name, name_en, name_ar,
status?}]. Local OpenAPI descriptions and existing app parsers agree on these
paths and item fields. Successful parsing tests use contract-shaped fixtures;
no valid current catalog contents were observed on the live service.

The PHP incomplete-class marker points to a server serialization/unserialization
failure. A cached Laravel Collection is a possible source, but the precise
Laravel/cache code path and keys have not been inspected or verified. This
workspace contains Flutter code and no artisan/composer.json/Laravel checkout.
The backend checkout path was requested while client work continued.

The backend must return actual catalog arrays from these existing endpoints.
Inspect the reference handlers and any Collection cache serialization, repair
the invalid payload generation, and invalidate affected catalog cache entries
as appropriate after repair. No production cache was cleared or backend code
changed in this session. Flutter cannot reconstruct missing slugs from the
incomplete-class object, and no substitute options/endpoints were added.

## Client fixes

- The shared parser recognizes the verified malformed Collection payload and
  reports “Reference options are temporarily unavailable. Please try again
  later.” It still rejects the invalid payload rather than treating it as an
  empty success. Other invalid shapes/fields and duplicate slugs remain errors.
- Profile Setup and Buddies Filters continue using the same ProfileSetupRepo /
  ReferenceItem infrastructure. Filters now preserves and displays mapped
  ApiError messages per category with its existing retry controls.
- Catalog refreshes no longer silently remove profile selections. Retained
  selections can be removed without permitting newly invented options.
- The eight Step3TravelStyle cards, artwork, order, two-column layout and
  three-selection limit are unchanged. No Step 3 presentation file was edited.

## Verified setup save contract

ProfileSetupRepo now parses PATCH /profile/setup into ProfileSetupResult, using
the returned UserResource through the existing ProfileModel plus strict typed
meta.profile_setup_step and boolean meta.profile_completed.

Request serialization retains travel_styles as a slug array with at most three
distinct selections. It does not derive travel-style slugs from labels. New
choices still require authoritative catalog values. Existing saved slugs echoed
in a PATCH UserResource are retained and may be resubmitted without depending on
a broken catalog fetch. An explicit [] clears styles without a catalog request.

Language/interest serialization retains the existing, previously verified app
label mappings and limits of four/six. It also preserves canonical selections
echoed by the server even if they are outside those fixed presentation lists;
no newly hardcoded catalog values are introduced. Username length is validated
at 3–30 characters, and optional gender is restricted to male/female/other.

## Metadata and navigation

The Cubit no longer discards setup responses or infers completion from local
controller values. It stores server setup/completion state and restores saved
selection slugs when those fields are present in the UserResource. Absent
selection fields preserve the current draft; explicit returned empty lists clear
them. New response validation failures cannot report a successful save.

- identity maps to the existing first page.
- languages_interests maps to the existing second page.
- travel_style maps to the existing third page.
- review maps to the existing third page; on Finish it authorizes the already
  implemented POST /profile/setup/complete, using server readiness instead of
  re-checking potentially incomplete local identity/selections.
- profile_completed:true confirms completion and retains the existing Home
  navigation. A PATCH already confirming completion avoids a redundant POST.
- profile_completed:false never marks the wizard complete. An inconsistent
  complete/false reply shows an error; completion validation failures retain
  selections for retry. Earlier server steps return to the corresponding page.

Completion parsing consumes its documented metadata independently of PATCH's
UserResource shape. No new endpoint or review screen is introduced. Existing
Back, Skip and Home navigation destinations remain in place. The existing Step 2
“nothing selected, nothing to save” skip path is retained.

## Files changed

- lib/features/profilesetup/data/reference_item.dart
- lib/features/profilesetup/data/profile_setup_result.dart (new)
- lib/features/profilesetup/data/profile_setup_repo.dart
- lib/features/profilesetup/data/profile_selection_options.dart
- lib/features/profilesetup/cubit/profile_setup_cubit.dart
- lib/features/profilesetup/cubit/profile_setup_state.dart
- lib/features/buddies/screens/buddies_filters_screen.dart
- test/features/profilesetup/profile_setup_test.dart (contract-shaped responses)
- test/features/profilesetup/reference_catalog_regression_test.dart (new)
- lib/features/profilesetup/data/username_availability_model.dart (formatting only)
- docs/PROFILE_SETUP_CATALOG_DIAGNOSIS.md (this report)

No unrelated features, navbar, authentication, Follow/Block or VS Code files were
changed. No private credentials were accessed and no backend mutations were run.

## Verification and remaining blocker

Targeted formatting and analysis cover Profile Setup and Buddies. Tests include
valid catalogs/localization, the exact live malformed payload, exact GET paths,
bad shapes/duplicates/transport errors, PATCH fields/limits/UserResource/metadata,
three-selection enforcement and all eight cards, retained selections, partial
saves, server-driven steps/completion, save ordering, duplicate requests/disposal,
and both consumers' error handling. Broader focused checks include existing
Buddies, profile editing, navbar and Follow/Block regressions.

```sh
flutter analyze --no-pub lib/features/profilesetup lib/features/buddies test/features/profilesetup test/features/buddies
flutter test --no-pub test/features/profilesetup test/features/buddies test/core/widgets/liquid_glass_bottom_nav_test.dart test/features/block/block_cubit_test.dart test/features/follow/follow_cubit_test.dart --reporter expanded
```

Final results: all 176 focused tests passed, including 35 Profile Setup/shared
catalog tests (21 new). Targeted Flutter analysis reported no issues; formatting
completed. An additional 16 existing profile-edit tests passed through a temporary
ScreenUtil-initialized wrapper at
/private/tmp/travibe_profile_edit_catalog_check_test.dart. The ordinary broader
run initially had 188 passes and four profile-edit widget failures caused by
ScreenUtil._data being uninitialized before darkTheme construction. The isolated
ordinary profile-edit run reproduced that test-setup error (12 passes/four
failures); the initialized wrapper passed all 16. No profile-edit production or
test file was changed to address this unrelated harness dependency.

The catalog data outage remains blocked on a Laravel-side repair; the client
changes do not restore missing live options. Once repaired, verify real catalog
arrays and all eight style mappings, then PATCH/complete with a real account and
inspect returned saved selections, step transitions and completion on device.

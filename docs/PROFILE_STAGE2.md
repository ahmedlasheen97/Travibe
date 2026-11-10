# Profile Stage 2 — Edit Profile

Save Changes follow-up (2026-10-29): Edit Profile now stages Current City selection/inline-X clearing until Save Changes, keeps location outside PATCH `/profile`, acknowledges partial successes independently, and synchronizes canonical profile state safely. See [PROFILE_CURRENT_CITY_UI.md](PROFILE_CURRENT_CITY_UI.md) for the code-based diagnosis, request ordering, 30 new focused tests and 601 passing regressions. Profile Setup's immediate city save is unchanged.

Current City UI follow-up (2026-10-29): Profile Setup and Edit Profile now share the corrected dark city picker, orange cursor/selection colors and borderless suggestions. See [PROFILE_CURRENT_CITY_UI.md](PROFILE_CURRENT_CITY_UI.md) for root cause and 426 passing regression tests. Current City location persistence follows [BUDDIES_BACKEND_INTEGRATION.md](BUDDIES_BACKEND_INTEGRATION.md); the earlier country-only selector description below is historical.

The existing edit screen now receives the authenticated ProfileCubit's loaded
ProfileModel. Demo values and the placeholder save action are removed. Existing
form geometry, selector chips/cards, dark colors and inherited Plus Jakarta Sans
are retained; an optional gender field uses the same form styling. Figma access
limitations remain as recorded in FIGMA_REFERENCE.md; exact visual alignment was
not reverified and no Figma file was changed.

## Fields and partial updates

| Form / request key | Behavior |
| --- | --- |
| Full name / `full_name` | Nonblank when changed, at most 255 Unicode code points. Uses the canonical write key rather than legacy `name`. |
| Username / `username` | Optional; 3–30 ASCII letters/digits/underscores/periods when supplied. Pattern matches the existing documented Profile Setup username contract. Uniqueness remains server-authoritative. |
| Bio / `bio` | Optional, maximum 180 Unicode code points. |
| Current City / dedicated location endpoints | Pending Photon selection or inline X clear is saved through PUT/DELETE `/profile/location` after ordinary changes; location is excluded from PATCH `/profile`. Existing `location: City, CODE` payload remains unchanged pending authoritative contract resolution. |
| Nationality / `nationality_code` | Same code validation/nullable clear. Does not reverse-engineer a country code from a legacy nationality label. |
| Gender / `gender` | male, female, other, or null (Not specified). |
| Languages / `languages_spoken` | Existing selection screen, max 4. |
| Interests / `interests` | Existing selection screen, max 6. |
| Travel styles / `travel_styles` | Existing card selector, max 3. |
| Avatar / `avatar_media_id` | Request adapter validates positive integer IDs/null, but there is no avatar upload or removal action. See upload limitation below. |

ProfileDraft compares changes against a fixed loaded baseline. Untouched fields
are omitted; restoring the original value removes the change. Selection order
alone does not trigger PATCH. Empty text in nullable fields becomes explicit null;
clearing a selection explicitly becomes null, never an empty array. A confirmation
explains profile incompleteness before clearing username/required selections.
Unchanged missing fields are not sent as defaults.

Selectors load choices using ProfileSetupRepo.loadCatalog and its existing
ReferenceKind/ReferenceItem parser. Values are slugs throughout selection and
serialization; localized labels remain presentation only. Existing selections
are merged by slug so an older/unknown selection is retained even when absent
from a current catalog. No free-text language-to-slug conversion is allowed.
Unknown travel artwork uses a neutral icon; no placeholder slug is created.
Catalog failures retain selections and allow retry via Edit.

## Saving, errors and navigation

ProfileRepo.updateProfile uses existing ApiService PATCH `profile`, JSON headers,
Bearer interceptor and ApiError handling. It sends only ProfileUpdate.toJson().
No PATCH response object schema is assumed: a successful transport is followed
by GET `profile` to load canonical values.

EditProfileCubit rejects repeated saves while saving or after success. The form
blocks interactions and makes text fields read-only during save, preserves draft
input on failure, and returns to Profile after success. Unsaved changes use the
existing discard dialog. No edit action is exposed in public-profile mode, even
when a public response has is_me:true. ProfileCubit also rejects public writes
and rejects a draft whose profile ID differs from its currently loaded owner.

The shared ApiError/ApiExceptions change is additive: 422 failures retain all
field message lists while preserving the previous first-message/status behavior.
The edit form displays field errors, including indexed selection errors, and a
friendly snackbar. Editing a text field clears its old backend error; each save revalidates changed fields. 401, connection
errors and timeouts retain draft input for retry; no automatic PATCH retry occurs.

After a committed PATCH, ProfileCubit invalidates pre-save reads and refreshes
using its existing generation/disposal guards. A failed follow-up GET shows the
normal Profile retry UI rather than old values or another PATCH. Follow/Block
logic is unchanged; no public profile cache is patched optimistically.

## Avatar upload limitation

Inspection found Profile Setup only stores File avatarFile locally; neither it
nor another feature implements an upload client. Its repository does not send
avatar_media_id. No working presign/upload/finalize pipeline exists to reuse.

OpenAPI documents POST /media/presign, PUT to signed storage, POST
/media/{media}/finalize and GET /media/{media}. However, presign's prose describes
upload_url/upload_method/upload_headers/expires_at and media.id, whereas its
response schema only declares data:MediaResource, which contains none of those
upload fields. Their envelope/nesting cannot be verified from the local schema.
The Profile Setup lifecycle permits Ready/Processing media; the corresponding
PATCH /profile avatar lifecycle is not separately documented locally.

The existing avatar is displayed (or a neutral missing-photo icon). Tapping its
existing add affordance explains upload is unavailable; it never selects a file
that would falsely appear saved. No removal or cover-photo action was added.
Before enabling upload, obtain a representative presign response confirming the
signed-upload fields/nesting and confirm PATCH avatar ownership/status behavior.
Then reuse that verified flow with a separate storage client that does not leak
the API bearer token to signed storage, and send the finalized media ID.
No new backend endpoint is proposed.

## Unverified response assumptions

Stage 1's lack of a captured full-profile response remains. New isolated parser
fields are nullable nationality_code and gender, plus full_name as an accepted
response alias for name. These names follow the confirmed write contract, but
need verification against a real GET /profile response. Missing fields stay null
and untouched. Existing response reference assumptions ({slug,name}) remain as
documented in PROFILE_STAGE1.md. No PATCH response fields are invented.

## Files changed

- lib/core/datasource/remotedata/api_error.dart — additive fieldErrors.
- lib/core/datasource/remotedata/api_exceptions.dart — preserve 422 fields.
- lib/features/profile/data/profile_model.dart — nullable editing fields/alias.
- lib/features/profile/data/profile_repo.dart — confirmed PATCH operation.
- lib/features/profile/data/profile_update.dart — draft diff, validation, serialization.
- lib/features/profile/cubit/profile_cubit.dart — owner-only save and guarded refresh.
- lib/features/profile/cubit/edit_profile_cubit.dart — save lifecycle and duplicate guard.
- lib/features/profile/screens/edit_profile_screen.dart — prefill, validation, save/discard.
- lib/features/profile/screens/languages_screen.dart — catalog-backed slug selection.
- lib/features/profile/screens/interests_screen.dart — catalog-backed slug selection.
- lib/features/profile/screens/travel_style_screen.dart — catalog-backed slug selection.
- lib/features/profile/screens/profile_screen.dart — authenticated edit navigation.
- lib/features/profile/widgets/profile_action_buttons.dart — edit callback.
- test/features/profile/edit_profile_test.dart — focused Stage 2 tests.
- test/features/profile/profile_screen_test.dart — owner navigation/public read-only assertions.
- docs/PROFILE_STAGE2.md — this report.

No Laravel, dependency, native-platform, Profile Setup implementation, Home,
Comments, Likes, Share, Search, Follow or Block files were modified.

## Verification

Targeted analysis of changed Dart sources and all Profile tests: no issues found.
The standard flutter test --no-pub test/features/profile command was attempted;
the sandbox denied localhost server sockets before any test could load.
The same four actual test files were compiled and executed through the existing
temporary no-socket frontend-server/flutter_tester harness (VM service disabled).
Final result: 42 passed, 0 failed, no skips (26 existing/updated Stage 1 tests and
16 focused Stage 2 tests). Logs/harness are /private/tmp/travibe-profile-*.

Coverage includes prefill/navigation, partial PATCH/null serialization, preserved
slugs, validation bounds, media ID validation, duplicate saves, 401/422 and
network/timeout mapping, retained failed-save drafts, owner/public identity
guards, refresh success/failure, stale responses, disposal and unchanged
Follow/Block integration. No live backend or physical-device testing was run.
Manual verification remains: actual GET field shapes, persisted PATCH values,
backend uniqueness/selection errors, country pickers, gender clearing, keyboard
and system-back behavior on iOS/Android. Avatar upload remains unavailable.

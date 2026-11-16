# Profile Setup identity, country and photo persistence

Implementation audit: 2026-11-16. No live profile mutations were performed.

## Reference availability and UI scope

The two user-supplied Profile Setup screenshots were not available in the local
workspace. The user was asked to provide them as
`docs/references/profile-setup/current.png` and `desired.png` (or their actual
paths). No pixel comparison was performed. Reference-dependent avatar reduction,
progress-indicator proportions, compact field geometry and exact vertical layout
remain pending. Existing three-step layout and avatar geometry are retained.
The explicitly requested light-gray placeholder/gray silhouette, required labels,
country label, upload feedback and removal of normal-flow Skip are implemented.
Do not describe this as a completed screenshot-matched redesign.

## Confirmed root cause of the missing photo

The prior Step1BasicInfo used ImagePicker to select an XFile, converted its path
to a File, and passed it to ProfileSetupCubit.setAvatar. The Cubit retained the
file only in widget-session state and CircleAvatar displayed a FileImage.
Neither the Cubit nor ProfileSetupRepo uploaded it, finalized media or sent an
avatar_media_id. No profile attachment was attempted. The disappearing photo
therefore has a concrete client-side missing-persistence path; there is no
captured production HTTP failure to attribute to storage, TLS or permissions.

## Verified backend contracts

Source: `docs/openapi.json`, especially ProfileSetupRequest, UserResource,
PresignMediaRequest and the operation descriptions. API_REFERENCE.md is an
existing summary; the OpenAPI file is authoritative.

- GET `/profile/username-availability?username=...`: 3–30 characters; returns
  `{data: {username, available}}`, with server-normalized handle. Shape failures
  use 422.
- PATCH `/profile/setup`: supports any subset of full_name, username,
  country_code, nationality_code, gender, bio, avatar_media_id and the documented
  taxonomy arrays. Returns UserResource plus next-step/completion metadata.
- GET `/reference/countries`: localized `{code,name,name_en,name_ar}` entries;
  reused through CountriesRepo and its public locale-keyed cache.
- POST `/media/presign`: filename/content_type/size; response fields are media,
  upload_url, upload_method=PUT, upload_headers and expires_at.
- Direct storage PUT uses the signed URL and returned headers. API bearer
  credentials are not forwarded to storage.
- POST `/media/{id}/finalize`, then GET `/media/{id}` until ready/failed.
- PATCH `/profile/setup` with `avatar_media_id` attaches the caller's verified
  media. The backend also permits processing media; the client reuses the
  existing more conservative ready-only uploader.
- GET `/profile` restores canonical profile fields; it is an existing confirmed
  authenticated endpoint, not a new preferences cache.
- POST `/profile/setup/complete` remains the completion operation. Only confirmed
  backend completion can send the wizard to Home.

Media/profile operations require appropriate authenticated access and verified
email. No authentication bypass, invented endpoint or permission escalation was
added.

## Required identity and Next

Full Name and User Name have orange asterisks. Full name is trimmed for validation
and submission; whitespace-only values fail, with the documented 255-character
maximum. The local draft itself is not destructively trimmed.

Username follows the documented 3–30 letter/digit/underscore/dot handle rules,
without a leading or trailing dot, using the existing app's handle alphabet.
The existing 500ms availability debounce and stale-request protection remain.
Invalid shapes do not trigger availability requests. Backend 422 field errors
are preserved and shown inline; a duplicate/invalid username cannot keep Next
enabled. A network check failure offers an explicit availability retry.

The Cubit also validates basic identity before PATCH, so UI disabling is not the
only boundary. Next is disabled while checking, restoring or saving, and while a
selected photo remains unresolved. A photo is optional: picker denial does not
make it required, and a failed draft can be explicitly removed before proceeding.
Fields are locked during the basic save. Duplicate concurrent saves are ignored.

Controllers belong to the wizard Cubit and survive back/forward step changes.
Existing saved identity, country, avatar and selections are restored from the
current-user resource or canonical profile read. An in-flight restore does not
replace user edits made after the request began. Failed restoration exposes Retry
and leaves editing available; requests have a bounded timeout.

## Photo lifecycle and retries

The setup flow now reuses ProfileAvatarRepo and MediaUploadService, already used
by Edit Profile. The native gallery is opened only after the user taps the avatar
or plus. Selection validates decodable image bytes and sniffs MIME, rather than
trusting an extension. Immutable bytes provide the immediate preview. Selecting
alone is never reported as upload success.

The uploader performs presign → storage PUT → finalize → bounded polling, then
Profile Setup attaches the returned backend ID. One compact Cupertino indicator
is shown over the avatar during selection/upload. Errors retain the selected
preview with Retry and Remove selected photo actions. Upload IDs that reached
ready state are reused after an attachment failure. Once attachment was confirmed,
a failed canonical read is retried as a read without replaying upload/attachment.
The existing uploader reconciles uncertain storage/finalize outcomes instead of
blindly repeating writes.

Back navigation with an unconfirmed draft asks before leaving. Explicitly leaving,
discarding, widget disposal or session changes cancel/invalidate pending work.
Storage cancellation uses CancelToken; bounded in-flight API requests can finish,
but stale results cannot attach another user's media or update the current UI.
Owned upload services are reset across sessions so old-account recovery IDs are
not queried with a new account's credentials. Server-confirmed profile/avatar data
updates the existing CurrentUserCubit; no second current-user store is introduced.
Sparse setup responses are not allowed to clear email/verification/completion
metadata in that shared resource. With a shared current user, avatar attachment
is followed by a canonical profile GET before publishing the new profile.
Sparse basic-info responses trigger refresh of the existing owner. A dedicated
regression checks preservation of verified-email metadata.

Confirmed saved media is restored after reopening/restart from the backend.
Unconfirmed image drafts are retained in memory while the wizard remains open;
they are not persisted across OS process termination. No promise of recovering an
unfinished local draft after an app kill is made.

## Current City (country picker removed)

Step 1 uses the shared Current City picker (`core/places/current_city_picker.dart`),
the same one Edit Profile uses. Picking a city calls `ProfileSetupCubit.setCity`,
which saves through `CurrentUserCubit.saveLocation` → `PUT profile/location`
with `{location: "City, CC"}` (ISO alpha-2 country code inside the location).
Profile Setup no longer sends `country_code` to `PATCH profile/setup`. The
short-lived `profile_country_picker.dart` sheet was removed;
`ProfileSetupRepo.loadCountries` stays because Buddies filters use it.
`test/core/places/current_city_picker_test.dart` asserts the location PUT for
both Profile Setup and Edit Profile.

## Skip and startup safety

Profile Setup no longer supplies Skip callbacks in either identity or
language/interest steps. Step1's bypass is removed; Step2 retains its optional
callback API for existing standalone reuse but renders no Skip in this wizard.
No completion endpoint or unrelated navigation route was deleted. Page swiping
remains disabled; step navigation and server metadata govern progression.
Startup/authentication decisions, email verification and session revalidation are
unchanged. Partially completed accounts can restore their saved fields and retry;
backend completion requirements still apply.

## Platform audit and limitations

Existing Info.plist includes NSPhotoLibraryUsageDescription and camera usage
text. These native files were not changed. The reused picker avoids full metadata
access and uses Android's scoped photo picker, without adding broad storage
permissions. No new dependency is required.

Supported image MIME types are the documented JPEG, PNG, GIF and WebP, with a
20MB limit enforced by MediaUploadService. Unsupported formats such as an
unconverted HEIC are rejected with useful feedback; no new image transcoding
pipeline was invented. Cancellation may leave an unclaimed media record on the server. No undocumented
media-delete/cleanup endpoint is called; server-side orphan cleanup/retention
needs backend confirmation. Native permission behavior and an actual iPhone gallery
upload were not manually verified. API behavior is verified with mocks, not a
production account.

## Files changed in this task

- `lib/features/profilesetup/data/profile_identity_validation.dart` (new)
- `lib/features/profilesetup/data/profile_setup_repo.dart`
- `lib/features/profilesetup/cubit/profile_setup_cubit.dart`
- `lib/features/profilesetup/cubit/profile_setup_state.dart`
- `lib/features/profilesetup/screens/profile_setup_screen.dart`
- `lib/features/profilesetup/widgets/step1_basic_info.dart`
- `lib/features/profilesetup/widgets/step2_languages_interests.dart`
- `test/features/profilesetup/identity_photo_test.dart` (new)
- `test/core/places/current_city_picker_test.dart`
- This document and `docs/ONBOARDING_API_STARTUP_FLOW.md`.

Existing uncommitted auth/legal work was preserved. Firebase, SwiftPM, signing,
Bundle ID, authentication, Chat, Stories and Notifications sources/configuration
were not changed by this task.

## Verification

- Focused upload, identity, country, location, startup and existing avatar tests:
  166 passed, zero failures.
- New cases include required/invalid/duplicate handles, field preservation,
  debounce/stale checks, successful shared upload pipeline, photo retry,
  confirmed attachment/read failure, account switching, disposal, duplicate
  suppression, canonical restoration, safe Back confirmation and country retry.
- Identity layouts at 320×568, 375×812, 393×852, 430×932 and 844×390 are exercised
  in English/Arabic RTL with 2× text and keyboard insets. Natural scrolling is
  retained. No standard-device zero-scroll or screenshot-fidelity claim is made.
- Targeted analysis: no issues.
- Full Flutter suite: **2,464 passed, zero failures, one existing intentional
  opt-in skip** (`flutter test --no-pub --reporter expanded`).
- iOS Simulator Debug build: **succeeded**, Xcode build 114.0s,
  `build/ios/iphonesimulator/Runner.app`. No Simulator launch or manual native
  picker verification was performed.
- Full-project analysis: zero errors, zero warnings; only the pre-existing Home
  `use_key_in_widget_constructors` informational lint in
  `lib/features/home/widgets/custom_bottom_nav.dart:10`.
- Final formatting: 16 files checked, zero changes; git diff whitespace check
  passed. No test was skipped or deleted for this change.
- Logs: `/private/tmp/travibe-setup-regressions-final.log`,
  `/private/tmp/travibe-setup-targeted-analysis-final.log`,
  `/private/tmp/travibe-setup-full-analysis-final.log`,
  `/private/tmp/travibe-setup-full-tests-final.log`,
  `/private/tmp/travibe-setup-ios-build-final.log`.

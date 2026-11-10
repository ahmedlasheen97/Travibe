# Settings & Privacy — Stage 5

Account actions follow-up (2026-10-29): Sign Out now integrates POST `/logout`, preserves global language during session cleanup, and fixes mixed Navigator/GoRouter exit behavior. Deletion retains the password-query contract and uses the compact Cupertino loader. See [PROFILE_ACCOUNT_ACTIONS.md](PROFILE_ACCOUNT_ACTIONS.md) for current behavior, security, contract discrepancies and tests.

Implemented 2026-10-27.

## Scope and API

Settings uses the existing authenticated Dio client and UserResource/ProfileModel.
Initial values come from the existing GET `profile`; no settings/catalog endpoint was invented.
PATCH `settings` sends only the changed documented field:
`locale`, `currency_code`, `show_active_status`, `show_in_travel_buddy`, or
`push_notifications_enabled`. Explicit null currency is retained.

An app-scoped CurrentUserCubit owns confirmed settings across navigation.
Requests are serialized, the affected control shows Saving, and controls retain
their previous values on failure. Request generations, user IDs and session
revisions reject stale responses, including session changes before dispatch.
Unknown/missing server settings display as unavailable rather than assumed defaults.

Language changes update the real MaterialApp locale, native Material localization
and text direction only after server confirmation. Currency changes update the
existing preference/presentation notifier; no rates or conversion were added.
Own-profile synchronization merges only settings fields, preserving unrelated
profile edits. Confirmed Travel Buddy visibility updates Buddies Home and refreshes
GET buddies; an older response cannot restore an obsolete visibility banner.

## Account deletion and session cleanup

Delete Account opens a dedicated warning/form; opening it never submits a request.
The user enters a password, can toggle visibility, explicitly accepts permanent
deletion and confirms again in a final dialog. Cancel clears the input.
Processing disables duplicate submissions and navigation out of the form.

DELETE `account` sends the password as a query parameter, with no JSON body,
using Bearer authentication. Redirects are disabled. This sensitive request
bypasses generic request observation, uses fixed safe errors, and removes query
parameters from retained request options. The password is not persisted, logged,
placed in Cubit state or included in emitted exceptions. No logging interceptor
is installed. Future HTTP/crash instrumentation must retain this exclusion.

Only HTTP 200 with the exact documented success message clears credentials,
user-specific preferences and image caches. Session listeners clear current-user,
profile and Buddies state; resetting navigation to Login disposes authenticated
screen-owned state, including the feed. Back cannot reopen authenticated screens.
Failed requests retain the session. Ambiguous outcomes block resubmission in the
flow and instruct the user to verify sign-in/account status or contact support;
there is no automatic deletion retry.

The Settings Sign Out action now confirms current-token revocation through POST
`logout` (204), then performs session cleanup/navigation reset. A 401 exits locally
without claiming revocation; other failures retain the session for explicit retry.
It never calls account deletion.

## Verification

- Formatted all 21 changed Dart files.
- Targeted analysis of those 21 files: **no issues**.
- Focused regression run: **241 tests passed**, including 39 Stage 5 tests.
- Coverage includes partial serialization, nullable/invalid settings, confirmed
  booleans and presentation preferences, failures, conflicting requests, stale
  reads, session changes, navigation persistence, profile merging, Buddies
  visibility, actual locale/RTL, deletion consent/password validation, query
  serialization, logging exclusion, strict success, 401/422, ambiguous network
  failures, duplicate prevention, cleanup and Login navigation.
- Existing Profile, Buddies Stages 1–4, Profile Setup/catalog, Follow/Block and
  Liquid Glass navbar regression tests passed.
- Settings and deletion form/dialog tested at 320px width and 2× text scaling.
- Mocked 390px screenshots were rendered and visually inspected with app fonts.
- **No live account deletion or live settings mutation was performed.** All
  deletion HTTP tests use a mock adapter.

Reproduce the focused run:

```sh
flutter test --no-pub test/features/profile/settings_privacy_test.dart test/features/profile/account_deletion_test.dart test/features/profile/profile_model_repo_test.dart test/features/profile/profile_cubit_test.dart test/features/profile/profile_screen_test.dart test/features/buddies test/features/profilesetup test/core/widgets/liquid_glass_bottom_nav_test.dart test/features/block/block_cubit_test.dart test/features/follow/follow_cubit_test.dart --reporter expanded
```

## Dependencies and manual checks

- The complete supported currency list remains unconfirmed. The picker offers
  AED (explicitly supplied in the backend contract), the authenticated user's
  returned currency and clearing the preference. It deliberately does not treat
  the former generic picker list as backend support. Supply a confirmed list to
  extend SettingsRepo's allowlist.
- Figma metadata access failed because of the plan/tool call limit. There are no
  saved Settings references available in this checkout. Existing screen styling
  was preserved, but exact Figma alignment remains unverified.
- Existing application strings are hardcoded English; actual Arabic locale,
  native controls and RTL work, but full Arabic app translations are still needed.
  Check all existing screens on an Arabic device before release.
- The push toggle saves the backend preference; delivery, OS permissions and push
  registration need device/backend verification. No push SDK flow was invented.
- Verify authenticated GET profile and PATCH settings against a test account,
  including full settings fields, persistence after relaunch and Buddies metadata.
- Manually check iOS/Android keyboard, password autofill, large text, RTL, currency
  presentation and navigation. Any destructive device check must use an explicitly
  disposable test account and separate authorization.

## Files changed

- `lib/features/profile/data/profile_model.dart`
- `lib/features/profile/data/settings_update.dart`
- `lib/features/profile/data/settings_repo.dart`
- `lib/features/profile/data/account_repo.dart`
- `lib/features/profile/cubit/current_user_cubit.dart`
- `lib/features/profile/cubit/account_deletion_cubit.dart`
- `lib/features/profile/cubit/profile_cubit.dart`
- `lib/features/profile/screens/profile_screen.dart`
- `lib/features/profile/screens/settings_screen.dart`
- `lib/features/profile/screens/delete_account_screen.dart`
- `lib/features/profile/screens/currency_screen.dart`
- `lib/features/profile/screens/session_exit.dart`
- `lib/features/buddies/data/buddies_home_response.dart`
- `lib/features/buddies/cubit/buddies_cubit.dart`
- `lib/features/buddies/screens/buddies_screen.dart`
- `lib/core/datasource/localdata/preferences_manager.dart`
- `lib/core/datasource/remotedata/api_service.dart`
- `lib/core/datasource/remotedata/dio_client.dart`
- `lib/main.dart`
- `test/features/profile/settings_privacy_test.dart`
- `test/features/profile/account_deletion_test.dart`
- `pubspec.yaml` — Flutter SDK localization dependency.
- `pubspec.lock` — records the direct SDK dependency.
- `docs/SETTINGS_PRIVACY_STAGE5.md` — this implementation record.

No production changes were made to Stories, Feed, Profile Setup, reference catalog
parsing, Buddies search/listings, Liquid Glass navbar or VS Code configuration.


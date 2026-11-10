# Profile account actions

Implemented 2026-10-29 in the existing **Profile → Settings and Privacy** flow.
Existing account deletion, authenticated Dio, PreferencesManager, navigation,
Profile/current-user state and all prior Buddies work were reused. No dependency,
Home/Buddies loader, location request/parser, or VS Code changes were introduced.
No live account deletion, logout, or authenticated profile mutation was executed.

## Sign Out

The checked-in `docs/openapi.json` defines POST `/logout`, operation ID
`auth.logout`, described as revoking only the bearer token used for the request.
Success is **204 No Content**; 401 means unauthenticated. Other device sessions
remain active. The endpoint was located in the API definition, not inferred from
a conventional route name.

`AuthRepo.logout()` delegates to the existing authenticated `ApiService` /
`DioClient`. It submits POST `/api/v1/logout`, with no body or query parameters,
Bearer authentication, redirects disabled and an expected session revision.
It verifies 204 without parsing a JSON resource. No separate client/service was
introduced and no token is printed.

`SignOutCubit` owns this action's request lifecycle. Settings opens one confirmation
with the requested title **Sign Out**, message **Are you sure you want to sign out
of Travibe?**, and Cancel / Sign Out actions. Cancel/system Back before submission
make no request. Confirm disables repeated submission and Cancel/Back while busy,
with one compact primary-orange CupertinoActivityIndicator inside the button.
No Home or Buddies loading overlay is used.

Policy:

- 204: confirmed current-token revocation, then local cleanup and Login navigation.
- 401: already-invalid token; clean up locally without claiming revocation.
- Other status/network error/timeout: keep the local session intact, show a safe
  message that revocation was not confirmed, and allow explicit retry or Cancel.
  There is no automatic retry and no false server-revocation success claim.
- Account change during a request: ignore the old result and do not clear the
  replacement account. Disposed action Cubits ignore late completions/errors.

The old local-only Settings logout implementation has been replaced; it no longer
clears preferences independently of the confirmed action.

## Permanent deletion

The supplied current `account.destroy` contract requires:

```http
DELETE /api/v1/account?password=<percent-encoded password>
Authorization: Bearer <current token>
```

There is **no JSON body**. This matches the existing `AccountRepo.delete()` →
`ApiService.deleteAccount()` implementation, which has been preserved. The local
OpenAPI snapshot omits this endpoint; the supplied authoritative account definition
is the source for the query parameter. Protected live docs could not be read
without Basic credentials, so this is not claimed as independent live verification.

Only **HTTP 200 and `{"message":"Account deleted successfully."}`** constitute
confirmed success. A 200 with another body, 202/204, server error, malformed body
or ambiguous transport outcome never causes a false success or early cleanup.
401/403 and 422 keep the session and show safe messages. Missing password and
missing confirmation are rejected before any request.

The existing dedicated deletion screen is retained. Opening it sends nothing.
It shows the requested permanent-deletion warning, an obscured password field,
visibility toggle, existing explicit-consent checkbox, Cancel and destructive red
Delete my Account action. The input disables suggestions, autocorrect, IME
personalization and autofill; no analytics or storage receives it.

The final dialog now uses **Permanently Delete Account?**, the irreversible-action
message, **Keep Account** and **Delete Permanently**. Only the final destructive
confirmation submits DELETE. Cancelling clears the password. The password is also
cleared immediately after submission and on disposal/session change. Processing
blocks duplicate requests and navigation, with one compact orange Cupertino loader.

Confirmed success uses the same local cleanup mechanism as sign-out and removes
the authenticated stack. Failure preserves the session. Incorrect-password 422
keeps the form available for a deliberate retry with a freshly entered password.
For uncertain network/server outcomes, the existing conservative guard blocks
resubmission in that flow and asks the user to verify account status safely rather
than automatically repeating a potentially completed deletion.

## Password security

The password exists only in the form and required in-flight transport value; it
is never stored in Cubit state, preferences, navigation arguments or analytics.
The sensitive request bypasses generic API observers and raw error mapping.
`DioClient` clears sensitive query parameters on success and error, and the API
method clears retained RequestOptions again on completion. Redirects are disabled.
Only safe, fixed deletion failures leave the API method; arbitrary server errors
may echo passwords and are deliberately not displayed or logged verbatim. There
is no logging interceptor or automatic destructive retry.

Regression tests exercise required query serialization, missing/incorrect password,
401/422, uncertain failures, request-option scrubbing, observer exclusion and
password absence from debug logs/emitted errors. All use a mock HTTP adapter.

Backend review remains warranted: passwords in query strings can reach server,
reverse-proxy or infrastructure access logs outside Flutter's control. Prefer a
password-in-body deletion contract only after the backend confirms that change.
The app has not silently substituted a body or changed the current contract.
Any future HTTP/crash instrumentation must honor `sensitiveAccountDeletion` and
exclude the entire deletion URL/query and raw transport exception.

## Cleanup and navigation

`PreferencesManager.clearSession()` extends the existing session-reset mechanism:

- Clear the active token synchronously and advance the session revision.
- Remove account-specific preference values, currency and local search history.
- Preserve the existing app language and its persisted selection. The app's theme
  is global/static; no new theme preference or allowlist of invented keys was added.
- Existing session listeners clear current-user/profile, feed, Stories, Buddies,
  search/autocomplete and cursor/notification state and invalidate stale requests.
- Clear in-memory image caches. Navigation disposes Root and screen-owned caches,
  including shared follow/block/interaction state, rather than introducing another
  global state-reset system.

Both actions call the existing `openSignedOutScreen()` helper. The audit found and
fixed a real mixed-navigation issue: Login uses `Navigator.pushReplacement` to open
Root, while GoRouter can still match `/login`. A plain `router.go('/login')` then
reuses its unchanged page configuration and leaves the imperative authenticated
screen visible. The helper now uses GoRouter when changing a router-managed path,
and otherwise uses root `Navigator.pushAndRemoveUntil` to clear the imperative
stack. Tests cover both cases and plain Navigator, with Login visible and
`canPop == false`. Profile cannot be reopened using Android/iOS Back.

An old action's response cannot clear another account's session. Existing account,
feed and Buddies generation/session guards remain; tests verify late feed/search
responses do not repopulate data after cleanup. No protected profile refresh is
scheduled after confirmed account deletion.

## Profile Location contract discrepancy

The preceding backend integration uses the earlier explicit developer contract:

```json
{"location":"Cairo, EG"}
```

with PUT `/profile/location`, DELETE 204 and canonical `current_location`.
The newly supplied API description instead lists `city`, `country_code`,
`current_city`, `current_country_code` and `location_updated_at`.

Inspection results:

- The working Flutter location implementation and mocked integration tests match
  the earlier developer contract.
- `docs/openapi.json` has neither `/profile/location` nor these newer resource
  fields, so it cannot resolve this discrepancy.
- `https://travibeapp.com/docs/api` returned **401** without Basic credentials.
- No authorized test credentials/profile mutation were used to probe field names.

The deployed location contract therefore remains **unresolved**. The location PUT
payload, response parsing and DELETE behavior were deliberately left unchanged,
as requested. Confirm the deployed schema with the backend developer/protected
current OpenAPI before making a location migration. Prior Buddies tests, Allow
Location ordering, search and page pagination continue to pass. The full integration
record remains [BUDDIES_BACKEND_INTEGRATION.md](BUDDIES_BACKEND_INTEGRATION.md).

## Files changed

Created:

- `lib/features/auth/cubit/sign_out_cubit.dart`
- `test/features/profile/profile_account_actions_test.dart`
- `docs/PROFILE_ACCOUNT_ACTIONS.md`

Modified:

- `lib/core/datasource/localdata/preferences_manager.dart`
- `lib/core/datasource/remotedata/api_service.dart`
- `lib/features/auth/data/auth_repo.dart`
- `lib/features/profile/cubit/account_deletion_cubit.dart`
- `lib/features/profile/screens/settings_screen.dart`
- `lib/features/profile/screens/delete_account_screen.dart`
- `lib/features/profile/screens/session_exit.dart`
- `lib/features/profile/widgets/logout_dialog_widget.dart`
- `test/features/profile/account_deletion_test.dart`
- `test/features/profile/settings_privacy_test.dart`
- `docs/SETTINGS_PRIVACY_STAGE5.md`

No files were removed. Buddies/Home implementations and their loading widgets,
Profile Setup/location code, API definitions, dependencies and `.vscode` were not
modified for this account-actions task.

## Automated verification

- `dart format`: all 12 affected Dart files formatted; final check changed zero.
- Focused mocked account/Settings tests passed; included in the broader run below.
- **655 tests passed, 0 failed** in the broader regression run:

```sh
flutter test --no-pub test/features/profile test/features/auth test/features/profilesetup test/features/home test/features/buddies test/core/pagination test/core/places test/core/widgets/liquid_glass_bottom_nav_test.dart test/core/widgets/travibe_loading_indicator_test.dart test/features/follow test/features/block test/features/stories/story_home_test.dart test/features/stories/story_widgets_test.dart test/features/stories/story_audience_test.dart
```

This includes confirmation/cancel, exact logout/DELETE serialization, duplicate
protection, safe failure/uncertainty handling, password controls/log exclusion,
cleanup/language preservation, navigation and Back, account switches/disposal,
stale feed/search responses, existing authentication, Home/Buddies loaders,
Profile Setup/location, Allow Location and pagination regressions.

Targeted analyzer: **0 errors, 0 warnings**, with one pre-existing style info in
`AuthRepo.register` (`use_null_aware_elements` for its unchanged optional locale
entry). That unrelated registration syntax was left intact. No new analyzer
findings remain. No failure in the final regression run is outstanding.

No live DELETE, authenticated logout or account mutation was performed. No manual
account-action Simulator/device check is claimed for this task.

## Manual iOS Simulator checklist

Use authorized disposable test accounts, especially for the irreversible step:

1. Profile → Settings → Sign Out: Cancel makes no request. Confirm sends one POST
   logout, shows one compact orange loader, and reaches Login without Back to Root.
   Verify the former token is revoked while another device's token stays valid.
2. Disable network during Sign Out: local session remains and the dialog explains
   unconfirmed revocation. Explicit retry works; repeated taps create one request.
3. Sign in as another account: verify no previous profile, feed, Stories, Buddies,
   follow/block state or local search history appears; language stays as selected
   until the next account's confirmed preference is applied.
4. Open Delete Account: no request. Check obscured input/visibility toggle, empty
   validation, Cancel, consent and final Keep Account actions.
5. With a wrong password, explicitly confirm: verify 422 feedback, cleared input
   and retained session. Inspect only sanitized diagnostics; never capture a full
   deletion URL/password in screenshots, proxy logs or bug reports.
6. With a disposable account only, enter its correct password and choose Delete
   Permanently. Confirm the exact HTTP 200 success, Login without Back, empty
   account caches, no automatic refresh of the deleted profile, and inability to
   sign in to that deleted account.
7. Interrupt the deletion network response: verify uncertainty messaging and no
   automatic repeat. Verify the account's status safely before taking further action.
8. Recheck Profile Setup, manual Current City, Allow Location and Buddies discovery.
   First resolve the location schema discrepancy with the backend; do not infer a
   field migration merely from a conflicting example.
9. Verify hardware/system Back and iOS swipe navigation, large text, password
   keyboard dismissal and compact loaders on the actual Simulator/device.

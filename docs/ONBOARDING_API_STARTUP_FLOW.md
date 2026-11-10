# Onboarding API and startup flow

Implemented 2026-11-03 using the existing singleton `PreferencesManager`,
SharedPreferences instance, session revision and current navigation architecture.
No additional preferences store, dependency, backend endpoint or native launch
configuration was introduced. The 1500ms SplashScreen animation is unchanged.

## Persisted app state and session isolation

`PreferencesManager.onboardingCompleted` reads `onboarding_completed`, defaulting
to false when absent. `completeOnboarding()` awaits a successful boolean write.
`main()` already awaits `PreferencesManager().init()` before `runApp`, so startup
never reads the flag before SharedPreferences initialization finishes.

Only explicit Skip or completion of the last backend slide writes the flag.
Viewing, changing slides, loading failures, interruption and disposal leave it
false. A failed persistence operation stays on onboarding and offers another try.
Successful completion replaces onboarding with Sign Up (`/register`), so Back
cannot expose the completed flow. A later unauthenticated launch goes to Login.

`clearSession()` preserves exactly `selected_language` and `onboarding_completed`.
It removes the token, `selected_currency`, and every other cached preference.
Logout and confirmed account deletion already use this method. `clear()` still
performs a full reset, including onboarding; it is not the logout operation.

Saving a token preserves app language. Changing tokens clears both in-memory and
persisted account currency. The existing `saveUserPresentation()` can still apply
a server-confirmed account locale and currency, guarded by sessionRevision.
Registration now sends the selected language instead of hardcoded English.

Token changes continue to increment sessionRevision and notify ChangeNotifier
listeners once; writing the same token does neither. Onboarding completion does
not impersonate a session change. Writes/removals begin before session listeners
run and before yielding. A listener starting another login cannot have its token
removed by an older logout or overwritten by an older token write. Late profile,
settings, and startup responses must pass their original revision/generation
checks before affecting account presentation or navigation.

## Startup decisions

`/splash` hosts StartupScreen, which starts StartupCubit and the original
SplashScreen concurrently. Public onboarding/locales prefetch also runs during
first-launch animation. The animation keeps its original controller, 1500ms
phases, rotating SVG, orange expansion, lifecycle and reduced-motion behavior.

| State | Destination after animation and decision are ready |
| --- | --- |
| Onboarding missing/false, with or without a token | `/onboarding` |
| Completed onboarding, no token | `/login` |
| Completed onboarding, validated verified account, completed profile | `/root` (existing Home tab) |
| Completed onboarding, validated verified account, incomplete profile | `/profile-setup` (existing ProfileSetupScreen) |
| Authenticated resource explicitly reports an unverified account | Existing OTP screen with the confirmed email |
| `/user` returns 401 | Clear this session; `/login` |
| `/user` returns 403 | `/login`, retain credentials; existing password login can resume verification |
| Timeout, connection/server failure, malformed authenticated resource | Keep credentials; show Retry after the animation, without navigating to Home/Login |

A stored token is only a candidate session. AuthRepo.currentUser() calls the
existing `GET /api/v1/user`, documented in `docs/openapi.json` as an authenticated,
verified-email, full-access current-user resource. It uses ApiService/DioClient,
including bearer authentication and a dispatch-time sessionRevision check.
The response must contain a valid profile ID, nonempty email,
`email_verified_at`, and a boolean `profile_completed`. Missing/malformed routing
fields cannot authorize Home. The existing ProfileModel parses the resource.
The request has a 12-second startup timeout; an underlying late response cannot
commit presentation or navigation after its generation is obsolete.

Only an explicit current-session 401 clears credentials. A stale 401 cannot clear
a replacement login. 403 is treated as restricted access, not proof of revocation.
The existing CurrentUserCubit continues to load the profile/settings resource and
apply canonical account presentation with its own revision protection.

When validation is slower than the animation, its final orange frame remains
visible until the decision is ready. Network retry does not replay the animation.
Navigation checks mounted state, lifecycle, current revision and an exactly-once
guard. Normal completion is already post-frame and adds no second vsync delay,
Future.delayed or intermediate destination. Reduced motion still waits for the
startup decision. Disposal and background/resume are covered by widget tests.

Password-login AuthSuccess now retains the existing AuthResponseModel rather than
dropping it, so LoginScreen can honor `email_verification_required`. Existing OTP,
registration, Google login and profile setup screens/endpoints remain in use.
No new session restoration token or verification bypass is introduced.

## Public contracts checked live

Read-only requests on 2026-11-03 confirmed HTTP 200 for:

- `GET https://travibeapp.com/api/v1/onboarding`
- `GET https://travibeapp.com/api/v1/locales`

Onboarding returned:

```json
{"data":[
  {"key":"discover","title":"Discover places you'll love","body":"Explore inspiring destinations and create unforgettable travel experiences.","asset_url":null},
  {"key":"plan","title":"Plan every journey effortlessly","body":"Book flights, hotels, and activities with a smooth, all-in-one experience.","asset_url":null},
  {"key":"together","title":"Travel is better together","body":"Meet other travelers, share experiences, and create memories.","asset_url":null}
]}
```

Locales returned:

```json
{"data":{"locales":[
  {"code":"en","name":"English","rtl":false},
  {"code":"ar","name":"العربية","rtl":true}
],"default":"en"}}
```

Both responses carried `Cache-Control: max-age=86400, public`. Onboarding also
carried `ETag: 8d69af20db317016dcb1a69dd6e10921` (passed through exactly as received).
An onboarding request with `Accept-Language: ar` returned the same English content
and ETag. The client does not invent translated server copy.

OnboardingRepo uses a public Dio transport, following the existing CountriesRepo
pattern, with no bearer credentials. It parses the server-provided order, keys,
titles, bodies, optional asset URLs, language names, default and RTL flags.
Production slide copy is no longer hardcoded. Because current asset URLs are
null, matching existing artwork is retained for discover/plan/together. Unknown
keys without artwork retain the image slot without substituting another slide's
image. Non-null HTTP(S) artwork URLs use Image.network and fall back to matching
local artwork on loading failure.

The language sheet is populated from `/locales`. Saving a selection uses the
existing language ValueNotifier/SharedPreferences path, updates MaterialApp's
locale and RTL, and reloads the slides for that locale. The API default never
overwrites an existing manual choice. The installed en/ar localization delegates
and resources remain unchanged; future unsupported backend languages are shown
disabled until their app resources are installed.

Caching is in memory, keyed by endpoint and language. Concurrent requests are
coalesced. Fresh max-age entries avoid requests; stale entries send If-None-Match
and accept 304. Age, no-cache and no-store are honored. Validation occurs before
caching, so malformed data cannot poison retries. Caches do not persist across
process restarts and contain no account data. On failure the UI offers Retry and
explicit Skip rather than silently supplying hardcoded production copy.

## Files changed

Production:

- `lib/core/datasource/localdata/preferences_manager.dart`
- `lib/core/datasource/remotedata/api_service.dart`
- `lib/core/routing/app_routes.dart`
- `lib/core/routing/router_generator.dart`
- `lib/features/auth/data/auth_repo.dart`
- `lib/features/auth/cubit/auth_cubit.dart`
- `lib/features/auth/screens/sign_up_screen.dart`
- `lib/features/onboarding/data/models/onboarding_model.dart`
- `lib/features/onboarding/data/models/app_locale.dart` (new)
- `lib/features/onboarding/data/onboarding_repo.dart` (new)
- `lib/features/onboarding/cubit/startup_cubit.dart` (new)
- `lib/features/onboarding/screens/startup_screen.dart` (new)
- `lib/features/onboarding/screens/onboarding_screen.dart`
- `lib/features/onboarding/widgets/language_button.dart`

Tests and documentation:

- `test/core/datasource/preferences_manager_test.dart` (new)
- `test/features/onboarding/onboarding_fixtures.dart` (new)
- `test/features/onboarding/onboarding_repo_test.dart` (new)
- `test/features/onboarding/onboarding_screen_test.dart` (new)
- `test/features/onboarding/startup_cubit_test.dart` (new)
- `test/features/onboarding/startup_screen_test.dart` (new)
- `test/features/onboarding/splash_screen_test.dart`
- `test/features/auth/google_auth_test.dart`
- `test/features/profile/profile_account_actions_test.dart`
- `docs/ONBOARDING_API_STARTUP_FLOW.md` (new)
- `docs/SPLASH_ANIMATION.md` (startup-policy cross-reference only)

## Verification

- `dart format` completed on the changed Dart files.
- Targeted `flutter analyze --no-pub` on preferences, API/routing, changed auth
  code, onboarding, and all changed/new tests: **No issues found**.
- Final test command:

```sh
flutter test --no-pub \
  test/core/datasource/preferences_manager_test.dart \
  test/features/onboarding \
  test/features/auth \
  test/features/profilesetup \
  test/features/profile/account_deletion_test.dart \
  test/features/profile/profile_account_actions_test.dart \
  test/features/profile/settings_privacy_test.dart \
  test/features/profile/profile_cubit_test.dart \
  --reporter expanded
```

**168 passed, 0 failed.** Coverage includes first-launch/interrupted onboarding,
Skip and completion persistence, Sign Up replacement, public API parsing and
caching, language persistence and actual MaterialApp RTL, authenticated/invalid/
unauthenticated startup, logout then relaunch, restricted and incomplete accounts,
network retry without deleting credentials, stale session responses, notification
ordering races, the unchanged splash timeline/rotation/coverage, exactly-once
navigation, background/resume, reduced motion, login/registration verification,
profile setup, logout and account deletion.

## Backend verification limits

The public response structures and headers above were checked live. Authenticated
`/user` verification/profile fields use the checked-in UserResource contract and
injected API responses; no real account credentials were used. Live revoked-token,
restricted-token, profile-setup restoration and authenticated Home restoration
have not been exercised against a real account in this change. A 304 round trip
and non-null remote artwork were tested with transport fixtures, not the live
backend. Arabic slide translation remains a backend-content limitation.

Figma metadata/Splash5 were consulted in the preceding animation task; remaining
design context requests reached the Figma plan limit. This integration retains the
existing onboarding layout and artwork rather than claiming a new visual match.
No Simulator/device build was requested or run for this integration. Existing
native launch files, SVGs, splash animation and VS Code settings were untouched.


## Simulator timeout diagnosis — 2026-11-07

The public response timeout is now 20 seconds (connection timeout remains 8),
after real simulator receiveTimeout failures with the former 8-second window.
See [ONBOARDING_API_FAILURE_DIAGNOSIS.md](ONBOARDING_API_FAILURE_DIAGNOSIS.md) for
the captured failure, minimal change, recovery tests and live-backend UI proof.
The UI, auth/startup routing, 1500ms splash, locale/cache and completion behavior
remain unchanged. Notifications and Firebase implementation were not modified.

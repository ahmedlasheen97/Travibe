# Onboarding API failure on iPhone 17 Simulator

## Observed failure, not a guessed HTTP error

On 2026-11-07 the actual onboarding flow was exercised on the booted iPhone 17
Simulator (iOS 26.5). Sanitized Dio interceptors captured:

```text
GET https://travibeapp.com/api/v1/onboarding
status: none (no response before timeout)
DioExceptionType: receiveTimeout
configured receive timeout: 8 seconds

GET https://travibeapp.com/api/v1/locales
status: none
DioExceptionType: receiveTimeout
```

The screen displayed its existing “Unable to load onboarding.” / Retry / Skip
state. Pressing Retry issued a new GET, which returned HTTP 200. The real JSON
parsed as three valid slides. Skip persisted completion in test-only memory and
navigated to the existing Sign Up screen, without creating credentials.

Independent public requests from the host also returned 200 for both endpoints.
A standalone Dart/Dio request failed with the original short response window and
then loaded all three slides with a longer response window. This is a client
receive-timeout failure, not an observed 401/403/404/500, bad URL, TLS exception or
model-validation failure. The underlying source of latency (network versus server)
cannot be isolated from client observations alone; no server outage is asserted.

The checked-in OpenAPI specifies public GET /onboarding and /locales without
required query parameters or bearer authentication. Current response shapes match
OnboardingModel and LocaleCatalog; locales contain en/ar with default en. The
existing Accept-Language header, locale cache keys and RTL behavior remain.

OnboardingRepo owns a public Dio transport; it does not use authenticated
DioClient interceptors or depend on Firebase readiness. No verified shared
Notifications/Firebase defect was found, and their implementation was not edited.

## Minimal production fix

Only lib/features/onboarding/data/onboarding_repo.dart changes production code:

- Connection establishment timeout remains 8 seconds.
- Response timeout increases from 8 to a bounded 20 seconds.
- Constants expose these existing public-transport settings to live diagnostics.
- The API URL, headers, parser, UI, authentication, caching, ETag/304 handling,
  locale selection and completion logic are unchanged.

There is no automatic infinite retry, hardcoded slide copy, success fallback,
certificate bypass, auth bypass or extra startup delay. Startup still navigates
through the unchanged 1500ms splash while content prefetch runs asynchronously.
If the backend takes longer than the bounded wait or returns malformed/error
content, the existing error state remains. Retry continues to coalesce concurrent
requests for the same locale and starts a fresh request after failure.

## Test and verification files

- test/features/onboarding/onboarding_repo_test.dart: receive-timeout coalescing /
  retry, HTTP 401/403/404/500/503, invalid JSON and subsequent recovery. Existing
  success/empty/duplicate slides, cache/ETag, locales and locale isolation remain.
- test/features/onboarding/onboarding_screen_test.dart: additional error-state
  Skip test, preserving the existing Sign Up path and completion persistence.
- test/features/onboarding/onboarding_firebase_startup_test.dart: startup reaches
  API-driven onboarding even when Messaging is unavailable; no automatic
  completion/session creation.
- integration_test/onboarding_live_test.dart: real HTTP on Simulator with
  sanitized status/type/timing diagnostics, real server-title UI assertion,
  Retry when necessary and safe Skip. It uses an in-process preferences override,
  not device data deletion, real account logout or a mocked API response.

No raw bearer/FCM tokens, request headers, user records, arbitrary server bodies
or private credentials are logged. Public slide copy is not dumped into logs.

## Verification results

- dart format: complete.
- Targeted flutter analyze: no issues.
- Focused onboarding/auth/session/Firebase/notification regressions: 187 passed.
- Real-backend simulator test: **1 passed** after a successful Xcode Debug build
  in **60.4s**. GET /locales returned 200 in **2857ms**; GET /onboarding returned
  200 in **2927ms**, parsed successfully, and the first UI state was content.
  The test asserted the actual server-provided first slide title in the screen
  and absence of the error message. This was not a mocked HTTP response.
- Simulator Skip reached SignUpScreen and persisted completion in test-only
  memory. The original pre-fix simulator run also confirmed Retry made a fresh
  request and obtained HTTP 200. Locale changes remain covered by widget tests.
- Backend latency is intermittent: increasing the bounded response window makes
  the client more tolerant, not a guarantee of server availability. There is no
  evidence of an ongoing HTTP/TLS/JSON contract problem. Errors exceeding the
  window still use the existing Retry/Skip presentation.
- Normal flutter run rebuilt lib/main.dart for iPhone 17 in **51.1s**, launched
  successfully and exposed the VM service. Flutter was detached with `d`, leaving
  the app running; simctl confirmed its process after detachment. This normal
  cold launch instantiates the shared transport with the new response timeout.
- Onboarding UI/model/locale code, pubspec/lockfile, Runner project, plists and
  SwiftPM lockfiles match the pre-task snapshots. Notifications, Firebase and
  authentication implementation were not changed. No real stored session or
  onboarding completion flag was cleared for the integration test.

No Git metadata exists in this checkout. A pre-change onboarding/native/config
snapshot was saved under /private/tmp/travibe-onboarding-before. No reset, clean,
cache deletion, signing/dependency-manager change or commit was performed.


Changed files: lib/features/onboarding/data/onboarding_repo.dart;
test/features/onboarding/onboarding_repo_test.dart;
test/features/onboarding/onboarding_screen_test.dart;
test/features/onboarding/onboarding_firebase_startup_test.dart (new);
integration_test/onboarding_live_test.dart (new); this diagnosis (new); and
docs/ONBOARDING_API_STARTUP_FLOW.md.

Logs: /private/tmp/travibe-onboarding-{probe,analysis,tests,config}.log. The first
pre-fix simulator run recorded receiveTimeout for both public endpoints and a
new HTTP 200 request on Retry; the probe log now contains the post-fix live run.

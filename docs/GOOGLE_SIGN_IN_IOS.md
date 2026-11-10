# Google Sign-In — iOS

Implemented 2026-10-24 using installed `google_sign_in` 7.2.0. No Firebase,
new dependencies, native project, URL scheme or VS Code changes.

## Flow

Both existing Google SocialLoginButtons invoke AuthCubit.loginWithGoogle.
GoogleAuthService initializes the package singleton once with the supplied iOS
client ID and Web/server client ID, then calls native authenticate and reads
account.authentication.idToken. This integration is explicitly iOS-only; other
platforms receive an availability message rather than an unconfigured sign-in.
Cancellation quietly returns to the idle state. Missing ID tokens, SDK/platform
failures and backend errors give safe user feedback without logging native error
descriptions, identity tokens or Travibe credentials.

AuthRepo exchanges the ID token through existing ApiService/DioClient:

```
POST auth/google/token
{device_name: "iPhone", id_token: <Google ID token>, nonce: null, name: null}
```

The existing AuthResponseModel parses the Laravel `data` envelope. The Google
method validates a nonempty string token, Bearer type, user object and recognized
verification flag before saving through PreferencesManager.saveToken. No Google
access token is used as a Travibe bearer token. The existing Dio interceptor uses
the persisted Travibe bearer token for later requests.

AuthSuccess carries the optional parsed response; existing password success
remains compatible. Google results requiring verification navigate to the existing
OTP screen using the returned email (missing email is rejected). Other successes
navigate to Root. No profile-completeness field or new routing rule is invented.

Loading suppresses duplicate Google/password submissions on Login. Signup guards
Google versus its existing registration request, disposes the Google Cubit and
form controllers, and preserves registration validation/terms/OTP rules. Late
Google/backend results cannot persist credentials after disposal or a changed
session; a success effect also verifies the current token before navigation.

## Existing iOS configuration checked

- Bundle ID `com.travibe.app` in Runner build configurations.
- Info.plist retains the supplied reversed iOS OAuth client URL scheme.
- Google plugin already appears in GeneratedPluginRegistrant and the generated
  Swift Package Manager dependency graph; AppDelegate registers plugins on the
  implicit Flutter engine. CocoaPods lockfile is absent; this project already uses
  generated Swift Package Manager integration. None of these files was edited.
- Client configuration is passed in Dart, as supported by the plugin; no
  GoogleService-Info.plist or Firebase setup was added.

References: https://pub.dev/packages/google_sign_in/versions/7.2.0 and
https://pub.dev/packages/google_sign_in_ios (Dart client/server ID alternative).

## Files changed

Behavior/integration:
- lib/features/auth/data/google_auth_service.dart
- lib/features/auth/data/auth_repo.dart
- lib/features/auth/cubit/auth_cubit.dart
- lib/features/auth/cubit/auth_state.dart
- lib/features/auth/screens/login_screen.dart
- lib/features/auth/screens/sign_up_screen.dart
- lib/features/auth/widgets/social_login_button.dart

Tests/documentation:
- test/features/auth/google_auth_test.dart
- docs/GOOGLE_SIGN_IN_IOS.md

An overly broad formatter invocation also changed formatting only in these existing
files; no behavior changes were intended or introduced there:
- lib/features/auth/data/auth_response_model.dart
- lib/features/auth/data/user_model.dart
- lib/features/auth/screens/enter_email_screen.dart
- lib/features/auth/screens/otp_verification_screen.dart
- lib/features/auth/screens/forgetpass/create_new_password_screen.dart
- lib/features/auth/screens/forgetpass/forget_password_screen.dart
- lib/features/auth/screens/forgetpass/reset_new_password_screen.dart
- lib/features/auth/widgets/custom_or_login_widget.dart
- lib/features/auth/widgets/terms_privacy_checkbox.dart

## Verification

17 focused tests pass using the installed Flutter test engine, with fake native
platform/API responses: actual package initialization and both IDs; native token,
missing token, cancellation and sanitized failures; exchange serialization;
Travibe session persistence; verification metadata; backend 401/403/422/network
errors and retry; duplicate Google/password submission; late account/disposal
responses; malformed responses; password login/validation regression.

Targeted analysis of changed integration files and tests reports no errors or
warnings, with one existing style info in AuthRepo's registration payload
(`use_null_aware_elements`). The wider auth-folder analysis additionally reports
existing password-screen lint/unused-import findings. No dependency changes or
unrelated lint fixes were made.

The standard flutter test runner is blocked by sandbox localhost socket access
(OS error 1, 127.0.0.1). Tests were compiled and run through the installed Flutter
engine without a VM-service socket. Runner and results are in
/private/tmp/travibe-google-auth-*. No real Google/Laravel exchange or new iOS
Simulator run is claimed.

## Backend and manual verification

Backend must validate ID-token signature, issuer, expiry and audience against the
configured Web OAuth client ID, and return the supplied Laravel auth envelope.
Confirm Google Cloud's iOS OAuth client bundle ID matches com.travibe.app, the
Web client is the intended token audience, and consent/test-user configuration
permits the testing account. Client IDs are public configuration, not secrets;
no OAuth client secret belongs in this app.

1. Fully stop/relaunch on an iOS Simulator/device using the normal flutter run
   flow. No new native files/dependencies were introduced; hot restart is normally
   enough for Dart changes, but a full launch also verifies installed registration.
2. On Login and Signup, tap Google, choose an allowed Google account and verify
   callback return, one backend exchange, Root navigation and API access using the
   Travibe token. Confirm persistence after relaunch using current app routing.
3. Cancel account selection: no error snackbar or Laravel request/session change.
4. Repeat taps; test offline/backend denial, retry and logout/account change while
   authentication is pending. Never copy ID tokens/bearer tokens into logs.
5. Verify the email-verification route if the backend can return that condition,
   and regression-check normal password login and signup/OTP.
6. If native callback fails, check bundle ID, URL scheme, signing and OAuth console
   configuration before changing code. Real end-to-end success remains pending.

# Auth back navigation

Implemented 16 November 2026 on `back-button-auth`. Rules follow Instagram/TikTok:
the back button, Android back and the iOS edge swipe always do the same thing.

## Rules

| Screen | Back button | Android back / iOS swipe |
|---|---|---|
| Splash | none | Android closes the app |
| Onboarding slide 1 | none | Android closes the app |
| Onboarding slides 2+ | none | Android → previous slide (slides already swipe sideways) |
| Login | **none** — bottom of the auth stack | Android closes the app |
| Signup | → Login | same; iOS swipe reveals Login beneath |
| Terms / Privacy from Signup | → Signup, form and checkbox kept | same |
| OTP (from Signup or Login) | → that screen, email kept | same |
| OTP (opened at startup) | → Signup (email prefilled) above Login | Android same; iOS has nothing to swipe to |
| Profile setup step 1 | none | Android does nothing; iOS swipe off |
| Profile setup steps 2–3 | → previous step | Android same; iOS swipe off (see limits) |
| Forgot password | → Login | same; its "Log In" link also pops, never stacks a 2nd Login |
| Reset code | → Forgot password, email kept | same |
| Create new password | glass confirm **"Cancel password reset?"** → Login (email prefilled) | Android same; iOS swipe off |
| "Password updated!" | none | Android → Login (email prefilled) |

After a step completes the whole stack is replaced, so back from the next
screen never shows auth screens: login/signup → Home, OTP verified → Profile
setup, setup completed → Home (unchanged).

## Implementation

- `lib/features/auth/screens/auth_navigation.dart` holds the rules:
  `resetTo` (clear every route), `back`, `backToLogin`, `toLogin`, `toSignup`.
- Signup is a child route of Login: `AppRoutes.register` is now
  `/login/register`, so `go(register)` builds Login with Signup on top. Its page
  is an explicit `MaterialPage`: go_router 18 otherwise falls back to a
  no-transition page here, which also has no iOS back swipe.
- Signup, OTP and Forgot password are **pushed**, not used to replace the
  current screen, so the previous step keeps its input.
- Every screen uses the shared `BackButtonWidget` at its defaults (44×44, 24
  icon); the per-screen wrappers with adaptive sizes and an 18 icon are gone.
  `AuthAppBar` takes `showBack` (false on Login) and `onBack`.
- Screens that intercept back use `PopScope`, calling the same handler as the
  button. Profile setup's "Leave without saving photo?" dialog is no longer
  reachable (step 1 can't be left), so it was removed.
- Removed the unused `EnterEmailScreen` (`enter_email_screen.dart`) and
  `VerifyOtpScreen` (`verify_otp_screen.dart`).

## Limits

- Flutter turns the iOS edge swipe off entirely wherever `PopScope(canPop:
  false)` intercepts back (Create new password, Profile setup). It can't be
  mapped to a confirm dialog or to a step change.
- Tests check the iOS swipe through the route (Material transition and
  `popGestureEnabled`) rather than simulating a drag: a simulated edge drag only
  starts when it is the first test in the file, so it isn't a reliable check.

## TODO: OTP → Signup with an existing unverified account

Going back from OTP to Signup is allowed, but the account already exists on
the server. Submitting the same email again currently shows the "email already
exists → Log In" dialog. It should instead return to OTP for that email with
"Resend code". Marked `TODO(back-button-auth)` in `sign_up_screen.dart`.

## Tests

- `test/features/auth/auth_back_navigation_test.dart`: Login, Signup, OTP,
  Forgot password, reset code, Create new password and stack clearing.
- `test/features/onboarding/onboarding_screen_test.dart`: previous slide and
  Signup-above-Login after onboarding.
- `test/features/profilesetup/identity_photo_test.dart`: setup steps and step 1.

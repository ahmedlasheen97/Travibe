# Authentication and shared glass UI polish

Implemented 2026-11-03 in the existing screens and navigation architecture.
No SVGs, dependencies, native launch configuration, preferences/session policy,
1500ms splash phases, startup decisions or VS Code settings were changed.

## Password controls — current mapping

Login Password and Sign Up Password/Confirm Password opt into the existing
CustomTextField's `passwordVisibilityToggle` option. They start obscured and
maintain independent widget state. The shared control keeps the original field
padding, dark fill, controllers, validators and keyboard configuration. Toggling
preserves text, selection/cursor and field focus. A 48px trailing target holds one
centered SVG rendered at 24 × 24. Explicit button semantics and visible tooltips
describe the action without duplicate screen-reader labels.

| Current state | Direct SVG | Accessible action |
| --- | --- | --- |
| Hidden (default) | `assets/images/onboarding/eye-slash.svg` | Show password |
| Visible | `assets/images/interactions/eye.svg` | Hide password |

The supplied eye-slash asset was inspected: it is a complete crossed-eye
illustration with a 20 × 20 viewBox, proportionally rendered in the existing 24px
slot. It replaces the previous eye.svg + slash-only eye2.svg composition. No SVGs
are overlaid, redrawn or modified. Other CustomTextField callers retain their
existing obscureText/suffixIcon behavior unless explicitly opted in.

## Standard action buttons — 32px radius / 18px labels

`ActionButtonStyle` defines the shared 32px rounded rectangle and 18 logical-pixel
Plus Jakarta Sans label. CustomButton uses it for both filled/outlined actions,
with the existing semibold weight, colors and configured height (48px by default).
The default ElevatedButton theme uses the same shape and explicit Plus Jakarta
Sans family while retaining its existing 18px regular weight and colors.
Button text styles need an explicit family because a ButtonStyle.textStyle can
replace the default theme label style instead of inheriting its font family.

The same style applies to standard Profile save/update/report actions, profile
empty-state CTAs, authentication Verify actions, social-login secondary actions,
onboarding Next, and the duplicate-email dialog's primary/secondary actions.
Local weights are retained (social and Next use medium, save actions semibold).
Existing destructive buttons, glass Back controls, icon buttons, tabs, chips,
Follow/Following pills and the special Get Started slider keep their own designs.
The logout dialog's compact/destructive actions and both glass surfaces are intact.

Profile Share Profile and Edit Profile remain **44px high** with their original
grey colors, equal widths, 12px gap and existing enabled/disabled callbacks.
Single-line scale-down fitting keeps nominal 18px labels inside fixed-height
compact controls, including narrow widths and enlarged text, without clipping.
It has no effect when the text already fits. Social buttons remain 50px high;
slightly smaller horizontal padding/gap accommodates their 18px labels. Save and
Verify actions remain 56px high. Loading indicators and submission guards are
unchanged. The duplicate-email dialog retains its minimum 48px action targets,
scrolling, warning illustration, layout and navigation behavior.

## Header rendering root cause and central fix

The horizontal line was reproduced in rendered Login and Sign Up AppBar titles
before editing: the RichText style contained `TextDecoration.lineThrough`.
The sole app-wide source was `darkTheme.textTheme.titleLarge`, which explicitly
set strikethrough and its decoration color. AppBar uses that style for its title;
local white-only TextStyles merged with it and retained the decoration. The line
was not a Divider, Stack overlap, clipping problem or Plus Jakarta Sans font
metric artifact. Font files and weight declarations were already correct.

The theme now sets `titleLarge.decoration = TextDecoration.none` and white title
text. The original titleLarge 16px size and regular weight are retained. Existing
local header sizes/weights (such as 17px bold Profile headers) continue to win.
AppBarTheme centers titles consistently and retains the existing dark background.
No per-screen decoration patches or header replacement was needed. Shared glass
Back controls, callbacks and header heights are unchanged.

The same two real auth-title tests that failed with inherited strikethrough pass
after the fix. Additional theme-rendering checks preserve explicit size/weight
for Edit Profile, Profile Setup, Followers/Following, Settings and Delete Account
header styles. ProfileTabs' legitimate 2px selection underline remains and still
moves when selecting another tab; no divider or tab decoration was removed.

## Duplicate-email error mapping

The checked-in OpenAPI RegisterRequest says email must not already be registered.
Its 422 ValidationException contains `message` and `errors`, with a list of
messages for each field. A read-only-contract, validation-only request to the live
register endpoint confirmed this envelope on 2026-11-03. It intentionally omitted
required credentials/device fields and supplied `terms_accepted: false`; it
returned 422 and did not create an account. The response reported missing
password/device_name and unaccepted terms, not email uniqueness.

`isDuplicateEmailError` requires both:

- HTTP status 422 in the existing typed ApiError.
- A structured `fieldErrors['email']` message exactly equal to
  `The email has already been taken.` after trimming and lowercasing.

It never searches an arbitrary exception's text or treats every 422 as a
registered email. Matching text on another field, a generic summary with no
email field error, invalid email syntax, password validation and server failures
do not open this modal. Unknown/localized uniqueness wording retains the normal
error message rather than being guessed. No undocumented numeric/code contract
was invented.

AuthRepo.register now rethrows ApiError unchanged, preserving the status and
structured field errors already mapped by ApiExceptions/ApiService. Other
registration failures keep their normal Snackbar message and client validators.
The exact duplicate-email wording was exercised through a transport fixture,
not verified against a real existing account; this is a backend verification
limit. A future confirmed alternate/localized message can be added narrowly.

## Glass email modal and actions

The compact centered EmailExistsDialog uses the actual unmodified
`assets/images/onboarding/Group 736.svg` at its original 80 × 80 proportions and
colors (red circle, white exclamation, subtle outer red ring). It uses:

- Shared clipped GlassSurface, sigma 8 blur, dark .82-opacity fill.
- 30px corners, thin low-contrast white border, responsive maximum width 340px.
- White 20px heading, muted 14px description, inherited Plus Jakarta Sans.
- Orange primary button and white secondary text, each at least 48px high.
- Dialog SafeArea behavior, keyboard dismissal before opening, and a scrollable
  surface for short viewports, keyboard insets and enlarged text.

Content is exactly:

> Email already exists
>
> An account with this email exists. Please log in or use another email.

**Log In Instead** dismisses the dialog and opens the existing Login screen,
prefilling only email. Passwords are never transferred. The normal GoRouter
path uses `/login?email=…`; a former imperative signup replacement is removed
once Login is installed. If GoRouter still matches a Login page that Signup
imperatively replaced, the existing Navigator architecture is reset directly.
Standalone navigation similarly removes the old auth stack. Regression tests
cover both router paths and ensure one Login and no back entry to the old form.

**Try Another Email** dismisses the modal, stays on Signup, focuses the email
input and selects its text for replacement. Password, confirmation, terms and
other form state remain intact. Barrier/system dismissal simply stays on Signup.
The in-flight registration and dialog guards prevent identical modals stacking.

## Shared glass component and BackButtonWidget

The existing BackButtonWidget was updated in place, keeping `onTap` compatible.
Optional `size`, `iconSize` and `enabled` parameters support existing compact
headers and loading guards. Default visual size is 44px; compact profile headers
retain their 36px circle and 16px arrow, with a minimum 44px target where parent
constraints permit. Existing 40px headers constrain target height without overflow.
The existing arrow-left SVG is white, excluded from duplicate semantics and
mirrored with text direction. Material's localized Back tooltip labels the button.
The default callback uses maybePop so a root Login is not accidentally removed.
Custom callbacks preserve route-specific behavior.

GlassSurface factors the existing logout dialog treatment into a shared widget.
Logout keeps its surface key, 24px radius, .78 opacity, content and session logic.
Back buttons use circular clipping and .65 opacity. Both buttons and dialogs use
a moderate shared sigma 8 filter clipped to their own bounds, not a full-screen
blur. High contrast or reduced motion uses an opaque surface without blur and a
stronger border. Only local state changes rebuild the password icon/field.
No frame-rate or physical-device performance claim is made.

## Screens using the shared Back button

- Login, Signup, email verification and legacy enter-email/OTP screens.
- Forgot Password, reset-code verification, create-new-password and its success
  state. Existing maybePop callbacks are retained.
- Profile Setup: retains goBack between setup steps before leaving the route.
- Edit Profile: retains the unsaved-edit/discard flow and session-change fallback.
- Settings, Change Password, Currency, Languages, Interests, Travel Styles,
  Report Problem, legal text pages, and Blocked Accounts.
- Delete Account: retains _cancel and disables Back while deletion is processing.
- Public Profile, Followers/Following, and the existing suggested Buddies route.
  Implicit AppBar back controls are customized only where a route can pop.
- Buddies listing, search and filters, including the session-change fallback.
- Story editor: retains its stable story-back key and Navigator.pop callback.
- Search already used BackButtonWidget and inherits its glass style automatically.

The current Explore tab has no details/back route, and there is no standalone
post-details screen to migrate. Comments/replies are a modal sheet with no
circular back control. No new buttons were added there. Bottom navigation,
forward chevrons, modal close/dismiss controls and non-back story tools are intact.

## Original glass update — files changed

Production:

- `lib/features/auth/screens/verify_otp_screen.dart`
- `lib/features/auth/screens/enter_email_screen.dart`
- `lib/features/auth/screens/otp_verification_screen.dart`
- `lib/features/auth/screens/forgetpass/create_new_password_screen.dart`
- `lib/features/auth/screens/forgetpass/reset_new_password_screen.dart`
- `lib/features/auth/screens/forgetpass/forget_password_screen.dart`
- `lib/features/follow/screens/follow_users_screen.dart`
- `lib/features/profilesetup/screens/profile_setup_screen.dart`
- `lib/features/stories/screens/story_editor_screen.dart`
- `lib/features/profile/screens/report_problem_screen.dart`
- `lib/features/profile/screens/languages_screen.dart`
- `lib/features/profile/screens/settings_screen.dart`
- `lib/features/profile/screens/delete_account_screen.dart`
- `lib/features/profile/screens/blocked_account_screen.dart`
- `lib/features/profile/screens/profile_screen.dart`
- `lib/features/profile/screens/currency_screen.dart`
- `lib/features/profile/screens/interests_screen.dart`
- `lib/features/profile/screens/change_password_screen.dart`
- `lib/features/profile/screens/edit_profile_screen.dart`
- `lib/features/profile/screens/travel_style_screen.dart`
- `lib/features/profile/widgets/legal_text_screen.dart`
- `lib/features/buddies/screens/buddies_filters_screen.dart`
- `lib/features/buddies/screens/buddies_search_screen.dart`
- `lib/features/buddies/screens/buddies_listing_screen.dart`
- `lib/core/widgets/custom_text_field.dart`
- `lib/core/widgets/back_button_widget.dart`
- `lib/core/widgets/glass_surface.dart`
- `lib/features/auth/screens/login_screen.dart`
- `lib/features/auth/screens/sign_up_screen.dart`
- `lib/features/auth/data/auth_repo.dart`
- `lib/features/auth/data/registration_error.dart`
- `lib/features/auth/widgets/email_exists_dialog.dart`
- `lib/features/profile/widgets/logout_dialog_widget.dart`
- `lib/core/routing/router_generator.dart`

Tests:

- `test/features/auth/auth_glass_ui_test.dart`
- `test/core/widgets/back_button_widget_test.dart`
- `test/features/profile/profile_screen_test.dart`
- `test/features/profile/edit_profile_test.dart`
- `test/features/profile/profile_followers_account_ui_test.dart`
- `test/features/profile/account_deletion_test.dart`

Documentation: `docs/AUTH_GLASS_UI_POLISH.md`.

## Original glass update — verification

Targeted `flutter analyze --no-pub` on all 40 changed production/test Dart files:
**No issues found** (2.5 seconds).

- Formatting completed for all changed Dart files.
- Focused auth/glass tests: 19 passed, 0 failed.
- Broader regression command:

```sh
flutter test --no-pub \
  test/features/auth \
  test/core/widgets/back_button_widget_test.dart \
  test/features/profile test/features/profilesetup \
  test/features/follow test/features/buddies test/features/onboarding \
  test/features/stories/story_editor_test.dart \
  test/features/stories/story_editor_alignment_test.dart \
  test/features/stories/story_widgets_test.dart \
  test/features/stories/story_audience_test.dart \
  test/core/datasource/preferences_manager_test.dart \
  --reporter expanded
```

**571 passed, 0 failed.** This includes password/cursor/focus/semantics and SVG
mapping, independent confirmation visibility, validation, typed duplicate errors,
other 422 errors, exact dialog copy/SVG, both modal actions, email focus and form
retention, duplicate-request guards, small/large-text layouts, router and
imperative navigation, glass styles and disabled callbacks, default safe Back,
Edit Profile discard, Followers/Following Back, Delete Account Back/loading,
logout/account deletion stack clearing, session isolation, onboarding, the
unchanged splash, Buddies and story-editor layout/navigation regressions.

Log: `/private/tmp/travibe-auth-glass-regressions.log`.

## Visual/reference and Simulator status

AGENTS.md and docs/FIGMA_REFERENCE.md were reviewed. A new Figma session was
created, but metadata was blocked by the Figma Starter-plan tool limit. No
screenshot attachment was present in the conversation. The modal follows the
written appearance/content requirements and existing Travibe logout treatment;
exact differences from a supplied screenshot cannot be measured.

The booted iPhone 17 / iOS 26.5 Simulator was detected. Interactive verification
was attempted with Computer Use, which returned “Computer Use permissions are
not granted.” Therefore no interactive Simulator verification or new Simulator
screenshots/build are claimed for this task. Automated widget rendering and
interaction tests passed; real-device blur/performance remains unverified.

## Button/header/password follow-up — files changed

The current follow-up changed only the files listed below.

- `lib/core/theme/action_button_style.dart`
- `lib/core/theme/dark_theme.dart`
- `lib/core/widgets/custom_button.dart`
- `lib/core/widgets/custom_text_field.dart`
- `lib/features/profile/widgets/profile_action_buttons.dart`
- `lib/features/profile/widgets/profile_empty_state.dart`
- `lib/features/profile/screens/edit_profile_screen.dart`
- `lib/features/profile/screens/change_password_screen.dart`
- `lib/features/profile/screens/report_problem_screen.dart`
- `lib/features/profile/screens/languages_screen.dart`
- `lib/features/profile/screens/interests_screen.dart`
- `lib/features/profile/screens/travel_style_screen.dart`
- `lib/features/auth/screens/otp_verification_screen.dart`
- `lib/features/auth/screens/forgetpass/reset_new_password_screen.dart`
- `lib/features/auth/widgets/social_login_button.dart`
- `lib/features/auth/widgets/email_exists_dialog.dart`
- `lib/features/onboarding/screens/onboarding_screen.dart`
- `test/features/auth/auth_glass_ui_test.dart`
- `test/core/theme/header_typography_test.dart`
- `test/core/widgets/action_button_style_test.dart`
- `docs/AUTH_GLASS_UI_POLISH.md`

## Button/header/password follow-up — verification

- `dart format` completed for all 20 changed/new Dart files.
- Targeted `flutter analyze --no-pub` over those files: **No issues found**
  (4.6 seconds).
- New button/header suite: **11 passed, 0 failed**.
- Broader final run: **637 passed, 0 failed** (41 seconds), covering the shared
  button/header tests, glass Back tests, session preferences, Login/Signup and
  typed errors/modal navigation, Profile/settings/edit/save/loading, profile
  setup, followers/following, Home, Buddies, onboarding and the unchanged splash.

```sh
flutter test --no-pub \
  test/core/theme/header_typography_test.dart \
  test/core/widgets/action_button_style_test.dart \
  test/core/widgets/back_button_widget_test.dart \
  test/core/datasource/preferences_manager_test.dart \
  test/features/auth test/features/profile test/features/profilesetup \
  test/features/follow test/features/home test/features/buddies \
  test/features/onboarding --reporter expanded
```

The original two auth-header regressions deliberately failed before the theme
fix, confirming the inherited lineThrough cause. Final checks pass for both real
auth titles, shared header inheritance, intact tab underlines, nominal 18px
Plus Jakarta Sans labels, 32px action radii, unchanged disabled/loading states,
44px Profile actions, 50px social actions, fitting at 320px width/large text,
hidden defaults and direct single-SVG mapping, independent password fields,
text/cursor/focus preservation, validators and existing glass navigation.

The Simulator access check in this follow-up returned “Computer Use was not
approved to use Simulator”. No new Simulator interaction, screenshots or visual
inspection is claimed. No screenshot attachment was accessible for comparison;
the header issue was independently reproduced and fixed through real rendered
widget styles. The prior Figma plan-limit restriction remains documented above.

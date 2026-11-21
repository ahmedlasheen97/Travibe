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

## MVP authentication controls — 2026-11-15

### Scope and implementation

- `lib/core/constants/feature_flags.dart`: centralized
  `kEnableSocialAuthentication = false`. Login and Sign Up conditionally omit the
  entire social block, including divider and its spacing. The shared
  `SocialLoginButton` also supplies a null callback while the flag is false,
  protecting a direct/accidental mounting of the component.
- Google services, repository methods, Cubits, dependencies and native
  configuration are retained. No Firebase, SwiftPM, Bundle ID, signing or backend
  endpoint changes. Re-enabling the flag restores the existing controls; it is
  not a claim that every provider is production-ready. The existing Apple UI
  callback was already a placeholder and remains one.
- `lib/features/auth/widgets/auth_app_bar.dart`: shared auth-only header using
  `assets/images/interactions/travibe_logo.svg`. The existing asset is an orange T
  symbol (119 × 108 viewBox), not a wordmark. It is rendered unchanged at 36px
  high, proportional width, with a “Travibe” accessibility label, centered title
  placement and the existing glass BackButtonWidget. `pubspec.yaml` already
  registers the interactions directory; no asset or manifest change is needed.
- Both auth screens paint their Scaffold and outer SafeArea background with
  `DarkColors.backgroundColor` (#080808). The local AppBar sets zero elevation
  and zero scrolled-under elevation, transparent tint/shadow and light status-bar
  icons. These overrides do not affect other screens or the global theme.
- Account-switch footer rows now wrap at narrow widths/large text scales while
  staying centered. The former social/footer gap on Login is reduced to the
  existing 32px spacing token when social controls are absent.
- Login accepts an optional AuthRepo for the same test-injection pattern already
  supported by Sign Up. Production defaults and email-password API flow remain
  unchanged.

### Diagnosed causes and limits

Social controls were unconditionally rendered. The duplicate-email dialog's
secondary action explicitly assigned a selection from offset 0 to the email
length. It now requests focus and assigns `TextSelection.collapsed` at that
length (including zero for empty text), retaining all form values and consent.
The current action is named **Try Another Email**; no separate **Try Another
Account** action exists in the inspected auth code, so the label is preserved.

The original headers relied on inherited Material 3 appearance and the global
#0A0A0A surfaces rather than the existing #080808 token. The installed Flutter
SDK supplies a default 3px scrolled-under elevation; its default surface tint is
already transparent. The reported exact purple pixels were not reproduced on a
Simulator in this task, so tint alone is **not** asserted as the confirmed cause.
Explicit local surfaces/elevation remove that dependency; rendered widget tests
verify the actual AppBar Material remains #080808 after scrolling with keyboard
insets. No global theme, overscroll physics or form styling was changed.

### Files for this update

- `lib/core/constants/feature_flags.dart`
- `lib/features/auth/widgets/auth_app_bar.dart` (new)
- `lib/features/auth/widgets/social_login_button.dart`
- `lib/features/auth/screens/login_screen.dart`
- `lib/features/auth/screens/sign_up_screen.dart`
- `test/features/auth/auth_mvp_ui_test.dart` (new)
- `test/features/auth/auth_glass_ui_test.dart` (cursor expectation updated)
- `test/core/theme/header_typography_test.dart` (auth headers now assert the
  centered original SVG; shared text-header decoration checks remain)
- `docs/AUTH_GLASS_UI_POLISH.md`

Existing uncommitted legal-page work was preserved.

### Verification

- New MVP widget tests: **15 passed**. Cover hidden social controls and disabled
  callbacks, original SVG/semantics/centering, actual email Login/Register calls
  using a mocked ApiService, OTP navigation, consent fields, retained/empty email
  selection, and 320/375/393/430px layouts at 1.6× text with a 300px keyboard inset.
- Focused authentication, shared header and legal-consent regressions:
  **85 passed, zero failures**. Existing Google implementation tests still run
  directly against the retained service/Cubit independently of hidden UI.
- The first run of the two new successful-auth tests waited for all animations
  to settle on the OTP screen, whose cursor animation does not settle. The tests
  now wait for route transition frames and assert OTP navigation. No production
  OTP behavior or assertions were removed.
- Initial targeted analysis: **no issues**. Full-project analysis: zero errors,
  zero warnings, one pre-existing informational
  `use_key_in_widget_constructors` in
  `lib/features/home/widgets/custom_bottom_nav.dart:10`.
- Full Flutter suite: **2,317 passed, zero failures, one existing intentional
  opt-in skip** (`flutter test --no-pub --reporter expanded`).
- iOS Simulator Debug build: **succeeded**, Xcode build 159.2s,
  `build/ios/iphonesimulator/Runner.app` (`flutter build ios --simulator --debug
  --no-pub`). No manual Simulator navigation is claimed.
- Final formatting: all eight changed/new Dart files unchanged by format check.
  Final targeted analysis: **no issues**.
- Logs: `/private/tmp/travibe-auth-mvp-focused.log`,
  `/private/tmp/travibe-auth-mvp-full-tests.log`,
  `/private/tmp/travibe-auth-mvp-targeted-final.log`,
  `/private/tmp/travibe-auth-mvp-full-analysis.log`,
  `/private/tmp/travibe-auth-mvp-ios-build.log`.
- No live authentication requests or native Google/Apple flows were performed.
  No manual Simulator navigation was performed for this update.

Figma metadata identified Login `157:6966` and Sign Up `190:7619`. Both design
context/screenshot requests were blocked by the Figma Starter-plan tool-call
limit. This update follows the requested MVP changes and existing components;
pixel-level comparison with those Figma frames was not performed.

## Authentication responsive sizing — 2026-11-15

This update supersedes the interim 32px auth body gap. Measured before this
change: both Login and Sign Up had 32 logical pixels of top padding, entirely
inside their SingleChildScrollView. That padding is replaced, not accumulated.

### Audit and layout changes

| Existing screen | Changes |
| --- | --- |
| Login | AppSizes header gap; bounded spacing, square icons and current typography; existing scroll owner retained |
| Sign Up | Same header gap; bounded spacing, icons and current typography; form, legal consent and collapsed email cursor retained |
| ForgotPasswordScreen | One vertical scroll owner; adaptive insets/gaps/icons; centered wrapping Login footer |
| ResetPasswordOtpScreen | Scrollable recovery body; adaptive square PIN cells and gaps; wrapping resend text/action with accessible touch target |
| CreateNewPasswordScreen | Both form and success views scroll; adaptive spacings, hint text constraints, radii and success illustration |
| OtpVerificationScreen | Scrollable email-verification body; adaptive PIN sizing/spacing; wrapping accessible resend action; custom verification callbacks retained |
| CreateNewPassScreen (`enter_email_screen.dart`) | Existing legacy placeholder, not referenced by current app routes; scrollable body and wrapping footer |
| VerifyOtpScreen | Existing legacy placeholder, not referenced by current app routes; scrollable body; previously 130px-wide PIN fields replaced with bounded 60-reference-pixel widths and text-aware heights |

No separate two-factor screen exists in the inspected module. No screen or
backend behavior was invented. Existing legacy placeholder actions/content remain
placeholders; responsiveness changes do not turn them into API integrations.

### AppSizes reuse

`lib/core/constants/app_sizes.dart` retains its legacy fields for other features.
The existing `adaptiveWidth`, `adaptiveHeight`, `adaptiveRadius` and
`adaptiveFont` helpers are reused throughout auth-owned layout. These evaluate
ScreenUtil at build time and bound growth/shrinkage, unlike eagerly initialized
legacy `static final` values that can retain metrics from their first access.

New getter: `AppSizes.authHeaderSpacing` uses `64.h.clamp(48.0, 64.0)`:
64 logical pixels on the 390 × 844 reference and taller screens, reduced on
compact displays. The existing root `splitScreenMode: true` may impose a minimum
ScreenUtil reference height; keyboard viewInsets do not change screen height or
recompute the gap from the reduced keyboard viewport. The gap remains in the
scrollable content and can scroll away. AppBar height, centered SVG geometry and
Login/Sign Up glass Back controls are unchanged.

Layout literals migrated include body/section gaps, recovery horizontal insets,
SVG/icon sizes, dialog insets/content padding/max width/radius, password-field
padding/radii, social controls, and consent/link spacing. Square artwork and PIN
cells use one radius scale, rather than independent width/height factors.
The existing horizontal design insets remain consistent within each flow:
8 reference pixels for Login/Sign Up and the legacy email page, 24 for recovery
and active verification pages. These now use bounded adaptive helpers; they were
not globally replaced with an unrelated layout.

The disabled social divider uses flexible separators/text instead of fixed-width
100px bars. Consent links and checkbox retain/improve accessible touch targets.
OTP resend controls wrap and use standard button touch targets. Existing 50px
social and 56px verification buttons have minimum height bounds so compact-screen
scaling does not shrink their interaction areas.

### Intentionally retained constants

- Auth AppBar toolbar height and original logo geometry (36px high, 119:108
  aspect ratio), explicitly required to remain unchanged.
- Existing core CustomTextField, CustomButton, BackButtonWidget and
  ActionButtonStyle defaults: these are shared across the app. Their established
  field padding, minimum button targets, 32px action radius and 18px labels were
  not globally changed by an auth-only refactor.
- Fixed minimum touch-target bounds, thin border/progress stroke widths and
  text line-height ratios. They are not arbitrary screen-width-scaled dimensions.
- Colors, opacity, font weights, animation/timer durations, OTP digit count,
  password length, validation regexes and API/navigation constants.
- Commented-out legacy Name field dimensions have no rendered effect.

Network/state methods preceding each screen's build were compared with the
pre-change workspace snapshot and are unchanged. No AuthRepo/AuthCubit, API,
route, session, social feature flag, Firebase, native configuration or dependency
was changed during this sizing update.

### Verification and scope

- New responsive matrix: **96 passed** — eight screens × six display sizes ×
  English/Arabic. Sizes: 320×568, 375×667, 390×844, 430×932, 360×800 and 844×390.
  Each case uses 2× text, SafeArea insets, a 270px keyboard inset and vertical
  scrolling. Header gap is checked separately at standard/compact heights.
- Existing MVP responsive tests now require the 64px standard gap, retaining
  keyboard/black AppBar checks at 320/375/393/430px widths and 1.6× text.
- Focused auth, typography and legal-consent tests: **181 passed, zero failures**.
- Initial matrix found 12 instances of the same legacy email-page fixed-column
  overflow; adding its missing scroll owner resolved all 12. Tests/assertions
  were retained.
- Targeted analysis: **no issues**. Full analysis retains the existing Home
  `use_key_in_widget_constructors` informational lint at
  `lib/features/home/widgets/custom_bottom_nav.dart:10`; no errors or warnings.
- Full Flutter suite: **2,413 passed, zero failures, one existing intentional
  opt-in skip** (`flutter test --no-pub --reporter expanded`).
- iOS Simulator Debug build: **failed during Xcode target integrity checks**.
  `firebase-core` and `firebase-messaging` require iOS 15.0; the generated
  `ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift`
  declares iOS 13.0. Runner's source project already declares 15.0. No source
  iOS/dependency files changed in this task; the generated SwiftPM deployment
  mismatch was not altered as part of this auth-only change. Do not interpret
  the passing Dart tests as a successful native build. No Simulator launch or
  manual verification was performed.
- Logs: `/private/tmp/travibe-auth-responsive-focused-final.log`,
  `/private/tmp/travibe-auth-responsive-matrix.log`,
  `/private/tmp/travibe-auth-responsive-targeted-final.log`,
  `/private/tmp/travibe-auth-responsive-full-analysis.log`,
  `/private/tmp/travibe-auth-responsive-full-tests.log`,
  `/private/tmp/travibe-auth-responsive-ios-build.log`.
- Layout verification is automated widget rendering, not manual Simulator or
  native-hardware verification. The module's English copy is unchanged; Arabic
  directionality is tested and existing localized consent text is retained.
  This does not claim newly translated Arabic auth copy or verification above
  2× text scaling on every platform/font combination.

Files for this update: AppSizes; all eight existing auth screens; auth-owned
`social_login_button.dart`, `custom_or_login_widget.dart`,
`terms_privacy_checkbox.dart`, `email_exists_dialog.dart`;
`auth_mvp_ui_test.dart`; new `auth_responsive_layout_test.dart`; this document.

## Text auth headers and compact Sign Up — 2026-11-15

This section supersedes the logo-header and Sign Up 64px-gap descriptions above.
The shared AuthAppBar now requires a title, using the original centered white
text style: **Login** and **Sign Up**. It retains the existing toolbar height,
glass BackButtonWidget, black surface, status-bar styling and disabled
scroll-under elevation/tint. The SVG asset and its pubspec registration remain
untouched; the header no longer renders the logo. Typography tests again assert
Plus Jakarta Sans, the original 16px regular header style and no strikethrough.

Login's AppSizes.authHeaderSpacing and body layout are unchanged. Sign Up alone
uses AppSizes.adaptiveHeight(24) as its entire top padding inside the existing
SingleChildScrollView. At the 390 × 844 reference this is 24 logical pixels.
One duplicated 16px spacer after the heading was removed (one 16px gap remains),
and the old 35px footer gap is now adaptive 16px. No input dimensions, text sizes,
consent/link targets, required elements, validation or authentication methods were
changed. Normal scroll physics remain available; no clipping or forced scroll
suppression is used.

Measured layout results using bundled Plus Jakarta Sans, SafeArea top/bottom
insets of 59/34, default text scaling and the keyboard closed:

| Display size | English | Arabic RTL |
| --- | --- | --- |
| 375 × 812 | Entire form fits; zero vertical scroll extent | Entire form fits; zero vertical scroll extent |
| 390 × 844 | Entire form fits; zero vertical scroll extent | Entire form fits; zero vertical scroll extent |
| 430 × 932 | Entire form fits; zero vertical scroll extent | Entire form fits; zero vertical scroll extent |

Natural scrolling remains necessary and was verified at 320 × 568 and 375 × 667,
at 844 × 390 landscape, with 2× text at 390 × 844, and with an active email
keyboard/270px inset at 390 × 844, in both directions. Tests scroll to the footer
and verify that it remains reachable. Error/validation messages or different
system fonts/insets may legitimately require additional scrolling.

Files for this focused update:
- `lib/features/auth/widgets/auth_app_bar.dart`
- `lib/features/auth/screens/login_screen.dart` (title argument only)
- `lib/features/auth/screens/sign_up_screen.dart`
- `test/core/theme/header_typography_test.dart`
- `test/features/auth/auth_mvp_ui_test.dart`
- `test/features/auth/auth_responsive_layout_test.dart`
- `test/features/auth/signup_fit_test.dart` (new; 16 fit/scroll cases)
- This document.

Verification: targeted analysis **no issues**; **197 focused tests passed**
(authentication, 96-screen responsive matrix, header typography, signup fit and
legal-consent regressions). Full suite: **2,429 passed, zero failures, one existing
intentional opt-in skip**. Formatting and git diff whitespace checks passed.
Logs: `/private/tmp/travibe-auth-cleanup-analysis.log`,
`/private/tmp/travibe-auth-cleanup-focused.log`,
`/private/tmp/travibe-auth-cleanup-full-tests.log`.
Layout verification is automated widget rendering; no manual Simulator or live
authentication verification is claimed. The prior native SwiftPM deployment
mismatch remains outside this focused UI task; no native files were modified.

## Forgot-password flow matches Login / Sign Up

All six auth screens (Login, Sign Up, Forgot Password, reset code, Create New
Password and its "Password updated!" view) now share one layout:

- `AuthPage` (`features/auth/widgets/auth_page.dart`): `AuthAppBar` + one
  `SingleChildScrollView` + `AppSizes.authPagePadding` (8 / 24 top / 8 / 8).
  Login and Sign Up use the titled bar. Forgot Password, Verify Code, New
  Password, "Password updated!" and Verify Email use `AuthPage.recovery`: the
  bar shows only the back button (none on "Password updated!") and the heading
  sits `AppSizes.authRecoveryHeaderGap` (40) below it. Back rules are unchanged
  (see `AUTH_BACK_NAVIGATION.md`).
- `AuthHeading`: `AppStyles.authTitleStyle` title, optional subtitle in
  `grey16MediumStyle` (16) `AppSizes.authSubtitleGap` (8) below.
- `AuthHeading.small` (forgot password, reset code, new password, "Password
  updated!", email verification): title `AppSizes.authSmallTitleFont` (20,
  same weight/line height as `authTitleStyle`), subtitle
  `AppSizes.authSmallSubtitleFont` (14) in `DarkColors.greyColor` (#BDBCBB),
  both centered. The masked email uses the same 14 size, centered, in white.
  Login and Sign Up keep the 32 left-aligned `AuthHeading`.
- Spacing tokens: `authTitleGap` 24, `authFieldGap` 20, `authActionGap` 32
  (Login's values). Sign Up was checked to still fit 390×844 and 375×812 without
  scrolling, so Sign Up's former 16/16/24 was replaced by these everywhere.
- Fields are `CustomTextField` (sms/lock icons, `PasswordEye` toggle); main
  buttons are `CustomButton`. The reset-code Verify button now shows
  "Verifying..." instead of a spinner, like Login's "Logging in...".
- The email-verification screen (`OtpVerificationScreen`) uses the same
  `AuthPage` / `AuthHeading` / `CustomButton` with bar title "Verify Email"
  (also when opened from Profile → change email). Wrong-code toast, the
  5-attempt lock and resend are unchanged.
- Tests: `forgot_password_ui_test.dart`; `auth_responsive_layout_test.dart`
  checks the heading gap, inset and style on every forgot-password and
  verification screen.

### Sizes come from AppSizes

Every size on the auth screens and their widgets (`features/auth/widgets/`) is a
named `AppSizes` token (`auth*`): paddings, gaps, fonts, icons, PIN cells,
success badge, social buttons, consent checkbox and the "Email already exists"
dialog. The shared field/button/theme use fixed `field*` / `button*` constants
with their previous values, so other screens are unchanged. Not tokenised on
purpose: zeros, elevation, `flex`, `maxLines`, line-height ratios (1.25 / 1.4 /
1.5), `kMinInteractiveDimension`, colors/alpha and non-size logic (attempts,
timer, code length). `BackButtonWidget` (44/24) keeps its own app-wide
constants. `auth_screen_sizes_test.dart` checks 375×667, 390×844 and 430×932.

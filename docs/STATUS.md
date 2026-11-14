# Status: settings screens (2026-11-14)

**Done and merged into `main`.** Branch `settings-screens` was split into one commit
per task (eye icons, report a problem, delete account, email address, docs),
merged with `--no-ff`, pushed and deleted locally.

## Verification at merge

- `flutter analyze --no-pub`: only the existing info in
  `lib/features/home/widgets/custom_bottom_nav.dart`.
- Full suite with `test/live/` excluded: 2257 passed.
  ```bash
  ls -d test/*/ | grep -v '^test/live/' | xargs flutter test --no-pub
  ```
- New: `test/features/auth/otp_verification_screen_test.dart` (signup path
  unchanged; custom `onVerify`/`onResend`/`onVerified` used).
- `profile_followers_account_ui_test.dart` updated for the new Delete Account UI
  (reason field shown, theme danger colour, button disabled on empty password).

## Testing notes

- The OTP pin cursor blinks forever: use bounded pumps, not `pumpAndSettle`.
- `CurrentUserCubit` in tests needs `SettingsRepo(apiService: api, supportedCurrencies: …)`.
- Re-entering a full code in the pin field needs a clear first (4→4 doesn't fire `onCompleted`).

## Open notes for the user

- **Change Password** is still the old stub (`// TODO: wire to AuthRepo`).
  `PATCH /password` exists in the spec; only the icons changed.
- **OTP signup resend** still calls `forgot-password` instead of `/email/resend-code`
  (pre-existing behaviour).
- **Email change.** The password is held in memory only for Resend (no resend
  endpoint for this flow); dropped on close or session change.
- **Report a Problem** uses the proposed `POST /support/problems`; see
  `docs/BACKEND_REQUESTS.md` with the other backend requests.

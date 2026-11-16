// Compile-time switches for features that are temporarily hidden.

/// Settings → App Preferences → Currency. Hidden until it returns with the
/// Explore tab; `CurrencyScreen` and the `currency_code` setting stay intact.
const bool kShowCurrencySetting = false;

/// Settings → Help & Legal → Report a Problem. Hidden until the backend ships
/// `POST /support/problems` (docs/BACKEND_REQUESTS.md); `ReportProblemScreen`
/// and `SupportRepo.reportProblem` stay intact.
const bool kShowReportProblem = false;

/// MVP: hide social controls and disable their callbacks. Native providers,
/// repositories and configuration remain available for a later release.
const bool kEnableSocialAuthentication = false;

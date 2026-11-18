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

/// Profile → Saved → Hotels sub-tab. Hidden until it returns with the
/// Explore tab; `HotelCard`, `ProfileSavedSubTabs` and the Hotels branch stay
/// intact.
const bool kShowSavedHotels = false;

/// Stories: "People you mention can reshare this story" toggle, the viewer's
/// Reshare button and the "reshared from mention" header. Hidden until the
/// backend ships `allow_reshare`, `can_reshare`, `reshare_of_story_id` and
/// `reshared_from` (docs/BACKEND_REQUESTS.md). Widgets take an
/// `enableReshare` parameter defaulting to this so tests can turn it on.
const bool kEnableStoryReshare = false;

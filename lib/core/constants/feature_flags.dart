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

/// Stories: the viewer's Reshare button, the "reshared from mention" header
/// and sending `allow_reshare` / `reshare_of_story_id` on `POST /stories`.
/// Off until the backend ships `allow_reshare`, `can_reshare`,
/// `reshare_of_story_id` and `reshared_from` (docs/BACKEND_REQUESTS.md). The
/// "People you mention can reshare this story" toggle is always shown and its
/// value is kept on the draft. The viewer takes an `enableReshare` parameter
/// defaulting to this so tests can turn it on.
const bool kEnableStoryReshare = false;

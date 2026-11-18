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

/// Stories: the viewer's Reshare button (`can_reshare` →
/// `POST /stories/{id}/reshare`) and the "reshared from @user" header
/// (`reshared_from`); see docs/backend/STORY_RESHARE.md. The editor's
/// "People you mention can reshare this story" toggle shows only for a public
/// story from a public account and is sent as `allow_mention_reshare`. The
/// viewer takes an `enableReshare` parameter defaulting to this.
const bool kEnableStoryReshare = true;

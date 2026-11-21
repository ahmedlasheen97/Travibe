/// Arabic is out of the MVP. Flip to `true` to bring back the Arabic option,
/// Arabic/RTL app locale and Arabic legal texts; all that code stays in place.
const bool kArabicEnabled = false;

/// Language codes the app can currently run in.
const Set<String> kAppLanguageCodes = kArabicEnabled ? {'en', 'ar'} : {'en'};

/// [code] when the app can run in it, otherwise English.
String effectiveAppLanguage(String? code) =>
    kAppLanguageCodes.contains(code) ? code! : 'en';

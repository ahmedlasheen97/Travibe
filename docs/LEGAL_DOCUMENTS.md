# Terms of Service and Privacy Policy

Implemented 14 November 2026; final verification 15 November 2026.

## Status and publication boundary

The legal readers are implemented. **The content is a draft requiring legal and
bilingual review before publication**, not an approved or currently effective
agreement. Every screen and exported review document displays that status.
Travibe is used only as the product name. No registered operator, contact address,
age requirement, retention period or governing jurisdiction has been invented.

Authoring version: `draft-2026-11-14.1`.
Last updated: `2026-11-14` (the draft authoring date, not a changing runtime date).
Effective date: deliberately unset, displayed as a confirmation placeholder.
`LegalDocument.requiresLegalReview` remains true.

Reviewable text generated from the application source:

- [Terms — English](legal/drafts/terms.en.md)
- [Terms — Arabic](legal/drafts/terms.ar.md)
- [Privacy — English](legal/drafts/privacy.en.md)
- [Privacy — Arabic](legal/drafts/privacy.ar.md)

Regenerate these local artifacts after editing the source:

```sh
dart tool/export_legal_documents.dart
```

The exporter writes only `docs/legal/drafts/`. It does not publish or upload,
contact any endpoint, or assert that a web version is live. Edit the Dart source,
not the generated Markdown, to keep the app and review copies aligned.

## Inspected implementation and factual boundaries

| Area | Sources inspected | Treatment in draft |
| --- | --- | --- |
| Authentication and consent | `auth_repo.dart`, Sign Up form, `RegisterRequest` and `UserResource` in `docs/openapi.json` | Email/password/device name/language/acceptance choice; verification/profile setup; no invented age gate or acceptance-version field. |
| Profile and settings | `ProfileModel`, Settings/CurrentUser Cubits, `UpdateSettingsRequest` | Profile fields, private-account and visibility controls; no anonymous-use or universal visibility guarantee. |
| Social content | Documented posts/stories/comments/likes/follows/saves/reports/media resources; Stories implementation notes | Feature processing and audience/access rules; story expiry is not represented as guaranteed erasure from backups or other users' copies. |
| Messaging | Chat models/repositories, memory drafts/history, REST/Reverb architecture | Messages, media, requests, presence, typing and receipts where supported; no end-to-end encryption or screenshot-prevention promise. |
| Device location and city lookup | `device_location_service.dart`, Buddies location flow, `photon_city_places_provider.dart` | User-initiated foreground coordinates/manual city choices; typed queries or coordinates sent to Photon; separate transport omits the Travibe bearer token. |
| Push notifications | Firebase bootstrap/client/service and device-token repository/docs | Firebase Core/FCM, token/platform registration, Apple delivery on iOS, settings and cleanup attempts; no guarantee of delivery or unverified retention claim. |
| Deletion | `AccountRepo`, documented DELETE `/account`, existing account-deletion implementation/docs | Available authenticated confirmation flow and documented associated-record/media deletion; backup/log/legal-retention coverage and operational timing still require confirmation. |
| Travel services | Explore implementation and API path inventory | No completed booking/payment integration was established by inspected code; provider identities, commercial relationships and responsibilities remain review items. |
| Server-only processing | Not provable from client code or API schemas | Hosting locations, subprocessors, logs, advertising/analytics practices, security at rest, incident procedures, lawful bases and retention explicitly remain unconfirmed. |

`docs/openapi.json` and `API_REFERENCE.md` were inspected. No Terms, Privacy or
legal-document delivery endpoint was found. The implementation therefore uses
bundled local documents; it adds no guessed API requests or networking service.

General drafting references consulted, without treating them as a determination
of the laws applicable to Travibe:

- [FTC guidance on marketing mobile apps accurately](https://search.ftc.gov/business-guidance/resources/marketing-your-mobile-app-get-it-right-start).
- [FTC mobile privacy disclosures report](https://www.ftc.gov/sites/default/files/documents/reports/mobile-privacy-disclosures-building-trust-through-transparency-federal-trade-commission-staff-report/130201mobileprivacyreport.pdf).

The wording is original draft copy based on the inspected features. It does not
copy Instagram terms or assert that a particular regulator's rules apply.

## Presentation, localization and navigation

The existing `TermsOfServiceScreen` and `PrivacyPolicyScreen` classes are retained.
They select typed local content and share `LegalTextScreen`. All document text,
section IDs, language variants and release metadata live separately in
`features/legal/data/`. The reader uses the existing glass BackButtonWidget,
black background, Plus Jakarta Sans, white section headings, muted body text,
orange related-document links, selectable text and a single vertical list.

ScreenUtil initialization is unchanged. AppSizes provides adaptive values while
system text scaling remains enabled. The header grows/wraps rather than clipping;
content is constrained to 720px on larger displays. SafeArea and directional
layout apply to both languages. Arabic includes all corresponding sections,
right-to-left layout and a mirrored existing back arrow. Language comes from the
existing MaterialApp locale; there is no second localization/preference service.

Settings already pushed the two existing screen classes from Help & Legal.
**`settings_screen.dart` was not modified**: no row, section, icon, divider,
spacing or typography changes were necessary. Tests exercise both existing rows
and return navigation using a mocked current user, without settings mutations.

The Sign Up legal labels are now accessible TextButtons with at least 44px
height, wrapping within the existing checkbox row. Opening a document unfocuses
the keyboard, preserves form/controller/checkbox state, and prevents repeated
link pushes. Only the checkbox invokes its existing consent callback. Opening,
scrolling, copying or returning from a document never accepts it.

The existing route constants `/settings/terms` and `/settings/privacy` are now
registered as public GoRouter pages. Navigator links from Settings and Sign Up
remain local. No authentication, startup redirect or onboarding logic was changed.
Related-document links also stay local and prevent duplicate rapid pushes.

## Legal facts requiring confirmation

Before approving either language, confirm at least:

1. The operator/controller's actual legal identity, address, contact email and
   legal/privacy request channels. Travibe must not be treated as a registered
   entity merely because it is the product name.
2. Markets served, applicable law, dispute process, minimum age and any guardian
   requirements or handling of children's data.
3. Operational content licence, third-party permissions, intellectual-property
   holders, community/moderation standards, restrictions, notices and appeals.
4. Termination procedures, lawful warranty/liability wording and mandatory rights.
5. Complete data inventory/purposes/lawful bases; hosting, storage and notification
   providers; advertising/analytics/sale/business-transfer practices, if any.
6. Location processing/visibility, diagnostic/network logs, security safeguards,
   incident handling and processing/storage countries or transfer arrangements.
7. Purpose-based retention and deletion schedules, including media, messages,
   reports, device tokens, logs, backups and legal holds. Validate actual deletion
   operations against the API description; do not promise immediate erasure of
   copies outside the service.
8. Applicable privacy rights, identity checks, response processes/deadlines,
   regulator/representative details where required and support escalation.
9. Any travel/booking relationships and associated terms/data flows before those
   services are enabled.
10. Approved English/Arabic equivalence, effective/update dates, update notices
    and when renewed agreement is needed. No language-precedence clause is assumed.

Do not simply hide the draft warning or remove brackets without confirming and
approving the underlying facts. Both the version metadata and translated visible
labels must be updated together when an approved release is prepared.

## Consent versioning limitation

The existing registration contract remains `terms_accepted` and the account
resource includes `terms_accepted_at`. No document-version acceptance field or
legal update/renewal endpoint is documented. Reading these pages does not add one.
The implementation does not claim that the backend records which version was
accepted, records a separate privacy-processing consent, or supplies an immutable
legal audit trail. Agree a supported backend contract before adding such behavior.
The existing registration validation and payload are unchanged.

## Public hosting requirements

Preferred destinations, stored only as metadata today:

- `https://travibeapp.com/terms`
- `https://travibeapp.com/privacy`

Their existence/content was not assumed or verified. No request to them is made
by these screens. For deployment, the web owner should:

1. Publish only the legally approved copy and metadata; keep a reviewable archive
   of prior versions and the approval/effective-date history.
2. Serve accessible HTTPS pages without sign-in or documentation Basic Auth, with
   real legal content rather than a homepage redirect. Verify responses, links
   and mobile screen-reader behavior before advertising the URLs in app stores.
3. Agree the English/Arabic language-selection and canonical-URL strategy. Keep
   app and web versions synchronized and check any web-specific processing or
   cookie disclosures separately.
4. Confirm contact channels, request handling and update-notification procedures
   actually operate before describing them as available.
5. If a legal content API is later supplied, verify its real authentication,
   language, version, publication status, dates, response envelope, caching and
   error contracts before wiring a repository to it. Do not infer endpoint names
   from the planned public web URLs.

No website, API contract, app-store metadata or production legal policy was
published or changed by this task.

## Verification — 15 November 2026

- **30 new legal tests passed**, including bilingual section coverage, visible
  draft metadata/placeholders, preferred URL metadata, 320/375/393/430px layouts
  at 2× text, 2.5× landscape text, heading semantics, Arabic direction/back arrow,
  existing Settings rows, unauthenticated GoRouter entry, related-document Back,
  Sign Up links, preserved form/consent and unchanged registration validation.
- **118 focused legal/authentication/Settings/account tests passed**.
- **Full Flutter suite: 2,302 passed, 0 failed, 1 existing intentional opt-in skip**,
  completed in 4m20s. No live test accounts or backend writes were used.
- Targeted analysis: **no issues**. Full analysis: **0 errors, 0 warnings, 1 existing
  informational lint** at `home/widgets/custom_bottom_nav.dart:10`
  (`use_key_in_widget_constructors`). No diagnostics were suppressed.
- iOS Simulator Debug build: **succeeded**, Xcode 164.2s,
  `flutter build ios --simulator --debug --no-pub`.
- English and Arabic widget frames were captured and visually inspected at
  390×844. Bundled Plus Jakarta Sans was loaded; Arabic preview used a host system
  Arabic fallback font. Production uses the existing OS font fallback. Preview
  paths: `/private/tmp/travibe-legal-en.png` and
  `/private/tmp/travibe-legal-ar.png`. This was widget rendering, not a claim of
  manually navigating a running Simulator or testing production registration.
- Figma metadata and screenshot/design context for Settings node `2470:40438`
  were inspected. No dedicated legal-reader frame was found in the inspected
  metadata. Existing Settings was preserved and the legal layout follows the
  supplied written requirements rather than an invented legal frame.
- Local Markdown export succeeded. No new dependency, Firebase/SwiftPM setting,
  Bundle ID, API/authentication contract or unrelated feature was changed.

Commands run:

```sh
dart format <changed Dart files>
flutter analyze --no-pub <legal/profile reader/auth link/routing/test paths>
flutter analyze --no-pub
flutter test --no-pub test/features/legal/legal_documents_test.dart --dart-define=LEGAL_SCREENSHOTS=true --reporter expanded
flutter test --no-pub test/features/legal test/features/auth test/features/profile/settings_privacy_test.dart test/features/profile/settings_loading_test.dart test/features/profile/account_deletion_test.dart --reporter expanded
flutter test --no-pub --reporter expanded
flutter build ios --simulator --debug --no-pub
dart tool/export_legal_documents.dart
```

Temporary logs: `/private/tmp/travibe-legal-{tests-final2,regressions,full-suite,
targeted-final,full-analysis,ios-build}.log`. Temporary captures/logs may not
survive a workspace restart. The first legal test run exposed only a test-helper
issue: Flutter's English `pageBack` lookup did not match the Arabic tooltip.
The test now taps the actual localized Back component; production Back behavior
was not weakened or replaced.

## Files changed

Application:
- `lib/features/legal/data/legal_document.dart` (new typed model/metadata).
- `lib/features/legal/data/legal_content_en.dart` (new English drafts).
- `lib/features/legal/data/legal_content_ar.dart` (new Arabic drafts).
- `lib/features/legal/data/legal_documents.dart` (new local selector).
- `lib/features/profile/widgets/legal_text_screen.dart`.
- `lib/features/profile/screens/terms_of_service_screen.dart`.
- `lib/features/profile/screens/privacy_policy_screen.dart`.
- `lib/features/auth/widgets/terms_privacy_checkbox.dart`.
- `lib/core/routing/router_generator.dart`.

Tests/review artifacts:
- `test/features/legal/legal_documents_test.dart` (new).
- `tool/export_legal_documents.dart` (new local-only exporter).
- `docs/legal/drafts/{terms,privacy}.{en,ar}.md` (four generated review copies).
- `docs/LEGAL_DOCUMENTS.md` (this report).

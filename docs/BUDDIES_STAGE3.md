# Buddies Stage 3 — Filters

Backend integration follow-up (2026-10-29): current profile location, device/Photon reverse geocoding, visibility, explicit page-based search, recent destination persistence, localized countries and floating Cupertino loaders are documented in [BUDDIES_BACKEND_INTEGRATION.md](BUDDIES_BACKEND_INTEGRATION.md). This supersedes earlier exclusions for those flows; the stage history below is retained.

Completed 2026-10-27 using the existing Stage 2 listing and filter infrastructure.
No listing rebuild, new discovery endpoint, dependencies, traveler fixtures in
production, or changes to authentication, Follow/Block, Root, Liquid Glass navbar
or VS Code configuration were introduced.

## Behavior

Both listing Filters buttons open a separate draft initialized from that
listing's applied filters. All five categories support multiple selections.
Gender uses Male/Female checkboxes; nationality uses the installed country picker
and removable country chips. Languages, interests and travel styles use selectable
catalog chips. Longer groups have independent Show More/Show Less controls, and
hidden selections remain selected. Discovery does not inherit profile setup's
selection-count limits.

Reset clears only the draft. Back/system Back discards changes. Apply returns
immutable selections to the originating listing, resets its pagination and
requests the filtered first page. Reopening Filters restores those applied
selections. Filters remain independent per listing Cubit, live for that listing
route, and are cleared on account/session changes; no disk persistence was added.
Stage 2 generation/session guards reject stale successes and failures, including
responses from pending pagination when filters change. Existing loading, empty,
error/retry, safe continuation links and block filtering remain in use.

Catalogs load independently with accessible loading labels, empty states and
retryable errors. New choices are possible only from returned active options.
Previously applied slugs absent from a refreshed/unavailable catalog remain
visible as removable Selected chips and are preserved on Apply until removed or
Reset. The actual slug is shown when no authoritative label is available; no
label or replacement value is invented. This supersedes Stage 2's historical
behavior of silently intersecting applied selections with a refreshed catalog.
Backend validation errors remain visible through the listing's existing error UI.

The dark filter screen retains its circular Back button, centered title,
orange selection styling, app typography and fixed safe-area Reset/Apply footer.
Title and nationality chip styles explicitly prevent inherited strikethrough;
buttons preserve the app font. Body side safe areas and wrapped nationality chips
support narrow screens and enlarged text. The existing bundled Buddies Back SVG
is reused.

## Query and catalog sources

Both GET /api/v1/buddies/in-your-city and
GET /api/v1/buddies/with-same-interests send only selected values:

| Parameter | Source | Remaining backend confirmation |
| --- | --- | --- |
| gender[] | User-verified male / female values | None for the specified values |
| nationality[] | Existing country_picker country codes/names | Live acceptance of the picker's supported territories/codes |
| languages[] | ProfileSetupRepo → GET reference/languages; returned slugs | Live catalog availability and Buddies acceptance of those slugs |
| interests[] | ProfileSetupRepo → GET reference/interests; returned slugs | Live catalog availability and Buddies acceptance of those slugs |
| travel_styles[] | ProfileSetupRepo → GET reference/travel-styles; returned slugs | Live catalog availability and Buddies acceptance of those slugs |

The exact [] suffixes are preserved. Empty categories are omitted. Display labels
are never converted into slugs, and no Figma sample choices or hardcoded profile
option mappings are used. Existing ProfileSetupRepo/reference parsing was reused
without changing profile setup. No live authenticated backend calls were made;
backend-specific country restrictions and catalog equivalence remain integration
checks rather than claimed verification.

## Design access and visual verification

AGENTS.md, both prior stage reports and docs/FIGMA_REFERENCE.md were read. There
are no saved Buddies Figma screenshots under docs/figma; only Stories references
exist there. The required figma-design-to-code skill was read. A read-only
metadata request for the previously identified Filters frame 2472:42175 returned
the Figma Starter-plan tool-call limit. No further Figma calls or speculative
frame IDs/assets were used.

The existing documented layout and the user's explicit UI requirements were
retained. Exact Filters frame comparison is blocked until Figma access or an
exported screenshot is available. A temporary app-font render with test-only
catalog fixtures was inspected at both scroll positions:
- /private/tmp/travibe-stage3-top.png
- /private/tmp/travibe-stage3-bottom.png

This verifies typography, controls, chip wrapping and fixed footer presentation,
not pixel-exact Figma equivalence or native-device behavior. No reference
screenshot is embedded into the application.

## Files changed

- lib/features/buddies/screens/buddies_filters_screen.dart — catalog states,
  explicit unavailable selections, selection preservation, typography/safe areas.
- lib/features/buddies/screens/buddies_listing_screen.dart — optional catalog
  repository injection passed to the existing Filters route; listing behavior
  and production repository defaults are retained.
- test/features/buddies/buddies_filters_test.dart — dedicated Stage 3 regressions.
- docs/BUDDIES_STAGE3.md — this report.

## Verification

Formatting and targeted analysis were run. The focused regression command covers
all Buddies stages plus existing navbar, Follow/Block and profile-catalog tests:

```sh
dart format lib/features/buddies/screens/buddies_filters_screen.dart lib/features/buddies/screens/buddies_listing_screen.dart test/features/buddies/buddies_filters_test.dart
flutter analyze --no-pub lib/features/buddies test/features/buddies
flutter test --no-pub test/features/buddies test/core/widgets/liquid_glass_bottom_nav_test.dart test/features/block/block_cubit_test.dart test/features/follow/follow_cubit_test.dart test/features/profilesetup/profile_setup_test.dart --reporter expanded
```

Stage 3 coverage includes exact multi-value query serialization, multi-select in
all groups, country picker/chip removal, draft versus applied state, Reset/Apply,
Back without Apply, reopening persistence, independent listing filters, pagination
reset, stale pagination success/error protection, catalog loading/empty/error and
retry, unavailable selection preservation/removal, expansion retaining hidden
choices, selection counts beyond profile limits, fixed footer and 320px/2x text.

Final results: 123 focused tests passed, including 15 new Stage 3 tests;
targeted Flutter analysis reported no issues and the three changed Dart files
were formatted. One additional temporary visual-capture test passed; both
app-font images were inspected. Native iOS/Android country-picker, safe-area and
accessibility verification remain manual checks along with the live backend
confirmation listed above.

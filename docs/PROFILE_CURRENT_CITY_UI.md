# Current City picker and Edit Profile saving

Updated 2026-10-29. Applies to the shared Current City bottom sheet used by both
Profile Setup and Edit Profile. The original dark-picker correction is recorded
below; the later Edit Profile save/inline-clear follow-up is documented separately.

## Cause

`pickCurrentCity` used a plain Material `TextField` with only `hintText` configured.
The app's existing `darkTheme.inputDecorationTheme` declares `filled: true` and
`fillColor: 0xFFFFFFFF`, so the field inherited a white background even in dark mode.
It also inherited selection/focus accents from Material defaults: the app's
`ThemeData.primaryColor` does not alone replace Material 3 `ColorScheme.primary`.
There was no separate light Theme or SearchBar/SearchAnchor implementation.

Other Profile fields override that global decoration. The shared city picker now
does the same explicitly, without changing the global theme or unrelated screens.

## Styling

All new colors use existing `DarkColors` tokens:

- Charcoal input fill: `darkgreyColor` (0xFF1C1C1C).
- Text and Current City heading: `whiteColor`.
- Placeholder, character counter, region/country labels, city icons and OSM
  attribution: `greyColor`.
- Cursor, selection handles, retry accents and compact loading: `primaryColor`
  (0xFFE45C10). Selection highlight uses the primary token at 30% opacity.
- Bottom sheet: `backgroundColor`, with rounded 24px top corners and clipping.
- Input: existing Profile-style 28px radius, 20px horizontal padding, dark fill
  in idle/focused/typing states and no light/purple focus outline.

The field uses scoped `TextSelectionTheme` for Material selection. iOS handles
read `CupertinoTheme.selectionHandleColor` independently, so a small field-scoped
CupertinoTheme override supplies the same orange. These scopes affect only the
Current City input, rather than changing application-wide themes.

The existing shared autocomplete results widget has an optional
`currentCityStyle` presentation flag, enabled only by Current City. In that mode:

- The panel is dark charcoal with no visible outline.
- Idle state returns no blank Material container.
- Empty/error states retain their readable messages and retry actions.
- Verified city names are white; the existing label's region/country remainder
  appears as a muted subtitle. A country-name fallback comes from the existing
  structured selection, without inferring country codes from display text.
- City icons are consistent and loading uses a compact orange Cupertino indicator.
- OpenStreetMap attribution remains visible and readable with suggestions.

The default mode retains Buddies destination-search presentation. No Buddies
screen, search query, pagination or loading overlay was modified.

## Layout and behavior preserved

Both callers still invoke the same `pickCurrentCity` function. Modal navigation,
autofocus, 120-character limit, selection callbacks and returned CitySelection are
unchanged by the original styling correction. The Edit Profile save timing follow-up
is described above. The sheet retains its existing list, 65% preferred height and 20px
horizontal padding. Bottom SafeArea protection supplements the existing modal
SafeArea; keyboard avoidance continues to use `MediaQuery.viewInsets.bottom`.
The list remains scrollable when the keyboard reduces the available height.

Photon endpoint/query parameters, User-Agent, debounce, rate limiting, parsing,
stale-response/session handling, city resolution, profile persistence and all
location request formats are untouched. Tests exercise both real UI entry points
with mocked Photon/profile responses and still observe exactly:

```text
PUT /profile/location
{"location":"Cairo, EG"}
```

No visibility settings write is introduced. This styling task does not resolve or
change the separately documented backend location-contract discrepancy.

## Edit Profile inline clear and Save Changes follow-up

Implemented 2026-10-29. Edit Profile now stages **both** city selection and city
clearing until Save Changes. Profile Setup retains its existing immediate location
save on selection. The shared Photon picker, dark styling and API parameters are
unchanged.

### Root causes found

The prior Edit Profile city callback immediately called `saveCurrentLocation`,
while `ProfileDraft` and `_isDirty` tracked only ordinary profile fields and the
avatar preview. Selecting a city therefore persisted it already and did not leave
anything for Save Changes to save. A disabled button after that city-only action
was consistent with the old implementation, rather than a broken PATCH handler.
No screenshot was attached in this session; this diagnosis comes from the code
and controlled widget tests, not assumptions about unseen image contents.

Additional issues addressed:

- Button enablement checked dirtiness but did not reflect client validation until
  submission. Invalid edits now show field validation and keep Save disabled.
- A bottom-positioned error snackbar could cover the enabled Save button and block
  immediate retry. Failure feedback now floats above the fixed save control.
- Ordinary profile refreshes did not publish changed identity fields to the shared
  current-user cache. They now do so, without letting an older settings response
  overwrite newer profile fields.
- The location helper silently returned when the owning profile was unavailable.
  It now reports an actionable failure rather than acknowledging an unsaved city.

### Inline X and layout

The separate orange Clear current city TextButton has been removed. The existing
selector-field component now accepts an independent clear callback. Current City
shows a white54 X immediately before its dropdown chevron whenever its displayed
value is nonempty, using the same close icon as Nationality. Clear and Choose
current city have separate accessible tooltips/tap targets. Tapping X clears only
the draft and never opens the picker. Field/chevron taps open the existing picker.

The city controls have 44px touch targets inside the original **52px field height**.
The field retains its original width, rounded styling and normal 20px following
form spacing. Removing the standalone button removes its extra vertical space;
clearing/showing the inline X does not change the field height.

### Draft, validation and synchronization

`ProfileDraft` stores the initial canonical location separately from ordinary
PATCH changes, plus a validated pending CitySelection or pending null clear.
Its dirty state includes location changes. Returning to the saved city removes
that dirty state. Opening/cancelling the picker sends no request and changes no
value; discarding the form cancels pending selection/clearing without a write.

The screen initializes from the owning Cubit's latest matching canonical profile,
rather than an older navigation snapshot. Existing name, username, nationality,
Current City and bio populate normally; a supplied legacy nationality display label
is shown without guessing a country code. Later reads do not overwrite active
text-entry controllers.

Save Changes remains disabled when there is no pending change, a changed ordinary
field is invalid, another editor action/save is busy, or the account session has
changed. Valid name/username/nationality/bio edits and pending city changes enable
it. An untouched missing field does not block a valid city-only operation. Reverting
a field to its initial value removes its pending update. Existing clearing-required-
profile-details confirmation is preserved.

While saving, one compact primary-orange CupertinoActivityIndicator appears inside
the existing Save button. The old simultaneous save LinearProgressIndicator and
white circular spinner are removed. Photo/catalog selection progress retains its
existing behavior. Form interactions, duplicate Save and Back are guarded during
submission; failed saves restore a usable button and preserve pending values.

### Separate requests and partial success

The save sequence is deliberately not represented as an atomic backend transaction:

1. Validate changed ordinary fields before uploads or writes.
2. Run the existing avatar flow if requested; PATCH `/profile` with changed,
   supported ordinary fields/verified avatar ID only.
3. Read GET `/profile` for canonical ordinary profile data and synchronize the own
   ProfileCubit/current-user cache.
4. If a location change remains, PUT `/profile/location` with the existing
   `{"location":"Paris, FR"}` payload, or DELETE `/profile/location` for a clear.
   DELETE 204 still has no JSON resource to parse.
5. Acknowledge successful operations individually and finish only after the
   requested writes are complete. Newer draft edits remain pending.

Location, city and country-code parameters never enter the ordinary PATCH map.
The previously documented location-schema discrepancy is unresolved; no API
contract change or unauthorized live mutation was used to resolve it.

If PATCH succeeds and the location request fails, ordinary changes stay committed
and their dirty flags are cleared, while the city remains pending with a field/
snackbar error. Explicit retry sends only the pending location operation. An avatar
already attached by that PATCH is not uploaded or patched again. If ordinary PATCH
fails, location is not attempted and both operations remain pending. Because the
ordering always puts ordinary PATCH before location, there is no later ordinary
write to fail after a committed location in the same save attempt.

A failed canonical GET does not cause a committed PATCH to be replayed. With a city
still pending, the editor reports the reload issue and explicit retry reloads then
saves the city. Ordinary-only saves retain the existing Profile refresh-error/retry
behavior without repeating the successful write. Successful dedicated location
responses update canonical labels immediately; clearing updates them to null and
preserves Buddies visibility. Existing Buddies location invalidation remains active.

Session/id/generation checks reject old-account responses. A confirmed newer
profile read is merged into current-user state even while a settings write is
pending; the eventual settings response applies its settings fields only and
cannot restore an older name/bio/username.

### Follow-up files

- `lib/features/profile/data/profile_update.dart`
- `lib/features/profile/cubit/edit_profile_cubit.dart`
- `lib/features/profile/cubit/profile_cubit.dart`
- `lib/features/profile/cubit/current_user_cubit.dart`
- `lib/features/profile/screens/edit_profile_screen.dart`
- `test/features/profile/edit_profile_city_save_test.dart` (new)
- `test/features/profile/profile_avatar_test.dart` (pump after validity changes)
- `test/core/places/current_city_picker_test.dart` (Edit Profile saves explicitly;
  Profile Setup continues to save on selection)
- `docs/PROFILE_CURRENT_CITY_UI.md`, `docs/PROFILE_STAGE2.md`

No Photon/provider, location repository payload/parser, Profile Setup implementation,
Buddies/Home loading implementation, API definition, dependency or VS Code changes
were made for this follow-up.

### Follow-up verification

**30 new focused tests pass**, including inline X position/visibility and 52px field
height, separate tap targets, deferred selection/clear/cancel, ordinary field
validation/enablement, exact PATCH/PUT/DELETE separation, canonical values on
reopening, snapshot freshness, loading/duplicate protection, partial failures,
committed-write/upload reuse, old-session/newer-draft protection and delayed
Settings responses.

**601 regression tests passed, 0 failed**:

```sh
flutter test --no-pub test/features/profile test/features/profilesetup test/features/buddies test/core/places test/features/home test/core/pagination test/core/widgets/liquid_glass_bottom_nav_test.dart test/core/widgets/travibe_loading_indicator_test.dart
```

Formatting completed on the eight changed Dart files. Targeted analysis of those
files reports **No issues found**. Existing avatar, Profile Setup, Photon, Buddies,
Allow Location, Home loader/navigation and cursor-pagination tests remain passing.
All HTTP calls are mocked. No live profile was modified.

Manual iOS Simulator checks remain pending: verify X/chevron touch targets, pending
clear/discard, name/username/nationality/bio edits, city-only Save, error retry,
compact button loader and reopening with saved data using an authorized test
account. The earlier keyboard/dark-picker manual checks below also remain useful.

## Original picker-styling files

- `lib/core/places/current_city_picker.dart`
- `lib/core/places/city_autocomplete_results.dart`
- `test/core/places/current_city_picker_test.dart` (new)
- `docs/PROFILE_CURRENT_CITY_UI.md` (new)
- `docs/PROFILE_STAGE2.md` (follow-up reference)

For the original picker-styling correction, no API/provider/Cubit/model, caller
screen, global theme, dependency, Home loader or VS Code files changed. The later
Edit Profile follow-up has its own file list above.

## Original picker-styling verification

- Formatting completed; final check reports zero changes.
- Targeted analysis of the two UI widgets and new test file: **No issues found**.
- **11 new widget tests passed**, covering explicit/resolved dark decoration,
  cursor and Android/iOS handle themes, white text, muted hints, no initial outlined
  box, loading/error/retry/empty states, OSM attribution, debounce and selection.
- Keyboard tests cover 390×844 and 320×568 viewports, up to 2.5× text scaling and
  keyboard insets up to 320px, with scroll-to-select and no layout exceptions.
- Profile Setup and Edit Profile entry tests share the same styling and verify the
  existing location PUT payload and no visibility mutation.
- **426 relevant regression tests passed, 0 failed**:

```sh
flutter test --no-pub test/core/places test/features/buddies test/features/profilesetup test/features/profile
```

These include existing Photon/provider/session tests, Buddies destination search
and filters, profile location/Allow Location, setup, editing and account actions.
All network responses are mocked; this visual correction needed no live requests.

## Manual verification

No manual iOS Simulator interaction or native screenshot verification was performed
for this styling task. On the Simulator, open Current City from both Profile Setup
and Edit Profile, type/select a city, select text to inspect native handles, and
check keyboard scrolling/dismissal, sheet corners and absence of white flashes.
Also check larger Accessibility text sizes and Dark appearance.

Figma access limitations remain as recorded in `FIGMA_REFERENCE.md`. Existing
Profile field geometry and the requested token-based styling were followed;
no fresh pixel-perfect Figma verification is claimed.

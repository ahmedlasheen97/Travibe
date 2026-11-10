# Profile and Stories test diagnostics — 2026-11-09

## Scope

The actual directories are `test/features/profile/` and
`test/features/stories/`, containing 36 test entry files plus helpers. There are
no `test/profile/` or `test/stories/` directories. The commands below use the
actual paths. Git status/diff could not run because this workspace has no `.git`
metadata. No files were reset, discarded, deleted, skipped or committed.

## Reproduced failures and fixes

| File | Diagnostic / root cause | Fix |
| --- | --- | --- |
| `test/features/profile/edit_profile_city_save_test.dart:105` | `invalid_override`: `Uploads.upload` lacks optional `onProgress` from `MediaUploadService.upload`. | Accept the same optional typed callback. |
| `test/features/profile/profile_avatar_test.dart:82` | Same mismatch in `_Upload.upload`. | Match the service signature, preserving fixture behavior and assertions. |
| `test/features/stories/story_upload_feedback_test.dart:24` | Same mismatch in `_Uploads.upload`. | Match the service signature, preserving pending completion and stage callbacks. |
| `test/features/stories/story_other_viewer_test.dart` | Three pre-existing expectations refer to superseded composer UI. | Test current SVG, disabled send control and native keyboard dismissal; retain meaningful draft, playback and story-change checks. |
| `lib/features/profile/widgets/discard_changes_dialog_widget.dart:2` | Unused `DarkColors` import. | Remove only the unused import. |

The override mismatch is attributable to the optional upload progress callback
introduced for Chat. Existing callers remain compatible, but subclasses must
accept every named argument supported by their parent. Production upload code
is correct and unchanged in this fix.

Initial Profile run: **184 passed, 3 loading failures**. The invalid overrides
prevented two files from compiling; the resident compiler also exited unexpectedly
while loading `avatar_first_save_test.dart`. This was a cascading compilation
failure, not a failed first-save assertion. Initial Stories run: **266 passed,
5 failures**: one invalid override, a compiler-exit loading failure attributed to
`story_owner_controls_test.dart`, and the following three assertion failures.
Both cascading load failures disappear after fixing the fake signatures.

### Story Viewer assertions

- `other-user row has composer and independent heart/options; owner controls unchanged`
  failed at line 147: expected one SVG, found zero. It searched for
  `happyemoji 20.svg`, which does not exist. Production uses the available native
  20×20 `happyemoji.svg`. The test still verifies dimensions, original colors,
  independent Like/options controls and absence of owner controls.
- `typing pauses progress, Done resumes and preserves the current draft without sending`
  failed at line 178: expected no `send.svg`, found one. Production renders an
  explicitly disabled “Send message (coming soon)” control. The test now verifies
  its null `onPressed`, explanatory tooltip, unchanged text and paused progress,
  followed by Done preserving text and resuming playback. No reply sending is
  implemented or simulated.
- `dismiss keyboard works; story change clears the ephemeral draft` failed at
  line 193: `tap()` found no “Dismiss keyboard” control. Its replacement test
  simulates the native keyboard inset opening and closing, verifies focus release,
  draft preservation and playback resumption, then advances to the next story
  and verifies draft clearing. It does not rely on a removed button.

These same three failures were recorded before Chat interactions in
`docs/STORIES_EDITOR_AUDIT.md` and `docs/FIREBASE_MESSAGING_AUDIT.md`.
No production Story Viewer/composer code or assets were changed.

The Profile duplicate-save test also now taps the disabled button's physical
location after verifying `onPressed == null`, retaining its assertion that only
one upload occurs. This avoids a misleading finder hit-test warning for a widget
that intentionally cannot receive taps; no warning setting is suppressed.

## Verification

| Run | Result |
| --- | --- |
| `dart format` on the five changed Dart files | No additional formatting changes |
| `flutter analyze` before | 3 errors, 1 warning, 2 informational findings |
| `flutter analyze` after | 0 errors, 0 warnings, 2 existing informational Home lints |
| Targeted analysis of both entire test directories and the import cleanup | No issues found |
| `flutter test test/features/profile/ --reporter expanded` | **242 passed** |
| `flutter test test/features/stories/ --reporter expanded` | **271 passed** |
| Isolated reply-composer tests | **15 passed** |
| `flutter test --no-pub test/features/chats test/core/media --reporter expanded` | **235 passed** |
| `flutter test --reporter expanded` | **1750 passed, 2 failed, 1 existing opt-in skip** |
| Isolated `test/features/search/search_screen_test.dart` | **7 passed, same 2 failures** |

The full default unit/widget suite was executed, not a partial batch. Its existing
skip is `test/live/chats_two_account_e2e_test.dart` (`skip: !enabled`), which requires
authorized live accounts and write permission. No new skips were added and no
live server records were mutated. Native integration tests and an iOS rebuild
were not necessary for these test compatibility fixes and unused-import cleanup.

### Remaining findings outside this task

The two full-suite failures are already documented in
`docs/FIREBASE_MESSAGING_AUDIT.md` and `docs/OTHER_USER_PROFILE.md`:

1. `test/features/search/search_screen_test.dart:200` —
   `small screen handles long names, missing avatars and keyboard`:
   `Expected: null; Actual: FlutterError: A RenderFlex overflowed by 13 pixels on the right.`
2. `test/features/search/search_screen_test.dart:218` —
   `Home search SVG keeps its original colors and tap action`:
   `Expected: 20; Actual: 17.0`.

Both reproduce independently. Search/Home implementation and those assertions
were left unchanged, as unrelated modules must not be modified solely to pass
the full suite.

Full analysis still reports informational `use_key_in_widget_constructors` at
`lib/features/home/widgets/custom_bottom_nav.dart:10` and
`unnecessary_underscores` at
`lib/features/home/widgets/trending_destinations_section.dart:54`. They were
present before this task. Flutter analyze therefore still exits nonzero for
these infos; the targeted run exits successfully. No analyzer exclusions or
suppression comments were introduced.

## Behavioral impact

There are no changes to Chat, Profile, Stories, Notifications, authentication or
Firebase runtime behavior. Four test files were updated and one unused import
removed. Chat integration documentation was deliberately left unchanged because
the integration itself was not modified. Dependencies, SwiftPM, Bundle ID,
configuration and existing uncommitted work were preserved.

Diagnostic logs for this run are under `/private/tmp/` with prefixes
`travibe-profile-`, `travibe-stories-`, `travibe-profile-stories-` and
`travibe-known-search-failures.log`; these are temporary local verification
artifacts, not committed application data.

## Search follow-up

The two Search failures listed above were investigated and fixed in the next
authorized task. See `docs/SEARCH_TEST_FIXES.md` for root causes, responsive
layout/icon corrections and final full-suite results. The counts above describe
the earlier Profile/Stories pass and are retained as historical verification.

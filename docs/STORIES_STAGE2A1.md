# Stories Stage 2A.1 — camera and confirmed UI fixes

Implemented 2026-10-20 after reading STORIES_STAGE1.md, STORIES_STAGE2A.md,
the existing local picker/editor flow and the installed image_picker sources.
No backend, upload, Story publication, dependency or unrelated feature changes.

## Camera implementation

- Take a Photo now calls StoryPickerCubit.capture → StoryPhotoRepo.capture →
  image_picker.pickImage with ImageSource.camera and requestFullMetadata:false.
  The single-image API captures exactly one photo; no video, microphone,
  multi-selection, compression or resizing options are used.
- Camera and gallery delegate to the same private selection method, decoded-image
  validator and immutable StoryEditorDraft creation. Original bytes are retained;
  the existing StoryEntry opens the existing StoryEditorScreen directly after
  the sheet returns the validated draft. No intermediate screen was introduced.
- Cancellation returns no draft and leaves the sheet open. Errors preserve the
  sheet and allow camera retry or switching to gallery. Denied/restricted camera
  access, Android no_available_camera, MissingPluginException, unsupported
  platforms and other PlatformException failures have safe user-facing messages.
  Raw native messages, paths or exception details are not logged.
- Camera/gallery/recovery share one Cubit busy lock. Repeated or competing taps
  cannot launch another picker. The active action displays a progress indicator;
  both actions are disabled until completion. Disposed Cubits reject late drafts,
  and the existing sheet/entry mounted checks prevent late navigation.
- The existing Story-owned pending-selection marker is also set for capture.
  Existing Android lost-data recovery accepts one image only, uses the same
  validator, and does not consume another feature's unowned plugin cache.
- Gallery still uses the scoped Android Photo Picker opt-in with restoration.
  Camera never modifies that gallery-specific plugin setting.

## Native configuration evidence

Installed versions inspected: image_picker 1.2.3, image_picker_android
0.8.13+22 and image_picker_ios 0.8.13+7. No package versions changed.

- Added NSCameraUsageDescription to ios/Runner/Info.plist. The existing photo
  library usage description remains. No microphone description was added.
- Android requires no application-manifest change for this external-camera flow,
  according to the locked plugin README and implementation. It uses
  ACTION_IMAGE_CAPTURE and the plugin's existing FileProvider; the current
  singleTop activity configuration remains. No CAMERA, storage or microphone
  permission was added.
- The iOS implementation checks camera authorization. Denied/restricted access
  returns camera_access_denied/camera_access_restricted. If no camera is available
  (including the iOS simulator), this plugin shows its native “Camera not
  available” alert and returns null. Dart treats that null safely as cancellation;
  it cannot distinguish it from cancellation or supply an additional exact
  hardware-unavailability message without a different native contract.
- Android reports no_available_camera when the external activity cannot launch.
  Camera-specific permission failures are also mapped without exposing details.
- A full iOS rebuild/reinstall/relaunch is required to validate the plist change;
  hot reload is insufficient. Existing plugin registration is reused.

## Confirmed styling changes

- Post a Story uses SvgPicture.asset for the existing, nonempty camera.svg and
  gallery.svg assets under assets/images/interactions/. Both SVG roots are 24px
  square and are rendered at 24px. The interaction directory was already declared
  in pubspec.yaml, so no asset registration/dependency change was needed.
- Camera remains white on the enabled primary-orange button. Gallery's supplied
  SVG has its own orange fill; its runtime ColorFilter uses DarkColors.primaryColor
  to follow the requested existing Travibe orange rather than hardcoding another
  orange. Neither asset file was edited.
- Camera/gallery actions, sheet heading/error text, editor Aa/Post, and text-entry
  controls explicitly use Plus Jakarta Sans. Relevant action styles use zero
  letter spacing. Text-entry Cancel/Done and gallery use DarkColors.primaryColor.
- Post remains disabled, with its existing tooltip/disabled semantics, while its
  background now uses the full theme orange and white text. No callback was added.

## Figma limitation and preserved editor behavior

The earlier six Story reference screenshots are mentioned in STORIES_STAGE1.md
but are not attached/available in this conversation. Only earlier Flutter preview
renders are available locally; those are not treated as Figma references. Figma
MCP was already rate-limited, and no further calls were made.

Exact current Figma alignment is therefore **not claimed**. Obtain the current
Post a Story sheet and editor screenshots (with node references if available),
including canvas crop/ratio, back control, profile/audience geometry, Post button,
toolbar artwork/dimensions/spacing and status/navigation insets before changing
those design-dependent values. Existing sheet padding, radius, background and
spacing are preserved; they have not been newly verified against Figma.

The editor canvas dimensions, centered display-only BoxFit.cover, safe areas,
header/profile geometry, toolbar layout and icon shapes are unchanged. No
unverified crop mode, asset, control position or new screen was invented.

StoryCanvas, StoryTextGeometry, StoryEditorCubit and StoryEditorDraft were not
modified. Text creation/editing, normalized transforms, pinch/drag transitions,
pointer cancellation, full-box bounds, precise release-point delete testing,
render-content isolation and keyboard behavior are preserved. Text-entry changes
are style-only; autofocus, controllers, dismissal and Done behavior are unchanged.

## Files changed

- lib/features/stories/data/story_photo_repo.dart — shared camera/gallery selection.
- lib/features/stories/cubit/story_picker_cubit.dart — capture, shared busy guard,
  safe camera error mapping.
- lib/features/stories/cubit/story_picker_state.dart — active camera indication.
- lib/features/stories/widgets/post_story_sheet.dart — enabled camera, SVGs/styles.
- lib/features/stories/screens/story_editor_screen.dart — orange disabled Post/font.
- lib/features/stories/widgets/story_text_entry.dart — font and primary-color styles.
- ios/Runner/Info.plist — camera usage description only.
- test/features/stories/fixtures.dart — injectable capture results/counters.
- test/features/stories/story_photo_test.dart — capture API/validation/errors/locks.
- test/features/stories/story_widgets_test.dart — camera flow, SVG/theme/regressions.
- docs/STORIES_STAGE2A1.md — this report.

## Verification

- Targeted analysis of lib/features/stories and test/features/stories: no issues.
- plutil -lint ios/Runner/Info.plist: OK.
- Standard flutter test --no-pub for Stories and the Create Post screen tests was
  attempted but blocked before loading by denied localhost socket binding.
- The actual tests ran with the temporary no-socket frontend-server/flutter_tester
  harness: **63 passed, 0 failed** (57 Story tests including 17 new camera/UI
  cases, plus 6 existing Create Post regressions).
- Coverage includes camera capture/cancellation, shared image validation,
  permission/unavailable/plugin/platform failures and retry, shared request locks,
  late/disposed results, direct camera-to-editor navigation, gallery regression,
  SVG asset loading, theme-orange Post remaining disabled and zero HTTP client
  creation. Existing Stage 2A tests cover text entry/editing, keyboard/Back,
  one/two-finger transitions, bounds, resize, cancellation and exact delete drops.
- A separate temporary render check passed and the updated sheet/editor renders
  were inspected with app fonts/icons, including both SVGs after asset loading.
  They are not native camera/device screenshots or a Figma comparison.
- Logs, temporary runner and render captures: /private/tmp/travibe-stories2a1-*.

The known pre-existing Home SVG expectation mismatch was not modified or included
in the focused run. No all-project test-suite pass is claimed.

## Manual device checks

1. On a real iPhone and Android device, grant/deny/restrict camera access, capture
   one photo, cancel, retry and use gallery afterwards. Check the actual native
   no-camera path where possible. Tests use an injected picker, not hardware.
2. Rebuild iOS for the plist change. Confirm there is no microphone prompt and
   no unnecessary full-library permission request from camera capture.
3. Verify large camera images, orientation/EXIF, HEIC on a real iPhone, validation
   failures and returning to the same Home state without an upload/publication.
4. On Android, cause genuine process death while the camera is open. Re-enter
   Home and verify exactly-once Story-owned image recovery. Mock lost-data tests
   do not establish OS process recreation behavior.
5. Recheck keyboard/IME/back order, safe-area/toolbar placement, text scaling,
   drag/pinch transitions and precise drag-to-delete behavior on both platforms.
   Exact visual signoff remains pending the current Figma references above.

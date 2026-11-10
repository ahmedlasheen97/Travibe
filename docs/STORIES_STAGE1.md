# Stories Stage 1 — Local photo selection and editor preview

Implemented 2026-10-20. Source of truth: the six current Story Flow screenshots
attached to this Codex conversation, the approved Story inspection, and the
existing Flutter architecture. No old Figma screens were used. Live Figma node
verification remains unavailable after the inspection's MCP plan-limit response;
this implementation does not claim pixel-verified Figma tokens or prototype rules.

## Delivered behavior

- The existing orange plus on the first Home story avatar opens the dark,
  rounded "Post a Story" sheet. Its visible 20px badge is preserved with a larger
  gesture area. Other avatars and Home feed behavior are unchanged.
- The center navigation plus still opens Create Post; Root and Create Post code
  were not edited.
- "Choose from Gallery" invokes image_picker's single-image gallery API with
  requestFullMetadata: false. No video, mixed-media, multi-image, camera, resize,
  or compression API/options are used by this feature.
- Cancel leaves the Story sheet open. Picker failures stay in the sheet with
  safe feedback and retry. Missing plugins, access restrictions, invalid/empty
  image data and unreadable files are handled without exposing native details.
- Duplicate sheet openings and picker calls are guarded. Late picker results do
  not navigate after disposal.
- A successful selection is checked for image decoding, then opens the local
  Story Editor directly. The selected image fills the canvas with BoxFit.cover:
  centered, aspect-preserving, display-only cropping.
- The editor includes Back, the profile/audience presentation, orange Post,
  and the right-side Text, Mention, Sticker/Emoji, Draw and Location toolbar.
  Only Back is active. Disabled controls, tooltips and a preview-only caption
  explain the current availability. "Take a Photo" is also visibly disabled.
- There is no Story API integration, image upload, publication, composition,
  camera capture, interactive overlay editing or audience mutation.

## Local architecture and image ownership

The isolated features/stories folder contains:

- data/story_photo_repo.dart: injectable image_picker access, pending-selection
  storage and decoded-image validation. It has no API client dependency.
- data/story_editor_draft.dart: local source bytes/path/name/dimensions and an
  immutable ordered layer list. The base layer defines local ID, normalized
  center and scale for future editor work; Stage 1 creates no overlays and
  defines no backend serialization fields.
- cubit/story_picker_cubit.dart and story_picker_state.dart: busy/error state,
  duplicate-operation guard, safe error mapping and disposal protection.
- widgets/story_entry.dart: owns selection/recovery and Navigator transitions.
- widgets/post_story_sheet.dart and screens/story_editor_screen.dart: sheet and
  preview UI, reusing SheetHandle, HomeUserAvatar and existing theme/font assets.

The app reads the picker-returned file without writing or resizing it. The draft
retains an immutable in-memory snapshot of those bytes for the entire editor
session, even if the picker cache file later disappears. The 1x1 validation decode
is discarded and never replaces the source or preview bytes. Future composition
must produce a separate output. This is session-local editing, not persistent
draft storage across arbitrary process termination after editing has begun.

## Android recovery and native picker behavior

Before opening the picker, the repository persists story_photo_picker_pending.
On Android, StoryEntry checks recovery when the Home Story entry mounts, including
when Home is reached after app restart. It calls retrieveLostData only if that
Story-owned marker exists; it does not consume the shared plugin cache for other
features. Exactly one recovered image is accepted, validated and opened in the
editor. Empty results, errors, multiple files and non-image recovery results clear
the marker. Recovery failures show safe feedback on Home. Normal selection also
clears the marker after success, cancellation or failure.

The locked image_picker_android 0.8.13+22 source requires explicit Photo Picker
opt-in below Android 16. Story selection temporarily enables
ImagePickerAndroid.useAndroidPhotoPicker, then restores its previous value in a
finally block. The native implementation uses PickVisualMedia with ImageOnly;
Android selects its supported system/backported picker or platform fallback.
Android 16+ uses Photo Picker regardless of the setting. No Android manifest,
storage permission, READ_MEDIA_IMAGES or full-library permission was added.
The existing singleTop activity mode was preserved.

image_picker_android and image_picker_platform_interface were promoted from
transitive dependencies to direct dependencies so their public opt-in APIs can
be used legitimately. Resolution used flutter pub get --offline. Existing locked
versions remain image_picker 1.2.3, image_picker_android 0.8.13+22 and
image_picker_platform_interface 2.11.1; no new package version was downloaded.

## iOS configuration

Added only NSPhotoLibraryUsageDescription in ios/Runner/Info.plist. No camera or
microphone usage description was added because capture is unavailable.
requestFullMetadata: false avoids requesting full-library metadata access for
the scoped PHPicker path on iOS 14+. The project still targets iOS 13, whose
legacy system-picker permission behavior must be verified separately.

Native behavior was checked against the locked plugin's README and implementation,
not by launching a native picker on a device. The package documentation is at
https://pub.dev/packages/image_picker/versions/1.2.3 . In particular, HEIC testing
on an iOS simulator is limited; use a real iPhone for that format.

## Verification

- Targeted Dart analysis of features/stories, both touched Home files and
  test/features/stories: no issues found.
- flutter test --no-pub test/features/stories
  test/features/create_post/create_post_screen_test.dart: **31 passed, 0 failed**
  (25 Story tests and 6 Create Post regressions).
- Story coverage includes exact gallery API/options; cancellation; invalid,
  empty and unreadable files; platform errors and retry; duplicate calls; late
  completion; scoped Android picker configuration and restoration; persisted
  pending marker; owned/unowned/empty/error/multiple/video recovery; editor
  navigation; original-file preservation; retained immutable local bytes; and
  disabled tools/publication with zero HTTP client creation in the local flow.
- The actual Home avatar action is tested through Root. Existing Create Post
  tests verify the center plus still publishes and refreshes the same mounted
  feeds while retaining Home state.
- An earlier combined run also exercised all 13 home_experience_test.dart cases:
  12 passed and 1 failed on the pre-existing "zero relationship state uses SVG
  without fake story avatars and opens discovery" assertion. FollowingEmptyState
  uses Image.asset while that test expects SvgPicture. This same failure is
  recorded in PROFILE_STAGE3.md; neither that widget nor test was changed.
  The complete existing Home suite is therefore not green.
- plutil -lint ios/Runner/Info.plist: OK.
- Temporary widget-render previews were inspected at 390x844 with text/icon
  fonts loaded: /private/tmp/travibe-story-editor.png and
  /private/tmp/travibe-story-sheet.png. These are Flutter test renders, not device
  screenshots. The temporary render test passed separately.

## Remaining visual gaps and device checks

- Exact Figma dimensions, tokens and font weights remain unverified. Native
  Material icons approximate the toolbar artwork from the supplied screenshot.
- Centered BoxFit.cover follows the visible full-bleed photo presentation;
  alternate aspect-ratio crop anchoring and background repositioning were not
  established by the single editor screenshot. There is no destructive crop.
- Disabled camera/audience/tools/Post styling and the preview-only caption are
  intentional Stage 1 differences. The profile control uses the loaded account
  avatar or the existing neutral fallback, rather than the reference user's photo.
- On real iOS 14+ and Android devices, confirm a single-image-only picker,
  cancellation, permissions/scoped access, cloud-backed assets, large images,
  portrait/landscape and EXIF orientation, unavailable/restricted access and
  navigation back to the same Home state.
- Check iOS 13 legacy permissions if that deployment target remains supported;
  verify HEIC on a real iPhone and safe error feedback for undecodable formats.
- On Android, verify current and older supported OS picker/fallback behavior,
  plus genuine process death while the native picker is open. Re-enter Home and
  confirm exactly-once recovery, cancellation/error handling and no recovery of
  another feature's selection. Tests simulate the lost-data responses; they do
  not prove OS process-recreation behavior.
- Confirm safe-area/status-bar placement, larger accessibility text, toolbar
  scrolling on short screens, and screen-reader disabled-control announcements.

## Changed files

- lib/features/home/screens/home_screen.dart
- lib/features/home/widgets/home_stories.dart
- lib/features/stories/data/story_editor_draft.dart
- lib/features/stories/data/story_photo_repo.dart
- lib/features/stories/cubit/story_picker_cubit.dart
- lib/features/stories/cubit/story_picker_state.dart
- lib/features/stories/widgets/story_entry.dart
- lib/features/stories/widgets/post_story_sheet.dart
- lib/features/stories/screens/story_editor_screen.dart
- test/features/stories/fixtures.dart
- test/features/stories/story_photo_test.dart
- test/features/stories/story_widgets_test.dart
- test/features/stories/story_home_test.dart
- ios/Runner/Info.plist
- pubspec.yaml
- pubspec.lock
- docs/STORIES_STAGE1.md

Profile, Buddies, Follow, Block, Laravel and Figma were not edited. Publication
remains deferred until the missing Story request/response schemas and signed
media-upload response contract are verified.

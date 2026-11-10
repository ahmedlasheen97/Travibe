# Integration test setup

## Investigation and root cause

Verified with Flutter **3.44.9 stable**, Dart **3.12.2**, on 2026-11-05.
`integration_test` was absent from `pubspec.yaml`, `pubspec.lock`, and
`.dart_tool/package_config.json`. The installed SDK does contain
`packages/integration_test/lib/integration_test_driver.dart`, including
`integrationDriver`, `writeResponseOnFailure`, and `responseDataCallback`.
Without the SDK dependency, the package URI cannot resolve and the function
becomes undefined. This is not an SDK removal or Firebase version conflict.

This checkout initially had **no project `integration_test/`, `test_driver/`,
runner scripts, or CI configuration**. The driver supplied in the task therefore
could not be verified as an existing project file. Firebase SwiftPM downloads
under `build/ios/SourcePackages/` and `build/macos/SourcePackages/` contain their
own example integration tests and drivers; those are not Travibe test entry
points. Full analysis currently traverses these third-party examples too.

## Dependencies

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
```

`flutter pub get` succeeded. The lockfile gained only the SDK packages
`integration_test`, `flutter_driver`, `fuchsia_remote_debug_protocol`, and their
required `process`, `sync_http`, and `webdriver` dependencies. No pre-existing
package versions changed; Firebase dependencies and platform configuration were
preserved. Do not delete the lockfile to resolve an IDE import warning.

## Test layout and reporting

```text
test/                                      Unit and widget tests
  widget_test.dart                         Real signed-out MyApp startup smoke
  infrastructure/integration_report_test.dart
  infrastructure/fixtures/report_probe.dart Host exit-code probe (not a test entry)
integration_test/app_test.dart              Device/browser startup and eye toggle
integration_test/support/test_reporting.dart Browser-safe result bridge
test_driver/integration_test.dart           Host-side flutter drive adapter
test_driver/test_report.dart                Shared host result validation
```

The adapter remains supported by this installed SDK. Native `flutter test`
does not require it; web `flutter drive` uses it. Keep the host driver's
`dart:io` import outside browser test entry points.

Every integration entry point initializes
`IntegrationTestWidgetsFlutterBinding.ensureInitialized()` once, then calls
`registerTestReporting(binding)` once. The helper registers a suite teardown
that copies binding results into `reportData['testResults']`, retaining any
other report data. Flutter's binding records `success` for passes and failure
details for failures; the host callback does not receive that result map
automatically without this bridge. The helper teardown runs before the
binding finalizes the response (suite teardowns run in reverse registration
order).

The host driver keeps `writeResponseOnFailure: true`, prints each test with
✅/❌, and prints `Web e2e summary: ...`. It writes the original JSON through
`writeResponseData` **before** validating results, so failure artifacts survive.
The default artifact is `build/integration_response_data.json` (the SDK's
`testOutputsDirectory` default). Empty, missing or malformed result maps are
infrastructure failures. Any value other than `success` fails the host process,
including a contradictory outer success response containing failed test data.
The SDK also fails when the binding reports a failed test.

The smoke test follows actual 1500ms startup to Login, verifies no session and
password visibility controls. Mock SharedPreferences contains only completed
onboarding, never device credentials. Its signed-out startup branch makes no
API calls, and no login submission occurs. It imports no `test/` fixtures and
does not initialize Firebase. `main.dart` currently has no Firebase
initialization requirement; adding duplicate initialization here would not help.
Future Firebase-dependent tests need explicit test configuration/emulators,
with initialization owned by one setup path. Never use production accounts or
API endpoints in mocked tests.

The old widget smoke test still expected Flutter's counter template. It now
exercises real MyApp startup, initializes preferences, loads Plus Jakarta Sans
(avoiding Ahem metrics), sets 390 × 844 reference dimensions, and disposes its
injected router/Cubit. No application UI was changed to accommodate tests.

## Commands

Run from the project root:

```sh
flutter --version
flutter doctor -v
flutter pub get
flutter pub deps
flutter analyze

# All unit/widget tests (does not run integration_test/).
flutter test
# Choose a unit or widget test explicitly when needed.
flutter test test/infrastructure/integration_report_test.dart
flutter test test/widget_test.dart

# List attached devices and available emulators first.
flutter devices
flutter emulators
# Boot the selected simulator/emulator separately, then use its actual ID.
flutter test integration_test/app_test.dart -d <ios-simulator-id>
flutter test integration_test/app_test.dart -d <android-emulator-id>
# All integration entry points on the chosen native device.
flutter test integration_test -d <device-id>
```

For web, install a ChromeDriver version compatible with the installed Chrome,
then run it in a separate terminal:

```sh
chromedriver --port=4444
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/app_test.dart -d web-server \
  --browser-name=chrome --browser-dimension=390,844 --driver-port=4444
```

`--headless` is available for CI. Use `flutter drive` for web; this SDK's
integration-test README still documents the WebDriver workflow, rather than
assuming native `flutter test ... -d chrome` is equivalent. Reference:
[installed SDK integration_test README](https://github.com/flutter/flutter/blob/6b182d2c75/packages/integration_test/README.md).

Compilation checks without executing a browser/device:

```sh
dart compile kernel test_driver/integration_test.dart -o /tmp/travibe-driver.dill
flutter build web --debug --no-pub --no-wasm-dry-run \
  --target=integration_test/app_test.dart
```

Compilation does not verify browser/device runtime or driver transport.

## CI and troubleshooting

No existing CI runner was found or replaced. A future CI job should pin the
Flutter SDK, run `flutter pub get`, analysis and unit/widget tests, then launch
a real platform runner. Web requires matching Chrome/ChromeDriver; Android
requires accepted SDK licenses and a booted emulator; iOS requires macOS/Xcode
and configured plugin tooling. Archive the raw response JSON even on failure,
and preserve the command's nonzero exit code (do not discard it through a pipe).

If the import remains red after successful resolution, check the active IDE
Flutter SDK and restart its Dart analysis server. Confirm package_config points
`integration_test` into that SDK. If the driver reports no results, check that
the target registered the report helper and reached teardown; do not bypass the
empty-results check. Bound `pumpAndSettle` calls and avoid it while continuous
loading animations or focused cursor animations are intentionally active.

## Verification and limitations

No application UI, Laravel
contract, bundle identifier, Firebase configuration, or .vscode settings changed.

- `flutter --version`, `flutter doctor -v`, `flutter pub deps` and
  `flutter pub get` executed. Dependency resolution succeeded, and package_config
  now resolves `integration_test` to the installed Flutter SDK.
- `dart format` completed for all seven changed/new Dart files.
- Targeted `flutter analyze --no-pub integration_test test_driver
  test/infrastructure test/widget_test.dart`: **no issues**.
- Full `flutter analyze`: **208 findings**, down from 228 before dependency
  resolution. **204** are in downloaded third-party source under `build/`;
  **four** are pre-existing Travibe lints (constructor key, two unused imports,
  unnecessary underscores). No analyzer exclusions or diagnostic suppression
  were introduced. Full analysis therefore still exits unsuccessfully.
- Host driver kernel compilation: **passed**.
- Browser integration entry point `flutter build web`: **passed**. This checks
  browser compilation independently of the host's `dart:io` dependency.
- Reporting and real-app startup tests: **11 passed, zero failed**, including
  separate Dart processes returning success for passing results and nonzero
  exit codes for failed/empty results.
- Final full `flutter test --no-pub --reporter expanded`: **1405 passed,
  five failed**. The stale counter-template failure is resolved by the real-app
  smoke test. Remaining failures, reproduced separately, are unchanged:
  - Search: `small screen handles long names, missing avatars and keyboard`
    (13px overflow) and `Home search SVG keeps its original colors and tap
    action` (expected 20px, responsive value 17px).
  - Story Viewer: `other-user row has composer and independent heart/options;
    owner controls unchanged`; `typing pauses progress, Done resumes and
    preserves the current draft without sending`; `dismiss keyboard works;
    story change clears the ephemeral draft`. These are the previously reported
    reply-composer failures, not fixed by this infrastructure change.
    The separately executed Story Viewer file finished with **12 passed,
    three failed**.
- iOS Simulator: iPhone 17 was connected. The integration command was attempted
  but remained in `xcodebuild -resolvePackageDependencies` for over seven minutes
  without running Dart tests; only this test process was interrupted. Native
  integration compilation/execution and visual verification remain unverified.
  An independent IDE app run was left untouched.
- Android: SDK installed, some licenses unaccepted, no connected emulator.
  No Android integration execution performed.
- Web: Chrome present, **ChromeDriver absent**. Full WebDriver transport and
  browser execution remain unverified. Install a matching driver and run the
  documented command. Xcode doctor also reports CocoaPods missing; inspect the
  project's SwiftPM/plugin resolution before assuming this alone caused the
  stalled native build.

Validation logs are in `/private/tmp/travibe-integration-*.log`, including
`full-tests-final`, `analysis-after`, `analysis-targeted`, `infrastructure-tests`,
`web-build`, `ios-test`, and `story-viewer-tests`. To complete device verification,
resolve the existing Xcode package fetch, then rerun the native command; accept
Android licenses and boot an emulator for Android. No global tooling was
installed or downgraded by this change.

Changed files: `pubspec.yaml`, `pubspec.lock`, `test_driver/integration_test.dart`,
`test_driver/test_report.dart`, `integration_test/app_test.dart`,
`integration_test/support/test_reporting.dart`,
`test/infrastructure/integration_report_test.dart`,
`test/infrastructure/fixtures/report_probe.dart`, `test/widget_test.dart`, and
this document. `.dart_tool/package_config.json` and plugin build artifacts are
generated by dependency resolution, not hand edited.

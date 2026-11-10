# Send Post sharing fix

## Current sheet

SendPostSheet contains the drag handle, Send Post heading, search, horizontal
Travibe member suggestions, Copy Link and More Options. Both profile repost
buttons and the UI-only `_repost` method/state/imports are removed. The sheet no
longer accepts SharesCubit or a share/post ID; it cannot mutate backend shares.
The standalone SharePostDialog and SharesCubit/SharesRepo/backend models remain.
Home's feed-count subscriptions and backend synchronization remain intact.

Home passes actual PostModel.content to `SendPostSheet.postText`. Posts without
text use “A post on Travibe.” The sheet constructs PostShareActions from that
text unless actions are injected. External sharing never calls POST /shares,
never increments shares_count and never reports that a repost was created.
Opening, completing or cancelling native sharing has no backend share effects.

The requested icons remain SvgPicture.asset without ColorFilter:

- `assets/images/interactions/link.svg` at its 46 × 46 intrinsic dimensions.
- `assets/images/interactions/share.svg` at its 32 × 32 intrinsic dimensions.

Both retain the existing 48 × 48 containers. Sheet colors, spacing, typography,
search and member layout remain. Exact Figma comparison is still unavailable as
recorded in FIGMA_REFERENCE.md; no Figma calls or modifications were made here.

## More Options diagnosis

The previous `catch (_)` discarded the exception and stack, mapping every failure
to “Unable to open sharing options. Please try again.” That message alone cannot
distinguish a missing handler/stale native build, an unavailable platform, or a
native presentation error. No device log was provided and simulator access was
denied in this environment, so the exact device runtime cause is **unconfirmed**.

Inspection found no Dart/Swift/Kotlin protocol mismatch:

- Channel: `travibe/post_sharing`.
- Method: `share`.
- Arguments: `text` or a verified `url`, plus `x`, `y`, `width`, `height`.
- Native completion/cancellation resolves the pending request without claiming
  delivery or making a backend call.

The old iOS registration had an optional plugin-registrar lookup with a silent
return; the app channel could be left unregistered if that lookup failed. It now
uses the current implicit engine's applicationRegistrar messenger directly,
retains the channel and prints a debug registration message. This removes that
silent failure path; it is not proof that this was the observed device failure.

Dart now logs operation, target platform, exception details and stack traces in
debug builds, while retaining the friendly UI feedback. MissingPluginException
and PlatformException are covered separately by tests. Logs do not explicitly
include shared post content, and release builds do not execute the debug logging.

## Native changes

### iOS

The existing scene/storyboard Flutter engine still initializes all generated
plugins. The application channel is registered directly on that same engine,
with UI work dispatched to the main queue. A released delegate now returns an
error rather than leaving the call unresolved.

Presentation resolves the foreground scene/window with AppDelegate window
fallback, follows presented/navigation/tab controllers and verifies that the
presenter is attached and not transitioning. UIActivityViewController receives
a String for text or URL for a verified permalink. The optional KVC subject setter
was removed. iPad anchors are converted from the actual Flutter view into the
presenter's coordinate system, clipped to its bounds and replaced by a centered
1 × 1 anchor when absent/invalid. Completion errors carry their native description.

### Android

MainActivity is configured as the launcher and uses Flutter embedding v2. Its
configureFlutterEngine registration matches the Dart channel/method. The correct
ACTION_SEND, text/plain, EXTRA_TEXT and Intent.createChooser behavior is retained.
It now rejects destroyed/finishing activities and includes native exception type
and message in PlatformException details. Debuggable builds also log the actual
launch exception and native stack with Log.e. No manifest permission, target-app
listing or extra dependency is needed for the existing system chooser approach.

No plugin was installed or added. These handlers are custom native application
channels. Native changes require stopping the running app and rebuilding/relaunching
it with Flutter/Xcode/Android Studio. Hot reload and Dart hot restart do not compile
or install changed Swift/Kotlin handlers. A stale binary can still produce
MissingPluginException until a full native rebuild.

Installed share destinations are controlled by the OS and each receiving app.
Actual appearance/content acceptance of WhatsApp, Facebook, X, LinkedIn and email
must be checked on devices; no individual destination is guaranteed by these tests.

## Public URLs

Copy Link remains unavailable: no verified canonical post URL or working post
link route exists in the checked-in model/schema/routing references. PostResource
and the confirmed share responses have no share_url. No public URL was fabricated.
More Options currently shares text only, which does not link to the original post.
A verified canonical URI takes precedence when supplied to PostShareActions.

Remaining public-link work is to implement and document a stable public post
page/route with visibility and deleted-post handling, expose or document its
canonical URL, and configure Flutter post-detail navigation plus platform/domain
associations if app links are desired. None of that backend/routing work was
performed in this fix.

## Files changed in this fix

| File | Change |
| --- | --- |
| `lib/features/shares/widgets/send_post_sheet.dart` | Remove profile UI/dependency, use postText fallback, debug exception/stack logging. |
| `lib/features/home/screens/home_screen.dart` | Pass post text directly and remove obsolete repost-result handling. |
| `ios/Runner/AppDelegate.swift` | Application-engine registration, presentation validation, coordinate-safe iPad anchor and native error details. |
| `android/app/src/main/kotlin/com/example/travibe/MainActivity.kt` | Activity checks and debug native exception diagnostics. |
| `test/features/shares/send_post_sheet_test.dart` | Removed-action checks, default text fallback, native success/error/retry and logging tests. |
| `test/features/shares/post_share_actions_test.dart` | MissingPluginException propagation coverage. |
| `test/features/shares/share_post_dialog_test.dart` | Home integration verifies actual content sharing without reposts/count changes. |
| `docs/SHARE_POST.md` | Diagnosis, implementation, rebuild instructions and verification limits. |

PostShareActions' existing text/verified-URL channel payload was inspected and
retained. No SharesCubit, SharesRepo, share-model, Likes, Comments, Search,
Create Post, Laravel, Figma, dependency or platform-configuration files changed.

## Executed validation

- Targeted analysis of shares, Home and shares tests: **no issues found**.
- Swift type checking against the Flutter framework and iOS simulator SDK: **passed**.
- Kotlin compilation against the cached Flutter embedding, Android SDK and lifecycle
  libraries: **passed** (compiler/JDK deprecation warning).
- Standard `flutter test --no-pub` remains blocked before test loading because the
  sandbox denies localhost server sockets. The existing temporary no-socket harness
  compiled the actual test files and ran all eight shares test files in flutter_tester:
  **64 passed, 0 failed, no skips**.
- Tests cover invocation/success, PlatformException and MissingPluginException,
  debug exception details/stack, retry, actual Home post text, URL priority,
  SVGs without recoloring, missing URL fallback, no repost/count mutation,
  removed profile actions, and existing backend synchronization behavior.

The temporary harness and logs live under `/private/tmp/travibe-share-*`; they are
not project dependencies. Full app/native device tests have **not** been performed.
After a full rebuild, verify native presentation on iPhone, iPad and Android,
installed destinations, completion/cancellation and unchanged backend counts.
If presentation still fails, the debug console now exposes the exact exception
needed to identify the remaining runtime issue.

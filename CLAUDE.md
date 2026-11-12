# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Travibe is a Flutter travel/social app (feed, stories, comments, chat, buddies,
notifications, profiles) backed by a Laravel API at `https://travibeapp.com/api/v1/`.
`AGENTS.md` holds the shared project guide (including Figma rules); prefer the code
if the two ever disagree.

## Commands

```bash
flutter pub get
flutter run
flutter analyze --no-pub                          # whole project
flutter analyze --no-pub lib/features/buddies test/features/buddies   # scoped
flutter test --no-pub                             # all unit/widget tests
flutter test --no-pub test/features/stories/story_viewer_test.dart    # single file
flutter test --no-pub test/features/stories --name "<test name substring>"
flutter test integration_test/app_test.dart -d <device-id>            # on-device
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/app_test.dart -d chrome                   # web e2e
dart format <changed files>
dart run tool/reverb_readiness.dart               # probe production Reverb websocket
```

- `test/live/` contains real two-account chat E2E tests that write to the backend.
  They are gated by `--dart-define=TRAVIBE_CHAT_E2E_ENABLE=true` plus
  `TRAVIBE_CHAT_E2E_*` environment variables; never run them without explicit approval.
- Other opt-in `--dart-define` flags: `CHAT_CAPTURE` (screenshot capture in chat tests),
  `CHAT_LOADING_DIAGNOSTICS`, `PHOTON_DEBUG`, `CHAT_TEST_LOCAL_GALLERY`.
- Integration entry points must call `IntegrationTestWidgetsFlutterBinding.ensureInitialized()`
  then `registerTestReporting(binding)` (`integration_test/support/`); see
  `docs/INTEGRATION_TEST_SETUP.md`.
- Tests that build `MyApp` must pass a fake `pushNotifications`
  (`FakeMessagingClient` from `test/core/notifications/push_fakes.dart`), or real
  Firebase starts and the test fails with a pending timer.

## Architecture

**Layers:** screen → Cubit → repository (`features/*/data/*_repo.dart`) → `ApiService`
→ `DioClient` → backend. No domain layer. Models parse JSON by hand using helpers in
`core/utils/json_parsers.dart`. Errors surface as `ApiError` (message, statusCode,
`fieldErrors`) via `ApiExceptions.handleError`.

**Dependency injection for tests:** there is no DI container. Repositories, Cubits,
`Root`, `MyApp` and `RouterGenerator.createRouter(...)` accept optional collaborators
(e.g. `Root(postsRepo: ...)`, `ApiService(client: ...)`) that default to real instances.
Tests pass fakes through these constructor parameters; follow the same pattern when
adding dependencies.

**Session safety:** `PreferencesManager` (singleton `ChangeNotifier`) stores the token
and a `sessionRevision` that increments on login/logout. `ApiService` tags many
requests with the revision, and `DioClient` cancels requests whose revision is stale,
so responses from a previous account are never applied. `CursorListCubit` listens to
the session and resets itself. Preserve this when adding endpoints or caches.

**Pagination:** feeds/lists use cursor pagination — `core/models/cursor_pagination.dart`
and the generic `core/cubit/cursor_list_cubit.dart` (`load`/`refresh`/`more`, generation
counters to drop stale pages). A cubit's scope is immutable; create a new instance
when the author/target/filters change.

**App shell:** `main.dart` → `MyApp` (ScreenUtil 390×844, dark theme, en/ar locales via
`PreferencesManager().language`) wrapped by `PushNotificationsHost` (Firebase
messaging) and `ChatReverbHost` (Laravel Reverb websocket via `dart_pusher_channels`).
GoRouter (`core/routing/`) handles splash → onboarding/login/OTP/profile-setup/root;
`StartupCubit` decides the target. Inside the app most navigation uses
`Navigator`/`MaterialPageRoute`.

**Root and shared cubits:** `lib/root.dart` owns tab state (Home, Explore, create post,
Buddies, Profile) and creates app-wide interaction cubits — `FollowCubit`, `LikesCubit`,
`SavesCubit`, `SharesCubit`, `BlockCubit`, `PostActivityCubit`, `HiddenPostsCubit` —
so likes/follows/blocks/saves stay consistent across every feed and profile. Feature
screens read these from context rather than creating their own. Blocked users are
also pushed to the Reverb service.

**Chats:** `features/chats/` implements REST conversations plus realtime events over
Reverb (`reverb_socket.dart`, `chat_reverb_service.dart`), with history cache, drafts,
presence and media upload (`core/media/media_upload_service.dart`).

## Reference material

API reference: docs/openapi.json (refresh with curl -u $TRAVIBE_DOCS_AUTH https://travibeapp.com/docs/api.json -o docs/openapi.json)

- `docs/openapi.json` (the only API spec), `API_REFERENCE.md`: backend contracts —
  check these before adding or changing endpoints.
- `docs/*.md`: per-feature implementation/stage notes (e.g. `CHAT_*`, `STORIES_STAGE*`,
  `PROFILE_STAGE*`, `CURSOR_PAGINATION_MIGRATION.md`); read the relevant one before
  modifying that feature.

## Conventions

- `package:travibe/...` imports, snake_case files; standard `flutter_lints`.
- Run dart format only on the specific files you changed — never on whole folders.
- Reuse `core/widgets/`, `AppSizes`, `AppStyles`, `DarkColors`; sizes via ScreenUtil.
- Cubit states commonly use sealed classes with `part`/`part of` files.
- UI work: consult the Figma file per `AGENTS.md` / `docs/FIGMA_REFERENCE.md` (access
  was previously blocked — report it rather than inventing designs). Keep API,
  repository and Cubit logic unchanged during visual-only work.
- Google sign-in is not active (`GoogleAuthService` init is commented out in `main.dart`).
- Don't explore `build/` or `.dart_tool/`; `build/*/SourcePackages` contains
  third-party Firebase examples that are not project tests.
## Role & style
You are a senior Flutter/Dart developer on Travibe.
- Be concise; show only changed code.
- Follow existing patterns (Cubit → repository → ApiService). No new packages without asking.
- For UI work, follow the Figma rules in AGENTS.md.
- Never run tests in test/live/ without my approval.
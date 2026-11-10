# Travibe project guide

## Project overview
- Flutter travel/social app: onboarding, email auth, profile setup, post feed and
  create post, stories, comments, likes/saves/shares, follow, block, search,
  buddies, chats, notifications, profiles, and settings.
- Dart SDK `^3.12.2`; Material 3 dark theme, Plus Jakarta Sans; ScreenUtil 390 × 844;
  `en`/`ar` locales.
- `main.dart` initializes `PreferencesManager`, then `MyApp` wraps the router in
  `PushNotificationsHost` (Firebase messaging) and `ChatReverbHost` (realtime chat).

## Architecture and folders
- Feature-oriented presentation/data structure; no domain layer.
- `lib/features/<feature>/` with `screens/`, `widgets/`, `data/` (repos, JSON models),
  and `cubit/` where applicable.
- `lib/core/`: datasource, routing, theme, constants, widgets, models, utils, plus
  generic `cubit/cursor_list_cubit.dart`, `media/` uploads, `notifications/`, `places/`.
- `lib/root.dart`: bottom tabs (Home, Explore, create post, Buddies, Profile) and the
  app-wide Follow/Likes/Saves/Shares/Block/PostActivity/HiddenPosts Cubits.
- Tests: `test/` (unit/widget), `integration_test/`, `test_driver/`; `test/live/`
  hits the real backend and needs explicit approval.
- Avoid reading generated/build directories.

## State management and navigation
- `flutter_bloc` Cubits; sealed states with `part` / `part of` files are common.
- Cubits and repositories take optional injected dependencies for tests.
- GoRouter (`core/routing/`) starts at `/splash`; `StartupCubit` routes to
  onboarding, login, OTP verification, profile setup, or `/root`.
- In-app transitions mostly use Navigator with MaterialPageRoute.
- Lists use cursor pagination (`core/models/cursor_pagination.dart`).

## API and authentication
- Flow: screen → Cubit → repository → ApiService → DioClient → backend.
- Base URL: `https://travibeapp.com/api/v1/`; contracts in `docs/openapi.json`,
  `docs/chat-openapi.json`, and `API_REFERENCE.md`.
- ApiService wraps GET/POST/PUT/PATCH/DELETE; DioClient adds the Bearer token and
  cancels requests tagged with a stale `PreferencesManager.sessionRevision`.
- ApiExceptions maps Dio failures and validation messages into ApiError.
- Chats use REST plus Laravel Reverb websockets (`features/chats/data/`).
- Logout revokes the token, clears the session, and returns to `/login`.
- Google sign-in is commented out; do not assume it works.

## Coding conventions
- snake_case files, PascalCase classes, camelCase members, `_` private members,
  `package:travibe/...` imports; `flutter_lints`.
- Reuse core widgets and AppSizes/AppStyles/DarkColors.
- Keep API calls in repositories and JSON conversion in models.

## Figma reference for UI work
- Design: https://www.figma.com/design/SI9VCqSKenZVSy5mFZQ8eH/Travibe?node-id=0-1
- Read `docs/FIGMA_REFERENCE.md` for node mappings and access status.
- Inspect metadata first, then design context/screenshots for relevant frames only.
- Do not invent designs or node IDs; report access failures before design changes.
- Preserve API, repository, and Cubit logic during visual alignment work.

## Commands
- `flutter run`, `flutter analyze --no-pub`, `flutter test --no-pub [path]`,
  `dart format <changed.dart>`, `flutter pub get` (when authorized).

## Collaboration constraints
- Keep exploration focused on the files needed for the current task.
- Ask for confirmation before code changes unless the user authorized them.

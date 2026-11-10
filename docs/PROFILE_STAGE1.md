# Profile Stage 1 — read-only loading

## Scope and endpoints

ProfileRepo now uses GET `profile` for the authenticated full profile and GET
`users/{integer ID}` for public profiles, relative to the existing `/api/v1/`
base URL. GET `me` was removed. GET `/user` and Home's minimal identity handling
are unchanged. Existing ApiService/DioClient provide JSON headers, optional bearer
attachment and ApiError conversion. Existing errors/status codes are preserved.
No PATCH, upload, Follow/Block mutation or post-loading implementation was added.

ProfileScreen defaults to own mode in the existing Root tab. Public mode reuses
that screen via `ProfileScreen(userId: id)` or
`ProfileScreen.open(context, userId: id)`. The navigation helper preserves existing
Root FollowCubit/BlockCubit instances through BlocProvider.value; popping the
route does not dispose those session controllers. No Home/Search tap handlers,
GoRouter routes or authentication redirects were changed in this stage.

## Response evidence and isolated assumptions

Sources inspected: `docs/openapi.json`, `API_REFERENCE.md`, the existing
UserResource/PublicUserResource definitions and Profile Setup/reference parsers.
The local OpenAPI file still does not declare either new GET operation. No
captured full-profile JSON example or live authenticated response was available.
The user's confirmed paths and semantics take precedence over the older API
reference memo, which recommends the previous minimal `/user` endpoint.

The generic `{ "data": [] }` documentation example is **not** treated as a valid
profile. ProfileRepo requires a JSON envelope with a `data` resource object.
ProfileModel.fromJson is the isolated response-field adapter. It requires a
positive integer `id`; other mapped fields may be absent/null without fabricating
values. An empty object, array or malformed supplied field becomes an ApiError.

| Response field | Model / UI |
| --- | --- |
| `id` | Integer converted to existing Dart string identity; public ID must match target. |
| `name`, `username` | Header identity; an actual username may substitute for an empty name. Email is never turned into a display name. |
| `email`, `locale`, `email_verified_at`, `terms_accepted_at` | Retained nullable account metadata; email is not displayed on public headers. |
| `profile_completed`, `profile_completed_at`, `created_at`, `updated_at` | Retained completion/timestamp metadata from existing UserResource conventions. |
| `avatar_url` | Existing network avatar and neutral missing-image placeholder. |
| `bio`, `country_code`, `nationality` | Header/About; missing fields are omitted. Country labels use the existing country-code lookup. |
| `languages_spoken` | Immutable `{slug, name}` selections; existing UserResource `languages` spelling is accepted only when `languages_spoken` is absent. |
| `interests`, `travel_styles` | Immutable `{slug, name}` selections, with labels used by existing About chips. |
| `posts_count`, `followers_count`, `following_count` | Nullable nonnegative integers; unknown values display `—`, not zero. |
| `is_me`, `is_following`, `follows_you`, `is_blocked` | Nullable relationship flags; supplied booleans and existing string/numeric 1/0, true/false representations are supported. Absence remains unknown. |

The new endpoint field names/types for bio, nationality, counts, relationship
flags and account metadata are not verified against an actual full-profile
response. Snake_case names follow the existing model/resources and the confirmed
task. Reference object shape `{slug, name}` comes from UserResource; string-only
reference arrays or differently named/nested fields are deliberately rejected
rather than assigned invented slugs/labels. Counts represented as strings are
also rejected until documented. Unknown additional fields are ignored. Cover
photo mapping is not introduced without a contract.

A representative owner/public JSON response is still needed to validate these
adapter assumptions against the deployed backend. Tests use explicitly synthetic
contract-shaped fixtures, not captured API responses.

## Loading and presentation

- Initial loading and errors reuse ProfileShimmer/ErrorRetryView.
- Retry and pull-to-refresh load the selected endpoint.
- Transient refresh errors keep existing data visible with error/retry feedback.
- HTTP 401/403/404 on refresh clears previously shown data into an error state.
- Only public `data: null` produces the explicit ProfileUnavailable state; missing
  optional flags do not imply blocking. The UI uses the neutral message “This
  profile is unavailable” rather than claiming which party blocked whom.
- Duplicate ordinary loads coalesce. Forced refreshes advance a generation;
  older successes/errors cannot replace newer results. Closure/target replacement
  invalidates pending responses, and widget subscriptions are cancelled on dispose.
- Own mode exposes existing owner layout/Saved tabs. A public response only gains
  owner controls when `is_me` is explicitly true. Other public profiles hide owner
  controls and Saved tabs. Settings uses the existing session BlockCubit when present.
- Editing and Share Profile buttons are disabled for this read-only stage, avoiding
  navigation into the existing demo-filled edit form or a nonfunctional share action.
- Hardcoded sample posts/hotels were removed from this screen. The existing tabs
  show “not loaded yet” placeholders, not false empty-list claims. Actual profile
  post/saved loading is outside Stage 1; reusable card widgets remain intact.

No new screen design was introduced. Existing widgets/theme/layout are reused;
conditional owner controls and loading/error/unavailable states are data-driven.
Figma access limitations remain recorded in FIGMA_REFERENCE.md; no Figma was modified.

## Follow and Block integration

Existing FollowCubit/BlockCubit implementations are unchanged. Confirmed follow
mutations refresh Profile so counts and viewer-aware fields come from the server.
Confirmed local block state immediately hides a targeted public profile and
invalidates old reads. Unblocking refreshes it. A known local block also prevents
an old/manual read from exposing cached profile content. No follow relationship
or count is synthesized, and no new Follow/Block controls or mutation endpoints
were implemented. Existing Settings/Blocked Accounts behavior is preserved.

## Files changed

| File | Change |
| --- | --- |
| `lib/features/profile/data/profile_model.dart` | Isolated nullable resource mapping, reference slugs/labels and viewer flags. |
| `lib/features/profile/data/profile_repo.dart` | Confirmed GET paths, envelope validation, nullable public resource and error preservation. |
| `lib/features/profile/cubit/profile_cubit.dart` | Targeted loading, retry/refresh, generation guards and disposal/block invalidation. |
| `lib/features/profile/cubit/profile_state.dart` | Loaded/refresh-error, unavailable and typed failure states. |
| `lib/features/profile/screens/profile_screen.dart` | Shared owner/public view, navigation helper, refresh, session subscriptions and removal of sample content. |
| `lib/features/profile/widgets/profile_stats.dart` | Unknown counts display as a dash. |
| `lib/features/profile/widgets/profile_tabs.dart` | Public profiles omit Saved. |
| `lib/features/profile/widgets/profile_action_buttons.dart` | Keep owner controls read-only during Stage 1. |
| `test/features/profile/fixtures.dart` | Synthetic resource fixtures and controllable repository. |
| `test/features/profile/profile_model_repo_test.dart` | Mapping, endpoints, null/malformed responses and API errors. |
| `test/features/profile/profile_cubit_test.dart` | Loading/retry/refresh, coalescing, stale responses, block invalidation and disposal. |
| `test/features/profile/profile_screen_test.dart` | Own/public UI, refresh, unknown fields, navigation and Follow/Block integration. |
| `docs/PROFILE_STAGE1.md` | Mapping evidence, assumptions, scope and verification results. |

No Home, Comments, Likes, Share, Profile Setup, Follow/Block implementation,
Laravel, dependency, auth/session, or routing-configuration files changed.

## Verification — 2026-10-19

- Targeted analysis of modified Profile data/Cubit/screen/widgets and Profile
  tests: **no issues found**.
- A broader Profile-directory analysis also found 10 pre-existing issues in
  unrelated settings/edit/selector/dialog files; these were left outside scope.
- Standard `flutter test --no-pub test/features/profile` was attempted but blocked
  before test loading by this sandbox's denial of localhost socket creation.
- The temporary no-socket harness compiled the three actual Profile test files
  and ran them with Flutter's frontend server/flutter_tester, VM service disabled,
  test_api declaration/invocation and per-widget-test tree cleanup:
  **25 passed, 0 failed, no skips**.
- Tests cover owner/public GETs, nullable and malformed fields, explicit public
  data:null, 401/network errors, pull-to-refresh/retry, stale success/error races,
  disposal, profile-target changes, navigation controller reuse, confirmed follow
  refreshes, and block/unblock visibility with stale-read protection.

No live backend requests, app-wide build/tests or deployed full-profile response
verification were performed. Temporary harness/logs are under
`/private/tmp/travibe-profile-*`, not project dependencies.

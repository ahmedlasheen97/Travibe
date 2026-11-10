# Travibe API reference

## Source and validation
- Source: [docs/openapi.json](docs/openapi.json), OpenAPI `3.1.0`, API `1.0.0`; reviewed 2026-10-13.
- Local structural checks passed: valid JSON, 53 paths, 65 operations, 30 schemas;
  all 208 `$ref` occurrences resolve, operation IDs are unique, path parameters
  are declared/required, and referenced security schemes exist.
- This is structural and contract review, not full OpenAPI meta-schema validation
  (validator unavailable) or live backend testing. Internal inconsistencies appear below.
- Compared all five Flutter API repositories, their models, shared HTTP/error
  layer and JSON helpers; inspected onboarding data without scanning UI.

## Later Chat audit

This older 53-path snapshot does not describe Chat. The later authorized Chat
contracts and 2026-11-08 Reverb readiness checks are documented in
[docs/CHAT_API_CONTRACT.md](docs/CHAT_API_CONTRACT.md) and
[docs/CHAT_E2E_READINESS.md](docs/CHAT_E2E_READINESS.md). Absence from this older
reference is not evidence that the confirmed Chat endpoints are unsupported.
No message writes or positive channel authorization were performed in that audit.

## Base URL, headers and authentication
- Specification server: `http://travibeapp.com/api/v1`.
- Flutter `DioClient`: `https://travibeapp.com/api/v1/`. Scheme differs;
  the introduction's `https://travibe.com/api/v1/users` is also inconsistent.
  These are documentation discrepancies, not verified alternative deployments.
- Paths below are relative to `/api/v1`. JSON headers:
  `Accept: application/json`, `Content-Type: application/json`.
- Root security is HTTP bearer (`bearerAuth`): `Authorization: Bearer <token>`.
  Operation-level `security: []` removes that requirement.
- Public operations are marked P below. Several public reads accept optional tokens;
  descriptions warn that invalid/expired tokens produce 401.
- Other operations inherit bearer security. Descriptions require full access and
  verified email for `/user`, feeds, sessions and social/content interactions.
  Media explicitly needs no email verification; profile setup declares bearer only.
- Registration returns a restricted token until verification. OTP verification
  upgrades the caller's token only when it belongs to the verified account;
  retain and send the registration token even though verification is public.
- Send a stable `device_name`; reusing it replaces that device's previous token.
  Logout revokes the current session; password reset revokes every device session.
  Introduction says tokens last until logout; resources also expose `expires_at`.

## Endpoint groups
All 65 operations are represented. Braces indicate path parameters.
P = no bearer requirement in the operation; B = inherited bearer security.
Description/security conflicts are recorded under specification caveats.

| Group | Methods and paths | Access |
| --- | --- | --- |
| Auth | POST `/login`, `/register`; GET `/user`; POST `/logout` | P login/register; B others |
| EmailVerification | POST `/email/verify-code`, `/email/resend-code` | P |
| PasswordReset | POST `/forgot-password`, `/email/verify-reset-code`, `/reset-password` | P |
| SocialAuth | POST `/auth/{provider}/token` (Google/Apple) | P |
| Token | GET `/tokens`; DELETE `/tokens/{token}` | B |
| ProfileSetup | GET `/profile/username-availability`; PATCH `/profile/setup`; POST `/profile/setup/complete` | B |
| Onboarding | GET `/onboarding`, `/locales` | P |
| Reference | GET `/reference/languages`, `/reference/interests`, `/reference/travel-styles`; POST `/reference/languages/request` | P GET; B POST |
| Search | GET `/search/users`, `/search/posts` | P |
| Feed | GET `/feed/following`, `/feed/explore` | B |
| Follow | GET `/users/{user}/followers`, `/users/{user}/following-list`; POST `/users/{user}/follow`, `/users/{user}/unfollow`; GET `/users/{user}/following`, `/users/suggested` | P first two; B others |
| Block | POST `/users/{user}/block`, `/users/{user}/unblock`; GET `/users/{user}/block`, `/me/blocks` | B |
| Post | GET/POST `/posts`; GET/PUT/DELETE `/posts/{post}`; POST `/posts/{post}/restore` | P GET; B others |
| Comment | GET/POST `/posts/{post}/comments`; GET/PUT/DELETE `/posts/{post}/comments/{comment}`; POST `/posts/{post}/comments/{comment}/restore` | B (GET prose says optional) |
| Like | GET `/posts/{post}/likes`, `/posts/{post}/comments/{comment}/likes`; POST/DELETE `/posts/{post}/like`, `/posts/{post}/comments/{comment}/like` | P GET; B others |
| HiddenPost | POST/DELETE `/posts/{post}/hide` | B |
| SavedPost | POST/DELETE `/posts/{post}/save`; GET `/users/me/saved` | B |
| Share | GET/POST `/posts/{post}/shares`; DELETE `/posts/{post}/shares/{share}` | B (GET prose says optional) |
| Media | POST `/media/presign`, `/media/{media}/finalize`; GET `/media/{media}` | B |
| Report | POST `/reports` | B |

## Authentication and profile contracts
- Login requires `email`, `password`, `device_name`; optional `remember` is a string.
- Register requires `email`, `password`, `password_confirmation`, `device_name`,
  `terms_accepted` (accepted true values); optional `locale` is `en`, `ar` or null.
- Login/register/social exchange return 200 `{data: AuthenticationTokenResource}`:
  required `token`, `token_type`, `expires_at`, `email_verification_required`, `user`.
  All except `user` are declared strings, including the verification flag.
- Email verification sends `{email, code}` (4-digit code), returns 200 `{message}`.
  Five wrong attempts invalidate the code. Resend sends `{email}`, returns
  202 `{message, email}` with masked email; cooldown 60 seconds, daily cap 20.
- Forgot password sends `{email}`, returns 200 `{message}` regardless of account existence.
  Reset-code exchange sends `{email, code}`, returns 200 `{message, data: {token}}`;
  token is nullable. Codes expire after 10 minutes and allow five attempts.
- Reset password requires `token`, `email`, `password`, `password_confirmation`;
  returns 200 `{message}`. Logout and token deletion return empty 204 responses.
- Social exchange requires `device_name`, `id_token`; optional `name`, `nonce`.
  Apple requires its original, single-use nonce (16–255 characters).
- GET `/user` returns `{data: UserResource}` with identity/email, `locale`,
  `terms_accepted_at`, `username`, `country_code`, `profile_completed_at`,
  `profile_completed`, timestamps, and required avatar/taxonomy fields for this operation.
  `languages`, `interests`, `travel_styles` contain `{slug, name}` objects.
  Counts/following state are optional; `bio`, `nationality`, `posts_count` are absent.
- Username availability requires query `username`: 3–30 letters/digits/underscores/dots;
  returns `{data: {username, available}}` with boolean availability.
- PATCH setup accepts any subset: `full_name` (legacy `name`), nullable `username`,
  `country_code`, `avatar_media_id`, `languages_spoken`, `interests`, `travel_styles`.
  Taxonomies use slug arrays, maxima 4/6/3; null clears, omitted fields stay unchanged.
  Avatar media must belong to the caller and be `ready` or `processing`.
- Completion needs name, username, 1–4 languages, 1–6 interests, 1–3 travel styles;
  optional body can supply `full_name`/`name`; 422 lists missing requirements.
- Setup responses require `data` (declared untyped array) and
  `meta.profile_completed`, `meta.profile_setup_step`. Steps are `identity`,
  `languages_interests`, `travel_style`, `review`, `complete`; completion fixes `complete`.
  Completion prose calls `data` a user; clarify before modeling it.
- Reference GETs supply localized slug/name options (`Accept-Language`);
  languages support `search`. Custom language request sends `{name}` (2–50 characters),
  returns 201 for creation or 200 for an existing match; pending options are requester-only.

## Pagination, content and errors
- Paginated lists use `page` (introductory convention) and `per_page` (explicit
  query parameter: 1–100, default 15). `page` is omitted from operation parameter lists.
- Envelope: `{data: [...], links: {first, last, prev, next}, meta: {...}}`.
  Meta requires `current_page`, `last_page`, `per_page`, `total`, `from`, `to`,
  `path`, `links`; link URLs and empty-slice bounds can be null.
  GET `/tokens` is an unpaginated `{data: [...]}` response.
- Search requires `q` length 3–100. GET `/posts?user_id=...` lists an author's
  posts; without it `/posts` serves explore content, not the following feed.
- Post/comment creation needs content, media, or both; content max 2000 characters.
  Post visibility: `public`, `followers`, `private`; edits use PUT, not PATCH.
- Media uses presign → direct storage PUT with returned headers → finalize → poll.
  Accepted MIME types: JPEG/PNG/GIF/WebP; default maximum 20 MB. No video upload contract.
- Most resources use `data`; message-only successes and empty 204s are exceptions.
  Content deletions generally return 200, so do not assume every DELETE is 204.
- 422 validation: `{message: string, errors: {field: [string, ...]}}`.
  Shared 401 authentication, 403 authorization and 404 not-found bodies: `{message: string}`.
- Prose also documents 409 conflicts (follow state/finalize) and 429 throttling;
  these are not comprehensively declared in responses. No global numeric rate limit.

## Flutter comparison and prioritized gaps
Paths in this table are relative to `lib/`. P0 = broken contract;
P1 = authentication/profile correctness; P2 = broader coverage.

| Priority | Existing source | Verified finding / required integration |
| --- | --- | --- |
| P0 | `features/profile/data/profile_repo.dart` | `getMyProfile()` calls GET `me`, absent from spec; use GET `/user`. `/me/blocks` does not imply `/me` exists. |
| P1 | `core/datasource/remotedata/dio_client.dart` | HTTPS differs from server HTTP; reconcile deployment/spec before changing transport. |
| P1 | `features/auth/data/auth_repo.dart` | Login/register/OTP/recovery paths and required payload keys match. Missing resend, server logout, session list/revocation and social token exchange; Google service is commented out. |
| P1 | `features/auth/data/auth_repo.dart` | Reset success revokes all sessions but method leaves the stored bearer token; clear invalid local credentials. Verification sends the stored bearer via interceptor, supporting token upgrade. |
| P1 | `features/auth/data/auth_response_model.dart` + `auth_repo.dart` | Verification flag schema is string; parser handles only true/`true`/1/`1`; other strings are unspecified. Nullable reset `data.token` is correctly rejected before conversion; top-level token fallback is extra tolerance, not the contract. |
| P1 | `features/auth/data/user_model.dart` | Drops required `locale`, `terms_accepted_at`, `username`, `country_code`, `profile_completed_at`, `profile_completed`; also omits avatar/taxonomies. Cannot retain profile completion state. |
| P1 | `features/profile/data/profile_model.dart` | Taxonomy objects parse to names correctly, but slug IDs are lost for editing; completion/email-verification/locale fields omitted. `bio`, `nationality`, `posts_count` have no specified source and default to null/0. |
| P1 | `features/profilesetup/data/profile_setup_repo.dart` | All three paths and sent keys match; `languages_spoken` write versus `languages` read is intentional. Missing `avatar_media_id`; null fields are omitted, preventing explicit clearing. Save/complete discard wizard metadata and returned data. |
| P1 | Profile/reference data layer | No repositories for reference catalogs/custom languages or avatar upload lifecycle; needed to persist supported options and avatar media. |
| P1 | Auth/profile/setup/posts repos + `ApiService` | Service throws `ApiError`; generic repository catches wrap it and lose status codes. Preserve status and field errors for 401/403 handling and setup's multi-field 422s. SearchRepo already rethrows `ApiError`. |
| P1 | `features/auth/data/auth_repo.dart` | Device name uses model/manufacturer, so same-model devices may replace each other's sessions. Raw login/reset responses are printed, including returned access/reset tokens. |
| P2 | `features/home/data/posts_repo.dart` | GET `/posts` and page model match; missing `user_id`/`per_page`, dedicated following/explore feeds and all post mutations/details. |
| P2 | `features/search/data/search_repo.dart` | GET `/search/users` and page model match; repository does not constrain `q` to 3–100 or expose `per_page`; `/search/posts` missing. |
| P2 | Page/public-user/post models | Parsed pagination subset, integer-ID string conversion and nested post/media fields are compatible. Optional fields default silently; PostModel omits optional `deleted_at`. Public follow/block strings accept only known truthy forms. |
| P2 | Remaining repositories | Missing follows/lists/checks/suggestions, blocks/list/checks, comments/replies, likes, hides, saves/list, shares and reports. Exact paths are in the group table. |
| P2 | Onboarding/locales + HTTP layer | Onboarding data is hardcoded; no onboarding/locales API integration found. ApiService lacks PUT/DELETE and direct storage upload support; DioClient has no automatic 401 recovery. No refresh endpoint is specified. |

## Specification caveats requiring backend clarification
- Comment GETs and share-list GET inherit bearer security while descriptions say
  bearer is optional. Several public GETs describe 401 without declaring that response.
- Setup success `data` is an untyped array; completion description promises a user.
- `email_verification_required`, public follow/block flags and session `current`
  are schema strings although descriptions use boolean semantics (`current: true`).
  Do not silently replace declared types with assumed booleans.
- Presign description promises `upload_url`, `upload_method`, `upload_headers`,
  `expires_at` and `media.id`; response only declares `data: MediaResource`,
  which has no upload fields. Upload integration needs a clarified envelope.
- Selection descriptions require 1+ entries but array schemas omit `minItems`;
  OTP describes four digits without length/pattern constraints. Onboarding
  `asset_url` is declared null-only despite describing managed slide assets.
- Intro examples (`/users`, `/profile`, changing email) are not declared paths;
  no standalone public-user detail or email-change operation is specified.
- Only this reference was updated; Flutter code/spec unchanged. No builds,
  dependency installation, Flutter tests or authenticated API calls were run.

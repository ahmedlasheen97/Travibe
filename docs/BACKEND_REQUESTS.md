# Backend requests

Open asks from the mobile client to the Laravel API. Each entry says what the
client does today and what changes once the endpoint ships. Older notification
asks are listed in `NOTIFICATION_BEHAVIOR_FIXES.md` ("Backend requests").

## Notifications: keep direct chat messages out of the inbox

Direct chat messages already appear in Chats with their own unread count. The
Notifications inbox and the Home bell should not show them as well.

**Definition used below.** A *direct chat message* is a `message_received`
notification whose `data.is_request` is not `true`. Message requests
(`message_received` with `data.is_request: true`) and
`message_request_accepted` **must stay** in both the list and the count;
without them a new request is easy to miss in the Requests tab.

### 1. `GET /notifications/unread-count`: do not count direct chat messages

Either:

- **Preferred:** exclude direct chat messages from `unread_count` by default, or
- accept `exclude_types[]` (same semantics as request 2), for example
  `GET /notifications/unread-count?exclude_types[]=message_received`.

The same exclusion should apply to the `unread_count` carried by the realtime
events (`notification.created`, `notification.read`,
`notifications.read_conversation`) and by push payloads. The badge is updated
from those too, so they must agree with the endpoint.

**Client today:** the bell shows the raw `unread_count`, which includes direct
chat messages. This is intentionally unchanged until the endpoint ships.

**Client after:** if the default changes, nothing to do. If it is a parameter,
`NotificationsRepo.unreadCount()` sends `exclude_types[]=message_received`.

### 2. `GET /notifications`: accept `exclude_types[]`

`GET /notifications?exclude_types[]=message_received&per_page=15&cursor=…`

- Rows of the listed types are left out **before** the page is cut, so every
  page holds up to `per_page` visible rows and `next_cursor` stays correct.
- For `message_received`, rows with `data.is_request: true` are kept (see the
  definition above). If a generic type filter cannot express this, a dedicated
  flag such as `exclude_direct_messages=1` is fine too.
- Unknown values in `exclude_types[]` are ignored rather than rejected with
  `422`, so older and newer clients can both send it.

**Client today:** `NotificationsCubit` drops direct chat messages after each
page is fetched. When a page contains only chat messages it requests the next
page, up to 5 in a row, then stops and leaves the cursor for scrolling. This
costs extra requests and can show a short or empty first page.

**Client after:** `NotificationsRepo.list()` sends the parameter and the
client-side page skipping in `NotificationsCubit` is removed. The client-side
filter stays as a safety net.

### Unchanged

`PATCH /notifications/read-all` should keep marking every unread row,
including direct chat messages. The inbox calls it on open, so hidden rows are
cleared too.

## Stories: document the maximum Story photo upload size

`POST /media/presign` says "a size over the configured per-type maximum is a
`422`", but `docs/openapi.json` never states the number for images, and
`POST /stories` doesn't say whether Stories use a different limit.

**Ask:** please document the maximum image size in bytes for a Story photo
(and the general image limit, if different). Ideally also the maximum pixel
dimensions, and whether the server re-encodes or resizes Story photos.

**Client today:** Stories upload a JPEG (quality 85) cropped to the editor
view and no larger than 1080×1920, usually 0.3–1 MB. The shared upload service
still enforces its own 20 MB client cap for images. The storage PUT timeout
grows with file size (60 s up to 10 min).

**Client after:** the client checks the documented limit before presigning and
shows a clear "photo too large" message instead of a generic failure.

## Stories: don't record/return the story owner's own view

`POST /stories/{story}/view` says "the first view creates the caller's view
row and increments the story's view count", with no exception for the author.
When owners open their own Story, they are counted in `views_count` and listed
in `GET /stories/{story}/viewers` (shown with a Follow button on themselves).

**Ask:** don't record/return the story owner's own view. Either skip the view
row for the author (the endpoint can still return success so seen-state code
keeps working) or exclude the author from `views_count` and from
`GET /stories/{story}/viewers`. Please also confirm what `has_seen` returns
for the author afterwards.

**Client today:** the viewers sheet hides the signed-in user's row, and when
the server reports `is_mine && has_seen` on the user's own Story, one view is
subtracted from the count (`StoryDetail.viewsCountExcludingOwner`).

**Client after:** if the author's view is no longer recorded, `has_seen` is
false for the owner and nothing is subtracted, so no client change is needed.
If `has_seen` stays true while the count already excludes the author, tell us
and we'll remove the subtraction.

## Support: Report a Problem endpoint

Settings → Report a Problem has no endpoint. `POST /reports` only accepts
`type: post|comment|user|story` plus an id, so it can't take app feedback.

**Ask:** add `POST /support/problems` (bearer token):

- `category`: required enum. The client currently sends `bug`, `account`,
  `posts_stories`, `chats`, `notifications` or `other`. Please confirm the
  list, or expose `GET /support/categories` returning `{slug, label}`.
- `description`: required string, maxLength 1000 (the same as
  `/reports.description`). Please document the real limit.
- `media_ids`: optional integer array, max 3. These are ids from the
  existing `POST /media/presign` → upload → `POST /media/{media}/finalize`
  flow (JPEG/PNG/GIF/WebP, ≤ 20 MB). Please document the max count.
- Responses: 201 `{data: {id, status, created_at}}`, 401, and 422 with
  per-field errors.

**Client today:** the Settings row is hidden behind `kShowReportProblem`
(`lib/core/constants/feature_flags.dart`), so users can't send reports into a
failing request. The screen is kept: `SupportRepo.reportProblem` already
posts this body to `support/problems`, and screenshots are uploaded before
the report and never re-uploaded on retry.

**Client after:** set `kShowReportProblem` to `true`. Nothing else is needed
if the contract matches. Otherwise we update the path, field names and limits
(`SupportRepo.categories`, `maxDescription`, `maxScreenshots`).

## Email change: resend, limits and pending state

`POST /email/change` and `POST /email/change/verify` exist, but some parts of
the flow are not specified.

**Ask:**

1. **Resend (needed).** Please add `POST /email/change/resend`: bearer token,
   no password, empty body. It re-sends a fresh code to the account's pending
   address, with the same cooldown, daily cap and 429 responses as the first
   send, and returns 422 when no change is pending.
   `/email/resend-code` doesn't cover this because it only mails unverified
   accounts. **Why it matters:** without this endpoint, the only way to
   resend is to post `POST /email/change` again, which needs
   `current_password`. So `EmailChangeCubit` keeps the user's password in
   memory for the whole OTP step, only so Resend can work. A dedicated
   endpoint lets the app drop the password right after the first request.
2. **Limits.** Please document the code length (the signup code is 4 digits),
   expiry, attempt limit, resend cooldown and daily cap, plus their 429
   responses.
3. **Wrong password.** Please document the 422 key for a wrong password on
   `/email/change` (we read `current_password`, then `password`) and the key
   for an email that is already taken (we read `email`).
4. **Pending state.** Add `pending_email` (nullable) to `UserResource` so the
   app can show "Verification pending for …" after a restart. Also declare
   `email_verified_at` as `format: date-time`.

**Client today:**

- The Email Address screen asks for the password in a dialog and calls
  `POST /email/change`.
- Resend sends the same request again, using the password held in memory.
- After `verify` returns, the client adopts the returned `UserResource`.

**Client after:**

- Resend switches to the dedicated endpoint, and the password is no longer
  kept after the first request.
- The UI shows the documented cooldown.

## Account: delete-account body and reason

`DELETE /account` takes `password` as a **query parameter**, so it can end up
in access logs. The description mentions a `DeleteAccountRequest`, but that
schema isn't in components. The Figma screen also collects an optional
reason.

**Ask:**

- Accept `{password, reason?}` as the JSON body. Keep the query parameter
  during migration if needed.
- `reason`: optional string, max 500.
- Document the wrong-password response (we expect 422 on `password`).

**Client today:**

- The password is sent as the query value, as specified.
- The "Why you want to delete this account?" field (max 500) is shown but not
  sent.
- A 422 is shown under the password field.

**Client after:** `ApiService.deleteAccount` sends the body, including
`reason`.

## Password: document complexity rules

`PATCH /password`, `POST /register` and `POST /reset-password` refer to "the
configured complexity rules" without stating them.

**Ask:** document the minimum length and the required character classes, so
the client validates before sending.

**Client today:** the client only checks for at least 8 characters and relies
on the server's 422.

## OTP: separate error codes for wrong and expired codes

`POST /email/verify-code` and `POST /email/verify-reset-code` answer both a
wrong code and an expired one with the same 422 and the same message,
"Invalid or expired code.", so the app cannot tell the user which one happened.

**Ask:** add a machine-readable code to the 422 body, for example:

```json
{
  "message": "Invalid or expired code.",
  "code": "otp_invalid",
  "errors": { "code": ["Invalid or expired code."] }
}
```

- `otp_invalid`: the code is wrong (the attempts left could also be returned).
- `otp_expired`: the code is past its 10-minute lifetime, or was invalidated
  after five wrong attempts.
- Document both in `docs/openapi.json`. The user-facing `message` can stay
  generic if account enumeration is a concern; only the code needs to differ.

**Client today:** the message text is ignored and every 422 shows "Wrong OTP
Try Again", including expired codes (the app cannot tell them apart). Wrong
attempts are counted on the device (`OtpAttempts` in
`lib/features/auth/screens/otp_verification_screen.dart`): the fifth shows
"Too many attempts. Tap Resend OTP" and disables Verify until a resend, which
resets the counter. This mirrors the server's five-attempt rule but can drift
from it (e.g. attempts made on another device, or after the app restarts).

**Client after:** map `otp_expired` / `otp_invalid` (and an
`otp_too_many_attempts` code, ideally with `attempts_remaining`) directly and
drop the device counter. With `otp_expired` the app can show "Code expired.
Tap Resend OTP" again.

## Stories: list a user's active stories (`GET /users/{user}/stories`)

Opening another user's profile should show their story ring and let the viewer
open the stories whenever the viewer is allowed to see them, **even without
following them**. Today the client can't do this: `GET /stories` only returns
the caller and the accounts they follow, and `PublicProfileResource` has no
story fields. So the client never learns the story ids of a public account it
doesn't follow.

**Ask:** add `GET /users/{user}/stories` (bearer token, same auth as
`GET /stories`):

- `200 {data: StoryBarGroupResource}`, with the same shape as one group of the
  stories bar (`user`, `has_unseen`, `stories` newest first, up to 10 active
  stories). Return an empty `stories` array (or `data: null`, as long as it is
  documented) when the caller can see none. The existing viewer then works
  unchanged.
- Only active (unexpired) stories the **caller may view**:
  - Public account + story visibility `public` → anyone signed in.
  - Story visibility `followers` → only the author's accepted followers.
  - Private account → only accepted followers, for every story (same as today).
  - The author themselves → all of their own stories.
  - A block in either direction → `403` (or an empty list; please document which).
  - Reshares: the same original-author rules as `GET /stories` (hidden when the
    original author blocks the caller or resharer, or their private account
    hides it).
- `has_seen` per story and `has_unseen` for the group, as in the bar.
- `404` for an unknown user.

Please also confirm that `GET /stories/{story}`, `POST /stories/{story}/view`
and `POST /stories/{story}/replies` accept exactly the same callers, so that
a non-follower opening a public story records a view and can reply. The spec
implies this but doesn't say it outright.

An acceptable lighter alternative is `has_active_story` / `has_unseen_story`
on `PublicProfileResource`, but the client would still need the list above to
open the stories.

**Client today:** the profile ring appears only for the signed-in user and
accounts they follow (from `GET /stories` via `StoriesCubit.groupOf`).

**Client after:** `ProfileScreen` falls back to `GET /users/{user}/stories`
when the user isn't in the stories bar, and shows the ring and opens the
viewer with that group. Views and replies use the existing endpoints, and the
reply bar stays hidden on the user's own stories.

## Chat: delete a message for me only

Long-press → "Delete for me" should remove a message from my side only. The
API's only option is `DELETE /messages/{message}`, which deletes for both
participants and only works for the sender, so it can't be used for someone
else's message or to tidy up my own without unsending it.

**Ask:** add a per-viewer hide, e.g. `POST /messages/{message}/hide` (or
`DELETE /messages/{message}?scope=me`), bearer token:

- Allowed for any participant of the conversation, on any message, mine or
  theirs, including already-deleted placeholders.
- Idempotent: hiding twice is still `200`.
- Responses: `200`, `401`, `404` (not a participant / unknown message, same
  as `/reports`).
- For that viewer only, hidden messages are left out of
  `GET /conversations/{id}/messages` (including `updated_since` syncs) and
  out of the conversation's `last_message` / inbox preview, which falls back
  to the previous visible message, the way delete-for-both already does.
- Optional: a `message.hidden` Reverb event to the viewer's private channel
  so their other devices drop it too.

**Client today:** `ChatHiddenMessages` keeps hidden message IDs on the device
per account (SharedPreferences key `chat_hidden_messages_<userId>`, IDs
only, kept across logout) and `ConversationScreen` filters them out. Gaps:
hidden messages come back on another device or after reinstalling, and the
chat list preview can still show a hidden last message.

**Client after:** "Delete for me" calls the endpoint, then removes the
message from the list. Existing local IDs are sent once in the background
and then the local store is cleared.

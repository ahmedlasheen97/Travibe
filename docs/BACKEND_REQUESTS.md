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

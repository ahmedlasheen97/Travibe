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

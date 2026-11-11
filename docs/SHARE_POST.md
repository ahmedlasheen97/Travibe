# Send Post sharing

## Current behaviour

`SendPostSheet.show(context, post: ...)` opens the Figma "Send Post" sheet. Non-public
posts get a "Only public posts can be shared." SnackBar instead. Callers: Home, Profile
posts, Saved posts, notification post detail.

- Left-aligned title, rounded "Search" field, horizontal people row (suggested people
  when the query is empty, `SearchRepo.searchUsers` for 3–100 characters).
- Tap a person to select (orange check badge), tap again to unselect; multiple allowed.
  Selections survive search changes and stay visible at the front of the row.
- No selection → Copy Link / More Options (left-aligned).
- Any selection → "Write Message" field (≤1000 chars) + full-width orange "Send".
- Send → for each person: `POST /conversations {user_id}` (returns the existing thread or
  creates one) then `POST /conversations/{id}/messages` as `type: text`. All succeed →
  sheet closes, SnackBar "Sent to {name}" / "Sent to N people". Partial failure → sheet
  stays open, sent people are deselected, failed people stay selected with an inline
  error each (403 → "You can't message {name}."), and Send retries only them.

Code: `features/shares/data/share_post_messenger.dart` (send seam),
`cubit/send_post_cubit.dart` (people, selection, send state), `widgets/send_post_sheet.dart`.

The message text is the optional note, a blank line, then
`Shared a post by {author}: “{excerpt ≤280 chars}”` (clamped to 5000 chars).

## Removed

The backend removed `/posts/{post}/shares*` and `PostResource.shares_count`. `SharesRepo`,
`SharesCubit`, `ShareModel` and `SharePostDialog` were deleted, unwired from Root, Home,
Profile, Saved and `PostsCubit`, and `PostModel.sharesCount` was dropped. The PostCard
share button shows no count.

## Backend requirements

### Post card in chat (not supported today)

`StoreMessageRequest.type` only allows `text | image | voice | video`; there is no
post field, and `MessageResource` has no post payload. To render a real post card:

1. Add `MessageType` `post`. Request: `post_id` (required for `post`), optional
   `body` (≤1000) as the note.
2. Validate: post exists and is not deleted; visible to both sender and recipient
   (public, or followers-only and the recipient may see it); no block in either
   direction between sender/recipient or recipient/author → `422`/`403` accordingly.
3. `MessageResource` for `post` messages embeds `shared_post`: `id`, `user {id, name,
   username, avatar_url}`, `content` (excerpt), first media `{type, url, thumbnail_url}`,
   `visibility`, and `is_available` (false once deleted/hidden/blocked — clients show
   "Post unavailable").
4. Send the same shape in the Reverb message event and use a `last_message` preview
   such as "Sent a post".
5. Optional: `POST /posts/{post}/send {user_ids[], body?}` returning per-user results,
   to avoid N×2 round trips.

Client change once shipped: replace the `sendText` call in
`SharePostMessenger._sendOne` with the `post` payload, add `ChatMessageKind.post`
parsing and a post-card bubble. The sheet and cubit need no changes.

### Copy Link (no public URL today)

`PostResource` has no `url`/`share_url`/`slug`, and there is no public web route.

1. A public post page, e.g. `https://travibeapp.com/p/{id}`, that respects visibility,
   returns 404/410 for deleted posts, and serves Open Graph tags.
2. `PostResource.share_url` (null when the post is not shareable).
3. For opening in the app: `apple-app-site-association` and `assetlinks.json` on the
   domain, Associated Domains / intent filters in the app, and a GoRouter route to post
   detail.

Until then, Copy Link shows "Post links aren't available yet." and More Options shares
the post text through the native `travibe/post_sharing` channel (see `PostShareActions`).
A verified `https` URI passed to `PostShareActions` takes precedence automatically.

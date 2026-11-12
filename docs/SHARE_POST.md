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
  creates one), then `POST /conversations/{id}/messages {type: post, post_id}`, then the
  optional note as a separate `type: text` message. All succeed → sheet closes, SnackBar
  "Sent to {name}" / "Sent to N people". Partial failure → sheet stays open, sent people
  are deselected, failed people stay selected with an inline error each (403 → "You can't
  message {name}.", 422 → "{name} can't see this post."), and Send retries only them. If
  the post sends but the note fails, the person counts as sent (no duplicate post on
  retry) and the SnackBar adds "Your message didn't send to {name}."
- Copy Link copies `PostModel.shareUri` (`PostResource.url`, falling back to
  `https://travibeapp.com/p/{id}`) and shows "Link copied". More Options shares the same
  URL through the native `travibe/post_sharing` channel (`PostShareActions`).

Code: `features/shares/data/share_post_messenger.dart` (send seam),
`cubit/send_post_cubit.dart` (people, selection, send state), `widgets/send_post_sheet.dart`.

## Post messages in chat

- `ChatMessageKind.post`; `ChatMessage.postId` + `ChatMessage.sharedPost`
  (`ChatSharedPost`, from `SharedPostResource`), same on `ChatLastMessage`.
- Bubble: `widgets/chat_post_card.dart` — author, first image, 3-line excerpt; tap opens
  the post via `shares/screens/open_shared_post.dart` (reuses
  `NotificationTargetsRepository` + `PostScreen`). `post == null` with a
  `post_id` → "Post unavailable", not tappable.
- Inbox preview: "Shared a post".
- `updated_since` re-delivers a post message when its card changes;
  `reconcileChatMessage` keeps the incoming card.

## Deep links

`travibe://posts/{id}` (the backend redirects `https://travibeapp.com/p/{id}` there) and
`travibe://users/{id}` (profile `url`) are registered in `Info.plist` (`CFBundleURLTypes`,
scheme-level) and the Android manifest (hosts `posts` and `users`). In these URIs
`posts`/`users` is the **host**, not the path (`Uri.parse('travibe://users/42').host ==
'users'`, `pathSegments == ['42']`). Flutter's default deep linking is disabled so links
never reach GoRouter.

`app_links` feeds `core/deeplinks/deep_links.dart`: `parseDeepLink` → `PostLink`/`UserLink`;
`DeepLinkCoordinator` keeps the latest link until `Root` attaches with a session (cold
start, background, or after login), then `openDeepLink` dispatches:

- post → `openSharedPost` (`shares/screens/open_shared_post.dart`).
- user → `openSharedProfile` (`profile/screens/open_shared_profile.dart`): the signed-in
  user's own id (current user, or `is_me` from the response) switches Root to the Profile
  tab; otherwise `GET /users/{id}` — `data: null` (blocked), 404/any error, or a user the
  viewer blocked → SnackBar "This profile is unavailable."; else `ProfileScreen.open`.

Root attaches with a context below its `MultiBlocProvider`, so opened screens share the
app-wide Follow/Block/Likes/Saves cubits.

Manual test: `xcrun simctl openurl booted "travibe://users/1"` /
`adb shell am start -a android.intent.action.VIEW -d "travibe://users/1"`.
Universal links / App Links still need `apple-app-site-association` / `assetlinks.json` on
the backend (send iOS Team ID + bundle ID, Android package + release SHA-256).

## Removed

The backend removed `/posts/{post}/shares*` and `PostResource.shares_count`. `SharesRepo`,
`SharesCubit`, `ShareModel` and `SharePostDialog` were deleted, unwired from Root, Home,
Profile, Saved and `PostsCubit`, and `PostModel.sharesCount` was dropped. The PostCard
share button shows no count.

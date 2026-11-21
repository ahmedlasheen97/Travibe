# Story replies

Backend note: `docs/backend/STORY_REPLIES.md`. Contract: `POST /stories/{story}/replies`
(`StoreStoryReplyRequest`), `MessageResource.story` (`SharedStoryResource`) and
`story_expires_at` in `docs/openapi.json`.

## Sending

- Story viewer (other people's stories): `StoryReplyComposer` → `onSend` →
  `_sendReply` in `story_viewer_screen.dart` → `StoriesRepo.reply(id, text)`.
- Text only (`type: text`, trimmed `body`, max 5000). The API also takes image, voice
  and video replies; the viewer has no attachment UI for them yet.
- The request carries `sessionRevision`, so a reply from a previous account is cancelled.
- Success (201 only): field clears and unfocuses, toast "Reply sent". Failure: text stays,
  error toast — 403 "You can't reply to this story.", 404 "This story is no longer
  available.", otherwise "Unable to send your reply. Please try again." No automatic retry.
- The story stays paused while typing (`reply`) and while the request runs (`reply-send`).

## Chat

- `ChatMessage.story` (`ChatSharedStory`) and `ChatMessage.storyExpiresAt`, same on
  `ChatLastMessage`. A non-null `storyExpiresAt` marks a story reply.
- Bubble header (`_storyReplyHeader` in `chat_widgets.dart`), from `storyReplyLabel`:
  - story owner (incoming): "Replied to your story"
  - replier (outgoing): "You replied to their story"
  - either side, when `story` is null or `story_expires_at` has passed: "Story unavailable"
  The thumbnail shows only while the story is available.
- Expiry doesn't touch the message, so `ConversationScreen` keeps one timer for the
  earliest future `story_expires_at` among loaded story replies and rebuilds when it fires
  (`_scheduleStoryExpiry`); no polling. `ConversationScreen.now` injects the clock.
- Tapping the thumbnail: `openSharedStory` (`stories/screens/open_shared_story.dart`)
  loads `GET /stories/{id}` fresh, then opens the same single-story viewer notifications
  use (`storyViewerDestination` in `notification_navigation.dart`). 403/404, an expired
  story or a blocked author → "Story unavailable" toast, and the screen marks that story
  gone so the bubble shows "Story unavailable". Offline/timeouts only show the error.
  The thumbnail ignores the image's own retry tap so a tap always opens the story.
- Inbox preview: "Replied to your story" / "You replied to their story" by sender.
- `reconcileChatMessage` and the `messages.read` copy keep both fields.

## Notifications

- Story replies are `message_received` (opens the chat). With `data.is_story_reply`,
  the in-app row reads "replied to your story" (only requests are listed in the inbox).
- Push text comes from the backend (its `preview` starts with "Replied to your story");
  the client does not build push text.

## Not done

- Photo, voice and video replies (the API accepts them; the viewer has no attachment UI).
- The header styling is not from Figma; there is no story-reply frame in `docs/figma`.

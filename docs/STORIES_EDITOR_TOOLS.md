# Story editor tools: Mention, Emoji, Draw

Branch `story-editor-tools`. Figma: `docs/figma/stories/story_editor_figma.png`.
The right-side tool column is now **Aa, @, ☺, ✏️** (same 44px translucent
`0xCC45433B` circles; the @ uses `assets/images/icons/mention_glyph.svg`).
Location was removed on purpose.

## API contract (docs/backend/STORY_MENTION_IDS.md)

`POST /stories` stores `elements` verbatim. Text comes back exactly as sent,
including spaces and empty strings. The API parses `@username` from the
`text`/`content` of `type: text` elements, and also takes
`mention_user_ids`: distinct user ids, at most 10. If any id is invalid or
duplicated, the request fails with 422. Mentioned users get the "mentioned
you in a story" notification under the normal visibility rules.

A private account can be mentioned only by its accepted followers. The
server silently drops anyone else (no error), and mention suggestions
(`GET /mentions/suggestions`) already leave them out.
`StoryDetailResource.mentions` returns `[{handle, user: {id, username}}]` for
the mentions that were kept, without blocked users.

## Two kinds of mention

1. **@ tool: hidden mention.** The Mention sheet (Figma `mention_sheet.png`)
   picks people. Nothing is drawn on the story. The people picked
   (`StoryEditorDraft.mentions`, at most 10, deduped by id) are sent as
   `mention_user_ids` (`CreateStoryRequest.mentionIds`). No element is
   created for them. The @ button shows an orange count badge, and its tooltip
   lists the usernames. Reopening the sheet shows them checked; anyone picked
   who isn't in the suggestions is listed at the top.
2. **Aa text.** Typing `@` in a text opens suggestions (Figma
   `mention_typing.png`). The chosen `@username` is inserted and drawn in
   orange inside the text bubble. The API reads it from the element's `text`.

The Mention sheet shows "People you mention can reshare this story" (default
on) right above Add, and the inline suggestions show it under the list. Both
set the same `StoryEditorDraft.allowReshare`. The toggle is shown **only** for
a `public` story from a public account (`CurrentUserCubit` profile
`is_private == false`; unknown counts as private). It is then sent as
`allow_mention_reshare: true`; otherwise the key is omitted, because the API
returns 422 for `true` on any other story.

## Reshare (docs/backend/STORY_RESHARE.md)

- Viewer: the orange Reshare pill shows only when `can_reshare` is true. A tap
  calls `POST /stories/{id}/reshare` (no body, so the API default `public`;
  a private account sends `visibility: followers`). Success shows the green
  "Story reshared" toast, hides the button and refreshes the stories bar.
  Already reshared (422 `story`), not allowed (403) and expired (404) show a
  red toast and hide the button. The story limit (422 `stories`) shows the
  server message.
- A reshare (`reshared_from` not null) shows "12h • reshared from @user" in
  the header. A tap opens that user's profile. `reshared_from.story_id` may be
  null (the original expired), so it never links to the source story.
- A reshare's `mentions` is empty: `@names` in its text are plain white,
  not tappable. The legacy hidden-mention element is still skipped by
  `decode`.
- Notification `story_reshared` ("X reshared your story.", portrait
  thumbnail) opens the reshare from `target_id`. A story that is gone shows
  "This story is no longer available."

## Element shapes

- **Text**: a v1 text element. Its look is the Figma text bubble: white text in
  a dark translucent rounded bubble (the header pill's glass), with
  `@username` in orange. Editor and viewer render it the same way.
- **Legacy hidden mentions** (stories from builds before
  `mention_user_ids`): one extra v1 text element with id `story-mentions`,
  `text: "\u200B"`, and `content: "@sara @omar"`. The API now returns its
  `text` exactly as sent (`"\u200B"`; stories saved earlier may have
  `null`). `decode` skips it by id, whatever its text, so no `@username` is
  ever drawn. This build never sends it.
- **Exact text**: element text is drawn as sent. A text that is empty or
  only whitespace or zero-width characters draws no bubble. Leading and
  trailing spaces are drawn where they are. `StoryTextGeometry` swaps
  line-end spaces for no-break spaces at render time (same length, so
  mention offsets still line up), because text layout would otherwise
  "hang" them.
- **Stickers from earlier builds** (`text: "@sara"` with `mention` metadata)
  decode as ordinary text, so they show as a text bubble with an orange
  `@sara`. Rotation is dropped.
- **Emoji and drawings** are never sent as elements. They are flattened into
  the photo.

## Export and upload (see also "Background upload")

- **Every** Story uploads a JPEG at quality 85 (`widgets/story_image_exporter.dart`),
  never a PNG and never the raw original. The exporter crops to the editor
  view (the `BoxFit.cover` area the user saw), fits the result within
  1080×1920 and never upscales.
- Without drawings or emojis, nothing is drawn: the photo is only cropped and
  compressed. With them, strokes and emojis are baked in using the editor's
  geometry. Text and mentions are never flattened; they stay elements.
- Threads: the engine decodes the photo already downsampled (on the IO
  thread), the raster thread renders, and `encodeStoryJpeg` runs in a
  `compute()` isolate. The UI thread only records a small picture.
- The exported bytes are cached per draft, so a retry uploads the same bytes
  and the media service can resume instead of sending them again.

## Background upload

- Post closes the editor right away (`StoryEditorScreen.onSubmit` →
  `StoryUploadCubit`, which Root owns). Root shows the shared floating toast:
  "Uploading your story" with a progress ring, then green "Story published
  successfully", or red "Couldn't publish your story" with Retry and X (X
  discards the story).
- No duplicates: if `POST /stories` times out, `StoriesRepo.findStoryByMedia`
  checks read-only first (`GET /media/{id}` `mediable_*`, then the caller's
  own active stories). If the story exists, that counts as success. If the
  check fails, the client stays uncertain and does not POST again. It posts
  again only after confirming no story was created, and even then the API
  rejects media that is already attached.
- The storage PUT `sendTimeout` scales with size: `storageSendTimeout`, 30 s
  plus 32 KB/s, clamped to 60 s–10 min. Dio's `sendTimeout` covers the whole
  request body, so the old fixed 60 s failed large files on slow uplinks.
- Users only ever see plain wording. The "upload result is uncertain…" text
  never reaches the story UI.

## Mention results

- **Dropped mentions**: after posting, `StoryUploadCubit` compares the
  `mention_user_ids` it sent with the returned `mentions` ids. If any are
  missing (e.g. a private account the author doesn't follow), Root shows the
  info toast "Some people couldn't be mentioned" instead of the green
  success toast. Typed Aa `@handles` aren't compared, because they can be
  any text.
- **422 on `mention_user_ids`** (any `mention_user_ids` / `mention_user_ids.N`
  field error): the story isn't created and the photo is already uploaded.
  The red toast reads "Couldn't mention some people" and offers
  **Post anyway**, which POSTs the same `media_ids` without
  `mention_user_ids` (no re-export or re-upload), and X, which discards.
  Other 422s keep the normal Retry.

## Interaction

- Emoji stickers can be dragged, pinched to scale and twisted to rotate. Text
  bubbles drag and scale but stay unrotated. Drop one on the trash target to
  delete it. Tapping text edits it.
- Draw mode hides the tools, audience and Post. It shows Undo and Done, a
  7-colour palette and a 2–24px brush slider. The stroke in progress stays local
  until the finger lifts.
- Caps: 50 text elements, 30 emojis, 10 people in the Mention sheet
  (hidden mentions don't count as elements).
- In the viewer, tapping an `@username` inside a text bubble that resolves
  through `detail.mentions` pauses the story. It then shows the "View profile"
  card (Figma `mention_view_profile.png`) under the bubble, with a small
  pointer at the username; "View profile" opens `ProfileScreen.open`. If the
  bubble is too close to the bottom, the card goes above it instead. A tap
  elsewhere closes the card and resumes. A tap on an unresolved mention, or on
  ordinary words, works as a normal previous/next tap. Hidden mentions show
  nothing in the viewer.

## Known limitation

The server's maximum image size isn't documented in `openapi.json`. It has
been requested in `docs/BACKEND_REQUESTS.md`.

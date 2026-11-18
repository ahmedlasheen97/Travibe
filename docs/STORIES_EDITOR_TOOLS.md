# Story editor tools: Mention, Emoji, Draw

Branch `story-editor-tools`. Figma: `docs/figma/stories/story_editor_figma.png`.
The right-side tool column is now **Aa, @, ☺, ✏️** (same 44px translucent
`0xCC45433B` circles; the @ uses `assets/images/icons/mention_glyph.svg`).
Location was removed on purpose.

## API contract (no backend change needed)

`POST /stories` stores `elements` verbatim and parses `@username` from `text`
/ `content` of `type: text` elements. Mentioned users get the "mentioned you in
a story" notification under the normal visibility rules. The server stores up
to 10 distinct mentions per story. `StoryDetailResource.mentions` returns
`[{handle, user: {id, username}}]`, with blocked users left out. The API takes
no separate user ids.

## Two kinds of mention

1. **@ tool: hidden mention.** The Mention sheet (Figma `mention_sheet.png`)
   picks people. Nothing is drawn on the story. The people picked
   (`StoryEditorDraft.mentions`, at most 10) are sent so they are mentioned
   and notified. The @ button shows an orange count badge, and its tooltip
   lists the usernames. Reopening the sheet shows them checked; anyone picked
   who isn't in the suggestions is listed at the top.
2. **Aa text.** Typing `@` in a text opens suggestions (Figma
   `mention_typing.png`). The chosen `@username` is inserted and drawn in
   orange inside the text bubble. The API reads it from the element's `text`.

The Mention sheet shows "People you mention can reshare this story" (default
on) right above Add, and the inline suggestions show it under the list. Both
set the same `StoryEditorDraft.allowReshare`. It is only sent as
`allow_reshare` once `kEnableStoryReshare` is on (the API doesn't support it
yet; see `docs/BACKEND_REQUESTS.md`).

## Element shapes

- **Text**: a v1 text element. Its look is the Figma text bubble: white text in
  a dark translucent rounded bubble (the header pill's glass), with
  `@username` in orange. Editor and viewer render it the same way.
- **Hidden mentions**: one extra v1 text element with the **identical** v1
  `style`:

```json
{ "version": 1, "id": "story-mentions", "type": "text",
  "text": "\u200B", "content": "@sara @omar",
  "position": {"x": 0.5, "y": 0.5}, "scale": 1, "style": { …v1… },
  "mentions": [{"user_id": 5, "username": "sara"},
               {"user_id": 7, "username": "omar"}] }
```

  The API reads `content`, so these users are mentioned. `text` is a
  zero-width space (U+200B). It is not whitespace to `String.trim`, so older
  app builds accept the element, and they draw nothing for it. They ignore
  `content` and `mentions`. This build's `decode` skips the element.
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

## Interaction

- Emoji stickers can be dragged, pinched to scale and twisted to rotate. Text
  bubbles drag and scale but stay unrotated. Drop one on the trash target to
  delete it. Tapping text edits it.
- Draw mode hides the tools, audience and Post. It shows Undo and Done, a
  7-colour palette and a 2–24px brush slider. The stroke in progress stays local
  until the finger lifts.
- Caps: 50 elements (text, plus one for hidden mentions), 30 emojis, 10
  people in the Mention sheet.
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

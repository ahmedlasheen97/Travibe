# Story editor tools: Mention, Emoji, Draw

Branch `story-editor-tools`. Figma: `docs/figma/stories/story_editor_figma.png`.
The right-side tool column is now **Aa, @, ☺, ✏️** (same 44px translucent
`0xCC45433B` circles). Location was removed on purpose.

## API contract (no backend change needed)

`POST /stories` stores `elements` verbatim and parses `@username` from `text`
/ `content` of `type: text` elements. Mentioned users are notified under the
normal visibility rules. `StoryDetailResource.mentions` returns
`[{handle, user: {id, username}}]`, with blocked users left out. The API does not
take separate user ids or mention positions. The element's own `position` is
the sticker position.

## Element shapes

- **Text**: unchanged v1 element.
- **Mention**: a v1 text element with the **identical** v1 `style` plus extra keys:

```json
{ "version": 1, "id": "story-mention-1", "type": "text", "text": "@sara",
  "position": {"x": 0.3, "y": 0.6}, "scale": 1.5, "style": { …v1… },
  "rotation": 0.25,
  "mention": {"user_id": 5, "username": "sara", "style": "light|dark|brand|plain"} }
```

  Older app builds ignore the extra keys and render a plain white `@sara`. They
  do not reject the whole Story, because `decode` still requires the exact v1
  style. If the mention metadata doesn't match the text, the element decodes as
  plain text.
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

- Stickers (mention and emoji) can be dragged, pinched to scale and twisted to
  rotate. Drop one on the trash target to delete it. Text stays unrotated, as
  before.
- Tapping a mention cycles its style. Tapping text edits it. Tapping an emoji
  does nothing.
- Draw mode hides the tools, audience and Post. It shows Undo and Done, a
  7-colour palette and a 2–24px brush slider. The stroke in progress stays local
  until the finger lifts.
- Caps: 50 elements (text and mentions), 30 emojis.
- In the viewer, a tap on a mention that resolves through `detail.mentions`
  opens `ProfileScreen.open`. A tap on an unresolved mention works as a normal
  previous/next tap.

## Known limitation

The server's maximum image size isn't documented in `openapi.json`. It has
been requested in `docs/BACKEND_REQUESTS.md`.

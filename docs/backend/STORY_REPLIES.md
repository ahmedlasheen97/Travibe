Hi! Story replies are now on the API 👋

A user can reply to a story from the story viewer. The reply goes to chat as a normal message to the story owner.

Where to look in the API docs (/docs/api):
•  New endpoint: POST /stories/{story}/replies (same body as a normal text/photo/voice/video message). It returns the message with its conversation_id.
•  Messages now have story (a small card with a thumbnail) and story_expires_at. If story_expires_at is set, show "Replied to your story". If story is null, or the expiry time has passed, show "Story unavailable".
•  The chat section in the docs has a short "Story replies" note.

Tell me if anything is unclear 🙏

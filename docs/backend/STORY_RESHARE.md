Hi, the story reshare backend is live ✅

Please check the API docs at /docs/api:
•  Stories: POST /stories, GET /stories/{story}, POST /stories/{story}/reshare
•  Notifications: story_reshared

What you need to add:

1. Add Story screen
Add the "People you mention can reshare this story" toggle and send it as allow_mention_reshare.
Show it only for a public story from a public account. Otherwise the API returns 422.

2. Story viewer
Show the Reshare button only when can_reshare is true.
On tap, call POST /stories/{story}/reshare. You can send visibility, and the default is public.

3. Reshared story
If reshared_from is not null, show "reshared from" with reshared_from.user.
reshared_from.story_id can be null after the original story expires.

4. Notification
Handle story_reshared and open the story using target_id.

Note: mentions is empty on a reshared story, so show @names in its text as plain text.

Tell me if anything is not clear 🙏

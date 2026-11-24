Hi! The endpoint for a user's stories is live now:
GET /api/v1/users/{user}/stories
It returns that user's active stories, newest first, in the same format as the stories in the bar. To open a story, use GET /stories/{story} as usual.
Full docs are at /docs/api.

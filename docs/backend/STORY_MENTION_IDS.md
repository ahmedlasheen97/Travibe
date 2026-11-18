Hi 👋 The story mention update is live on the server, and the API docs are updated.

POST /stories now accepts mention_user_ids (array of user IDs), so you can mention people without the hidden text element.

Please check:
1. Stories created with the current hidden element: text now comes back as "\u200B" instead of null. Make sure @username does not appear on the story.
2. Switch to mention_user_ids and remove the hidden element. Invalid or duplicate IDs return 422, and the max is 10.
3. Text in elements now comes back exactly as sent, including spaces and empty strings. Make sure rendering is OK.
4. Private accounts can now be mentioned only by their accepted followers. Other mentions are dropped with no error, and these accounts no longer appear in mention suggestions.

Tell me if anything looks wrong 🙏

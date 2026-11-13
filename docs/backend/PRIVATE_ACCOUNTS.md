Hey 👋 Private accounts are live on travibeapp.com (develop) 🔒

Settings
•  PATCH /api/v1/settings now takes  is_private  (true/false)
•  Switching back to public auto-accepts all pending requests

Follow button – 3 states
•   is_following: true  → Following
•   follow_requested: true  → Requested
•  both false → Follow
•  POST /users/{id}/follow on a private account returns 201 with  follow_requested: true 
•  POST /users/{id}/unfollow also cancels a pending request

Follow requests (new)
•  GET /api/v1/follow-requests → list (paginated)
•  POST /api/v1/follow-requests/{user}/accept
•  DELETE /api/v1/follow-requests/{user} → decline

Profile
•  New  is_private  and  can_view_content  fields
•  If  can_view_content  is false, show the locked "This account is private" screen
•  Followers/following lists on a locked account return 403

Notifications (new types)
•   follow_requested  → someone requested to follow you
•   follow_request_accepted  → your request was accepted

Full schemas are in /docs/api 👍

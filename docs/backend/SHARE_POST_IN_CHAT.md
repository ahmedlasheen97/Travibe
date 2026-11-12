# Mobile brief: share posts in chat

## What shipped

The 1:1 chat API now supports a  post  message type. A user can send a post into a chat and open it. This is live on  https://travibeapp.com .

## Send a post message

 POST /api/v1/conversations/{conversation}/messages 

 json
{
  "type": "post",
  "post_id": 4
}
 

Rules:

•   type  accepts  text ,  image ,  voice ,  video , and the new  post .
•   post_id  is required for  type: post . It is not allowed for other types.
•   body ,  media_id ,  poster_media_id  and  duration_ms  are not allowed for  type: post .
•  The post must be visible to both participants and not blocked from either. Otherwise the API returns  422  with a  post_id  validation error.
•  The response is  201  with a  MessageResource .

## Message payload

Every live message now carries  post_id  and  post . Both are always present.

•   post_id : the shared post ID, or  null .
•   post : a compact card, or  null .

The card has these fields:

| Field | Note |
| --- | --- |
|  id  | Post ID |
|  user  | Author,  PublicUserResource  shape |
|  content  | Post text, or  null  |
|  media  | Images,  PublicMediaResource  list |
|  url  | Share link,  https://travibeapp.com/p/{id}  |
|  created_at  | ISO 8601 UTC |

 post  is  null  when the post is deleted, or when the viewer may no longer open it.  post_id  stays. Show the message as unavailable in that case.

## Inbox

 GET /api/v1/conversations  and  GET /api/v1/conversations/{conversation}  now return the same card on  last_message . Render the post preview from  last_message.post .

## Realtime

 message.sent  carries the same  MessageResource , including the card. No change to your append logic.

## Incremental fetch

 GET /conversations/{conversation}/messages?updated_since=  returns a shared post again when its card changes: edit, visibility change, delete, restore, follow change, block, unblock, or author account deletion. Replace the message you already have.

## Share link and deep link

•  Every post payload has  url , an HTTPS link on  https://travibeapp.com .
•  A browser that opens  https://travibeapp.com/p/{id}  receives  302  to  travibe://posts/{id} .
•  The app must register the  travibe  scheme and handle  travibe://posts/{id} .
•  A soft-deleted or unknown post returns  404 .
•  The redirect does not check visibility. The app applies the normal visibility and block rules when it fetches the post with  GET /api/v1/posts/{id} .

## Notifications and push

•  The in-app notification  data.preview  is  Shared a post .
•  The push  data.preview_excerpt  is localized:  Shared a post  in English,  شارك منشورًا  in Arabic.

## Client work

1. Accept  post  in the message type enum.
2. Render the post card from  post , and an unavailable state when  post  is null but  post_id  is set.
3. Send  type: post  with  post_id .
4. Add a "share to chat" action that picks a conversation.
5. Use  url  for the external share sheet.
6. Register the  travibe  scheme and route  travibe://posts/{id}  to the post screen.

## Note

The redirect to a custom scheme works best when the app is installed. Universal links for  https://travibeapp.com/p/{id}  need  /.well-known/apple-app-site-association  and  /.well-known/assetlinks.json . Those files are not served yet. Send me the Apple team ID and the Android signing SHA-256 if you want them added.

Hey, profile share links are live 🎉

Sharing: use the  url  field as-is, don't build the link in the app.
•  Other profiles:  GET /api/v1/users/{id}  →  data.url 
•  Own profile:  GET /api/v1/profile  and  GET /api/v1/user  (also on login/register/profile update)

Opening: the link opens the app via  travibe://users/{id}  → fetch  GET /api/v1/users/{id} . If  data  is null (blocked) or it's a 404, show unavailable.
Heads up: in  travibe://users/42 , "users" is the URL host, not the path.

Test:  xcrun simctl openurl booted "travibe://users/1"  or  adb shell am start -a android.intent.action.VIEW -d "travibe://users/1" 

If you want links to open the app directly (no Safari prompt, works in Instagram/WhatsApp in-app browsers), send me the iOS Team ID + bundle ID and the Android package name + release SHA-256 fingerprint, and I'll set up Universal Links / App Links.

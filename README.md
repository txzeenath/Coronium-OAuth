# Coronium-OAuth


A coronium plugin to allow secure social logins to your website or app.


Currently supports Google,Facebook and GitHub.

---

Just some rough notes (these should be easily adaptable to work outside of the corona module):

---

###Request a login URL:
#####Service is the service's name in all lowercase
#####UUID and sessionID are for users who are already logged in (account linking). They can be nil for a fresh login.
#####For scopes see your selected service for valid scopes. If this is nil, defaults are used
```lua
local req = cloud:request('/OAuth/requestAccessUrl',{service=service,scopes=scopes,uuid=OAuth.UUID,sessionID=OAuth.sessionID},listener)
```

###Parse URL to get "state" parameter. This is your request key
```lua
local reqKey = OAuth.parseurl(evt.response.url,"state")
```

###Open URL
```lua
system.openURL( evt.response.url ) 
```
###Poll for login status (I use a 2s timer for this)
######Returns 0 for waiting, -1 for error/failed, and 1 for success
```lua
local req = cloud:request('/OAuth/waitForAuth',{reqKey=reqKey},listener) --and wait
```
###On success, grab your sessionID and UUID from the reply
```lua
if evt.response.status == 1 then
  OAuth.sessionID = evt.response.sessionID
  OAuth.UUID = evt.response.uuid
end
```


######All requests are done as POST besides the redirect that the service sends.

######In the "service" directory, client IDs and secrets must be filled out and valid.
######In api.lua you must pass a full connection table to OAuthLib.conTab
######In api.lua you must define a table prefix
######In api.lua you must define a valid database name (which already exists)

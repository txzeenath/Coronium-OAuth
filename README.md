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

---
#Crappy docs below
---

```lua
function api.post.getServiceList(input)
```
#####Inputs:   
None
#####Returns:   
A table of services from api.lua

---
```lua
function api.post.requestAccessUrl( input )
```
For retrieving a login URL for a service
#####Inputs:   
service - (service to grab URL for) - string  
uuid - (current user's UUID) - string  
sessionID - (current user's sessionID) - string  

#####Returns:   
url - (url to login with) - string  

---
```lua
function api.get.redirect(input)
```
Login service redirect endpoint.
#####Inputs:   
None
#####Returns:   
None

---
```lua
function api.post.waitForAuth(input)
```
For polling login status
#####Inputs:  
reqKey (request key) - string
#####Returns:  
status (-1 fail,0 waiting,1 success) - int  
service (service name) - string  
error (error) - string  

---
```lua
function api.post.checkAccess(input)
```
For checking access of user against their sessionID (secures the profile to a single login point, even if the UUID is 'leaked')
#####Inputs:  
uuid - (user's UUID) - string  
sessionID - (user's sessionID) - string  
#####Returns:  
status (-1 fail,1 success) - int  
service (always "Unknown") - string  
error = (error) - string  

---
```lua
function api.post.getList( input )
```
For getting a list of services and scopes for user
#####Inputs:  
uuid - (user's UUID) - string  
sessionID - (user's sessionID) - string  
#####Returns:  
status (-1 fail,1 success) - int  
service (key/value pairs of scopes) - table  
error (error) - string  

---
```lua
function api.post.deleteProfile( input )
```
Deletes all auth data for user
#####Inputs:  
uuid - (user's UUID) - string  
sessionID - (user's sessionID) - string  
#####Returns:  
status (-1 fail,1 success) - int  
service (array of removed services) - table  
error (error) - string

---
```lua
function api.post.removeLink( input )
```
Removes a service from user's profile
#####Inputs:  
uuid - (user's UUID) - string  
sessionID - (user's sessionID) - string  
service - (service name) - string  
#####Returns:
status (-1 fail,1 success) - int  
service (name of service) - string  
error (error) - string  


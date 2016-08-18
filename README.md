# Coronium-OAuth


A coronium plugin to allow secure social logins to your website or app.


Currently supports Google,Facebook and GitHub.

---
#Crappy docs below
---

```lua
function api.post.getServiceList(input)
```
#####Inputs:   
None
#####Returns:   
A table of supported services.

---
```lua
function api.post.requestAccessUrl( input )
```
For retrieving a login URL for a service
#####Inputs:   
service - (service to grab URL for) - string  
sessionID - (current user's sessionID) - string  
scopes - (service specific scopes) - string

#####Returns:   
url - (url to login with) - string  
reqKey - (request key) - string

---
```lua
function api.get.redirect(input)
```
Login service redirect endpoint.
#####Inputs:   
None
#####Returns:   
HTML confirmation message

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
newUser (new user?) - boolean
error (error) - string  

---
```lua
function api.post.getList( input )
```
For getting a list of services and scopes for user
#####Inputs:  
sessionID - (user's sessionID) - string  
#####Returns:  
status (-1 fail,1 success) - int  
service (key/value pairs of scopes) - table  
error (error) - string  

---
```lua
function api.post.removeLink( input )
```
Removes a service from user's profile
#####Inputs:  
sessionID - (user's sessionID) - string  
service - (service name) - string  
#####Returns:
status (-1 fail,1 success) - int  
service (name of service) - string  
error (error) - string  


---
You can hook into the OAuth database using the OAuthLib.mDB function.
This can be used for reading or writing keys.
```lua
    local function getUUID(sessionID)
      local db = OAuth.mDB()
      res,err = db.users:find_one({sessionID=sessionID})
      if err then return nil,"Access denied" end
      return res.UUID
    end
```
######Valid keys:   
OAuthID - Unique ID tied to a service   
service - service name for the login entry   
UUID - unique internal ID   
active - access token for service   
expires - expiration time for token   
scopes - space delimited scope list for service   
sessionID - unique ID issued per login   

######Users will have a seperate entry per login method. You can uniquely identify users by:   
service + OAuthID - unique login from service   
sessionID (preferred) - unique ID issued per login   
UUID - unique permanent user ID   

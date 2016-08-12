--===========================================================================--
--== Coronium LS
--===========================================================================--
local api = cloud.api()
local debugging = false
local OAuthLib = require("OAuth.OAuthLib")
-----------------------------------------------------------------------------------------
--Parameters
-----------------------------------------------------------------------------------------
OAuthLib.supported_services = {google=true,facebook=true,github=true,slack=false,foursquare=false,dropbox=false,twitter=false} -- must match with service module name
OAuthLib.tablePrefix = "TESTF" -- Must not be nil. This is the prefix for all tables created and read by this API
OAuthLib.makeTables = true --Automatically make tables if they're missing. This can be turned off after the first execution except when adding new services.
OAuthLib.conTab = require("tinywar-DBController.dbParams").conTab() -- This an instance of a MySql parameter table. You can just put a normal table here.
OAuthLib.conTab['database'] = 'REG_TINYWAR'
OAuthLib.init()
--===========================================================================--
--== Routing Methods
--===========================================================================--
function api.post.getServiceList(input)
  return OAuthLib.supported_services
end

local function debug(string)
  if debugging == true then cloud.log(string) end
end

--Provide user with URL to get an access code
function api.post.requestAccessUrl( input )
  debug("User requesting access URL")
  local service = input.service
  if not service then return {error="Service must be specified"} end
  if not OAuthLib.supported_services[service] then return {status=-1,service=service,error="Unsupported service: " .. service} end
  local URL,err = nil,nil,nil

  URL,err = OAuthLib.makeAccessUrl(service,input.sessionID,input.scopes)
  if err then 
    cloud.log(err)
    return {status=-1,service=service,error="Failed to generate URL"}
  end

  return {status=0,service=service,url=URL}
end

--We need to make sure to update status code here,
--as our client app is not listening to this function.
--However, the redirect page will display anything we return
--here. So care must be taken not to return any critical data.
--
--Endpoint for our redirect request
function api.get.redirect(input)
  if not input or not next(input) then return {status=-1,service="Unknown",error="No Input"} end
  if input["error"] then return input end --If request has an error bounce it back

  --Grab parameters out of response
  local code = input["code"]
  local reqKey = input["state"]
  local res,err = OAuthLib.processRedirect(reqKey,code)
  if err then
    cloud.log(err)
    return {status=-1,service="Unknown",error="Bad request"}
  end

  return "Welcome! Authentication Complete. You can now close this page."
end

-- -1 = failed, try again
--  0 = waiting
--  1 = success
function api.post.waitForAuth(input)
  debug("Client requesting status")
  --Check for a bad request
  if not input or not next(input) then return {status=-1,service="Unknown",error="No Input"} end
  if input["error"] then return input end --Input already has an error message for some reason. bounce it back.
  local reqKey = input.reqKey
  if not reqKey then return {status=-1,service="Unknown",error="No reqKey provided"} end

  local status,service,err,sessionID = OAuthLib.checkAuthStatus(reqKey)
  if err then
    cloud.log(err)
    return {status=-1,service=(service or "Unknown"),error="Error checking status"}
  end

  return {status=status,service=service,error=nil,sessionID=sessionID} --Otherwise report the status
end

---------------------------------------------------------------------------------------------------
--- User management/Protected functions - These require a matching session ID
--------------------------------------------------------------------------------------------------
function api.post.exampleGetProfile( input )
  --[[These params are needed to get our token]]--
  local service = input.service
  local sessionID = input.sessionID
  if not service or not sessionID then return {error = "Missing parameters"} end
  --[[----------------------------------------]]--
  
  local token = OAuthLib.userToken(sessionID,service) --Get token
  if not token then return {status=-1,service=service,error="Access denied"} end
  
  --[[------Build network request-------------]]--
  local servNet = cloud.network.new("www.googleapis.com",443)
  servNet:method(cloud.GET)
  servNet:ssl_verify(true)
  servNet:path("/oauth2/v2/userinfo")
  servNet:keep_alive(5000,10)
  servNet:headers({
      ['Content-Type'] = 'application/json',
      ['Authorization'] = 'Bearer '..token, --<--- Insert user's token
      ['Accept'] = 'application/json'
    })

  local res,err = servNet:result() --<-- Get result
  if err or not res then return {error = "Could not get profile"} end --<-- Catch errors
  res = cloud.decode.json(res)--Force to table.
  return res --<--- Respond
end

function api.post.getList( input )
  local sessionID = input.sessionID
  if not sessionID then return {status=-1,service="Unknown",error="Access denied"} end
  local res,err = OAuthLib.getUser(nil,sessionID)
  local UUID = res[1]['UUID']
  if err or not UUID then 
    cloud.log(err) 
    return {status=-1,service="Unknown",error="Access denied for session"} 
  end
  debug("Getting user's authorization list")

  res,err = OAuthLib.getKeys(UUID,nil,nil,10,"SERVICE,SCOPES")
  if err then return {status=-1,service="Unknown",error="Failed to get keys"} end
  local service = {}
  for i=1,#res do
    service[i] = {res[i]['SERVICE'],res[i]['SCOPES']}
  end

  if not next(service) then return {status=-1,service="Unknown",error="No authorizations found"} end

  return {status=1,service=service,error=nil}
end


function api.post.deleteProfile( input )
  local sessionID = input.sessionID
  if not sessionID then return {status=-1,service="Unknown",error="Access denied"} end
  local res,err = OAuthLib.getUser(nil,sessionID)
  if err then cloud.log(err); return {status=-1,service="Unknown",error="Access denied for session"} end
  local UUID = res[1]['UUID']
  if not UUID then return {status=-1,service="Unknown",error="No user found"} end
  debug("User deleting account")
  local removed = {}
  for i,v in pairs(OAuthLib.supported_services) do
    if v then
      res,err = OAuthLib.removeAuth(i,UUID)
      if err then 
        cloud.log(err)
        return {status=-1,service=removed,error="Failed to remove authorization for "..i} 
      end
      if res then debug(res); removed[#removed+1] = i end
    end
  end

  return {status=1,service=removed,error=nil}
end

--Returns a user's unique ID
function api.post.getUUID(input)
  local sessionID = input.sessionID
  if not sessionID then return {status=-1,service=service,error="Access denied"} end
  local res,err = OAuthLib.getUser(nil,sessionID)
  if err then cloud.log(err); return {status=-1,service="Unknown",error="Access denied for session"} end
  debug("User requesting UUID")
  local UUID = res[1]['UUID']
  if not UUID then return {status=-1,service="Unknown",error="No user found"} end

  return {status=1,service="Unknown",error=nil,uuid=UUID}
end

function api.post.logout( input )
  local sessionID = input.sessionID
  if not sessionID then return {status=-1,service=service,error="Access denied"} end
  local res,err = OAuthLib.logoutUser(sessionID)
  debug("Logging user out")
  if err then cloud.log(err) return {status=-1,service="Unknown",error="Failed to log out user"} end

  return {status=1,service="Unknown",error=nil}
end

--Returns true/nil,service,error
function api.post.removeLink( input )
  local service = input.service
  local sessionID = input.sessionID
  if not service then return {status=-1,service="Unknown",error="Service must be specified"} end
  if not sessionID then return {status=-1,service=service,error="Access denied"} end
  if not OAuthLib.supported_services[service] then return {status=-1,service=service,error="Unsupported service"} end
  local res,err = OAuthLib.getUser(nil,sessionID)
  if err then cloud.log(err); return {status=-1,service="Unknown",error="Access denied for session"} end
  local UUID = res[1]['UUID']
  if not UUID then return {status=-1,service="Unknown",error="No user found"} end

  debug("User removing linked account")
  res,err = OAuthLib.removeAuth(service,UUID)
  if res then debug(res) end
  if err then 
    cloud.log(err)
    return {status=-1,service=service,error="ERROR: Failed to remove link."} 
  end
  if not res then return {status=-1,service=service,error="No authorization found."} end

  return {status=true,service=service,error=nil}
end  
--===========================================================================--
return api

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
OAuthLib.tablePrefix = "TESTOAUTH" -- Must not be nil. This is the prefix for all tables created and read by this API
OAuthLib.makeTables = true --Automatically make tables if they're missing. This can be turned off after the first execution except when adding new services.
OAuthLib.authTableName = OAuthLib.tablePrefix.."_QUEUE"
OAuthLib.conTab = {
    database = nil,
    user="cloud",
    password="cloudadmin",
    host=localhost,
    port=3306
  }
  
  OAuthLib.conTab['database'] = 'REG_ALPHA'

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
  local sessionID = input.sessionID
  local UUID = input.uuid
  local URL,res,err = nil,nil,nil
  if sessionID then 
    res,err = OAuthLib.checkAccess(UUID,sessionID)
    if err then cloud.log(err)
      return {status=-1,service=service,error="Access denied for session"} 
    end
  end
  URL,err = OAuthLib.makeAccessUrl(service,UUID,input.scopes)
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

  local status,service,err,UUID = OAuthLib.checkAuthStatus(reqKey)
  if err then
    cloud.log(err)
    return {status=-1,service=(service or "Unknown"),error="Error checking status"}
  end
  local sessionID = nil
  if UUID then
    sessionID,err = OAuthLib.getSessionID(UUID)
    if err then
      cloud.log(err)
      return {status=-1,service=service,error="Error getting session ID"}
    end
  end

  return {status=status,service=service,error=nil,uuid=UUID,sessionID=sessionID} --Otherwise report the status
end

---------------------------------------------------------------------------------------------------
--- User management/Protected functions - These require a matching session ID
--------------------------------------------------------------------------------------------------
function api.post.checkAccess(input)
  local UUID = input.uuid
  local sessionID = input.sessionID
  if not UUID or not sessionID then return {status=-1,service="Unknown",error="Access denied"} end
  local res,err = (OAuthLib.checkAccess(UUID,sessionID)
    if err then 
      cloud.log(err)
      return {status=-1,service="Unknown",error="Access denied"} 
    end

    return {status=1,service="Unknown",error=nil}
  end

  function api.post.getList( input )
    local UUID = input.uuid
    local sessionID = input.sessionID
    if not UUID or not sessionID then return {status=-1,service="Unknown",error="Access denied"} end
    local res,err = OAuthLib.checkAccess(UUID,sessionID)
    if err then 
      cloug.log(err) 
      return {status=-1,service="Unknown",error="Access denied for session"} 
    end
    debug("Getting user's authorization list")

    local service = {}
    for i,v in pairs(OAuthLib.supported_services) do
      if v then
        res,err = OAuthLib.getKeys(UUID,nil,i)
        if err then 
          cloud.log(err)
          return {status=-1,service={i},error="Failed to get data for "..i} 
        end
        if res then
          service[i] = res[1]['SCOPES']
        end
      end
    end

    if not next(service) then return {status=-1,service="Unknown",error="No authorizations found"} end

    return {status=1,service=service,error=nil}
  end

--Return true/nil,service,error
  function api.post.deleteProfile( input )
    local UUID = input.uuid
    local sessionID = input.sessionID
    if not UUID or not sessionID then return {status=-1,service="Unknown",error="Access denied"} end
    local res,err = OAuthLib.checkAccess(UUID,sessionID)
    if err then 
      cloug.log(err)
      return {status=-1,service="Unknown",error="Access denied for session"} 
    end

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


--Returns true/nil,service,error
  function api.post.removeLink( input )
    local service = input.service
    local UUID = input.uuid
    local sessionID = input.sessionID
    if not service then return {status=-1,service="Unknown",error="Service must be specified"} end
    if not UUID or not sessionID then return {status=-1,service=service,error="Access denied"} end
    if not OAuthLib.supported_services[service] then return {status=-1,service=service,error="Unsupported service"} end
    local res,err = OAuthLib.checkAccess(UUID,sessionID)
    if err then 
      cloug.log(err)
      return {status=-1,service=service,error="Access denied for session"} 
    end

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

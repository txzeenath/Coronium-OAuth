--===========================================================================--
--== Coronium LS
--===========================================================================--
local api = cloud.api()
local debugging = false
local OAuthLib = require("OAuth.OAuthLib")
-----------------------------------------------------------------------------------------
--PUBLIC ENDPOINT
-----------------------------------------------------------------------------------------
--===========================================================================--
--== Routing Methods
--===========================================================================--
local function debug(string)
  if debugging == true then cloud.log(string) end
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
  debug("Got redirect")
  --Grab parameters out of response
  local code = input["code"]
  local reqKey = input["state"]
  local res,err = OAuthLib.processRedirect(reqKey,code)
  if err then
    cloud.log(err)
    return {status=-1,service="Unknown",error="Bad request"}
  end

  return '<b>Welcome! Authentication Complete. You can now close this page.</b>',cloud.HTML
end

--===========================================================================--
return api

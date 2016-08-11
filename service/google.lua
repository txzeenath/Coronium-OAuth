local proc = {}
proc.client_id = ""
proc.client_secret = ""
proc.redirect_url = "myfulldomainURL/OAuth/redirect"
proc.auth_url = "https://accounts.google.com/o/oauth2/auth"
proc.token_urn_host = "accounts.google.com"
proc.token_urn_path = "/o/oauth2/token"
proc.defaultScopes = "https://www.googleapis.com/auth/userinfo.profile"
local function sSplit(inputstr, sep)
  if inputstr == nil then return nil end
  if sep == nil then
    sep = "%s"
  end
  local t={} ; i=1
  for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
    t[i] = str
    i = i + 1
  end
  return t
end

proc.processForID = function(reqKey,resp)
  local iToken = sSplit(resp['id_token'],".") --JWT - required
  local rToken = resp['refresh_token'] --not required
  local aToken = resp['access_token'] --required
  local tToken = resp['token_type'] --not required
  local eToken = resp['expires_in'] --not required

  if not iToken or not next(iToken) or not aToken then
    return nil,nil,nil,nil,nil,"Did not find a valid token"
  end

  local tPayLoad = cloud.decode.json(cloud.decode.b64(iToken[2])) --Decode our JWT payload
  local tSource = tPayLoad['iss']
  local tID = tPayLoad['id'] or tPayLoad['sub']
  if tSource ~= proc.token_urn_host then return nil,nil,nil,nil,nil,"Token source does not match request. Something is very wrong" end

  if not tID then return nil,nil,nil,nil,nil,"Could not find unique ID" end
    
  return tID,aToken,eToken,tToken,rToken,nil
end

return proc
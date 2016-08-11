local proc = {}
proc.client_id = ""
proc.client_secret = ""
proc.redirect_url = "myfulldomainURL/OAuth/redirect"
proc.auth_url = "https://github.com/login/oauth/authorize"
proc.token_urn_host = "github.com"
proc.token_urn_path = "/login/oauth/access_token"
proc.defaultScopes = "user:email"

local APIHost = "api.github.com" --Github specific, for getting user info
local APIPath = "/user"
proc.processForID = function(reqKey,resp)
  local iToken = nil -- generated below
  local rToken = nil --Does not use refresh tokens
  local aToken = resp['access_token'] --required
  local tToken = resp['token_type'] --not required
  local eToken = nil --Does not provide an expiration
  if not aToken then return nil,nil,nil,nil,nil,"Did not find a valid token" end

 
  local servNet = cloud.network.new(APIHost,443)
  servNet:method(cloud.GET) -- GitHub requires a GET
  servNet:ssl_verify(true)
  servNet:path(APIPath) --GitHub request goes into the URL
  servNet:keep_alive(5000,10)
  servNet:headers({
      ['Content-Type'] = 'application/json',
      ['Authorization'] = 'token '..aToken,
      ['Accept'] = 'application/vnd.github.v3+json'})
  local respB,err = servNet:result()
  if err or not respB then return nil,nil,nil,nil,nil,"Could not retrieve token" end
  iToken = cloud.decode.json(respB)
  local tID = iToken['id']

  if not tID then return nil,nil,nil,nil,nil,"Could not find unique ID" end

  return tID,aToken,eToken,tToken,rToken,nil
end

return proc
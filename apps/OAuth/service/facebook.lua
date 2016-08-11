local proc = {}
proc.client_id = ""
proc.client_secret = ""
proc.redirect_url = "myfulldomainURL/OAuth/redirect"
proc.auth_url = "https://www.facebook.com/dialog/oauth"
proc.token_urn_host = "graph.facebook.com"
proc.token_urn_path = "/v2.3/oauth/access_token"
proc.defaultScopes = "public_profile"

proc.appToken = "" --FB specific, for token inspection

proc.processForID = function(reqKey,resp)
  local iToken = nil --Generated below
  local rToken = nil --FB does not use refresh tokens
  local aToken = resp['access_token'] --required
  local tToken = resp['token_type'] --not required
  local eToken = resp['expires_in'] --not required
  local err,respB = nil,nil
  if not aToken then return nil,nil,nil,nil,nil,"Did not find a valid token" end
  
  local reqString = cloud.sf("/debug_token?input_token=%s&access_token=%s", aToken, proc.appToken)
  
  local servNet = cloud.network.new(proc.token_urn_host,443)
  servNet:method(cloud.GET) -- FB requires a GET
  servNet:ssl_verify(true)
  servNet:path(reqString) --FB request goes into the URL
  servNet:keep_alive(5000,10)
  respB,err = servNet:result()
  if err or not respB then return nil,nil,nil,nil,nil,"Could not retrieve token" end
  iToken = cloud.decode.json(respB)
  if not iToken['data'] or not next(iToken['data']) then return nil,nil,nil,nil,nil,"Did not find a valid token" end
  local tID = iToken['data']['user_id']
  local appID = iToken['data']['app_id']
  
  if appID ~= proc.client_id then return nil,nil,nil,nil,nil,"Authorized app does not match request. Something is very wrong." end
  
  if not tID then return nil,nil,nil,nil,nil,"Could not find unique ID" end

  return tID,aToken,eToken,tToken,rToken,nil
end

return proc
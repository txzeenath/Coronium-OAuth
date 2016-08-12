local api = cloud.api()
local OAuthLib = require("OAuth.OAuthLib")

function api.post.exampleGetProfile( input )
  --[[These params are needed to get our token]]--
  local service = input.service
  local sessionID = input.sessionID
  if not service or not sessionID then return {error = "Missing parameters"} end
  --[[----------------------------------------]]--

  local token = OAuthLib.userToken(sessionID,service) --Get token
  if not token then return {status=-1,service=service,error="Access denied"} end --No match

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


return api
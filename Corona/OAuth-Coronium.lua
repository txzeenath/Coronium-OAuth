local OAuth = {}
local onSimulator = system.getInfo( "environment" ) == "simulator"

OAuth.UUID = nil --Our unique identity.
OAuth.sessionID = nil
OAuth.authenticate = nil
local webView = nil --Forward declare so we can call "toFront" on this from our loading display
local authDelay = 3*1000 --Delay between auth requests and status checks
local authTimeout = 20*1000 --Time before attempt times out, this includes all steps of authentication
local loadingFadeout = 2000 --Fadeout duration
local loadingRotationRatio = 4 --Spin speed as ratio of time. Higher value means slower rotation.

OAuth.unescape = function(s)
  s = string.gsub(s, "+", " ")
  s = string.gsub(s, "%%(%x%x)", function (h)
      return string.char(tonumber(h, 16))
    end)
  return s
end

OAuth.parseurl = function(s,param)
  if s == nil then return s end
  for k, v in string.gmatch( s, "([^&=?]+)=([^&=?]+)" ) do
    if k == param then
      return OAuth.unescape(v)
    end
  end
end

--   Event values               -- | status | service | error |
--                              -------------------------------
--   0 = waiting                -- |   yes  |   yes   |  no   |
--  -1 = server generated error -- |   yes  |   yes   |  yes  | 
--  -2 = timed out              -- |   yes  |   no    |  yes  |
--  -3 = client generated error -- |   yes  |   yes   |  yes  | 
--   1 = success                -- |   yes  |   yes   |  no   | 
local function sendOAuthEvent(status,service,error)
  Runtime:dispatchEvent({name="OAuth-Coronium",status = status, service = service, error = error})
end

local loadingBar = nil
local loadingFrame = nil
local transit = nil
local function doLoadingScreen(disable,success)
  local function blocker(event) return true end --Touch blocker
  if not loadingFrame then
    loadingFrame = display.newRect(display.contentCenterX,display.contentCenterY,display.actualContentWidth,display.actualContentHeight)
    loadingFrame:setFillColor(0,0,0,0.5)
    loadingFrame:addEventListener("touch",blocker) --Touch blocker
    loadingBar = display.newPolygon(display.contentCenterX,display.contentCenterY,
      { 0,-110*1.25, --[[Top corner]]
        27*.5,-35*.5, --[[Topright inner]]
        105*1.25,-35*1.25, --[[Topright corner]]
        43*.5,16*.5,  --[[Right inner]]
        65*1.25,90*1.25, --[[Bottomright corner]]
        0*.5,45*.5, --[[Middle inner]]
        -65*1.25,90*1.25, --[[Bottomleft corner]]
        -43*.5,15*.5, --[[Left inner]]
        -105*1.25,-35*1.25, --[[Topleft corner]]
        -27*.5,-35*.5, --[[Topleft inner]] }) --This can be changed to whatever display object is desired.
    loadingBar.strokeWidth = 4
    loadingBar:setFillColor(1,0,0,0.6)
  end

  loadingFrame:toFront()
  loadingBar:toFront()
  if webView then webView:toFront() end

  if disable then
    if success then loadingBar:setFillColor(0,1,0,0.6) end
    if transit then transition.cancel(transit);transit=nil end
    transit = transition.to(loadingBar,{time=loadingFadeout,alpha=0,rotation = loadingBar.rotation+(loadingFadeout/loadingRotationRatio),onComplete=function()loadingBar:removeSelf();loadingFrame:removeSelf();loadingBar=nil;loadingFrame=nil;return true end})
  else
    if transit then transition.cancel(transit);transit=nil end
    transit = transition.to(loadingBar,{time=authTimeout,rotation = authTimeout/loadingRotationRatio, onComplete=function() doLoadingScreen(true,false);sendOAuthEvent(-2,nil,"Timed out") end})
  end
end

OAuth.getList = function(cloud)

  local function listener(evt)
    if evt.phase == "ended" then
      for i,v in pairs(evt.response.service) do
        print(i,v)
      end
    end
  end

  local req = cloud:request('/OAuth/getList',{uuid=OAuth.UUID,sessionID=OAuth.sessionID},listener)
end

OAuth.removeLink = function(cloud, service)
  local function listener(evt)
    if evt.phase == "ended" then
    end
  end

  local req = cloud:request('/OAuth/removeLink',{service=service,uuid=OAuth.UUID,sessionID=OAuth.sessionID},listener)
end
--   Start loop and wait for server to verify.
--   Sets OAuth.UUID on success
local function waitForAuth(reqKey,cloud,service,scopes)
  if not reqKey then
    sendOAuthEvent(-3,service,"No request key.")
    return false
  end
  if not loadingFrame then return false end --Once frame is gone we've expired or completed our action.


  local function listener(evt)
    if evt.phase == 'ended' then
      if not evt.response then
        sendOAuthEvent(-3,service,"No server response")
        doLoadingScreen(false,false)
        return
      elseif evt.isError or (evt.response.error and (not evt.response.status or evt.response.status ~= -1)) then --We had an error that was unexpected or not set by code -1
        doLoadingScreen(true,false)
        sendOAuthEvent(-3,service,(evt.response.error or "Unknown Error"))
        return
      elseif evt.response.status == 0 then --Still waiting, check again in 2s
        sendOAuthEvent(0,service,nil)
        timer.performWithDelay(authDelay,function() waitForAuth(reqKey,cloud,service,scopes); return true end)
      elseif evt.response.status == -1 then --Expire request
        doLoadingScreen(true,false)
        sendOAuthEvent(-1,service,"Auth failed. Try again") --<-- display login selection here
        return
      elseif evt.response.status == 1 then
        doLoadingScreen(true,true)
        OAuth.sessionID = evt.response.sessionID
        OAuth.UUID = evt.response.uuid
        sendOAuthEvent(1,service,nil)
      end
    end
  end

  local req = cloud:request('/OAuth/waitForAuth',{reqKey=reqKey},listener) --and wait
  return true
end

OAuth.authenticate = function(cloud, service, scopes)
  if loadingFrame then print("Must wait for current login to finish") return false end
  doLoadingScreen()
  local function listener(evt)
    if evt.phase == 'ended' then
      if evt.isError or not evt.response or evt.response.error then
        print(evt.response.error or evt.error or evt.response or "Unknown")
        sendOAuthEvent(-3,service,"Get URL Failed")
        doLoadingScreen(true,false)
        return
      else
        local reqKeyA = OAuth.parseurl(evt.response.url,"state")
        print(reqKeyA)
        webView = native.newWebView( display.contentCenterX, display.contentCenterY, 1, 1)
        if onSimulator then
          webView = nil
          system.openURL( evt.response.url )
          waitForAuth(reqKeyA,cloud,service,scopes) --Wait for server response
          return
        end
        local function webListener(event)
          if event.type == "loaded" then
            local transit = transition.to(webView,{time=1000,width=display.contentWidth,height=display.contentHeight})
            local code = OAuth.parseurl(event.url,"code")
            if code then--Got a code
              local reqKeyB = OAuth.parseurl(event.url,"state")
              if reqKeyA == reqKeyB then --Request key matches the one we sent out
                if transit then transition.cancel(transit);transit=nil end
                webView:removeSelf() --Close and wait for server response
                webView = nil
                waitForAuth(reqKeyA,cloud,service,scopes) --Start waiting
                return
              else
                if transit then transition.cancel(transit);transit=nil end
                webView:removeSelf() --Close and wait for server response
                webView = nil
                sendOAuthEvent(-3,service,"No matching key. ABORT.")
              end
            end
          end

        end
        webView:request(evt.response.url)
        webView:addEventListener( "urlRequest", webListener )
      end
    end
  end

  local req = cloud:request('/OAuth/requestAccessUrl',{service=service,scopes=scopes,uuid=OAuth.UUID,sessionID=OAuth.sessionID},listener)
  return true
end

return OAuth
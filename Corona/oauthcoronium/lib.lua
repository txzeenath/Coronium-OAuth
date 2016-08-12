local OAuth = {}
local Coronium = require('coronium.cloud')
local lfs = require("lfs")
local utils = require("oauthcoronium.utilities")
local dS = require("oauthcoronium.display")

local onSimulator = system.getInfo( "environment" ) == "simulator"

OAuth.sessionID = nil
OAuth.loginPanel = nil
local webView = nil

local authDelay = 3*1000 --Delay between auth requests and status checks. In ms
local authTimeout = 20*1000 --Time before attempt times out, this includes all steps of authentication. In ms

OAuth.sendEvent = function(params)
  local outParams = {}
  outParams['name'] = "OAuth-Coronium"
  outParams['service'] = params.service or "Unknown"
  outParams['error'] = params.error or nil
  outParams['status'] = params.status or 0
  outParams['action'] = params.action or "Unknown"
  Runtime:dispatchEvent(outParams)
end



--Draws a service icon and returns the display group
--Icons are pulled from /files/OAuth/images/<servicename>.png
--You must not do any work on the icon object itself. All functions should
--use the display group. Since the icon is loaded into the group AFTER
--it gets returned to the caller.
OAuth.drawServiceIcon = function(service,listener,disableEffects,label)
  local sysDir = system.pathForFile("",system.DocumentsDirectory)
  local res = lfs.chdir(sysDir)
  local icon_foldern = "OAuth-Coronium"
  if res then lfs.mkdir(icon_foldern) else print("Could not create directory") return nil end
  local icon_path = '/'..icon_foldern..'/'..service..'.png'
  local iconG = display.newGroup()
  local iconB = display.newCircle(iconG,0,0,71+3)
  local iconLabel = nil
  if label then 
    iconLabel = display.newText(iconG,label,0,71+3,native.systemFont,20)
    iconLabel.anchorX,iconLabel.anchorY=0.5,0
    iconLabel:setFillColor(0)
  end
  iconB.strokeWidth=6
  iconB:setStrokeColor(0,0,0)
  local iconI = nil
  if not utils.doesFileExist(icon_path,system.DocumentsDirectory) then
    local function listener(evt)
      if evt.phase == "ended" then
        if iconG then
          iconI = display.newImage(iconG,icon_path,system.DocumentsDirectory,0,0)
          iconI.width,iconI.height = 100,100
          iconG.IMG = iconI
          if listener then
            iconI.touch = listener
            iconI:addEventListener("touch")
          end
          if not disableEffects then iconI:addEventListener("touch",dS.touchPulse)  end
        else
          print("It appears our display group has vanished.")
        end
      end
    end
    local req = OAuth.cloud:download("/OAuth/images/"..service..".png",icon_path,listener,system.DocumentsDirectory)
  else
    iconI = display.newImage(iconG,icon_path,system.DocumentsDirectory,0,0)
    iconI.width,iconI.height = 100,100
    if not disableEffects then iconI:addEventListener("touch",dS.touchPulse) end
    if listener then
      iconI.touch = listener
      iconI:addEventListener("touch")
    end
  end 
  iconG.BG = iconB
  iconG.IMG = iconI
  iconG.alpha = 0
  if not disableEffects then transition.to(iconG,{time=500,alpha=1}) end
  return iconG
end

OAuth.showLoginPanel = function(hide,disableEffects,header)
  if not hide then
    if OAuth.loginPanel then
      return false
    end
    local function listener(evt)
      if evt.phase == "ended" then
        if evt.isError or not evt.response or evt.response.error then
          print("Error getting service list")
          return
        end
        local function Blocker(event) return true end
        OAuth.loginPanel = display.newGroup()
        local touchBlocker = display.newRect(OAuth.loginPanel,0,0,display.actualContentWidth,display.actualContentHeight)
        touchBlocker:addEventListener("touch",Blocker)
        touchBlocker.alpha = 0.5
        touchBlocker:setFillColor(0)
        local BG = display.newRect(OAuth.loginPanel,0,0,display.actualContentWidth*.75,display.actualContentHeight*.75)
        BG:setFillColor(1)
        BG.strokeWidth=4
        BG:setStrokeColor(0)
        if header then
          OAuth.loginPanel.header = display.newText(OAuth.loginPanel,header,0,-(BG.height/2),native.systemFont,40)
          OAuth.loginPanel.header:setFillColor(0)
          OAuth.loginPanel.header.anchorY=0
          OAuth.loginPanel.header.anchorX=0.5
        end
        OAuth.loginPanel.BG = BG
        local perRow = 5
        local thisIcon
        local iconCount = 0
        local icons = display.newGroup()
        for i,v in pairs(evt.response) do
          if v then
            iconCount=iconCount+1
            thisIcon = OAuth.drawServiceIcon(i,function() OAuth.showLoginPanel(true); OAuth.authenticate(i) end,false,i)
            thisIcon.y = (math.floor(iconCount/perRow)*(thisIcon.height+10))
            thisIcon.x = ((iconCount*(thisIcon.width+10))) - thisIcon.y
            icons:insert(thisIcon)
          end
        end
        icons.anchorX=0.5
        icons.anchorY=0.5
        icons.anchorChildren = true
        OAuth.loginPanel:insert(icons)
        OAuth.loginPanel.x,OAuth.loginPanel.y = display.contentCenterX,display.contentCenterY
        if not disableEffects then
          OAuth.loginPanel.alpha = 0
          OAuth.loginPanel.xScale = 0.001
          OAuth.loginPanel.yScale = 0.001
          transition.to(OAuth.loginPanel,{time=500,xScale=1,yScale=1,alpha=1})
        end
      end
    end
    local req = OAuth.cloud:request('/OAuth/getServiceList',{},listener)
  else
    if OAuth.loginPanel then
      if not disableEffects then
        transition.to(OAuth.loginPanel,{time=500,alpha=0,xScale=1.5,yScale=1.5,onComplete=function() OAuth.loginPanel:removeSelf();OAuth.loginPanel=nil end})
      else
        OAuth.loginPanel:removeSelf()
        OAuth.loginpanel = nil
      end
    end
  end

end

OAuth.checkUser = function (onTrue,onFalse)
  local function listener(evt)
    if evt.phase == "ended" then
      if evt.isError or not evt.response or evt.response.error or evt.response.status ~= 1 then
        print("Error. Could not check user")
        if onFalse then onFalse() end
        return
      end
      if evt.response.status == 1 then
        print("User is good!")
        if onTrue then onTrue() end
      end
    end
  end
  local req = OAuth.cloud:request('/OAuth/checkUser',{sessionID = OAuth.sessionID},listener)
end

local waitingIcon = nil
local waitingFrame = nil
local function doWaitingScreen(disable,service)
  local function blocker(event) return true end
  if not waitingFrame then
    waitingFrame = display.newRect(display.contentCenterX,display.contentCenterY,display.actualContentWidth,display.actualContentHeight)
    waitingFrame:setFillColor(0,0,0,0.5)
    waitingFrame:addEventListener("touch",blocker) --Touch blocker
    waitingIcon = OAuth.drawServiceIcon(service,nil,nil)
    waitingIcon.x,waitingIcon.y = display.contentCenterX,display.contentCenterY
  end

  if disable then
    dS.animatePulseA(waitingIcon,1000,true,true)
    waitingFrame:removeSelf()
    waitingFrame = nil
    waitingIcon = nil
  else
    waitingFrame:toFront()
    waitingIcon:toFront()
    dS.animatePulseA(waitingIcon,1000)
  end
  if webView then webView:toFront() end
  timer.performWithDelay(authTimeout,function() OAuth.sendEvent({action="login",status=-2,service=service,error="Timed out"}); doWaitingScreen(true,service) end)
end


OAuth.getList = function()
  local function listener(evt)
    if evt.phase == "ended" then
      if evt.isError or not evt.response or evt.response.error then
        print("Error getting list")
        return
      end

      for i,v in pairs(evt.response.service) do
        print(v[1].." - "..v[2])
      end
    end
  end

  local req = OAuth.cloud:request('/OAuth/getList',{sessionID=OAuth.sessionID},listener)
end

OAuth.removeLink = function(service)
  local function listener(evt)
    if evt.phase == "ended" then
      for i,v in pairs(evt.response) do
        print(i,v)
      end
    end
  end

  local req = OAuth.cloud:request('/OAuth/removeLink',{sessionID=OAuth.sessionID,service=service},listener)
end

--   Start loop and wait for server to verify.
--   Sets OAuth.UUID on success
local function waitForAuth(reqKey,service,scopes)
  if not reqKey then
    OAuth.sendEvent({action=login,status=-3,service=service,error="No request key."})
    return false
  end
  if not waitingFrame then return false end --Once frame is gone we've expired or completed our action.


  local function listener(evt)
    if evt.phase == 'ended' then
      if not evt.response then
        OAuth.sendEvent({action="login",status=-3,service=service,error="No server response"})
        doWaitingScreen(true,service)
        return
      elseif evt.isError or (evt.response.error and (not evt.response.status or evt.response.status ~= -1)) then --We had an error that was unexpected or not set by code -1
        doWaitingScreen(true,service)
        OAuth.sendEvent({action="login",status=-3,service=service,error=(evt.response.error or "Unknown Error")})
        return
      elseif evt.response.status == 0 then --Still waiting, check again in 2s
        OAuth.sendEvent({action="login",status=0,service=service})
        timer.performWithDelay(authDelay,function() waitForAuth(reqKey,service,scopes); return true end)
      elseif evt.response.status == -1 then --Expire request
        doWaitingScreen(true,service)
        OAuth.sendEvent({action="login",status=-1,service=service,error="Server rejected request"}) --<-- display login selection here
        return
      elseif evt.response.status == 1 then
        doWaitingScreen(true,service)
        OAuth.sessionID = evt.response.sessionID
        OAuth.sendEvent({action="login",status=1,service=service})
      end
    end
  end

  local req = OAuth.cloud:request('/OAuth/waitForAuth',{reqKey=reqKey},listener) --and wait
  return true
end

OAuth.authenticate = function(service, scopes)
  if waitingFrame then print("Must wait for current login to finish") return false end
  doWaitingScreen(false,service)
  local function listener(evt)
    if evt.phase == 'ended' then
      if evt.isError or not evt.response or evt.response.error then
        print(evt.response.error or evt.error or evt.response or "Unknown")
        OAuth.sendEvent({action="login",status=-3,service=service,error="Get URL Failed"})
        doWaitingScreen(true,service)
        return
      else
        local reqKey = evt.response.reqKey
        if onSimulator then
          system.openURL( evt.response.url )
          timer.performWithDelay(authDelay, function() waitForAuth(reqKey,service,scopes) end) --Wait for server response
          return
        else
          webView = native.newWebView( display.contentCenterX, display.contentCenterY, 1, 1)
          local function webListener(event)
            if event.type == "loaded" then
              local code = utils.parseurl(event.url,"code")
              if code then --Got a code
                transition.cancel(webView)
                webView:removeSelf() --Close and wait for server response
                webView = nil
                timer.performWithDelay(authDelay, function() waitForAuth(reqKey,service,scopes) end) --Start waiting
                return
              else
                transition.to(webView,{time=500,width=display.contentWidth*.75,height=display.contentHeight*.75})
              end
            end
          end
          webView:request(evt.response.url)
          webView:addEventListener( "urlRequest", webListener )
        end
      end
    end
  end

  local req = OAuth.cloud:request('/OAuth/requestAccessUrl',{service=service,scopes=scopes,sessionID=OAuth.sessionID},listener)
  return true
end

return OAuth
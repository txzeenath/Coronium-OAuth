local OAuth = {}
local Coronium = require('coronium.cloud')
local lfs = require("lfs")
local utils = require("oauthcoronium.utilities")
local dS = require("oauthcoronium.display")

local onSimulator = system.getInfo( "environment" ) == "simulator"

OAuth.sessionID = nil
OAuth.loginPanel = nil
OAuth.mPanel = nil
OAuth.linked = {}
OAuth.linkedCount = 0
OAuth.services = {}
local webView = nil

local authDelay = 3*1000 --Delay between auth requests and status checks. In ms
local authTimeout = 20*1000 --Time before attempt times out, this includes all steps of authentication. In ms
local timeout = nil

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
OAuth.drawServiceIcon = function(service,listener,disableEffects,label,iconSize)
  local sysDir = system.pathForFile("",system.DocumentsDirectory)
  local res = lfs.chdir(sysDir)
  local icon_foldern = "OAuth-Coronium"
  if res then lfs.mkdir(icon_foldern) else print("Could not create directory") return nil end
  local icon_path = '/'..icon_foldern..'/'..service..'.png'
  local iconG = display.newGroup()
  local iconB = display.newCircle(iconG,0,0,((iconSize*(2^.5))/2)*1.1)
  local iconLabel = nil
  if label then 
    iconLabel = display.newText(iconG,label,0,iconB.path.radius+1,native.systemFont,20)
    iconLabel.anchorX,iconLabel.anchorY=0.5,0
    iconLabel:setFillColor(0)
    iconG.label = iconLabel
  end
  iconB.strokeWidth=iconB.path.radius*.1
  iconB:setStrokeColor(0,0,0)
  local iconI = nil
  if not utils.doesFileExist(icon_path,system.DocumentsDirectory) then
    local function listener(evt)
      if evt.phase == "ended" then
        if iconG then
          iconI = display.newImageRect(iconG,icon_path,system.DocumentsDirectory,iconSize,iconSize)
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
    local req = OAuth.cloud:download("OAuth/images/"..service..".png",icon_path,listener,system.DocumentsDirectory)
  else
    iconI = display.newImageRect(iconG,icon_path,system.DocumentsDirectory,iconSize,iconSize)
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

OAuth.showManagementPanel = function(hide,disableEffects,header,x,y)
  if not hide then
    if OAuth.mPanel then
      transition.cancel(OAuth.mPanel)
      OAuth.mPanel:removeSelf()
      OAuth.mPanel = nil
    end
    local function listener(evt)
      if evt.phase == "ended" then
        if evt.isError or not evt.response or evt.response.error then
          print("Error getting service list")
          return
        end
        local function Blocker(event) return true end
        OAuth.mPanel = display.newGroup()
        local touchBlocker = display.newRect(OAuth.mPanel,0,0,display.actualContentWidth*2,display.actualContentHeight*2)
        touchBlocker:addEventListener("touch",Blocker)
        touchBlocker.alpha = 0.5
        touchBlocker:setFillColor(0)
        local BG = display.newRect(OAuth.mPanel,0,0,(display.actualContentWidth*.5)-4,(display.actualContentHeight*.5)-4)
        BG:setFillColor(1)
        BG.strokeWidth=4
        BG:setStrokeColor(0)
        OAuth.mPanel.curHeader = display.newText(OAuth.mPanel,"Your linked accounts (touch to unlink)",(-(BG.width/2))+5,-(BG.height/2)+5,native.systemFont,20)
        OAuth.mPanel.curHeader:setFillColor(0)
        OAuth.mPanel.curHeader.anchorY=0
        OAuth.mPanel.curHeader.anchorX=0

        OAuth.mPanel.BG = BG
        local perRow = 5
        local thisIcon
        local iconCount = 0
        local icons = display.newGroup()
        OAuth.linked = {}
        for i,v in pairs(evt.response.service) do
          OAuth.linked[v[1]] = true
          iconCount=iconCount+1
          thisIcon = OAuth.drawServiceIcon(v[1],function() OAuth.showManagementPanel(true,false); OAuth.removeLink(v[1],true) end,false,v[1],60)
          thisIcon.y = OAuth.mPanel.curHeader.y+OAuth.mPanel.curHeader.height+thisIcon.BG.path.radius+5
          thisIcon.x = OAuth.mPanel.curHeader.x+(((iconCount*(thisIcon.width+10))))
          icons:insert(thisIcon)
        end
        OAuth.linkedCount = iconCount
        OAuth.mPanel.avHeader = display.newText(OAuth.mPanel,"Supported (touch to link)",OAuth.mPanel.curHeader.x,(OAuth.mPanel.BG.height/2)-(thisIcon.BG.path.radius*2)-40-thisIcon.label.height,native.systemFont,20)
        OAuth.mPanel.avHeader:setFillColor(0)
        OAuth.mPanel.avHeader.anchorY=0
        OAuth.mPanel.avHeader.anchorX=0
        iconCount=0
        for i=1,#OAuth.services do
          if not OAuth.linked[OAuth.services[i]] then
            iconCount=iconCount+1
            thisIcon = OAuth.drawServiceIcon(OAuth.services[i],function() OAuth.showManagementPanel(true,false); OAuth.authenticate(OAuth.services[i]) end,false,OAuth.services[i],60)
            thisIcon.y = OAuth.mPanel.avHeader.y+OAuth.mPanel.avHeader.height+thisIcon.BG.path.radius+5
            thisIcon.x = OAuth.mPanel.avHeader.x+(((iconCount*(thisIcon.width+10))))
            icons:insert(thisIcon)
          end
        end
        if iconCount == 0 then
          OAuth.mPanel.avHeader:removeSelf()
          OAuth.mPanel.avHeader = nil
        end
        OAuth.mPanel:insert(icons)
        OAuth.mPanel.exit = display.newText(OAuth.mPanel,"X",(OAuth.mPanel.BG.width/2),-(OAuth.mPanel.BG.height/2),native.systemFontBold,30)
        OAuth.mPanel.exit:setFillColor(1,0,0)
        OAuth.mPanel.exit.strokeWidth = 8
        OAuth.mPanel.exit:setStrokeColor(1,0,0)
        OAuth.mPanel.exit.anchorX=1
        OAuth.mPanel.exit.anchorY=0
        OAuth.mPanel.exit:addEventListener("touch",function() OAuth.showManagementPanel(true,false) end)
        if not x or not y then
          OAuth.mPanel.x,OAuth.mPanel.y = display.contentCenterX,display.contentCenterY
        else
          OAuth.mPanel.x,OAuth.mPanel.y = x,y
        end
        if not disableEffects then
          OAuth.mPanel.alpha = 0
          OAuth.mPanel.xScale = 0.001
          OAuth.mPanel.yScale = 0.001
          transition.to(OAuth.mPanel,{time=500,xScale=1,yScale=1,alpha=1})
        end
      end
    end
    local req = OAuth.cloud:request('/OAuth/getList',{sessionID=OAuth.sessionID},listener)
  else
    if OAuth.mPanel then
      if not disableEffects then
        transition.to(OAuth.mPanel,{time=500,alpha=0,xScale=1.5,yScale=1.5,onComplete=function(obj) obj:removeSelf() end})
        OAuth.mPanel=nil 
      else
        OAuth.mPanel:removeSelf()
        OAuth.mPanel = nil
      end
    end
  end
end

OAuth.showLoginPanel = function(hide,disableEffects,header)
  if not hide then
    if OAuth.loginPanel then
      transition.cancel(OAuth.loginPanel)
      OAuth.loginPanel:removeSelf()
      OAuth.loginPanel = nil
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
        local BG = display.newRect(OAuth.loginPanel,0,0,(display.actualContentWidth*.5)-4,(display.actualContentHeight*.25)-4)
        BG:setFillColor(1)
        BG.strokeWidth=4
        BG:setStrokeColor(0)
        if header then
          OAuth.loginPanel.header = display.newText(OAuth.loginPanel,header,0,-((BG.height/2))+5,native.systemFont,20)
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
            OAuth.services[iconCount] = i
            thisIcon = OAuth.drawServiceIcon(i,function() OAuth.showLoginPanel(true); OAuth.authenticate(i) end,false,i,60)
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
        transition.to(OAuth.loginPanel,{time=500,alpha=0,xScale=1.5,yScale=1.5,onComplete=function(obj) obj:removeSelf()end})
        OAuth.loginPanel = nil
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
  local action = nil
  if OAuth.sessionID then action = "link" else action = "login" end
  local function blocker(event) return true end
  if not waitingFrame then
    waitingFrame = display.newRect(display.contentCenterX,display.contentCenterY,display.actualContentWidth,display.actualContentHeight)
    waitingFrame:setFillColor(0,0,0,0.5)
    waitingFrame:addEventListener("touch",blocker) --Touch blocker
    waitingIcon = OAuth.drawServiceIcon(service,nil,nil,nil,100)
    waitingIcon.x,waitingIcon.y = display.contentCenterX,display.contentCenterY
  end

  if disable then
    dS.animatePulseA(waitingIcon,1000,true,true)
    waitingFrame:removeSelf()
    waitingFrame = nil
    waitingIcon = nil
    if timeout then timer.cancel(timeout);timeout=nil end
  else
    waitingFrame:toFront()
    waitingIcon:toFront()
    dS.animatePulseA(waitingIcon,1000)
    timeout = timer.performWithDelay(authTimeout,function() OAuth.sendEvent({action=action,status=-2,service=service,error="Timed out"}); doWaitingScreen(true,service) end)
  end
  if webView then webView:toFront() end
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

OAuth.removeLink = function(service,promptFirst)
  if not OAuth.linkedCount or OAuth.linkedCount <= 1 then 
    native.showAlert("Warning","You can't unlink your last account!",{"Ok"})
    OAuth.sendEvent({action="unlink",status=-1,service=service,error="Can't unlink last account"})
    return
  end

  if promptFirst then
    local function listener(event)
      if event.index == 1 then
        OAuth.removeLink(service,nil)
      else
        OAuth.showManagementPanel(false,false)
      end
    end


    local alert = native.showAlert( "Warning", "Are you sure you want to unlink your "..service.." account?", { "Yes", "No","Nope","Maybe" }, listener )
  else


    local function listener(evt)
      if evt.phase == "ended" then
        if not evt.response or evt.response.error or evt.isError then
          native.showAlert("Error","Could not unlink account",{"Ok"})
          OAuth.sendEvent({action="unlink",status=-1,service=service,error="Failed to unlink account"})
        else
          OAuth.sendEvent({action="unlink",status=1,service=evt.response.service,error=nil})
          native.showAlert("Service Removed","Successfully unlinked "..evt.response.service,{"Ok"})
        end
      end
    end

    local req = OAuth.cloud:request('/OAuth/removeLink',{sessionID=OAuth.sessionID,service=service},listener)
  end
end

--   Start loop and wait for server to verify.
--   Sets OAuth.UUID on success
local function waitForAuth(reqKey,service,scopes)
  local action = nil
  if OAuth.sessionID then action = "link" else action = "login" end
  if not reqKey then
    OAuth.sendEvent({action=action,status=-3,service=service,error="No request key."})
    return false
  end
  if not waitingFrame then return false end --Once frame is gone we've expired or completed our action.

  local function listener(evt)
    if evt.phase == 'ended' then
      if not evt.response then
        OAuth.sendEvent({action=action,status=-3,service=service,error="No server response"})
        doWaitingScreen(true,service)
        return
      elseif evt.isError or (evt.response.error and (not evt.response.status or evt.response.status ~= -1)) then --We had an error that was unexpected or not set by code -1
        doWaitingScreen(true,service)
        OAuth.sendEvent({action=action,status=-3,service=service,error=(evt.response.error or "Unknown Error")})
        return
      elseif evt.response.status == 0 then --Still waiting, check again in 2s
        OAuth.sendEvent({action=action,status=0,service=service})
        timer.performWithDelay(authDelay,function() waitForAuth(reqKey,service,scopes); return true end)
      elseif evt.response.status == -1 then --Expire request
        doWaitingScreen(true,service)
        OAuth.sendEvent({action=action,status=-1,service=service,error="Server rejected request"}) --<-- display login selection here
        return
      elseif evt.response.status == 1 then
        doWaitingScreen(true,service)
        OAuth.sessionID = evt.response.sessionID
        OAuth.sendEvent({action=action,status=1,service=service})
      end
    end
  end

  local req = OAuth.cloud:request('/OAuth/waitForAuth',{reqKey=reqKey},listener) --and wait
  return true
end

OAuth.authenticate = function(service, scopes)
  if waitingFrame then print("Must wait for current login to finish") return false end
  local action = nil
  if OAuth.sessionID then action = "link" else action = "login" end
  doWaitingScreen(false,service)
  local function listener(evt)
    if evt.phase == 'ended' then
      if evt.isError or not evt.response or evt.response.error then
        print(evt.response.error or evt.error or evt.response or "Unknown")
        OAuth.sendEvent({action=action,status=-3,service=service,error="Get URL Failed"})
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
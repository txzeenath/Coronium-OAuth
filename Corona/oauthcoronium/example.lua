local composer = require( "composer" )
local scene = composer.newScene()
local example = {}
local Coronium = require('coronium.cloud')
local OAuth = require("oauthcoronium.lib")
OAuth.cloud = Coronium:new({--Set the OAuth cloud. This is used by the OAuth API
    host = 'nyc1.tinywar.net',
    app_key = '0',
    https = true
  })

--Set our example cloud.
local cloud = Coronium:new({ --Set our example project's cloud
    host = 'nyc1.tinywar.net',
    app_key = '1234',
    https = true
  })

local function checkUser()
   --Prompt user for login, OAuth.checkUser(function on true, function on false)
  OAuth.checkUser(function() print("User is logged in.") end,function() OAuth.showLoginPanel(nil,nil,"Please Select a Service To Log In") end)
end

function scene:show( event )

  local sceneGroup = self.view
  local phase = event.phase
  if ( phase == "did" ) then
    checkUser()
  end
end

example.getProfile = function(service)
  if service ~= "google" then
    print("Only 'google' is a valid service for this function")
    return
  end
  local function listener(evt)
    if evt.phase == "ended" then
      if evt.response.error or evt.isError then
        OAuth.sendEvent({action="getProfile",service=service,error="Failed to get profile"})
        print("Error getting profile")
      else
        OAuth.sendEvent({action="getProfile",service=service,error=nil})
        for i,v in pairs(evt.response) do
          print(i,v)
        end
      end
    end
  end
  
  local req = cloud:request('/example/exampleGetProfile',{sessionID=OAuth.sessionID,service="google"},listener)
end

--Listen for OAuth events
local function listener(evt)
  if evt.action == "login" then
    if evt.status == 1 then
      print("User logged in using: "..(evt.service or "Unknown"))
      example.getProfile(evt.service)
    elseif evt.status == 0 then
      print("Waiting")
    elseif evt.status == -1 then
      print("Server error. Try again")
      checkUser()
    elseif evt.status == -2 then
      print("Timed out. Try again")
      checkUser()
    elseif evt.status == -3 then
      print("Client error. Try again")
      checkUser()
    end
  elseif evt.action == "getProfile" then
    if evt.error then
      print("Error, failed to get profile from "..evt.service)
    else
      print("Returned profile table from "..evt.service)
    end
  end
end


Runtime:addEventListener("OAuth-Coronium", listener)
scene:addEventListener( "create", scene )
scene:addEventListener( "show", scene )
scene:addEventListener( "hide", scene )
scene:addEventListener( "destroy", scene )
-- -----------------------------------------------------------------------------------

return scene
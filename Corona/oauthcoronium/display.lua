---These are display related functions that don't connect to the OAuth network
local dS = {}

dS.touchPulse = function(event)
  if event.phase == "began" then
    transition.to(self,{time=500,alpha=.5,xScale=1.1,yScale=1.1,onComplete=function() transition.to(event.target,{time=500,alpha=1,xScale=1,yScale=1})end})
  end
end

local function animatePulseB(object,delay,stop,removeOnStop)
  transition.cancel(object)
  if not stop then
    transition.to(object,{time=delay,xScale=1.0,yScale=1.0,alpha=1,onComplete=function() dS.animatePulseA(object,delay,stop,removeOnStop) end})
  else
    if removeOnStop then
      transition.to(object,{time=delay,xScale=1.25,yScale=1.25,alpha=0,onComplete=function() object:removeSelf() end})
    else
      transition.to(object,{time=delay,xScale=1.0,yScale=1.0,alpha=1})
    end
  end
end
dS.animatePulseA = function(object,delay,stop,removeOnStop)
  transition.cancel(object)
  transition.to(object,{time=delay,xScale=.9,yScale=.9,alpha=0.5,onComplete=function() animatePulseB(object,delay,stop,removeOnStop) end})
end




return dS
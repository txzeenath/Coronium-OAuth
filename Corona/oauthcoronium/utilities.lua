---These are generic handling functions that don't connect to the OAuth network
local utils = {}
local function unescape(s)
  s = string.gsub(s, "+", " ")
  s = string.gsub(s, "%%(%x%x)", function (h)
      return string.char(tonumber(h, 16))
    end)
  return s
end

utils.parseurl = function(s,param)
  if s == nil then return s end
  for k, v in string.gmatch( s, "([^&=?]+)=([^&=?]+)" ) do
    if k == param then
      return unescape(v)
    end
  end
end

utils.doesFileExist = function( fname, path )
  local results = false
  local filePath = system.pathForFile( fname, path )
  if filePath then
    filePath = io.open( filePath, "r" )
  end
  if  filePath then
    filePath:close()
    results = true
  end
  return results
end


return utils
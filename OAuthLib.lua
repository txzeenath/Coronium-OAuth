local OAuthLib = {}

local debugging = true

local function debug(string)
  if debugging == true then cloud.log(string) end
end

local function createTables()
  local result,err = cloud.mysql.query(OAuthLib.conTab,
    "CREATE TABLE IF NOT EXISTS `"..OAuthLib.authTableName.."` (`reqKey` varchar(64) NULL, `TIME` int(32) NULL, `SERVICE` varchar(32) NULL,`SCOPES` varchar(64) NULL,`STATUS` tinyint(1) NULL, `UUID` varchar(64) NULL, PRIMARY KEY (`reqKey`)) ENGINE='InnoDB' COLLATE 'utf8_unicode_ci';")
  if err then
    return nil,err
  end
  local keyTableName = nil
  for i,v in pairs(OAuthLib.supported_services) do
    if v then
      keyTableName = OAuthLib.tablePrefix.."_"..i.."_KEYS"
      local result,err = cloud.mysql.query(OAuthLib.conTab,
        "CREATE TABLE IF NOT EXISTS `"..keyTableName.."` (`UUID` varchar(64) NULL, `OAUTH_ID` varchar(64) NULL, `REFRESH` varchar(64) NULL, `ACTIVE` varchar(64) NOT NULL,`EXPIRES` int(64) NULL,`SESSIONID` varchar(64) NULL, `SCOPES` varchar(512),`lastUsed` int(16) NULL,INDEX (`UUID`),PRIMARY KEY(`OAUTH_ID`)) ENGINE='InnoDB' COLLATE 'utf8_unicode_ci';")

      if err then 
        return nil,err
      end
    end
  end
end

--reqKey is optional and will forcibly remove the entry from the table
local function pruneAuth(reqKey)
  if not reqKey then reqKey = "" end --Make an empty string so we don't get a concat error
  local db = cloud.mysql.databag(OAuthLib.conTab)
  local result,err = db:delete({
      tableName=OAuthLib.authTableName,
      where = "TIME < "..cloud.time.epoch()-(60*5).." OR `reqKey`="..cloud.mysql.string(reqKey) --Codes are good for 5 minutes, and then they get wiped
    })
  return result,err
end


--Remove an authorization key from table
OAuthLib.removeAuth = function(service,UUID)
  if not UUID or not service then return nil,"Can't remove auth: Parameters missing" end
  local keyTableName = OAuthLib.tablePrefix.."_"..service.."_KEYS"
  local db = cloud.mysql.databag(OAuthLib.conTab)
  local result,err = db:delete({
      tableName=keyTableName,
      where = "`UUID` = "..cloud.mysql.string(UUID),
      limit=1
    })
  return result,err
end

--sets auth status for provided request key
-- When the client polls for status we'll
-- check this value to see what action should be
-- taken.
-- If client takes more than 5 minutes to verify the request we assume our ID is lost
-- and we'll have to log back in.
--  0 = pending
--  1 = successful. Waiting for client to acknowledge
-- -1 = failed. Client should try again.
local function setAuthStatus(reqKey,statusCode,UUID)
  local query = nil
  if not UUID then UUID = 'NULL' else UUID = cloud.mysql.string(UUID) end
  query = "UPDATE "..OAuthLib.authTableName.." SET `STATUS`="..statusCode..",`UUID`=COALESCE("..UUID..",`UUID`) where `reqKey`="..cloud.mysql.string(reqKey).." LIMIT 1;"
  local result,err = cloud.mysql.query(OAuthLib.conTab,query)

  if not result or not next(result) or err then return nil,(err or "Unknown") end
  return result,err
end

--Get entry from auth queue
local function getAuth(reqKey)
  local db = cloud.mysql.databag(OAuthLib.conTab)
  local result,err = db:select({
      tableName=OAuthLib.authTableName,
      where = "`reqKey`="..cloud.mysql.string(reqKey),
      limit = 1
    })

  if next(result) then
    for i,v in pairs(result[1]) do
      if v == ngx.null then result[1][i] = nil end
    end
  else
    result = nil --We don't pass empty tables back
  end
  return result,err
end

--Write entry to auth queue
local function writeAuth(reqKey,service,scopes,status,UUID)
  local columns = nil
  if UUID then columns = {'reqKey','TIME','SERVICE','SCOPES','STATUS','UUID'}
  else columns = {'reqKey','TIME','SERVICE','SCOPES','STATUS'} end
  local db = cloud.mysql.databag(OAuthLib.conTab)
  local result,err = db:insert({
      tableName=OAuthLib.authTableName,
      columns=columns,
      values = {reqKey,cloud.time.epoch(),service,scopes,status,UUID}
    })


  if not result or not next(result) or err then return nil,(err or "Unknown") end
  return result,err
end

--Inserts keys as provided
--If entry already exists, updates active,lastUsed and expires.
--OAUTH_ID is never changed.
local function writeKeys(UUID,OID,service,refresh,active,expires,scopes)
  if not UUID or not service or not active or not OID then
    cloud.log("Missing arguments to writeKeys function!")
    return nil,"Missing arguments"
  end
  if not expires then expires = 999999999 end --Never expires
  if not refresh then refresh = 'NULL' end
  local keyTableName = OAuthLib.tablePrefix.."_"..service.."_KEYS"

  local query = nil
  query = "INSERT INTO `"..keyTableName.."` (`UUID`, `OAUTH_ID`,`REFRESH`, `ACTIVE`, `EXPIRES`,`SCOPES`,`lastUsed`) VALUES ("..cloud.mysql.string(UUID)..",".. cloud.mysql.string(OID)..","..cloud.mysql.string(refresh)..",".. cloud.mysql.string(active)..",".. cloud.time.epoch()+tonumber(expires)..","..cloud.mysql.string(scopes)..","..cloud.time.epoch()..") ON DUPLICATE KEY UPDATE `UUID`=VALUES(`UUID`),`ACTIVE`=VALUES(`ACTIVE`),`REFRESH`=VALUES(`REFRESH`),`SCOPES`=VALUES(`SCOPES`),`EXPIRES`=VALUES(`EXPIRES`),`lastUsed`=VALUES(`lastUsed`);"

  local result,err = cloud.mysql.query(OAuthLib.conTab, query)


  if not result or not next(result) then return nil,err end
  return result,err
end

local function writeSessionID(UUID,sessionID)
  if not UUID then return nil,"No identity to set sessionID" end
  if not sessionID then return nil,"Need a sessionID to be able to set it" end
  debug("Writing session ID")

  local query=nil
  local keyTableName = nil
  local res,err=nil,nil
  for i,v in pairs(OAuthLib.supported_services) do
    if v then
      keyTableName = OAuthLib.tablePrefix.."_"..i.."_KEYS"
      query = "UPDATE "..keyTableName.." SET `SESSIONID`="..cloud.mysql.string(sessionID).." where `UUID` ="..cloud.mysql.string(UUID).." LIMIT 1;"
      res,err = cloud.mysql.query(OAuthLib.conTab,query)
      if err then return nil,err end
    end
  end
  return true,nil
end

--Can check for UUID or OAuthID to grab keys
OAuthLib.getKeys = function(UUID,OAuthID,service)
  local keyTableName = OAuthLib.tablePrefix.."_"..service.."_KEYS"

  if not UUID then UUID = "" end
  if not OAuthID then OAuthID = "" end
  local db = cloud.mysql.databag(OAuthLib.conTab)
  local result,err = db:select({
      tableName=OAuthLib.tablePrefix.."_"..service.."_KEYS",
      where = "`UUID`="..cloud.mysql.string(UUID).." OR `OAUTH_ID`="..cloud.mysql.string(OAuthID),
      limit = 1
    })

  if next(result) then
    for i,v in pairs(result[1]) do
      if v == ngx.null then result[1][i] = nil end --This might make holes in the table
    end
  else
    result = nil --But we don't pass empty tables back
  end
  
  return result,err
end

OAuthLib.getSessionID = function(UUID)
  if not UUID then return nil,"Missing params to get session ID" end
  debug("Getting session ID")
  local res,err = nil,nil
  local sessionDB = nil
  for i,v in pairs(OAuthLib.supported_services) do
    if v then
      res,err = OAuthLib.getKeys(UUID,nil,i)
      if err then return nil,err end
      if res then
        sessionDB = res[1]['SESSIONID']
        if sessionDB then return sessionDB,nil end
      end
    end
  end

  return nil,"No session ID could be found"
end

OAuthLib.checkAccess = function(UUID,sessionID)
  if not UUID or not sessionID then return nil,"Missing params to check access" end
  debug("Checking access for user")
  local sessionDB,err = OAuthLib.getSessionID(UUID)
  if err then cloud.log(err); return nil,err end

  if sessionDB and sessionDB == sessionID then return true,nil end

  return false,"Invalid sessionID"
end


OAuthLib.makeAccessUrl = function(service,UUID,inScopes)
  if OAuthLib.makeTables then createTables() end --Create all tables
  local res,err = nil,nil
  local proc = require("OAuth.service."..service)
  local auth = proc.auth_url
  local redirect = proc.redirect_url
  local clientID = proc.client_id
  local reqKey = cloud.uuid() --Generate a unique key for this request
  local scopes = ""
  scopes = proc.defaultScopes --Grab default scope
  if inScopes then
    for i=1,#inScopes do
      scopes = scopes.." "..inScopes[i] --Add on our requested scopes
    end
  end
  --Build auth URL
  local URL = cloud.sf("%s?redirect_uri=%s&response_type=%s&client_id=%s&scope=%s&approval_prompt=%s&access_type=%s&state=%s", auth, redirect, "code", clientID, scopes, "auto", "offline",reqKey)
  res,err = writeAuth(reqKey,service,scopes,0,UUID)
  if err then return nil,err end

  return URL,nil
end

OAuthLib.processRedirect = function(reqKey,code)
  local setData,getData,resp,err,errStr = nil,nil,nil,nil,nil
  if not reqKey or not code then return nil,"Response parameters missing." end

  --Check if this reqKey initiated an auth request
  getData,err = getAuth(reqKey)
  if err or not getData then return nil,(err or "Invalid state. Expired or not found.") end
  local service = getData[1]['SERVICE']
  local scopes = getData[1]['SCOPES']
  local UUID = getData[1]['UUID']
  if not service or not scopes then 
    setAuthStatus(reqKey,-1,nil)
    return nil,"Missing parameter from database" 
  end
  local proc = require("OAuth.service."..service)
  --Build token request
  local auth = proc.auth_url
  local redirect = proc.redirect_url
  local clientID = proc.client_id
  local secret = proc.client_secret
  local tokenHost = proc.token_urn_host
  local tokenPath = proc.token_urn_path

  --Exchange code for token
  local reqString = cloud.sf("code=%s&redirect_uri=%s&client_id=%s&client_secret=%s&scope=%s&grant_type=%s", code, redirect, clientID, secret, scopes, "authorization_code")

  local servNet = cloud.network.new(tokenHost,443)
  servNet:method(cloud.POST)
  servNet:ssl_verify(true)
  servNet:body(reqString)
  servNet:path(tokenPath)
  servNet:keep_alive(5000,10)
  servNet:headers({
      ['Content-Type'] = 'application/x-www-form-urlencoded',
      ['Content-Length'] = string.len(servNet:body()),
      ['Accept'] = 'application/json'
    })
  resp,err = servNet:result()
  if err then 
    setAuthStatus(reqKey,-1,nil)
    return nil,err
  end

  local resp = cloud.decode.json(resp)
  if not resp or not next(resp) then
    setAuthStatus(reqKey,-1,nil)
    return nil,"Could not decode response."
  end

  --Use our service specific processing function to generate the needed information.
  --     ID,access,expire,type,refresh,error
  local tID,aToken,eToken,tToken,rToken,err = proc.processForID(reqKey,resp)
  if err then
    setAuthStatus(reqKey,-1,nil)
    return nil,err
  end
  local sessionID = nil
  if not UUID then -- No UUID was provided with the request. Check for an existing entry with this auth ID
    sessionID = cloud.uuid() --Generate a session ID for this login
    local getData,err = OAuthLib.getKeys(nil,tID,service)
    if err then 
      setAuthStatus(reqKey,-1,nil)
      return nil,"Error retrieving key table."
    end
    if getData then UUID = getData[1]['UUID'] end
  end
  if not UUID then UUID = cloud.uuid() end --No UUID existing or provided. Create a new one

  --Whatever UUID gets passed here is this user's permanent ID that links all of their
  --logins together. This will either be a random ID or the one provided by the client.
  setData,err = setAuthStatus(reqKey,0,UUID) --Write ID here so user can grab it
  if err then setAuthStatus(reqKey,-1,nil) return nil,err end
  if sessionID then 
    setData,err = writeSessionID(UUID,cloud.uuid())
    if err then cloud.log(err) end
  end
  setData,err = writeKeys(UUID,tID,service,rToken,aToken,eToken,scopes)
  if err then setAuthStatus(reqKey,-1) return nil,err
  else setData,err = setAuthStatus(reqKey,1,nil)
    if err then cloud.log(err) end
    return true,nil
  end

  return nil,"Unknown"
end

OAuthLib.checkAuthStatus = function(reqKey)
  local getData,err = getAuth(reqKey)
  if err or not getData then return nil,nil,(err or "Invalid reqKey. Expired or not found."),nil end
  local status = getData[1]['STATUS']
  local service = getData[1]['SERVICE']
  local scopes = getData[1]['SCOPES']
  local UUID = getData[1]['UUID']

  if not status or status == -1 or not service or not scopes or (not UUID and status == 1) then
    return -1,service,"Authentication Error",nil --If we failed or have invalid data
  end

  if status == 1 then --Success, return UUID and status code
    local res,err = pruneAuth(reqKey)
    if err then cloud.log("Pruning error: "..err) end
    return 1,service,nil,UUID
  end

  return status,service,nil,nil
end


return OAuthLib
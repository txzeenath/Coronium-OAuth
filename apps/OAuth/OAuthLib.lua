local OAuthLib = {}

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
local debugging = true
OAuthLib.supported_services = {google=true,facebook=true,github=true,slack=false,foursquare=false,dropbox=false,twitter=false} -- must match with service module name
local tablePrefix = "TESTF" -- Must not be nil. This is the prefix for all tables created and read by this API
local makeTables = true --Automatically make tables if they're missing. This can be turned off after the first execution except when adding new services.
local conTab = require("tinywar-DBController.dbParams").conTab() -- This an instance of a MySql parameter table. You can just put a normal table here.
conTab['database'] = 'REG_TINYWAR'
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------




local queueTableName = tablePrefix.."_".."QUEUE"
local keyTableName = tablePrefix.."_".."KEYS"
local userTableName = tablePrefix.."_".."USERS"
local function sqlUUID()
  local id = string.gsub(cloud.uuid(),"-","")
  return id
end

local function debug(string)
  if debugging == true then cloud.log(string) end
end


local function createTables()
  local res,err = cloud.mysql.query(conTab,
    "CREATE TABLE IF NOT EXISTS `"..queueTableName.."` (`reqKey` varchar(32) NULL, `EXPIRES` int(16) NULL, `SERVICE` varchar(16) NULL,`SCOPES` varchar(512) NULL,`STATUS` tinyint(1) NULL, `SESSIONID` varchar(32) NULL, PRIMARY KEY (`reqKey`)) ENGINE='InnoDB' COLLATE 'utf8_unicode_ci';")
  if err then
    return nil,err
  end
  res,err = cloud.mysql.query(conTab,
    "CREATE TABLE IF NOT EXISTS `"..userTableName.."` (`UUID` varchar(32) NULL, `sessionID` varchar(32) NULL, `lastLogin` int(16) NULL, PRIMARY KEY (`UUID`)) ENGINE='InnoDB' COLLATE 'utf8_unicode_ci';")
  if err then
    return nil,err
  end
  res,err = cloud.mysql.query(conTab,
    "CREATE TABLE IF NOT EXISTS `"..keyTableName.."` (`UUID` varchar(32) NULL, `SERVICE` varchar(16) NULL, `OAUTH_ID` varchar(32) NULL,`REFRESH` varchar(256) NULL,`ACTIVE` varchar(256) NULL, `EXPIRES` int(16) NULL, `SCOPES` varchar(512) NULL, `CREATED` int(16) NULL, PRIMARY KEY (`UUID`,`OAUTH_ID`), UNIQUE (`SERVICE`,`OAUTH_ID`)) ENGINE='InnoDB' COLLATE 'utf8_unicode_ci';")
  if err then
    return nil,err
  end

end

--reqKey is optional and will forcibly remove the entry from the table
local function pruneAuth(reqKey)
  if not reqKey then reqKey = "" end --Make an empty string so we don't get a concat error
  local db = cloud.mysql.databag(conTab)
  local result,err = db:delete({
      tableName=queueTableName,
      where = "`EXPIRES` < "..cloud.time.epoch().." OR `reqKey`="..cloud.mysql.string(reqKey)
    })
  return result,err
end

OAuthLib.userToken = function(sessionID,service)
  local res,err = OAuthLib.getUser(nil,sessionID)
  if err then return nil end
  local UUID = res[1]['UUID']
  if not UUID then return nil end

  res,err = OAuthLib.getKeys(UUID,nil,service,1,'ACTIVE')
  if err then cloud.log(err); return nil end
  if not res then return nil end
  local access_token = res[1]['ACTIVE']

  if not access_token then return nil end
  return access_token
end

--Remove an authorization key from table for user
OAuthLib.removeAuth = function(service,UUID)
  if not UUID or not service then return nil,"Can't remove auth: Parameters missing" end
  local db = cloud.mysql.databag(conTab)
  local result,err = db:delete({
      tableName=keyTableName,
      where = '`UUID` = '..cloud.mysql.string(UUID)..' AND `SERVICE`='..cloud.mysql.string(service),
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
local function setAuthStatus(reqKey,statusCode,sessionID)
  local query = nil
  if not sessionID then sessionID = 'NULL' else sessionID = cloud.mysql.string(sessionID) end
  query = "UPDATE "..queueTableName.." SET `STATUS`="..statusCode..",`SESSIONID`=COALESCE("..sessionID..",`SESSIONID`) where `reqKey`="..cloud.mysql.string(reqKey).." LIMIT 1;"
  local result,err = cloud.mysql.query(conTab,query)

  if not result or not next(result) or err then return nil,(err or "Unknown") end
  return result,err
end

--Get entry from auth queue
local function getAuth(reqKey)
  local db = cloud.mysql.databag(conTab)
  local res,err = db:select({
      tableName=queueTableName,
      where = "`reqKey`="..cloud.mysql.string(reqKey),
      limit = 1
    })

  if next(res) then
    for i,v in pairs(res[1]) do
      if v == ngx.null then res[1][i] = nil end
    end
  else
    res = nil --We don't pass empty tables back
  end
  if not res then return nil,"No user found" end
  return res,err
end

--Write entry to auth queue
local function writeAuth(reqKey,service,scopes,status,sessionID)
  local columns = nil
  if sessionID then columns = {'reqKey','EXPIRES','SERVICE','SCOPES','STATUS','SESSIONID'}
  else columns = {'reqKey','EXPIRES','SERVICE','SCOPES','STATUS'} end
  local db = cloud.mysql.databag(conTab)
  local result,err = db:insert({
      tableName=queueTableName,
      columns=columns,
      values = {reqKey,cloud.time.epoch()+(60*5),service,scopes,status,sessionID}
    })


  if not result or not next(result) or err then return nil,(err or "Unknown") end
  return result,err
end

local function writeKeys(UUID,OID,service,refresh,active,expires,scopes)
  if not UUID or not service or not active or not OID then
    cloud.log("Missing arguments to writeKeys function!")
    return nil,"Missing arguments"
  end
  if not expires then expires = 999999999 end --Never expires
  if not refresh then refresh = 'NULL' end

  local UUID = cloud.mysql.string(UUID)
  local OID = cloud.mysql.string(OID)
  local refresh = cloud.mysql.string(refresh)
  local active = cloud.mysql.string(active)
  local scopes = cloud.mysql.string(scopes)
  local expires = cloud.time.epoch()+tonumber(expires)
  local service = cloud.mysql.string(service)
  local query = nil
  local tables = "(`UUID`,`SERVICE`,`OAUTH_ID`,`REFRESH`,`ACTIVE`,`EXPIRES`,`SCOPES`,`CREATED`)"
  local values = "VALUES("..UUID..","..service..","..OID..","..refresh..","..active..","..expires..","..scopes..","..cloud.time.epoch()..")"
  local onDup = "`UUID`=VALUES(`UUID`),`ACTIVE`=VALUES(`ACTIVE`),`REFRESH`=VALUES(`REFRESH`),`SCOPES`=VALUES(`SCOPES`),`EXPIRES`=VALUES(`EXPIRES`)"

  query = "INSERT INTO `"..keyTableName.."` "..tables.." "..values.." ON DUPLICATE KEY UPDATE "..onDup..";"
  local res,err = cloud.mysql.query(conTab, query)


  if not res or not next(res) then return nil,(err or "Unknown") end
  return res,err
end


local function writeUser(UUID,sessionID)
  if not UUID or not sessionID then
    cloud.log("Missing arguments to writeUser function!")
    return nil,"Missing arguments"
  end

  UUID = cloud.mysql.string(UUID)
  sessionID = cloud.mysql.string(sessionID)
  local query = nil
  local tables = "(`UUID`, `SESSIONID`,`lastLogin`)"
  local values = "VALUES("..UUID..","..sessionID..","..cloud.time.epoch()..")"
  local onDup = "`SESSIONID`=VALUES(`SESSIONID`),`lastLogin`=VALUES(`lastLogin`)"

  query = "INSERT INTO `"..userTableName.."` "..tables.." "..values.." ON DUPLICATE KEY UPDATE "..onDup..";"

  local res,err = cloud.mysql.query(conTab, query)


  if not res or not next(res) then return nil,(err or "Unknown") end
  return res,err
end

--Invalidates sessionID for user to forcibly lock their account until next login
OAuthLib.logoutUser = function(UUID,sessionID)
  if not UUID and not sessionID then
    cloud.log("Missing arguments to logout function!")
    return nil,"Missing arguments"
  end
  if not UUID then UUID = "" end
  if not sessionID then sessionID = "" end
  UUID = cloud.mysql.string(UUID)
  sessionID = cloud.mysql.string(sessionID)
  local query = "UPDATE `"..userTableName.."` SET `SESSIONID`="..sqlUUID().." WHERE `UUID`="..UUID.." OR `SESSIONID`="..sessionID.." LIMIT 1;"
  local res,err = cloud.mysql.query(conTab, query)

  if err then return nil,err end

  return res,err
end

--Can check for UUID or OAuthID to grab keys
OAuthLib.getKeys = function(UUID,OAuthID,service,limit,column)
  if not UUID and not OAuthID then return nil,"Missing params to get keys" end
  if OAuthID and not service then return nil,"Must provide service when searching by OAuthID" end

  if not UUID then UUID = "" end
  if not OAuthID then OAuthID = "" end
  UUID = cloud.mysql.string(UUID)
  OAuthID = cloud.mysql.string(OAuthID)
  if service then service = cloud.mysql.string(service) end
  if not column then column = "*" end
  local query = nil
  if service then 
    query ="SELECT "..column.." FROM "..keyTableName.." WHERE (`UUID`="..UUID.." OR `OAUTH_ID`="..OAuthID..") AND `SERVICE`="..service.." LIMIT "..limit..";"
  else
    query ="SELECT "..column.." FROM "..keyTableName.." WHERE `UUID`="..UUID.." OR `OAUTH_ID`="..OAuthID.." LIMIT "..limit..";"
  end
  local res,err = cloud.mysql.query(conTab,query)

  if err then return nil,err end

  if next(res) then
    for i=1,#res do
      for x,v in pairs(res[i]) do
        if v == ngx.null then res[i][x] = nil end --This might make holes in the table
      end
    end
  else
    res = nil --But we don't pass empty tables back
  end

  return res,nil
end

--Gets a user row from a UUID or sessionID
OAuthLib.getUser = function(UUID,sessionID)
  if not UUID and not sessionID then return nil,"Missing params to get user" end
  debug("Getting user")
  if not UUID then UUID = "" end
  if not sessionID then sessionID = "" end
  UUID = cloud.mysql.string(UUID)
  sessionID = cloud.mysql.string(sessionID)
  local db = cloud.mysql.databag(conTab)
  local res,err = db:select({
      tableName=userTableName,
      where = "`UUID`="..UUID.." OR `SESSIONID`="..sessionID,
      limit = 1
    })
  if err then 
    cloud.log(err)
    return nil,"No user found"
  end

  if next(res) then
    for i,v in pairs(res[1]) do
      if v == ngx.null then res[1][i] = nil end --This might make holes in the table
    end
  else
    res = nil --But we don't pass empty tables back
  end

  if not res then return nil,"No user found" end

  return res,nil
end


OAuthLib.makeAccessUrl = function(service,sessionID,inScopes)
  local res,err = nil,nil
  if makeTables then 
    res,err = createTables() --Create all tables
    if err then cloud.log(err) end
  end
  local proc = require("OAuth.service."..service)
  local auth = proc.auth_url
  local redirect = proc.redirect_url
  local clientID = proc.client_id
  local reqKey = sqlUUID() --Generate a unique key for this request
  local scopes = ""
  scopes = proc.defaultScopes --Grab default scope
  if inScopes then
    for i=1,#inScopes do
      scopes = scopes.." "..inScopes[i] --Add on our requested scopes
    end
  end
  --Build auth URL
  local URL = cloud.sf("%s?redirect_uri=%s&response_type=%s&client_id=%s&scope=%s&approval_prompt=%s&access_type=%s&state=%s", auth, redirect, "code", clientID, scopes, "auto", "offline",reqKey)
  res,err = writeAuth(reqKey,service,scopes,0,sessionID)
  if err then return nil,nil,err end

  return URL,reqKey,nil
end

OAuthLib.processRedirect = function(reqKey,code)
  if not reqKey or not code then return nil,"Response parameters missing." end

  --Check if this reqKey initiated an auth request
  local res,err = getAuth(reqKey)
  if err then return nil,err end
  local service = res[1]['SERVICE']
  local scopes = res[1]['SCOPES']
  local sessionID = res[1]['SESSIONID']
  if not service or not scopes then 
    setAuthStatus(reqKey,-1,nil)
    return nil,"Missing parameter from database" 
  end
  local proc = require("OAuth.service."..service)
  --Build token request
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
  res,err = servNet:result()
  if err then 
    setAuthStatus(reqKey,-1,nil)
    return nil,err
  end

  res = cloud.decode.json(res)
  if not res or not next(res) then
    setAuthStatus(reqKey,-1,nil)
    return nil,"Could not decode response."
  end

  --Use our service specific processing function to generate the needed information.
  --     ID,access,expire,type,refresh,error
  local tID,aToken,eToken,tToken,rToken,err = proc.processForID(reqKey,res)
  if err then setAuthStatus(reqKey,-1); return nil,err end
  local UUID = nil

  if not sessionID then -- No sessionID was found in request.
    sessionID = sqlUUID() --Generate a session ID for this login
    local res,err = OAuthLib.getKeys(nil,tID,service,1,"UUID") --Check for an existing OAuth ID
    if err then cloud.log(err); setAuthStatus(reqKey,-1); return nil,"Error retrieving key table." end
    if res then UUID = res[1]['UUID'] end
  else --Session was provided, find user
    res,err = OAuthLib.getUser(nil,sessionID)
    if err then setAuthStatus(reqKey,-1); return nil,err end
    UUID = res[1]['UUID']
    if not UUID then setAuthStatus(reqKey,-1); return nil,"No UUID found" end
  end

  if not UUID then UUID = sqlUUID() end --No UUID found in keys or session. Create a new one

  res,err = setAuthStatus(reqKey,0,sessionID) --Write session ID here so user can grab it
  if err then setAuthStatus(reqKey,-1); return nil,err end

  res,err = writeUser(UUID,sessionID)
  if err then setAuthStatus(reqKey,-1); return nil,err end

  res,err = writeKeys(UUID,tID,service,rToken,aToken,eToken,scopes)
  if err then setAuthStatus(reqKey,-1); return nil,err end

  res,err = setAuthStatus(reqKey,1,nil)
  if err then cloud.log(err) end

  return true,nil
end

OAuthLib.checkAuthStatus = function(reqKey)
  local getData,err = getAuth(reqKey)
  if err or not getData then return nil,nil,(err or "Invalid reqKey. Expired or not found."),nil end
  local status = getData[1]['STATUS']
  local service = getData[1]['SERVICE']
  local scopes = getData[1]['SCOPES']
  local sessionID = getData[1]['SESSIONID']

  if not status or status == -1 or not service or not scopes or (not sessionID and status == 1) then
    return -1,service,"Authentication Error",nil --If we failed or have invalid data
  end

  if status == 1 then --Success, return UUID and status code
    local res,err = pruneAuth(reqKey)
    if err then cloud.log("Pruning error: "..err) end
    return status,service,nil,sessionID
  end

  return status,service,nil,nil
end


return OAuthLib
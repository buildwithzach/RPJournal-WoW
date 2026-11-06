-- Capability checks for Forever's Mainline-derived UI. No client globals are replaced.
CMCompat = {}
local C = CMCompat
C.unsupportedEvents = {}

function C.IsSecret(value)
  return type(issecretvalue) == "function" and issecretvalue(value)
end

function C.Read(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d = pcall(fn, ...)
  if not ok or C.IsSecret(a) or C.IsSecret(b) or C.IsSecret(c) or C.IsSecret(d) then return nil end
  return a, b, c, d
end

function C.UnitGUID(unit)
  local guid = C.Read(UnitGUID, unit)
  return type(guid) == "string" and guid or nil
end

function C.UnitName(unit)
  local name, realm = C.Read(UnitName, unit)
  if type(name) ~= "string" then return nil end
  return name, type(realm) == "string" and realm ~= "" and realm or nil
end

function C.GuildInfo(unit)
  local fn = C_GuildInfo and C_GuildInfo.GetGuildInfo or GetGuildInfo
  return C.Read(fn, unit)
end

function C.RegisterEvent(frame, event)
  local valid = not C_EventUtils or not C_EventUtils.IsEventValid or C.Read(C_EventUtils.IsEventValid, event)
  local ok = valid and pcall(frame.RegisterEvent, frame, event)
  if not ok then C.unsupportedEvents[event] = true end
  return ok and true or false
end

function C.Text(value, limit)
  if C.IsSecret(value) or type(value) ~= "string" then return "" end
  value = value:gsub("[%z\001-\008\011\012\014-\031]", "")
  limit = limit or 2048
  if #value <= limit then return value end
  local cut = limit
  while cut > 0 do
    local nextByte = value:byte(cut + 1)
    if not nextByte or nextByte < 128 or nextByte >= 192 then break end
    cut = cut - 1
  end
  return value:sub(1, cut)
end

function C.Display(value, limit)
  return (C.Text(value, limit):gsub("|", "||"))
end

function C.NameKey(value)
  if type(value) ~= "string" or C.IsSecret(value) then return nil end
  value = value:gsub("%s", "")
  if value == "" or #value > 100 or value:find("[|%c]") then return nil end
  if not value:find("-", 1, true) then
    local realm = C.Read(GetNormalizedRealmName) or C.Read(GetRealmName)
    if realm then value = value .. "-" .. realm:gsub("%s", "") end
  end
  return value:lower()
end

function C.ClientInfo()
  local version, build, _, interface = C.Read(GetBuildInfo)
  return { version = version or "unknown", build = build or "unknown", interface = interface,
    forever = version == "1.60.1" and interface == 16001 }
end

function C.SendChat(text, channel)
  local fn = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
  if type(fn) ~= "function" then return false end
  local ok = pcall(fn, C.Text(text, 250):gsub("|", ""), channel)
  return ok
end

-- Fail closed before modules register events, timers, hooks or migrate saved data.
C.supported = C.ClientInfo().forever
if not C.supported then
  local function unsupported()
    print("RP Journal requires WoW Forever 1.60.1 (Interface 16001). Addon disabled; journal data is unchanged.")
  end
  CharacterMemory_OpenJournal = unsupported
  CharacterMemory_RememberTarget = unsupported
  unsupported()
end

function C.Version()
  local fn = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
  return C.Read(fn, "CharacterMemory", "Version") or "unknown"
end

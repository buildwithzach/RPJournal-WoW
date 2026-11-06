-- Explicit, synthetic WoW API boundary. No game process or network connection.
MOCK = { epoch = 1792231200, elapsed = 100, frames = {}, tickers = {}, messages = {}, chat = {} }
local actors = {
  player = { guid = "Player-1-SELF", name = "Rowan", realm = "FictionalRealm" },
  target = { guid = "Player-1-ELARA", name = "Elara", realm = "FictionalRealm" },
}
function GetTime() return MOCK.elapsed end
function time() return MOCK.epoch end
function date(format) return os.date(format, MOCK.epoch) end
function InCombatLockdown() return false end
function UnitExists(unit) return actors[unit] ~= nil end
function UnitIsPlayer(unit) return actors[unit] ~= nil end
function UnitGUID(unit) return actors[unit] and actors[unit].guid end
function UnitName(unit)
  local actor = actors[unit]
  if actor then return actor.name, actor.realm end
end
function UnitClass() return "Mage", "MAGE" end
function UnitRace() return "Human", "Human" end
function UnitLevel() return 12 end
function UnitFactionGroup() return "Alliance" end
function UnitSex() return 3 end
function UnitIsFriend() return true end
function IsInGroup() return false end
function IsInRaid() return false end
function IsInInstance() return false, "none" end
function IsResting() return false end
function GetNumGroupMembers() return 0 end
function GetNumSubgroupMembers() return 0 end
function GetZoneText() return "Elwynn Forest" end
function GetSubZoneText() return "Goldshire" end
function wipe(value) for key in pairs(value) do value[key] = nil end end
function SendChatMessage(text, channel) MOCK.chat[#MOCK.chat + 1] = { text = text, channel = channel } end
C_Map = { GetBestMapForUnit = function() return 37 end, GetMapInfo = function() return { name = "Elwynn Forest" } end }
C_FriendList = { IsFriend = function() return false end }
C_ChatInfo = {
  RegisterAddonMessagePrefix = function() return true end,
  SendAddonMessage = function(prefix, message, channel, target)
    MOCK.messages[#MOCK.messages + 1] = { prefix = prefix, message = message, channel = channel, target = target }
  end,
}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) MOCK.chat[#MOCK.chat + 1] = { text = message } end }
function print(message) MOCK.chat[#MOCK.chat + 1] = { text = tostring(message) } end
SlashCmdList, StaticPopupDialogs, UISpecialFrames = {}, {}, {}
local methods = {}
function methods:RegisterEvent(event) self.events[event] = true end
function methods:SetScript(event, callback) self.scripts[event] = callback end
function methods:HookScript(event, callback) self.scripts[event] = callback end
function methods:IsShown() return false end
function methods:GetText() return self.text or "" end
function methods:GetChecked() return false end
function CreateFrame(kind, name)
  local frame = setmetatable({ events = {}, scripts = {}, kind = kind }, { __index = methods })
  MOCK.frames[#MOCK.frames + 1] = frame
  if name then _G[name] = frame end
  return frame
end
UIParent = CreateFrame("Frame", "UIParent")
RPBioFrame = CreateFrame("Frame", "RPBioFrame")
local function timer(seconds, callback)
  local value = { seconds = seconds, callback = callback, cancelled = false }
  function value:Cancel() self.cancelled = true end
  MOCK.tickers[#MOCK.tickers + 1] = value
  return value
end
C_Timer = { NewTicker = timer, NewTimer = timer, After = function(seconds, callback) return timer(seconds, callback) end }
function MOCK.Emit(event, ...)
  for _, frame in ipairs(MOCK.frames) do
    if frame.events[event] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end
  end
end
function MOCK.Advance(seconds)
  MOCK.epoch = MOCK.epoch + seconds
  MOCK.elapsed = MOCK.elapsed + seconds
end

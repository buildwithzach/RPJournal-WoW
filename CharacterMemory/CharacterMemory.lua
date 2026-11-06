if not CMCompat or not CMCompat.supported then return end
--[[
Character Memory — RP Relationship Journal with Leveling System

WoW Forever RP journal. No external libraries.

Features
- Per-target memory journal (players) storing first/last seen context and notes
- Relationship leveling system with XP sources, cooldowns, and tiers
- Movable UI panel showing key info and a relationship bar
- Slash commands for notes, sharing, toggles, relation info, and manual XP adjust
- Per-character SavedVariables persistence

Implementation notes
- Uses UnitGUID as key; display short name (without realm) in UI
- Timestamps stored as ISO UTC via date("!%Y-%m-%d %H:%M:%S UTC")
- Zone context via C_Map.GetBestMapForUnit("player") and GetSubZoneText()
- UI hides in combat and restores after

Future TODOs (not required for MVP)
- Options panel (interface options)
- Full journal list/search UI
- Minimap button via LibDBIcon (if desired)
]]

-- OPT: Diagnostics off for WoW API stub noise in editors; no runtime impact
---@diagnostic disable: undefined-field, param-type-mismatch, assign-type-mismatch, cast-local-type, need-check-nil

local ADDON_NAME = ...

-- OPT: Hoist hot globals to locals to reduce global table lookups (CPU)
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local CreateFrame = CreateFrame
local UIParent = UIParent
local UnitExists = UnitExists
local UnitIsPlayer = UnitIsPlayer
local UnitGUID = CMCompat.UnitGUID
local UnitName = CMCompat.UnitName
local UnitClass = UnitClass
local UnitRace = UnitRace
local UnitLevel = UnitLevel
local UnitFactionGroup = UnitFactionGroup
local UnitSex = UnitSex
local UnitIsFriend = UnitIsFriend
local C_FriendList = C_FriendList
local GetGuildInfo = CMCompat.GuildInfo
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local IsInInstance = IsInInstance
local IsResting = IsResting
local GetNumGroupMembers = GetNumGroupMembers
local GetNumSubgroupMembers = GetNumSubgroupMembers
local GetRaidRosterInfo = GetRaidRosterInfo
local SendChatMessage = SendChatMessage
local SetPortraitTexture = SetPortraitTexture
local C_Map = C_Map
local time = time
local date = date
local print = print
local string_format = string.format
local math_floor = math.floor
local math_sqrt = math.sqrt

-- -----------------------------------------------------------------------------
-- SavedVariables bootstrap
-- -----------------------------------------------------------------------------

CharacterMemoryDB = CharacterMemoryDB or {}

-- OPT: Lightweight debug logger gated by CMUI.debug
_G.CMUI = _G.CMUI or {}
CMUI.debug = CMUI.debug or false
local function dbg(fmt, ...)
  if CMUI and CMUI.debug then
    DEFAULT_CHAT_FRAME:AddMessage("|cff999999[CM]|r " .. (select('#', ...) > 0 and string_format(fmt, ...) or tostring(fmt)))
  end
end

-- Forward declarations to allow early helper usage
local computeLevelFromXP
local computeTierFromLevel
local getOrCreateEntry
local awardXP
local awardToAllGroupmates
local incStatForAllGroupmates
local maybeCreditDungeonOnExit
local handleLFGCompletion
local handleChallengeModeCompleted
local handleScenarioCompleted
local handlePvpMatchComplete
local resetDungeonRun
local refreshRelationship

local function initializeDatabase()
  CharacterMemoryDB.version = tonumber(CharacterMemoryDB.version) or 1
  CharacterMemoryDB.settings = CharacterMemoryDB.settings or {
    showOnTarget = true,
    shareEnabled = false,
    anchor = { point = "CENTER", x = 0, y = 200 },
  }
  CharacterMemoryDB.settings.ui = CharacterMemoryDB.settings.ui or {
    journal = { x = 0, y = 0, w = 900, h = 520, isShown = false, darkOverlay = true },
    targetPanel = { x = 0, y = 200, w = 420, h = 220, darkOverlay = true },
  }
  -- ensure new defaults exist
  if CharacterMemoryDB.settings.showOnTarget == nil then CharacterMemoryDB.settings.showOnTarget = true end
  if not CharacterMemoryDB.settings.quietJournalDefaults then
    CharacterMemoryDB.settings.shareEnabled = false
    CharacterMemoryDB.settings.quietJournalDefaults = true
  end
  CharacterMemoryDB.settings.anchor = CharacterMemoryDB.settings.anchor or { point = "CENTER", x = 0, y = 200 }
  if CharacterMemoryDB.settings.useSheetOnTarget == nil then CharacterMemoryDB.settings.useSheetOnTarget = true end
  CharacterMemoryDB.settings.minimap = CharacterMemoryDB.settings.minimap or { enabled = true, angle = 210 }
  CharacterMemoryDB.entries = CharacterMemoryDB.entries or {}
  if CharacterMemoryDB.settings.bioSharing == nil then CharacterMemoryDB.settings.bioSharing = false end
  CMChronicle.Initialize(CharacterMemoryDB)
  CMProfile.Ensure()
end

local function fixupEntries()
  for guid, e in pairs(CharacterMemoryDB.entries) do
    if type(e) == "table" then
      e.guid = guid
      e.profile = type(e.profile) == "table" and e.profile or {}
      e.stats = type(e.stats) == "table" and e.stats or {}
      e.notes = type(e.notes) == "string" and e.notes or ""
      e.metCount = tonumber(e.metCount) or 0
      e.xp = tonumber(e.xp) or 0
      if e.xp ~= e.xp or e.xp == math.huge or e.xp < 0 then e.xp = 0 end
      refreshRelationship(e)
    end
  end
  CharacterMemoryDB.version = math.max(2, CharacterMemoryDB.version or 1)
end

-- -----------------------------------------------------------------------------
-- Constants and helpers
-- -----------------------------------------------------------------------------

local POSITIVE_EMOTES = {
  wave = true, bow = true, cheer = true, hug = true, salute = true, kiss = true, love = true,
}

local TIER_THRESHOLDS = {
  { level = 20, name = "Bonded" },
  { level = 15, name = "Trusted" },
  { level = 10, name = "Close Friend" },
  { level = 6,  name = "Friend" },
  { level = 3,  name = "Familiar" },
  { level = 1,  name = "Acquaintance" },
  { level = 0,  name = "Stranger" },
}

local CHAT_PREFIX = "|cffb48c55Character Memory|r"

local function printMessage(msg)
  -- OPT: Route through one concatenation; user-facing messages remain
  DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. " " .. (msg or ""))
end

-- -----------------------------------------------------------------------------
-- Addon message protocol (public bio sharing)
-- -----------------------------------------------------------------------------

local ADDON_MSG_PREFIX = CMProtocol.PREFIX

-- -----------------------------------------------------------------------------
-- Interface Options panel wiring
-- -----------------------------------------------------------------------------

local function ensureOptionsPanelRegistered()
  if not _G.CM_OptionsPanel then return end
  if Settings and Settings.RegisterAddOnCategory then
    -- Dragonflight+ Settings UI
    if not _G.CM_OptionsCategory then
      local category = Settings.RegisterCanvasLayoutCategory(_G.CM_OptionsPanel, "RP Journal")
      category.ID = "CharacterMemoryOptions"
      Settings.RegisterAddOnCategory(category)
      _G.CM_OptionsCategory = category
    end
  elseif _G.InterfaceOptions_AddCategory then
    -- Classic/older
    _G.InterfaceOptions_AddCategory(_G.CM_OptionsPanel)
  end
end

local function wireEscapeAndFocus()
  if UISpecialFrames then
    for _, name in ipairs({ "CMJ_RootXML", "RPBioFrame" }) do
      local exists = false; for _, saved in ipairs(UISpecialFrames) do if saved == name then exists = true; break end end
      if not exists then table.insert(UISpecialFrames, name) end
    end
  end
end

function CharacterMemory_OptionsOnShow() if CMSettings then CMSettings.Load() end end
function CharacterMemory_OptionsSave() if CMSettings then CMSettings.Save() end end
-- Preserve old callers without exposing a second profile editor or destructive footer.
function CharacterMemory_OptionsTabSwap(which) if which == "Bio" then CharacterMemory_OpenCharacterSheet() end end
function CharacterMemory_OptionsPublish()
  CharacterMemory_OpenCharacterSheet()
  printMessage("Enable Share public profile in your character sheet, then Save.")
end
function CharacterMemory_OptionsClearSelected()
  local guid = CMUI.GetSelectedEntry and CMUI.GetSelectedEntry()
  if guid and CMUI.DeleteEntry then CMUI.DeleteEntry(guid) end
end

function CharacterMemory_RequestBioFrom(targetFullName, guid)
  if not guid then
    local key = CMCompat.NameKey(targetFullName)
    for id, e in pairs(CharacterMemoryDB.entries or {}) do
      if type(e) == "table" and key and CMCompat.NameKey(e.name) == key then guid = id; break end
    end
  end
  return CMProtocol.Request(targetFullName, guid)
end

-- -----------------------------------------------------------------------------
-- Theme (fantasy parchment + gold accents)
-- -----------------------------------------------------------------------------

local THEME = {
  gold = { r = 0.95, g = 0.82, b = 0.31 },
  goldHex = "|cfff2d24f",
  silverHex = "|cffcfd5de",
  darkOverlayAlpha = 0.8,
  -- Prefer TGA parchment if provided; fallback to generic only if missing
  bgParchment = (function()
    local tga = "Interface/AddOns/CharacterMemory/Art/parchment.tga"
    local ok, fileID = pcall(GetFileIDFromPath, tga)
    if ok and fileID and fileID ~= 0 then return tga else return "Interface/FrameGeneral/UI-Background-Rock" end
  end)(),
  border = "Interface/Tooltips/UI-Tooltip-Border",
  quillTex = "Interface/PaperDollInfoFrame/Character-TitleIcon",
}

-- Prefer local TGA art if it exists; otherwise use provided fallback
local function preferArt(localBaseName, fallback)
  local tga = "Interface/AddOns/CharacterMemory/Art/" .. localBaseName .. ".tga"
  local ok, fileID = pcall(GetFileIDFromPath, tga)
  if ok and fileID and fileID ~= 0 then return tga end
  return fallback
end

THEME.quillTex = preferArt("quill", THEME.quillTex)

-- Remove PNG stylings from base module; Journal/Profile manage their own art
local MEDIA = { parchment = THEME.bgParchment }

-- safely add a round alpha mask to a texture if supported
local function tryApplyRoundMask(texture)
  if not texture or not texture.CreateMaskTexture then return end
  local ok, mask = pcall(texture.CreateMaskTexture, texture)
  if not ok or not mask then return end
  mask:SetAllPoints(true)
  mask:SetTexture("Interface/CharacterFrame/TempPortraitAlphaMask")
  if texture.AddMaskTexture then
    pcall(texture.AddMaskTexture, texture, mask)
  end
end

local function setGoldText(fontString, text, large)
  local prefix = THEME.goldHex
  local suffix = "|r"
  fontString:SetText((prefix)..(text or "")..suffix)
  if large then fontString:SetFontObject("GameFontNormalLarge") end
end

local function setTextureSafe(tex, path)
  if tex and path then
    pcall(tex.SetTexture, tex, path)
  end
end

local function setTexCoordSafe(tex, a,b,c,d)
  if tex and a then
    pcall(tex.SetTexCoord, tex, a,b,c,d)
  end
end

-- Forward declare for use before definition
local applyParchmentBackground

-- Creates a parchment skinned frame with an inner content canvas honoring padding
local function CM_CreateParchmentFrame(parent, width, height, padding)
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  f:SetSize(width or 900, height or 520)
  applyParchmentBackground(f)
  padding = padding or 18
  local canvas = CreateFrame("Frame", nil, f)
  canvas:SetPoint("TOPLEFT", padding, -padding)
  canvas:SetPoint("BOTTOMRIGHT", -padding, padding)
  f._cmCanvas = canvas
  return f, canvas
end

function applyParchmentBackground(frame)
  if frame._cmBgTex then frame._cmBgTex:Hide() end
  local bg = frame:CreateTexture(nil, "BACKGROUND")
  setTextureSafe(bg, MEDIA.parchment)
  bg:SetPoint("CENTER")
  local function layout()
    local w = math.max(300, frame:GetWidth() or 900)
    local h = math.max(200, frame:GetHeight() or 520)
    local texW, texH = 1024, 512
    local scaledH = (w / texW) * texH
    if scaledH >= h then
      bg:SetSize(w, scaledH)
    else
      bg:SetSize((h / texH) * texW, h)
    end
  end
  frame:HookScript("OnSizeChanged", layout)
  layout()
  frame._cmBgTex = bg

  -- Gold corners
  local function corner(path, point, ox, oy)
    local t = frame:CreateTexture(nil, "BORDER")
    setTextureSafe(t, path)
    t:SetSize(24, 24)
    t:SetPoint(point, frame, point, ox or 0, oy or 0)
  end
  -- Guard optional corner art; only create if paths are present
  if MEDIA.cornerTL and MEDIA.cornerTR and MEDIA.cornerBL and MEDIA.cornerBR then
    corner(MEDIA.cornerTL, "TOPLEFT", 6, -6)
    corner(MEDIA.cornerTR, "TOPRIGHT", -6, -6)
    corner(MEDIA.cornerBL, "BOTTOMLEFT", 6, 6)
    corner(MEDIA.cornerBR, "BOTTOMRIGHT", -6, 6)
  end

  local overlay = frame:CreateTexture(nil, "BORDER")
  overlay:SetAllPoints(true)
  overlay:SetColorTexture(0, 0, 0, 0.22)
  frame._cmOverlay = overlay
end

-- Removed unused styleGoldButton; journal provides its own visuals

-- Removed unused styleSearchEdit helper

-- Removed unused createGoldBar helper

local function classColorHex(classFile)
  if not classFile or not RAID_CLASS_COLORS or not RAID_CLASS_COLORS[classFile] then return nil end
  local c = RAID_CLASS_COLORS[classFile]
  return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end

local function colorizeNameByClass(name, classFile)
  local hex = classColorHex(classFile)
  if hex then return hex .. (name or "") .. "|r" end
  return name or ""
end

local function shortName(name)
  if not name then return "Unknown" end
  local base = name:match("([^%-]+)")
  return base or name
end

local function nowUTCString()
  return date("!%Y-%m-%d %H:%M:%S UTC")
end

-- OPT: Debounced zone context to avoid repeated C_Map calls (CPU); refreshed on zone change
local zoneCache = { name = nil, sub = nil, stamp = 0 }
local function getZoneContext()
  local t = GetTime()
  if (t - (zoneCache.stamp or 0)) < 0.5 and zoneCache.name then
    return zoneCache.sub and (zoneCache.name .. " - " .. zoneCache.sub) or zoneCache.name
  end
  local uiMapID = C_Map.GetBestMapForUnit("player")
  local info = uiMapID and C_Map.GetMapInfo(uiMapID)
  local zoneName = (info and info.name) or GetZoneText() or "Unknown"
  local subzone = GetSubZoneText()
  if subzone == "" or subzone == zoneName then subzone = nil end
  zoneCache.name, zoneCache.sub, zoneCache.stamp = zoneName, subzone, t
  return subzone and (zoneName .. " - " .. subzone) or zoneName
end

-- OPT: Defensive format helpers per spec
local function FmtDate(s)
  return (type(s) == "string" and #s >= 10) and s:sub(1,10) or "—"
end
local function FmtZone(z)
  return (type(z) == "string" and z ~= "") and z or "—"
end
local function FmtNum(n)
  n = tonumber(n or 0) or 0
  local s = tostring(math_floor(n))
  local k; repeat s,k = s:gsub("^(%-?%d+)(%d%d%d)", '%1,%2') until k==0
  return s
end
local function FmtTimeShort(secs)
  secs = tonumber(secs or 0) or 0
  local h = math_floor(secs/3600); local m = math_floor((secs%3600)/60)
  if h>0 then return string_format("%dh %dm", h, m) else return string_format("%dm", m) end
end
local function FmtRel(xp)
  xp = tonumber(xp) or 0
  local level = math_floor(math_sqrt(xp / 100))
  local tier = computeTierFromLevel(level)
  local curr = (level * level) * 100
  local nextF = ((level + 1) * (level + 1)) * 100
  local span = nextF - curr
  local pct = span > 0 and math_floor(((xp - curr) / span) * 100 + 0.5) or 100
  return level, tier, pct
end

-- OPT: Expose helpers for UI module usage
CMUI.FmtDate = FmtDate
CMUI.FmtZone = FmtZone
CMUI.FmtRel = FmtRel
CMUI.FmtNum = FmtNum
CMUI.FmtTimeShort = FmtTimeShort

function computeLevelFromXP(xp)
  -- OPT: Use local math bindings
  xp = tonumber(xp) or 0
  if xp ~= xp or xp == math.huge or xp < 0 then xp = 0 end
  return math_floor(math_sqrt(xp / 100))
end

function computeTierFromLevel(level)
  for _, t in ipairs(TIER_THRESHOLDS) do
    if level >= t.level then
      return t.name
    end
  end
  return "Stranger"
end

_G.computeLevelFromXP = computeLevelFromXP
_G.computeTierFromLevel = computeTierFromLevel

-- Next level threshold helpers for progress bar
local function xpForLevel(level)
  -- Solve for xp such that level = floor(sqrt(xp/100)) => min xp for level L is (L^2)*100
  return (level * level) * 100
end

local function progressToNextLevel(xp)
  local level = computeLevelFromXP(xp)
  local currFloor = xpForLevel(level)
  local nextFloor = xpForLevel(level + 1)
  local span = nextFloor - currFloor
  local into = xp - currFloor
  local pct = span > 0 and math.min(100, math.max(0, (into / span) * 100)) or 100
  return level, pct
end

-- -----------------------------------------------------------------------------
-- Item Level capture and caching
-- -----------------------------------------------------------------------------

local lastInspectAt = 0
local function canInspectNow()
  local t = GetTime() or 0
  return (t - lastInspectAt) > 2.0 and not InCombatLockdown()
end

function CharacterMemory_UpdatePlayerItemLevel()
  if not UnitGUID or not GetAverageItemLevel then return end
  local guid = UnitGUID("player")
  if not guid then return end
  local e = getOrCreateEntry(guid)
  if not e then return end
  local avg, equipped = GetAverageItemLevel()
  if equipped and equipped > 0 then
    e.itemLevel = math_floor(equipped + 0.5)
    CharacterMemory_UpdateUI()
  end
end

function CharacterMemory_RequestTargetItemLevel()
  if CharacterMemoryDB.settings.enableInspect == false then return end
  if not UnitExists or not UnitIsPlayer or not UnitGUID then return end
  if not canInspectNow() then return end
  if not CanInspect or not NotifyInspect then return end
  if not UnitExists("target") or not UnitIsPlayer("target") then return end
  if UnitIsUnit and UnitIsUnit("target", "player") then
    CharacterMemory_UpdatePlayerItemLevel(); return
  end
  if CheckInteractDistance and not CheckInteractDistance("target", 1) then return end -- 28 yards
  lastInspectAt = GetTime() or 0
  pcall(NotifyInspect, "target")
end

function CharacterMemory_OnInspectReady(inspectedGuid)
  if not inspectedGuid or inspectedGuid ~= UnitGUID("target") then return end
  local e = getOrCreateEntry(inspectedGuid)
  if not e then return end
  -- Some builds expose GetInspectItemLevel or C_PaperDollInfo.GetInspectItemLevel
  local ilvl = nil
  if _G.C_PaperDollInfo and _G.C_PaperDollInfo.GetInspectItemLevel then
    local ok, v = pcall(_G.C_PaperDollInfo.GetInspectItemLevel, "target")
    if ok and not CMCompat.IsSecret(v) and type(v) == "number" and v > 0 then ilvl = v end
  end
  if not ilvl and _G.GetAverageItemLevel then
    -- Fallback: GetAverageItemLevel returns your own; not for inspected targets
    ilvl = nil
  end
  if ilvl and ilvl > 0 then
    e.itemLevel = math_floor(ilvl + 0.5)
    CharacterMemory_UpdateUI()
  end
end

-- -----------------------------------------------------------------------------
-- State and cooldowns
-- -----------------------------------------------------------------------------

local State = {
  -- legacy UI frame fields intentionally unused; kept to avoid runtime errors
  frame = nil,
  bar = nil,
  barText = nil,
  bodyFontString = nil,
  noteEditBox = nil,
  shareButton = nil,
  currentGUID = nil,
  wasOpenBeforeCombat = false,
}

-- Per-target cooldown tables (GUID -> timestamp)
local Cooldowns = {
  emote = {},       -- 10s
  whisper = {},     -- 60s
  retarget = {},    -- track last seen in entry; this table unused for logic but kept for clarity
  groupTick = {},   -- 300s gating per GUID
  tavernTick = {},  -- 120s gating per GUID
  instanceGroupTick = {}, -- 120s while inside instances
}

local function canFireCooldown(tbl, guid, cdSeconds)
  local last = tbl[guid]
  local t = GetTime()
  if not last or (t - last) >= cdSeconds then
    tbl[guid] = t
    return true
  end
  return false
end

-- Track counted group session per target to increment party/raid once per session
local GroupSessionCounted = {}
local GroupSessionStartAt = 0
local lastNearbyTickAt = 0
local lastChatTickAt = 0

-- -----------------------------------------------------------------------------
-- Data accessors
-- -----------------------------------------------------------------------------

function getOrCreateEntry(guid)
  if type(guid) ~= "string" or not guid:match("^Player%-") then return nil end
  local e = CharacterMemoryDB.entries[guid]
  if not e then
    -- Only create entries for real player GUIDs; do not persist NPCs/creatures
    if type(guid) ~= "string" or not guid:match("^Player%-") then
      return nil
    end
    e = {
      name = "",
      isPlayer = false,
      class = nil,
      classFile = nil,
      race = nil,
      charLevel = nil,
      faction = nil,
      gender = nil,
      firstMetAt = nil,
      firstMetWhere = nil,
      lastSeenAt = nil,
      lastSeenWhere = nil,
      notes = "",
      metCount = 0,
      xp = 0,
      level = 0,
      tier = "Stranger",
      _lastSeenStamp = 0,
      profile = {
        alias = "",
        alignment = "",
        personality = "",
        ideals = "",
        bonds = "",
        flaws = "",
        plans = "",
        background = "",
        otherInfo = "",
        backstory = "",
        languages = "",
        proficiencies = "",
        appearance = { age = "", height = "", weight = "", eyes = "", hair = "" },
      },
      stats = {
        parties = 0,
        raids = 0,
        pvpMatches = 0,
        arenaMatches = 0,
        duels = 0,
        petDuels = 0,
        trades = 0,
        whispers = 0,
        emotes = 0,
        dungeonCompletions = 0,
        mplusCompletions = 0,
        scenarioCompletions = 0,
        bossKillsDungeon = 0,
        bossKillsRaid = 0,
        groupTicks = 0,
        instanceTicks_party = 0,
        instanceTicks_raid = 0,
        instanceTicks_pvp = 0,
        instanceTicks_arena = 0,
        tavernTicks = 0,
        reconnects = 0,
        firstMeets = 0,
      },
    }
    CharacterMemoryDB.entries[guid] = e
  end
  if type(e) ~= "table" then return nil end
  e.guid = guid
  e.metCount = tonumber(e.metCount) or 0
  e.xp = tonumber(e.xp) or 0
  e.profile = e.profile or {}
  e.stats = e.stats or {}
  CMChronicle.Prepare(e, guid)
  return e
end

-- Expose for achievements module
_G.CharacterMemory_GetOrCreateEntry = getOrCreateEntry

local function deleteEntry(guid)
  if guid and CharacterMemoryDB.entries[guid] then
    CharacterMemoryDB.entries[guid] = nil
    if State.currentGUID == guid then
      State.currentGUID = nil
    end
  end
end

-- -----------------------------------------------------------------------------
-- XP engine
-- -----------------------------------------------------------------------------

function refreshRelationship(entry)
  entry.level = computeLevelFromXP(entry.xp)
  
  -- Hard requirement: Strangers need 3 completed achievements to become Acquaintances
  if entry.level >= 1 then
    local achievementSummary = _G.CharacterMemory_GetAchievementSummary and _G.CharacterMemory_GetAchievementSummary(entry.guid)
    local completedAchievements = achievementSummary and achievementSummary.done or 0
    
    if completedAchievements >= 3 then entry.relationshipUnlocked = true end
    if not entry.relationshipUnlocked then
      -- Force them to stay at level 0 (Stranger) until they complete 3 achievements
      entry.level = 0
      entry.tier = "Stranger"
      return
    end
  end
  
  entry.tier = computeTierFromLevel(entry.level)
end

CharacterMemory_RefreshRelationship = refreshRelationship

local function ensureStats(entry)
  entry.stats = entry.stats or {}
  local s = entry.stats
  local defaults = {
    parties=0, raids=0, pvpMatches=0, arenaMatches=0, duels=0, petDuels=0,
    trades=0, whispers=0, emotes=0, dungeonCompletions=0, mplusCompletions=0,
    scenarioCompletions=0, bossKillsDungeon=0, bossKillsRaid=0, groupTicks=0,
    instanceTicks_party=0, instanceTicks_raid=0, instanceTicks_pvp=0, instanceTicks_arena=0,
    tavernTicks=0, reconnects=0, firstMeets=0,
    readyChecks=0, wipesWith=0,
    bgWins=0, bgLosses=0, arenaWins=0, arenaLosses=0,
    groupSeconds=0,
    invitesFrom=0, invitesTo=0,
    nearbyTicks=0,
    partyChatMsgs=0, raidChatMsgs=0,
  }
  for k,v in pairs(defaults) do if s[k] == nil then s[k] = v end end
  return s
end

-- Achievements are defined and exposed from CM_Achievements.lua

local function incStat(guid, key, amount)
  local e = getOrCreateEntry(guid)
  if not e then return end
  local s = ensureStats(e)
  s[key] = (s[key] or 0) + (amount or 1)
  refreshRelationship(e)
  if CMJ and CMJ.NotifyDataChanged then CMJ.NotifyDataChanged() end
end

-- Relationship progress belongs in the journal, not repeated chat notifications.
function awardXP(guid, amount, reason)
  local entry = getOrCreateEntry(guid)
  if not entry or type(amount) ~= "number" or amount ~= amount or amount == math.huge or amount <= 0 then return end
  entry.xp = (entry.xp or 0) + amount
  refreshRelationship(entry)
  if _G.CMJ and _G.CMJ.NotifyDataChanged then _G.CMJ.NotifyDataChanged() end
end

-- Make awardXP available for slash manual award
_G.CharacterMemory_AwardXP = awardXP

-- -----------------------------------------------------------------------------
-- UI
-- -----------------------------------------------------------------------------

-- Compact floating panel removed; journal UI handles display

-- Legacy journal UI removed; CM_Journal.lua provides CMUI journal
-- (journal list helpers removed here to avoid duplicate UI; CM_Journal.lua owns the journal UI)

-- Legacy CharacterMemory_ToggleJournal removed; CMUI.Toggle handles journal

function CharacterMemory_UpdateUI()
  -- No-op: compact panel removed; use the journal instead (/cm journal)
  -- OPT: Nudge the journal to refresh if it is open so selection/details stay in sync
  if _G.CMJ and _G.CMJ.refs and _G.CMJ.refs.root and _G.CMJ.refs.root:IsShown() then
    if _G.CMJ.RefreshList then _G.CMJ.RefreshList() end
    if _G.CMJ.PopulateDetail and _G.CMJ.refs and _G.CMJ.refs.root then
      local sel = _G.CharacterMemoryDB and _G.CharacterMemoryDB.settings and _G.CharacterMemoryDB.settings.ui and _G.CharacterMemoryDB.settings.ui.journal and _G.CharacterMemoryDB.settings.ui.journal.lastSelected
      if sel then pcall(_G.CMJ.PopulateDetail, sel) end
    end
  end
end

local function showIfSettingAllows()
  if CharacterMemoryDB.settings.showOnTarget then
    CharacterMemory_UpdateUI()
  else
    if State.frame then State.frame:Hide() end
  end
end

-- -----------------------------------------------------------------------------
-- Event handling and business logic
-- -----------------------------------------------------------------------------

local function shareChannel()
  return IsInRaid() and "RAID" or IsInGroup() and "PARTY" or "SAY"
end

StaticPopupDialogs["CMJ_SHARE_SUMMARY"] = {
  text = "Post this encounter summary to %s?\n\n%s\n\nPrivate notes, memories and stories are not included.",
  button1 = "Post summary", button2 = "Cancel", timeout = 0, whileDead = true, hideOnEscape = true,
  OnAccept = function(_, data)
    if data and data.channel == shareChannel() and CharacterMemoryDB.entries[data.guid] then
      CMCompat.SendChat(data.message, data.channel)
    end
  end,
}
function CharacterMemory_Share(guid)
  guid = guid or State.currentGUID
  local e = guid and CharacterMemoryDB.entries[guid]
  if not e then return end
  local msg = CMCompat.Text(string.format("%s — First met %s in %s. Lv %d (%s), %d XP.", shortName(e.name), e.firstMetAt or "—", e.firstMetWhere or "—", e.level or 0, e.tier or "Stranger", e.xp or 0), 250):gsub("|", "")
  local channel = shareChannel()
  StaticPopup_Show("CMJ_SHARE_SUMMARY", channel, msg, {guid = guid, channel = channel, message = msg})
end

local function isCurrentTargetGroupmate()
  if not UnitExists("target") then return false end
  local tName, tRealm = UnitName("target")
  local check = tRealm and (tName .. "-" .. tRealm) or tName
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local name = GetRaidRosterInfo(i)
      if name and (name == check or shortName(name) == shortName(check)) then return true end
    end
  elseif IsInGroup() then
    for i = 1, GetNumSubgroupMembers() do
      local unit = "party" .. i
      if UnitExists(unit) then
        local n, r = UnitName(unit)
        local full = r and (n .. "-" .. r) or n
        if full == check or shortName(full) == shortName(check) then return true end
      end
    end
  end
  return false
end

-- Track one-time awards to avoid double-credit inside the same encounter/session
local AwardedEncounters = {} -- [guid] = { [encounterID] = true }

-- Track a simple dungeon run state for non-LFG 5-man dungeons so we can
-- credit "Dungeons" on exit even when LFG-specific events don't fire.
local DungeonRun = {
  active = false,        -- we killed at least one boss in a 5-man instance this run
  instanceID = nil,      -- GetInstanceInfo() instanceID captured when we first succeed a boss
  lastBossKillAt = 0,    -- time of the most recent successful boss
  credited = false       -- whether we already counted a completion for this run
}

function resetDungeonRun()
  DungeonRun.active, DungeonRun.instanceID, DungeonRun.lastBossKillAt, DungeonRun.credited = false, nil, 0, false
end

-- Iterate current group's member GUIDs (excluding the player) and invoke a callback
local function forEachGroupmateGUID(callback)
  if type(callback) ~= "function" then return end
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local unit = "raid" .. i
      if UnitExists(unit) and not UnitIsUnit(unit, "player") then
        local guid = UnitGUID(unit)
        if guid then callback(guid, unit) end
      end
    end
  elseif IsInGroup() then
    for i = 1, GetNumSubgroupMembers() do
      local unit = "party" .. i
      if UnitExists(unit) and not UnitIsUnit(unit, "player") then
        local guid = UnitGUID(unit)
        if guid then callback(guid, unit) end
      end
    end
  end
end

function awardToAllGroupmates(amount, reason)
  if not amount or amount <= 0 then return end
  forEachGroupmateGUID(function(guid)
    awardXP(guid, amount, reason)
  end)
end

function incStatForAllGroupmates(key, amount)
  forEachGroupmateGUID(function(guid)
    incStat(guid, key, amount or 1)
  end)
end

function maybeCreditDungeonOnExit()
  local inside, instanceType = IsInInstance()
  if inside and instanceType == "party" then return end
  -- If we recently killed a boss in a 5-man and we leave the instance without
  -- seeing LFG/Scenario/Challenge completion events, count a completion once.
  if not DungeonRun.active or DungeonRun.credited then return end
  local now = GetTime and GetTime() or 0
  if (now - (DungeonRun.lastBossKillAt or 0)) > 900 then -- safety window 15m
    resetDungeonRun()
    return
  end
  awardToAllGroupmates(100, "dungeon complete")
  incStatForAllGroupmates("dungeonCompletions", 1)
  DungeonRun.credited = true
  resetDungeonRun()
end

local function isInInstanceOfTypes(types)
  local inInstance, instType = IsInInstance()
  if not inInstance then return false end
  for _, t in ipairs(types) do
    if instType == t then return true end
  end
  return false
end

local function awardIfTargetGroupmate(amount, reason)
  if not State.currentGUID then return end
  if not UnitExists("target") or not UnitIsPlayer("target") then return end
  if not isCurrentTargetGroupmate() then return end
  awardXP(State.currentGUID, amount, reason)
end

-- Find a current groupmate by short name and return their GUID (and unit token)
local function getGroupmateGUIDByName(name)
  if not name or name == "" then return nil, nil end
  local targetShort = shortName(name)
  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local unit = "raid" .. i
      if UnitExists(unit) then
        local n, r = UnitName(unit)
        local full = r and (n .. "-" .. r) or n
        if shortName(full) == targetShort then return UnitGUID(unit), unit end
      end
    end
  elseif IsInGroup() then
    for i = 1, GetNumSubgroupMembers() do
      local unit = "party" .. i
      if UnitExists(unit) then
        local n, r = UnitName(unit)
        local full = r and (n .. "-" .. r) or n
        if shortName(full) == targetShort then return UnitGUID(unit), unit end
      end
    end
  end
  return nil, nil
end

local function handleTargetChanged()
  if InCombatLockdown() then return end
  local nextGUID = UnitExists("target") and UnitGUID("target")
  local previousTarget = State.currentGUID
  if previousTarget and previousTarget ~= nextGUID then
    local previousEntry = CharacterMemoryDB.entries[previousTarget]
    if previousEntry then
      previousEntry._lastSeenStamp, previousEntry.lastSeenAt = time(), nowUTCString()
    end
  end
  if not UnitExists("target") then
    State.currentGUID = nil
    if CMJourney then CMJourney.CancelNotice() end
    if State.frame then State.frame:Hide() end
    return
  end

  local guid = UnitGUID("target")
  if not guid then if CMJourney then CMJourney.CancelNotice() end; return end
  if guid == UnitGUID("player") then
    State.currentGUID = nil
    if CMJourney then CMJourney.CancelNotice() end
    return
  end
  -- Ignore non-player GUIDs; do not create or update entries for NPCs/creatures
  if not guid:match("^Player%-") then
    State.currentGUID = nil
    if CMJourney then CMJourney.CancelNotice() end
    return
  end
  State.currentGUID = guid

  local entry = getOrCreateEntry(guid)
  if not entry then return end
  local name, realm = UnitName("target")
  if not name then return end
  local fullName = realm and (name .. "-" .. realm) or name
  entry.displayName = fullName
  entry.name = fullName or entry.name or "Unknown"
  entry.isPlayer = UnitIsPlayer("target") and true or false
  if entry.isPlayer then
    local className, classFile = UnitClass("target")
  local raceName, raceFile = UnitRace("target")
    local level = UnitLevel("target")
    local faction = UnitFactionGroup("target")
    local gender = UnitSex("target") -- 2 male, 3 female
    local guildName = GetGuildInfo and select(1, GetGuildInfo("target")) or nil
    entry.class = className
    entry.classFile = classFile
    entry.race = raceName
    entry.raceFile = raceFile
    entry.charLevel = level
    entry.faction = faction
    entry.gender = gender
    entry.guildName = guildName
    -- Friend flag (simple heuristic)
    if C_FriendList and C_FriendList.IsFriend then
      local isFriend = C_FriendList.IsFriend(guid) or false
      entry.isFriend = isFriend and true or false
    end
  end

  -- Request an inspect to fetch item level for the target player (throttled)
  if entry.isPlayer then
    CharacterMemory_RequestTargetItemLevel()
  end

  local nowStamp = time()
  if previousTarget == guid then entry._lastSeenStamp = nowStamp end
  local previousSeenAt = entry._lastSeenStamp
  local where = getZoneContext()

  local firstMeet = false
  if entry.metCount == 0 then
    entry.firstMetAt = nowUTCString()
    entry.firstMetWhere = where
    firstMeet = true
  end

  local newEncounter = firstMeet or not entry._lastSeenStamp or nowStamp - entry._lastSeenStamp >= 600
  if newEncounter then entry.metCount = (entry.metCount or 0) + 1 end
  entry.lastSeenAt = nowUTCString()
  entry.lastSeenWhere = where

  -- Retarget XP if >= 10 minutes
  if entry._lastSeenStamp and entry._lastSeenStamp > 0 then
    if (nowStamp - entry._lastSeenStamp) >= 600 then
      awardXP(guid, 10, "retarget")
      incStat(guid, "reconnects", 1)

    end
  end
  entry._lastSeenStamp = nowStamp

  -- First meet XP
  if firstMeet then
    incStat(guid, "firstMeets", 1)
    awardXP(guid, 50, "first meet")
    CMChronicle.Offer(guid, "meeting", where)
    if CharacterMemoryDB.settings.shareEnabled then
      printMessage("A new acquaintance: " .. CMCompat.Display(shortName(entry.name)) .. ". A moment is waiting in Notes → Memories.")
    end
  end

  if CMJourney then CMJourney.OnTarget(guid, previousSeenAt, firstMeet) end
  showIfSettingAllows()
  if _G.CMJ and _G.CMJ.NotifyDataChanged then _G.CMJ.NotifyDataChanged() end
end

-- CHAT_MSG_TEXT_EMOTE: positive emotes
local function handleTextEmote(event, text, playerName)
  -- Emotes are target/proximity based (no group required), but must be tied to current target
  if not State.currentGUID or CMCompat.IsSecret(text) or CMCompat.IsSecret(playerName) or type(text) ~= "string" then return end
  local entry = CharacterMemoryDB.entries[State.currentGUID]
  if not entry or not entry.isPlayer then return end
  local emote = text and text:match("^%*(%w+)") -- rarely of the form "PlayerName waves" in text emotes; safer is to use standard parsing
  -- Fallback: try find keyword present in text
  local matched = nil
  for k in pairs(POSITIVE_EMOTES) do
    if text and text:lower():find(k) then matched = k break end
  end
  if not matched then return end

  -- verify sender matches the target or player
  local targetShort = shortName(entry.name)
  if playerName and (shortName(playerName) == targetShort or shortName(playerName) == shortName(UnitName("player"))) then
    if canFireCooldown(Cooldowns.emote, State.currentGUID, 10) then
      awardXP(State.currentGUID, 8, "emote")
      incStat(State.currentGUID, "emotes", 1)
    end
    -- Track per-emote history for achievements regardless of cooldown
    local tl = matched and matched:lower() or ""
    if tl == "hug" or tl == "kiss" or tl == "love" then
      if _G.CM_LogEmoteForAchievements then _G.CM_LogEmoteForAchievements(State.currentGUID, tl) end
    end
  end
end

-- Whisper exchange
local function handleWhisper(event, text, otherName)
  if CMCompat.IsSecret(otherName) or type(otherName) ~= "string" then return end
  -- Whispers are target-based (no group required)
  if not State.currentGUID then return end
  local entry = CharacterMemoryDB.entries[State.currentGUID]
  if not entry or not entry.isPlayer then return end
  -- otherName is sender for CHAT_MSG_WHISPER, recipient for CHAT_MSG_WHISPER_INFORM
  if not otherName then return end
  if CMCompat.NameKey(otherName) ~= CMCompat.NameKey(entry.name) then return end
  if canFireCooldown(Cooldowns.whisper, State.currentGUID, 60) then
    awardXP(State.currentGUID, 12, "whisper")
    incStat(State.currentGUID, "whispers", 1)
    CMChronicle.Offer(State.currentGUID, "conversation", getZoneContext())
  end
end

-- Trade
local function handleTradeClosed()
  -- Closing a trade is not evidence that it completed. Keep its partner briefly
  -- so the locale-independent ERR_TRADE_COMPLETE notification can confirm it.
  State.tradeClosedAt = GetTime()
end

-- Duel
local function handleDuelFinished()
  -- Duels are target-based (no group required)
  if not State.currentGUID then return end
  local e = CharacterMemoryDB.entries[State.currentGUID]
  if not e or not e.isPlayer then return end
  awardXP(State.currentGUID, 40, "duel")
  incStat(State.currentGUID, "duels", 1)
end

-- Group tick (every 300s)
local function groupTick()
  -- Credit all current groupmates every 5 minutes
  forEachGroupmateGUID(function(guid)
    if canFireCooldown(Cooldowns.groupTick, guid, 300) then
      awardXP(guid, 25, "group time")
      incStat(guid, "groupTicks", 1)
      local e = getOrCreateEntry(guid)
      if e then
        e.stats = ensureStats(e)
        local now = GetTime()
        if GroupSessionStartAt == 0 then GroupSessionStartAt = now end
        e.stats.groupSeconds = (e.stats.groupSeconds or 0) + 300
      end
      if not GroupSessionCounted[guid] then
        GroupSessionCounted[guid] = true
        if IsInRaid() then
          incStat(guid, "raids", 1)
        else
          incStat(guid, "parties", 1)
        end
      end
    end
  end)
end

-- Tavern tick (every 120s) while resting and target exists and is player
local function tavernTick()
  -- Award only when resting and with nearby groupmates (roughly within interact range)
  if not IsResting() then return end
  forEachGroupmateGUID(function(guid, unit)
    local nearby = false
    if CheckInteractDistance then nearby = CheckInteractDistance(unit, 1) and true or false end -- ~28 yards
    if nearby and canFireCooldown(Cooldowns.tavernTick, guid, 120) then
      awardXP(guid, 20, "tavern")
      incStat(guid, "tavernTicks", 1)
      CMChronicle.Offer(guid, "shared_rest", getZoneContext())
    end
  end)
end

-- Instance group tick (every 120s) while in dungeon/raid/bg/arena with target groupmate
local function instanceGroupTick()
  local inInstance, instType = IsInInstance()
  if not inInstance then return end
  local amount = 0
  if instType == "party" then amount = 15
  elseif instType == "raid" then amount = 20
  elseif instType == "pvp" then amount = 12
  elseif instType == "arena" then amount = 18 end
  if amount <= 0 then return end
  forEachGroupmateGUID(function(guid)
    if canFireCooldown(Cooldowns.instanceGroupTick, guid, 120) then
      awardXP(guid, amount, "instance time")
      if instType == "party" then incStat(guid, "instanceTicks_party", 1)
      elseif instType == "raid" then incStat(guid, "instanceTicks_raid", 1)
      elseif instType == "pvp" then incStat(guid, "instanceTicks_pvp", 1)
      elseif instType == "arena" then incStat(guid, "instanceTicks_arena", 1) end
    end
  end)
end

-- Boss kills and completions
local function handleEncounterEnd(encounterID, encounterName, difficultyID, raidSize, endStatus)
  if endStatus ~= 1 then return end -- only on success
  local inInstance, instType = IsInInstance()
  if not inInstance then return end
  -- Credit all current groupmates once per encounterID
  forEachGroupmateGUID(function(guid)
    AwardedEncounters[guid] = AwardedEncounters[guid] or {}
    if not AwardedEncounters[guid][encounterID] then
      AwardedEncounters[guid][encounterID] = true
      getOrCreateEntry(guid)
      CMChronicle.Offer(guid, "adventure", getZoneContext())
      if instType == "party" then
        awardXP(guid, 40, "boss kill")
        incStat(guid, "bossKillsDungeon", 1)
        -- Mark that we have an active dungeon run with at least one boss kill
        DungeonRun.active = true
        DungeonRun.lastBossKillAt = GetTime and GetTime() or 0
        DungeonRun.instanceID = select(8, GetInstanceInfo())
      elseif instType == "raid" then
        awardXP(guid, 80, "boss kill")
        incStat(guid, "bossKillsRaid", 1)
      end
    end
  end)
end

-- Wipe tracking
local function handleEncounterStart(encounterID)
  forEachGroupmateGUID(function(guid)
    AwardedEncounters[guid] = AwardedEncounters[guid] or {}
    AwardedEncounters[guid][encounterID] = AwardedEncounters[guid][encounterID] or false
  end)
end

local function handleEncounterEndAny(encounterID, encounterName, difficultyID, raidSize, endStatus)
  if endStatus ~= 1 then
    incStatForAllGroupmates("wipesWith", 1)
  end
end

function handleLFGCompletion()
  awardToAllGroupmates(100, "dungeon complete")
  incStatForAllGroupmates("dungeonCompletions", 1)
end

function handleChallengeModeCompleted()
  awardToAllGroupmates(120, "mythic+ complete")
  incStatForAllGroupmates("mplusCompletions", 1)
end

function handleScenarioCompleted()
  awardToAllGroupmates(60, "scenario complete")
  incStatForAllGroupmates("scenarioCompletions", 1)
end

function handlePvpMatchComplete()
  local inInstance, instType = IsInInstance()
  if not inInstance then return end
  if instType == "pvp" then
    awardToAllGroupmates(40, "battleground match")
    incStatForAllGroupmates("pvpMatches", 1)
  elseif instType == "arena" then
    awardToAllGroupmates(50, "arena match")
    incStatForAllGroupmates("arenaMatches", 1)
  end
end

-- -----------------------------------------------------------------------------
-- Slash commands
-- -----------------------------------------------------------------------------

local function printHelp()
  printMessage("/cm help — Show commands")
  printMessage("/cm note <text> — Save note for current target")
  printMessage("/cm remember <text> — Keep a private memory")
  printMessage("/cm recall [older|newer|first|latest] — Read your memories")
  printMessage("/cm continue — Pick up the selected unfinished story")
  printMessage("/cm story <title> — Start a private story thread")
  printMessage("/cm status — Show client compatibility information")
  printMessage("/cm share — Post a brief encounter summary to group or say")
  printMessage("/cm show — Open the journal")
  printMessage("/cm hide — Close the journal")
  printMessage("/cm delete — Delete current target memory")
  printMessage("/cm toggle — Toggle show-on-target")
  printMessage("/cm autoshares — Toggle private meeting reminders in chat")
  printMessage("/cm rel — Show relationship info")
  printMessage("/cm reladd <xp> — Add XP to current target")
  printMessage("/cm journal — Toggle the journal window")
  printMessage("/cm profile — Show profile for current target")
  if GetCVar and GetCVar("scriptProfile") == "1" then
    printMessage("/cm cpu — AddOn CPU usage and top funcs (dev)")
    printMessage("/cm mem — AddOn memory usage (dev)")
  end
end

SLASH_CHARACTERMEMORY1 = "/cm"
SLASH_CHARACTERMEMORY2 = "/cmem"
SLASH_CHARACTERMEMORY3 = "/charactermemory"
SLASH_CHARACTERMEMORY4 = "/cmemory"
local function storyPerson()
  local selected = CMUI.GetSelectedEntry and CMUI.GetSelectedEntry()
  if CMJ.refs.root and CMJ.refs.root:IsShown() and selected then return selected end
  return State.currentGUID or selected
end
SlashCmdList["CHARACTERMEMORY"] = function(msg)
  msg = msg or ""
  local cmd, rest = msg:match("^(%S+)%s*(.-)$")
  cmd = cmd and cmd:lower() or "journal"

  if cmd == "help" or cmd == "" then
    printHelp()

  elseif cmd == "note" then
    if not State.currentGUID then printMessage("No target.") return end
    local e = getOrCreateEntry(State.currentGUID)
    e.notes = rest or ""
    printMessage("Saved note for " .. shortName(e.name))
    CharacterMemory_UpdateUI()

  elseif cmd == "remember" then
    local memoryID, err = CMChronicle.Remember(State.currentGUID, nil, rest, nil, getZoneContext())
    printMessage(memoryID and "Memory added to your journal." or err)

  elseif cmd == "recall" then
    local guid = storyPerson()
    if guid and CharacterMemoryDB.entries[guid] then
      if rest == "" then CMJourney.Read(guid)
      elseif not CMJourney.Browse(guid, rest:lower()) then printMessage("Use /cm recall older, newer, first, or latest.") end
    else printMessage("Target someone you know, or choose a person in your journal.") end

  elseif cmd == "continue" then
    local guid = storyPerson()
    if not guid then printMessage("Choose a person and an unfinished story in your journal.") return end
    local ok, err = CMJourney.Continue(guid)
    if not ok then printMessage(err) end

  elseif cmd == "story" then
    local storyID, err = CMChronicle.AddStory(State.currentGUID, rest, "", getZoneContext())
    printMessage(storyID and "Story thread added to your journal." or err)

  elseif cmd == "status" then
    local client = CMCompat.ClientInfo()
    printMessage(string_format("RP Journal %s · client %s (%s), interface %s", CMCompat.Version(), client.version, client.build, tostring(client.interface)))

  elseif cmd == "share" then
    CharacterMemory_Share()

  elseif cmd == "show" then
    if _G.CharacterMemory_OpenJournal then _G.CharacterMemory_OpenJournal() else printMessage("Use /cm journal.") end

  elseif cmd == "hide" then
    if CMJ and CMJ.refs and CMJ.refs.root then CMJ.refs.root:Hide() end

  elseif cmd == "delete" then
    if not State.currentGUID then printMessage("No target.") return end
    CMUI.DeleteEntry(State.currentGUID)

  elseif cmd == "toggle" then
    CharacterMemoryDB.settings.showOnTarget = not CharacterMemoryDB.settings.showOnTarget
    printMessage("Show on target: " .. (CharacterMemoryDB.settings.showOnTarget and "ON" or "OFF"))

  elseif cmd == "autoshares" then
    CharacterMemoryDB.settings.shareEnabled = not CharacterMemoryDB.settings.shareEnabled
    printMessage("Private meeting reminders: " .. (CharacterMemoryDB.settings.shareEnabled and "ON" or "OFF"))

  elseif cmd == "rel" then
    if not State.currentGUID then printMessage("No target.") return end
    local e = getOrCreateEntry(State.currentGUID)
    printMessage(string.format("%s — Lv %d (%s), %d XP", shortName(e.name), e.level or 0, e.tier or "Stranger", e.xp or 0))

  elseif cmd == "reladd" then
    if not State.currentGUID then printMessage("No target.") return end
    local val = tonumber(rest or "0") or 0
    if val <= 0 then printMessage("Usage: /cm reladd <xp>") return end
    awardXP(State.currentGUID, val, "manual")

  elseif cmd == "journal" then
    -- Ensure the external CM_Journal UI is used; fallback safely if not loaded
    if _G.CharacterMemory_OpenJournal then
      _G.CharacterMemory_OpenJournal()
    elseif CMUI and CMUI.Toggle then
      CMUI.Toggle()
    else
      printMessage("Journal UI not loaded.")
    end

  elseif cmd == "profile" or cmd == "sheet" or cmd == "prof" then
    if CMChronicleUI then CMChronicleUI.ShowProfile(storyPerson()) end

  elseif GetCVar and GetCVar("scriptProfile") == "1" and (cmd == "cpu" or cmd == "mem") then
    -- OPT: Dev-only profiling helpers (to be removed in release)
    if cmd == "cpu" then
      UpdateAddOnCPUUsage()
      local addonCPU = GetAddOnCPUUsage("CharacterMemory")
      printMessage(string_format("CPU: %d ms", addonCPU or 0))
      local profList = _G.CharacterMemory_ProfiledFunctions or {}
      local scores = {}
      for name, fn in pairs(profList) do
        local cpuFn = rawget(_G, "GetFunctionCPUUsage")
        local used = (type(cpuFn) == "function") and cpuFn(fn, true) or 0 -- OPT: guard for linter
        table.insert(scores, {name=name, used=used or 0})
      end
      table.sort(scores, function(a,b) return a.used > b.used end)
      for i=1, math.min(5, #scores) do
        printMessage(string_format("%d) %s — %d ms", i, scores[i].name, scores[i].used))
      end
    else
      UpdateAddOnMemoryUsage()
      local mem = GetAddOnMemoryUsage("CharacterMemory")
      printMessage(string_format("Mem: %.1f KB", tonumber(mem or 0)))
    end

  else
    printHelp()
  end
end

-- -----------------------------------------------------------------------------
-- Event frame
-- -----------------------------------------------------------------------------

local evt = CreateFrame("Frame")

evt:SetScript("OnEvent", function(self, event, ...)
  if event == "ADDON_LOADED" then
    local addon = ...
    if addon == ADDON_NAME then
      initializeDatabase()
      wireEscapeAndFocus()
      fixupEntries()
      ensureOptionsPanelRegistered()
      -- Seed player's own item level immediately
      CharacterMemory_UpdatePlayerItemLevel()
      -- do not spawn legacy compact frame at load; journal handles main UI
      if State.frame then State.frame:Hide() end
      -- ensure slash command is bound to this handler
      SlashCmdList["CHARACTERMEMORY"] = SlashCmdList["CHARACTERMEMORY"] or function(msg) end
      -- Position
      local anch = CharacterMemoryDB.settings.anchor
      if State.frame then
        State.frame:ClearAllPoints()
        State.frame:SetPoint(anch.point or "CENTER", UIParent, anch.point or "CENTER", anch.x or 0, anch.y or 200)
      end
      -- Startup is intentionally silent; /cm status provides diagnostics on demand.
    end

  elseif event == "PLAYER_TARGET_CHANGED" then
    handleTargetChanged()

  elseif event == "CHAT_MSG_TEXT_EMOTE" then
    handleTextEmote(event, ...)

  elseif event == "READY_CHECK" then
    if State.currentGUID then incStat(State.currentGUID, "readyChecks", 1) end

  elseif event == "PARTY_INVITE_REQUEST" then
    -- Someone invited us; if it's current target, count invitesFrom
    local inviter = ...
    if inviter and State.currentGUID then
      local e = getOrCreateEntry(State.currentGUID)
      if e and e.name and shortName(inviter) == shortName(e.name) then
        incStat(State.currentGUID, "invitesFrom", 1)
      end
    end

  elseif event == "GROUP_ROSTER_UPDATE" then
    -- If we have a target and we invite them (target in our party after invite), count invitesTo
    if State.currentGUID and UnitExists("target") and UnitGUID("target") == State.currentGUID then
      if isCurrentTargetGroupmate() then
        incStat(State.currentGUID, "invitesTo", 1)
      end
    end

  elseif event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_WHISPER_INFORM" then
    handleWhisper(event, ...)

  elseif event == "TRADE_SHOW" then
    State.tradeGUID = UnitGUID("NPC")
    State.tradeStartedAt = GetTime()
    State.tradeClosedAt = nil

  elseif event == "TRADE_CLOSED" then
    handleTradeClosed()

  elseif event == "UI_INFO_MESSAGE" then
    local _, message = ...
    if ERR_TRADE_COMPLETE and message == ERR_TRADE_COMPLETE and State.tradeGUID
      and GetTime() - (State.tradeStartedAt or 0) <= 600
      and (not State.tradeClosedAt or GetTime() - State.tradeClosedAt <= 5) then
      local guid = State.tradeGUID
      State.tradeGUID = nil
      incStat(guid, "trades", 1)
      awardXP(guid, 60, "trade")
    end

  elseif event == "DUEL_FINISHED" then
    handleDuelFinished()

  elseif event == "ENCOUNTER_END" then
    handleEncounterEnd(...)
    handleEncounterEndAny(...)

  elseif event == "ENCOUNTER_START" then
    handleEncounterStart(...)

  elseif event == "LFG_COMPLETION_REWARD" then
    handleLFGCompletion()
    resetDungeonRun()

  elseif event == "CHALLENGE_MODE_COMPLETED" then
    handleChallengeModeCompleted()
    resetDungeonRun()

  elseif event == "SCENARIO_COMPLETED" then
    handleScenarioCompleted()
    resetDungeonRun()

  elseif event == "PVP_MATCH_COMPLETE" or event == "BATTLEFIELDS_CLOSED" then
    handlePvpMatchComplete()

  elseif event == "PLAYER_REGEN_DISABLED" then
    local root = CMJ and CMJ.refs and CMJ.refs.root
    State.wasOpenBeforeCombat = root and root:IsShown() or false
    if State.wasOpenBeforeCombat then root:Hide() end

  elseif event == "PLAYER_REGEN_ENABLED" then
    local root = CMJ and CMJ.refs and CMJ.refs.root
    if State.wasOpenBeforeCombat and root then root:Show() end
    State.wasOpenBeforeCombat = false
    handleTargetChanged()

  elseif event == "INSPECT_READY" then
    local inspectedGuid = ...
    CharacterMemory_OnInspectReady(inspectedGuid)

  elseif event == "UNIT_INVENTORY_CHANGED" then
    local unit = ...
    if unit == "player" then CharacterMemory_UpdatePlayerItemLevel() end

  elseif event == "PLAYER_EQUIPMENT_CHANGED" then
    CharacterMemory_UpdatePlayerItemLevel()

  elseif event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" or event == "FRIENDLIST_UPDATE" then
    -- Refresh guild/friend flags for current target if visible
    if State.currentGUID and UnitExists("target") and UnitGUID("target") == State.currentGUID then
      local e = getOrCreateEntry(State.currentGUID)
      if e then
        e.guildName = GetGuildInfo and select(1, GetGuildInfo("target")) or e.guildName
        if C_FriendList and C_FriendList.IsFriend then
          e.isFriend = C_FriendList.IsFriend(State.currentGUID) or e.isFriend
        end
      end
      CharacterMemory_UpdateUI()
    end

  elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" or event == "ZONE_CHANGED_NEW_AREA" then
    -- OPT: Refresh zone cache quickly on zone transitions
    zoneCache.stamp = 0
    -- If leaving a 5-man after a successful boss and we never saw a completion
    -- event (e.g., non-LFG classic dungeons), grant a completion once.
    maybeCreditDungeonOnExit()

  elseif event == "PLAYER_LOGOUT" then
    local current = State.currentGUID and CharacterMemoryDB.entries[State.currentGUID]
    if current then current._lastSeenStamp, current.lastSeenAt = time(), nowUTCString() end
    -- OPT: Cancel tickers to avoid orphan timers on reload
    CMProtocol.Stop()
    if _G.CharacterMemory_Tickers then
      for _, tk in ipairs(_G.CharacterMemory_Tickers) do pcall(tk.Cancel, tk) end
    end

  elseif event == "NAME_PLATE_UNIT_ADDED" then
    if CharacterMemoryDB.settings.enableProximity == false or InCombatLockdown() then return end
    local unit = ...
    if not unit or not UnitExists(unit) then return end
    local guid = UnitGUID(unit)
    if not guid or guid ~= State.currentGUID then return end
    -- Only count proximity when not already grouped; throttle to once every 30s
    if isCurrentTargetGroupmate() then return end
    local now = GetTime() or 0
    if (now - (lastNearbyTickAt or 0)) >= 30 then
      lastNearbyTickAt = now
      incStat(State.currentGUID, "nearbyTicks", 1)
      CharacterMemory_UpdateUI()
    end
  elseif event == "NAME_PLATE_UNIT_REMOVED" then
    -- no-op; presence is counted on added with throttle
  end
end)

CMCompat.RegisterEvent(evt, "ADDON_LOADED")
CMCompat.RegisterEvent(evt, "PLAYER_TARGET_CHANGED")
CMCompat.RegisterEvent(evt, "CHAT_MSG_TEXT_EMOTE")
CMCompat.RegisterEvent(evt, "READY_CHECK")
CMCompat.RegisterEvent(evt, "PARTY_INVITE_REQUEST")
CMCompat.RegisterEvent(evt, "GROUP_ROSTER_UPDATE")
CMCompat.RegisterEvent(evt, "CHAT_MSG_WHISPER")
CMCompat.RegisterEvent(evt, "CHAT_MSG_WHISPER_INFORM")
CMCompat.RegisterEvent(evt, "TRADE_CLOSED")
CMCompat.RegisterEvent(evt, "TRADE_SHOW")
CMCompat.RegisterEvent(evt, "UI_INFO_MESSAGE")
CMCompat.RegisterEvent(evt, "DUEL_FINISHED")
CMCompat.RegisterEvent(evt, "ENCOUNTER_END")
CMCompat.RegisterEvent(evt, "ENCOUNTER_START")
CMCompat.RegisterEvent(evt, "LFG_COMPLETION_REWARD")
CMCompat.RegisterEvent(evt, "CHALLENGE_MODE_COMPLETED")
CMCompat.RegisterEvent(evt, "SCENARIO_COMPLETED")
CMCompat.RegisterEvent(evt, "PVP_MATCH_COMPLETE")
CMCompat.RegisterEvent(evt, "BATTLEFIELDS_CLOSED")
CMCompat.RegisterEvent(evt, "PLAYER_REGEN_DISABLED")
CMCompat.RegisterEvent(evt, "PLAYER_REGEN_ENABLED")
CMCompat.RegisterEvent(evt, "ZONE_CHANGED")
CMCompat.RegisterEvent(evt, "ZONE_CHANGED_INDOORS")
CMCompat.RegisterEvent(evt, "ZONE_CHANGED_NEW_AREA")
CMCompat.RegisterEvent(evt, "PLAYER_LOGOUT")
CMCompat.RegisterEvent(evt, "GUILD_ROSTER_UPDATE")
CMCompat.RegisterEvent(evt, "PLAYER_GUILD_UPDATE")
CMCompat.RegisterEvent(evt, "FRIENDLIST_UPDATE")
CMCompat.RegisterEvent(evt, "NAME_PLATE_UNIT_ADDED")
CMCompat.RegisterEvent(evt, "NAME_PLATE_UNIT_REMOVED")
CMCompat.RegisterEvent(evt, "INSPECT_READY")
CMCompat.RegisterEvent(evt, "UNIT_INVENTORY_CHANGED")
CMCompat.RegisterEvent(evt, "PLAYER_EQUIPMENT_CHANGED")

-- Versioned public-profile transport. No unsolicited profile writes are accepted.
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
  pcall(C_ChatInfo.RegisterAddonMessagePrefix, CMProtocol.PREFIX)
end
local bioEvt = CreateFrame("Frame")
CMCompat.RegisterEvent(bioEvt, "CHAT_MSG_ADDON")
bioEvt:SetScript("OnEvent", function(_, _, prefix, message, channel, sender)
  CMProtocol.Receive(prefix, message, channel, sender)
end)

-- Tickers
-- OPT: Store ticker refs for cleanup on reload/disable
_G.CharacterMemory_Tickers = _G.CharacterMemory_Tickers or {}
table.insert(_G.CharacterMemory_Tickers, C_Timer.NewTicker(300, groupTick))
table.insert(_G.CharacterMemory_Tickers, C_Timer.NewTicker(120, tavernTick))
table.insert(_G.CharacterMemory_Tickers, C_Timer.NewTicker(120, instanceGroupTick))

-- OPT: Removed duplicate/no-op event frame, tooltip, and unused options panel to avoid taint and redundant handlers

-- OPT: Build profiling registry for /cm cpu (dev only)
_G.CharacterMemory_ProfiledFunctions = {
  awardXP = awardXP,
  handleTargetChanged = handleTargetChanged,
  handleTextEmote = handleTextEmote,
  handleWhisper = handleWhisper,
  groupTick = groupTick,
  tavernTick = tavernTick,
  instanceGroupTick = instanceGroupTick,
}

-- Delete entry confirmation dialog
StaticPopupDialogs["CONFIRM_DELETE_CHARACTER_MEMORY_ENTRY"] = {
  text = "Are you sure you want to delete this character from your memory? This action cannot be undone.",
  button1 = "Delete",
  button2 = "Cancel",
  OnAccept = function(self, data)
    if data and data.guid then
      -- Remove the entry from the database
      if CharacterMemoryDB and CharacterMemoryDB.entries then
        CharacterMemoryDB.entries[data.guid] = nil
      end
      
      -- Update UI if this was the selected entry
      if _G.CMJ and _G.CMJ.NotifyDataChanged then
        _G.CMJ.NotifyDataChanged()
      end
      
      -- Clear selection if this was the selected entry
      if _G.CMJ and _G.CMJ.refs and _G.CMJ.refs.root and _G.CMJ.refs.root:IsShown() then
        if _G.CMJ.Model and _G.CMJ.Model.selected == data.guid then
          _G.CMJ.Model.selected = nil
          _G.CMJ.PopulateDetail(nil)
        end
      end
      
      if State.currentGUID == data.guid then State.currentGUID = nil end
    end
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

if not CMCompat or not CMCompat.supported then return end
-- SavedVariablesPerCharacter: RPJournalDB

local ALIGNMENT_OPTIONS = {
  "Lawful Good","Neutral Good","Chaotic Good",
  "Lawful Neutral","True Neutral","Chaotic Neutral",
  "Lawful Evil","Neutral Evil","Chaotic Evil",
}

local AVAILABILITY_OPTIONS = { "Always", "Evenings", "Weekends", "By arrangement" }

local function ensureDB() return CMProfile.Ensure() end

local function g(name) return _G[name] end
local function getBox(name) local o = g(name); return o and o:GetText() or "" end
local function setBox(name, v) if g(name) then g(name):SetText(v or "") end end

-- InputScrollFrameTemplate helpers
local function multiBox(name)
  local scroll = g(name)
  return scroll and scroll.EditBox or g(name.."EditBox")
end
local function getMulti(name)
  local eb = multiBox(name); return eb and eb:GetText() or ""
end
local function setMulti(name, v)
  local eb = multiBox(name); if eb then eb:SetText(v or "") end
end

local function initDropdown(frameName, options, savedValue)
  local frame = g(frameName)
  if not frame then return end
  UIDropDownMenu_SetWidth(frame, (frame.fieldWidth or 208) - 28)
  local function choose(value)
    frame.value = value
    UIDropDownMenu_SetText(frame, value ~= "" and value or "Not specified")
    if RPBioUI then RPBioUI.MarkDirty() end
  end
  UIDropDownMenu_Initialize(frame, function(self, level)
    local blank = UIDropDownMenu_CreateInfo()
    blank.text, blank.checked, blank.func = "Not specified", frame.value == "", function() choose("") end
    UIDropDownMenu_AddButton(blank, level)
    for _, label in ipairs(options) do
      local info = UIDropDownMenu_CreateInfo()
      info.text, info.checked = label, frame.value == label
      info.func = function() choose(label) end
      UIDropDownMenu_AddButton(info, level)
    end
  end)
  frame.value = savedValue or ""
  UIDropDownMenu_SetText(frame, frame.value ~= "" and frame.value or "Not specified")
end

local function joinList(value)
  return type(value) == "table" and table.concat(value, ", ") or (type(value) == "string" and value or "")
end

local function joinLines(value)
  return type(value) == "table" and table.concat(value, "\n") or (type(value) == "string" and value or "")
end
local function lines(value)
  local out = {}; if value == "" then return out end
  for line in (value .. "\n"):gmatch("(.-)\n") do out[#out + 1] = line end
  return out
end
local function splitList(s)
  local out = {}
  s = (s or ""):gsub("%s*,%s*", ",")
  for item in string.gmatch(s, "([^,]+)") do
    item = item:sub(1, 24)
    table.insert(out, item)
  end
  return out
end

function RPBio_Save()
  local shortBio = getMulti("RPBio_ShortBio")
  if #shortBio > 500 then
    RPBioUI.ShowPage("Story"); RPBioUI.status:SetText("Short bio exceeds 500 bytes")
    RPBioUI.status:SetTextColor(1, 0.25, 0.25); return false
  end
  local db = ensureDB()

  db.identity.title        = getBox("RPBio_Title")
  db.identity.nicknames    = splitList(getBox("RPBio_Nicknames"))
  db.identity.pronouns     = getBox("RPBio_Pronouns")
  db.identity.race         = getBox("RPBio_Race")
  db.identity.homeland     = getBox("RPBio_Homeland")
  db.identity.residence    = getBox("RPBio_Residence")
  db.identity.affiliations = getBox("RPBio_Affiliations")

  db.appearance.height     = getBox("RPBio_Height")
  db.appearance.build      = getBox("RPBio_Build")
  db.appearance.eyes       = getBox("RPBio_Eyes")
  db.appearance.hair       = getBox("RPBio_Hair")
  db.appearance.features   = getBox("RPBio_Features")
  db.appearance.attire     = getBox("RPBio_Attire")

  shortBio = CMCompat.Text(shortBio, 500)
  db.lore.shortBio   = shortBio or ""
  db.lore.backstory  = CMCompat.Text(getMulti("RPBio_Backstory"), 12000)
  db.lore.alignment  = (g("RPBio_AlignmentDD") and g("RPBio_AlignmentDD").value) or ""
  db.lore.creed      = getBox("RPBio_Creed")
  db.lore.deeds      = getMulti("RPBio_Deeds")

  db.personality.traits = splitList(getBox("RPBio_Traits"))
  db.personality.ideals = getBox("RPBio_Ideals")
  db.personality.bonds  = getBox("RPBio_Bonds")
  db.personality.flaws  = getBox("RPBio_Flaws")
  db.personality.hooks  = getMulti("RPBio_Hooks")

  db.skills.occupation  = getBox("RPBio_Occupation")
  db.skills.languages   = splitList(getBox("RPBio_Languages"))
  db.skills.hobbies     = splitList(getBox("RPBio_Hobbies"))
  db.skills.combatFocus = getBox("RPBio_CombatFocus")

  db.relationships.partner      = { character = getBox("RPBio_Partner"), note = getBox("RPBio_PartnerNote") }
  db.relationships.family       = lines(getMulti("RPBio_Family"))
  db.relationships.allies       = lines(getMulti("RPBio_Allies"))
  db.relationships.rivals       = lines(getMulti("RPBio_Rivals"))
  db.relationships.pets         = lines(getMulti("RPBio_Pets"))

  db.rpPrefs.availability = (g("RPBio_AvailabilityDD") and g("RPBio_AvailabilityDD").value) or ""
  db.rpPrefs.tone         = splitList(getBox("RPBio_Tone"))
  db.rpPrefs.limits       = getMulti("RPBio_Limits")
  db.rpPrefs.oocContact   = getBox("RPBio_OOC")
  db.rpPrefs.limitsPrivate = true

  db.notes.public = getMulti("RPBio_PublicNotes")
  db.notes.private = getMulti("RPBio_PrivateNotes")

  CharacterMemoryDB.settings.bioSharing = _G.RPBio_PublicSharing and _G.RPBio_PublicSharing:GetChecked() and true or false
  CMProfile.SyncLegacy()
  if CMJ and CMJ.NotifyDataChanged then CMJ.NotifyDataChanged() end
  if RPBioUI then RPBioUI.dirty = false; RPBioUI.status:SetText("Character saved"); RPBioUI.status:SetTextColor(0.7, 1, 0.7) end
  return true
end

local function loadIntoFields()
  if RPBioUI and RPBioUI.dirty then return end
  local b = ensureDB()
  if _G.RPBio_PublicSharing then _G.RPBio_PublicSharing:SetChecked(CharacterMemoryDB.settings.bioSharing == true) end

  setBox("RPBio_Title", b.identity.title)
  setBox("RPBio_Nicknames", joinList(b.identity.nicknames))
  setBox("RPBio_Pronouns", b.identity.pronouns)
  setBox("RPBio_Race", b.identity.race)
  setBox("RPBio_Homeland", b.identity.homeland)
  setBox("RPBio_Residence", b.identity.residence)
  setBox("RPBio_Affiliations", b.identity.affiliations)

  setBox("RPBio_Height", b.appearance.height)
  setBox("RPBio_Build", b.appearance.build)
  setBox("RPBio_Eyes", b.appearance.eyes)
  setBox("RPBio_Hair", b.appearance.hair)
  setBox("RPBio_Features", b.appearance.features)
  setBox("RPBio_Attire", b.appearance.attire)

  setMulti("RPBio_ShortBio", b.lore.shortBio)
  setMulti("RPBio_Backstory", b.lore.backstory)
  initDropdown("RPBio_AlignmentDD", ALIGNMENT_OPTIONS, b.lore.alignment)
  setBox("RPBio_Creed", b.lore.creed)
  setMulti("RPBio_Deeds", b.lore.deeds)

  setBox("RPBio_Traits", joinList(b.personality.traits))
  setBox("RPBio_Ideals", b.personality.ideals)
  setBox("RPBio_Bonds", b.personality.bonds)
  setBox("RPBio_Flaws", b.personality.flaws)
  setMulti("RPBio_Hooks", b.personality.hooks)

  setBox("RPBio_Occupation", b.skills.occupation)
  setBox("RPBio_Languages", joinList(b.skills.languages))
  setBox("RPBio_Hobbies", joinList(b.skills.hobbies))
  setBox("RPBio_CombatFocus", b.skills.combatFocus)

  setBox("RPBio_Partner", (b.relationships.partner and b.relationships.partner.character) or "")
  setBox("RPBio_PartnerNote", (b.relationships.partner and b.relationships.partner.note) or "")
  setMulti("RPBio_Family", joinLines(b.relationships.family))
  setMulti("RPBio_Allies", joinLines(b.relationships.allies))
  setMulti("RPBio_Rivals", joinLines(b.relationships.rivals))
  setMulti("RPBio_Pets", joinLines(b.relationships.pets))

  initDropdown("RPBio_AvailabilityDD", AVAILABILITY_OPTIONS, b.rpPrefs.availability)
  setBox("RPBio_Tone", joinList(b.rpPrefs.tone))
  setMulti("RPBio_Limits", b.rpPrefs.limits)
  setBox("RPBio_OOC", b.rpPrefs.oocContact)
  if g("RPBio_LimitsPrivate") then g("RPBio_LimitsPrivate"):SetChecked(b.rpPrefs.limitsPrivate and true or false) end

  setMulti("RPBio_PublicNotes", b.notes.public)
  setMulti("RPBio_PrivateNotes", b.notes.private)

  local multi = {
    "RPBio_ShortBio","RPBio_Backstory","RPBio_Deeds","RPBio_Hooks",
    "RPBio_Family","RPBio_Allies","RPBio_Rivals","RPBio_Pets",
    "RPBio_Limits","RPBio_PublicNotes","RPBio_PrivateNotes",
  }
  for _, base in ipairs(multi) do
    local eb = multiBox(base)
    if eb then eb:SetMultiLine(true); eb:SetAutoFocus(false); eb:SetFontObject(GameFontHighlightSmall) end
  end
end

RPBioFrame:HookScript("OnShow", function()
  loadIntoFields()
  if _G.RPBio_AlignmentDD and not _G.RPBio_AlignmentDD.value then initDropdown("RPBio_AlignmentDD", ALIGNMENT_OPTIONS, nil) end
  if _G.RPBio_AvailabilityDD and not _G.RPBio_AvailabilityDD.value then initDropdown("RPBio_AvailabilityDD", AVAILABILITY_OPTIONS, nil) end
end)

function CharacterMemory_OpenCharacterSheet()
  if not _G.RPBioFrame then return end
  _G.RPBioFrame:Show()
  _G.RPBioFrame:Raise()
  _G.RPBioFrame:SetFrameStrata("DIALOG")
  _G.RPBioFrame:SetToplevel(true)
  loadIntoFields()
end

SLASH_RPBIO1 = "/rpbio"
SlashCmdList.RPBIO = CharacterMemory_OpenCharacterSheet



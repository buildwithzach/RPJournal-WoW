if not CMCompat or not CMCompat.supported then return end
-- A single preferences canvas; character authoring lives in the character sheet.
CMSettings = {}
local S, F = CMSettings, CMForms
S.controls = {}
local defs = {
  { key = "showOnTarget", name = "CM_OptionsPanelShowOnTarget", title = "Encounter prompts", detail = "Offer a quiet first-meeting or reunion prompt while you play.", default = true },
  { key = "enableProximity", name = "CM_OptionsPanelEnableProximity", title = "Nearby time", detail = "Use nameplates to remember time spent near someone.", default = true },
  { key = "enableInspect", name = "CM_OptionsPanelEnableInspect", title = "Equipment details", detail = "Read available equipment details when you target a player.", default = true },
  { key = "shareEnabled", name = "CM_OptionsPanelAutoShare", title = "First-meeting chat reminder", detail = "Also show a private line in your own chat. Nothing is broadcast.", default = false },
}
function S.Load()
  local settings = CharacterMemoryDB and CharacterMemoryDB.settings or {}
  for _, def in ipairs(defs) do
    local value = settings[def.key]; if value == nil then value = def.default end
    S.controls[def.key]:SetChecked(value == true)
  end
end
function S.Save()
  for _, def in ipairs(defs) do CharacterMemoryDB.settings[def.key] = S.controls[def.key]:GetChecked() and true or false end
  if CMJourney and not CharacterMemoryDB.settings.showOnTarget then CMJourney.CancelNotice() end
end
local function build()
  local labels = {}
  local function label(...) local fs = F.Label(...); labels[#labels + 1] = fs; return fs end
  local root = CM_OptionsPanel
  label(root, "RP Journal", 20, 18, 300, 24, "GameFontNormalLarge")
  label(root, "Choose what your journal notices while you play.", 20, 50, 500, 28, "GameFontHighlightSmall")
  local scroll = CreateFrame("ScrollFrame", "CMSettingsScroll", root, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 20, -92); scroll:SetPoint("BOTTOMRIGHT", -36, 20)
  local content = CreateFrame("Frame", "CMSettingsContent", scroll); content:SetSize(500, 452); scroll:SetScrollChild(content)
  S.content = content
  for i, def in ipairs(defs) do
    local y = (i - 1) * 70
    local box = CreateFrame("CheckButton", def.name, content, "UICheckButtonTemplate")
    box:SetPoint("TOPLEFT", 0, -y); box:SetSize(24, 24); box.Text:SetText(def.title)
    box:SetScript("OnClick", S.Save); S.controls[def.key] = box
    label(content, def.detail, 30, y + 26, 460, 30, "GameFontHighlightSmall")
  end
  label(content, "Your character", 0, 294, 500, 20, "GameFontNormalLarge")
  label(content, "Edit your character sheet and choose whether to share a public profile.", 0, 322, 500, 32, "GameFontHighlightSmall")
  local function leaveSettings()
    if SettingsPanel then SettingsPanel:Hide() end
    if InterfaceOptionsFrame then InterfaceOptionsFrame:Hide() end
  end
  S.sheet = F.Button(content, "CM_OptionsPanelOpenSheet", "My character", 0, 366, 140, function() leaveSettings(); CharacterMemory_OpenCharacterSheet() end)
  S.journal = F.Button(content, "CM_OptionsPanelOpenJournal", "Open journal", 152, 366, 140, function() leaveSettings(); CharacterMemory_OpenJournal() end)
  label(content, "Notes, memories and stories stay private. Preferences save when changed.", 0, 410, 500, 32, "GameFontDisableSmall")
  -- Bind text to the canvas width; native Settings can be narrower than its default size.
  local function fitLabel(fs, parent, right) fs:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(right or 0), -fs._cmY) end
  -- Keep each label inside its own container when the canvas changes size.
  for _, region in ipairs(labels) do fitLabel(region, region:GetParent(), region:GetParent() == root and 20 or 0) end
  scroll:HookScript("OnSizeChanged", function(self)
    local width = math.max(300, self:GetWidth() - 16); content:SetWidth(width)
  end)
  root:HookScript("OnShow", S.Load)
end
build()

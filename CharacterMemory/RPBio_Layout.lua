if not CMCompat or not CMCompat.supported then return end
-- One character sheet. Each section has its own bounded, scrollable page.
RPBioUI = { pages = {}, tabs = {}, fields = {}, active = "Identity" }
local U, F = RPBioUI, CMForms
local WIDTH, HEIGHT, CONTENT = 740, 580, 518
function U.MarkDirty()
  U.dirty = true
  if U.status then U.status:SetText("Unsaved changes"); U.status:SetTextColor(1, 0.82, 0) end
end
local function field(page, name, title, x, y, width, multiline, limit)
  local box = F.Field(page, name, title, x, y, width or CONTENT, multiline, limit)
  U.fields[#U.fields + 1] = box
  box.edit:HookScript("OnTextChanged", function(_, userInput) if userInput then U.MarkDirty() end end)
  return box
end
function U.ShowPage(name)
  if not U.pages[name] then return end
  U.active = name
  for key, page in pairs(U.pages) do page.scroll:SetShown(key == name); U.tabs[key]:SetEnabled(key ~= name) end
  if GetCurrentKeyBoardFocus then local edit = GetCurrentKeyBoardFocus(); if edit and edit.ClearFocus then edit:ClearFocus() end end
end
local function page(name, description, height)
  local root = RPBioFrame
  local scroll = CreateFrame("ScrollFrame", "RPBioPage" .. name, root, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 166, -64); scroll:SetPoint("BOTTOMRIGHT", -34, 64)
  local content = CreateFrame("Frame", "RPBioContent" .. name, scroll)
  content:SetSize(CONTENT, height); scroll:SetScrollChild(content)
  F.Label(content, description, 0, 0, CONTENT, 40, "GameFontHighlightSmall")
  U.pages[name] = { scroll = scroll, content = content }
  return content
end
local function build()
  local root = RPBioFrame
  root:SetSize(WIDTH, HEIGHT); F.DialogTitle(root); root:SetClampedToScreen(true); root.TitleText:SetText("My character")
  F.Label(root, "RP Journal", 20, 36, 126, 20, "GameFontNormalLarge")
  local identity = page("Identity", "The name and details people remember you by.", 396)
  field(identity, "RPBio_Title", "Title", 0, 56)
  field(identity, "RPBio_Nicknames", "Nicknames / aliases", 0, 114)
  field(identity, "RPBio_Pronouns", "Pronouns", 0, 172, 250)
  field(identity, "RPBio_Race", "Race / sub-race", 268, 172, 250)
  field(identity, "RPBio_Homeland", "Homeland", 0, 230, 250)
  field(identity, "RPBio_Residence", "Current residence", 268, 230, 250)
  field(identity, "RPBio_Affiliations", "Affiliations / guilds", 0, 288)
  local appearance = page("Appearance", "A few details that help someone picture your character.", 396)
  field(appearance, "RPBio_Height", "Height", 0, 56, 250)
  field(appearance, "RPBio_Build", "Build", 268, 56, 250)
  field(appearance, "RPBio_Eyes", "Eyes", 0, 114, 250)
  field(appearance, "RPBio_Hair", "Hair", 268, 114, 250)
  field(appearance, "RPBio_Features", "Distinctive features", 0, 172)
  field(appearance, "RPBio_Attire", "Typical attire", 0, 230)
  local story = page("Story", "Only the short bio is included in your public profile. Your longer story stays here.", 628)
  local shortBio = field(story, "RPBio_ShortBio", "Short bio", 0, 56, CONTENT, 88, 500)
  U.bioCount = F.Label(story, "0 / 500 bytes", CONTENT - 140, 56, 140, 16, "GameFontHighlightSmall")
  U.bioCount:SetJustifyH("RIGHT")
  shortBio.edit:HookScript("OnTextChanged", function(self) U.bioCount:SetText(#(self:GetText() or "") .. " / 500 bytes") end)
  field(story, "RPBio_Backstory", "Backstory / lore", 0, 181, CONTENT, 170, 12000)
  F.Dropdown(story, "RPBio_AlignmentDD", "Alignment", 0, 388, 250)
  field(story, "RPBio_Creed", "Creed / beliefs", 268, 388, 250)
  field(story, "RPBio_Deeds", "Notable deeds", 0, 450, CONTENT, 120, 4000)
  local personality = page("Personality", "Give other roleplayers a reason to start a conversation.", 462)
  field(personality, "RPBio_Traits", "Traits · separated by commas", 0, 56)
  field(personality, "RPBio_Ideals", "Ideals", 0, 114)
  field(personality, "RPBio_Bonds", "Bonds", 0, 172)
  field(personality, "RPBio_Flaws", "Flaws", 0, 230)
  field(personality, "RPBio_Hooks", "RP hooks", 0, 288, CONTENT, 120, 2048)
  local skills = page("Skills", "Your day-to-day work, interests and skills.", 396)
  field(skills, "RPBio_Occupation", "Occupation / profession", 0, 56)
  field(skills, "RPBio_Languages", "Languages · separated by commas", 0, 114)
  field(skills, "RPBio_Hobbies", "Hobbies · separated by commas", 0, 172)
  field(skills, "RPBio_CombatFocus", "Combat specialty / magic", 0, 230)
  local people = page("Relationships", "The people and companions in your character's life. These details stay private.", 634)
  field(people, "RPBio_Partner", "Partner", 0, 56, 250)
  field(people, "RPBio_PartnerNote", "A note about them", 268, 56, 250)
  field(people, "RPBio_Family", "Family", 0, 114, CONTENT, 80, 4000)
  field(people, "RPBio_Allies", "Allies", 0, 231, CONTENT, 80, 4000)
  field(people, "RPBio_Rivals", "Rivals", 0, 348, CONTENT, 80, 4000)
  field(people, "RPBio_Pets", "Pets / companions", 0, 465, CONTENT, 80, 4000)
  local preferences = page("Preferences", "Your availability and boundaries. Limits and contact details are never sent with your public profile.", 430)
  F.Dropdown(preferences, "RPBio_AvailabilityDD", "Availability", 0, 56, 250)
  field(preferences, "RPBio_Tone", "Preferred tone · comma separated", 268, 56, 250)
  field(preferences, "RPBio_Limits", "Limits / content warnings", 0, 118, CONTENT, 150, 4000)
  field(preferences, "RPBio_OOC", "OOC contact", 0, 305)
  local notes = page("Notes", "Personal notes for this character. Neither of these pages is sent with your public profile.", 466)
  field(notes, "RPBio_PublicNotes", "Character notes", 0, 56, CONTENT, 130, 4000)
  field(notes, "RPBio_PrivateNotes", "Private notes", 0, 223, CONTENT, 170, 12000)
  for i, name in ipairs({"Identity", "Appearance", "Story", "Personality", "Skills", "Relationships", "Preferences", "Notes"}) do
    U.tabs[name] = F.Button(root, nil, name, 20, 64 + (i - 1) * 30, 126, function() U.ShowPage(name) end)
  end
  local sharing = CreateFrame("CheckButton", "RPBio_PublicSharing", root, "UICheckButtonTemplate")
  sharing:SetSize(24, 24); sharing:SetPoint("BOTTOMLEFT", 18, 16); sharing.Text:SetText("Share public profile")
  sharing:SetScript("OnClick", U.MarkDirty)
  sharing:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Share your short bio and public character details when another RP Journal player requests them. Notes, stories, relationships, limits and contact details stay private.", nil, nil, nil, nil, true); GameTooltip:Show()
  end); sharing:SetScript("OnLeave", function() GameTooltip:Hide() end)
  U.status = F.Label(root, "", 270, HEIGHT - 34, 220, 18, "GameFontHighlightSmall")
  U.close = F.Button(root, nil, "Close", WIDTH - 232, HEIGHT - 42, 100, function() root:Hide() end)
  U.save = F.Button(root, "RPBioSaveButton", "Save", WIDTH - 120, HEIGHT - 42, 100, function() RPBio_Save() end)
  root:HookScript("OnShow", function() F.Fit(root, WIDTH, HEIGHT); U.ShowPage(U.active) end)
  root:HookScript("OnHide", function()
    for _, box in ipairs(U.fields) do if box.edit then box.edit:ClearFocus() end end
  end)
  if UISpecialFrames then table.insert(UISpecialFrames, "RPBioFrame") end
  U.ShowPage("Identity")
end
build()

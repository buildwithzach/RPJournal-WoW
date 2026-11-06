if not CMCompat or not CMCompat.supported then return end
-- Native click menus around the existing journal. Nothing is sent or auto-authored.
CMStorybook = {}
local S, M, J, U = CMStorybook, CMChronicle, CMJourney, CMChronicleUI
local PAGE = 10
local function person(guid) return CharacterMemoryDB and CharacterMemoryDB.entries and CharacterMemoryDB.entries[guid] end
local function caption(value) return CMCompat.Display((value or ""):gsub("%s+", " "), 80) end
local function line(title, fn, disabled, heading)
  local info = UIDropDownMenu_CreateInfo()
  info.text, info.notCheckable, info.keepShownOnClick = caption(title), true, true
  info.disabled, info.isTitle = disabled, heading
  info.func = fn
  UIDropDownMenu_AddButton(info, 1)
end
local function action(title, fn, disabled)
  line(title, function() CloseDropDownMenus(); if not InCombatLockdown() then fn() end end, disabled)
end
local function edit(guid, kind, itemID)
  local collection = kind == "story" and "stories" or "memories"
  local item = M.Find(guid, collection, itemID)
  if not item or not J.Reveal(guid) then return end
  if J.reader then J.reader:Hide() end
  CMUI.TabSwap("Notes"); U.SetMode(kind == "story" and "stories" or "memories")
  local copy = {}; for k, v in pairs(item) do copy[k] = v end; copy.type = kind
  U.Edit(kind, copy)
end

function S.Keepsake(guid, memoryID)
  if InCombatLockdown() or not M.Find(guid, "memories", memoryID) then return end
  StaticPopup_Show("CMJ_KEEP_KEEPSAKE", nil, nil, {guid = guid, id = memoryID})
end

local function refreshReader(guid)
  local r = J.reader
  if not r or not r:IsShown() or r.guid ~= guid then return end
  if r.mode == "stories" then J.ReadStory(guid, r.storyID)
  else J.Read(guid, r.memoryID, nil, r.chapterStoryID) end
end

StaticPopupDialogs["CMJ_KEEP_KEEPSAKE"] = {
  text = "Keep a small reminder with this memory.\nDescribe it in one line, or paste one item link.\nThis is a private journal keepsake.",
  button1 = "Keep", button2 = "Cancel", hasEditBox = true, maxLetters = 512,
  OnShow = function(dialog)
    local data = dialog.data
    local memory = data and M.Find(data.guid, "memories", data.id)
    local input = dialog:GetEditBox()
    input:SetText(memory and memory.keepsake and (memory.keepsake.link or memory.keepsake.label) or "")
    input:SetFocus(); input:HighlightText()
  end,
  OnAccept = function(dialog, data)
    if InCombatLockdown() then return true end
    local ok, message = M.SetKeepsake(data.guid, data.id, dialog:GetEditBox():GetText())
    if not ok then DEFAULT_CHAT_FRAME:AddMessage(message); return true end
    refreshReader(data.guid)
  end,
  EditBoxOnEscapePressed = function(input) input:GetParent():Hide() end,
  timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["CMJ_FIND_PAGE"] = {
  text = "Find words in this person's memories, stories, places or keepsakes.",
  button1 = "Find", button2 = "Cancel", hasEditBox = true, maxLetters = 120,
  OnShow = function(dialog) dialog:GetEditBox():SetText(""); dialog:GetEditBox():SetFocus() end,
  OnAccept = function(dialog, data)
    local query = CMCompat.Text(dialog:GetEditBox():GetText(), 120):match("^%s*(.-)%s*$")
    if query == "" or InCombatLockdown() then return true end
    S.Open(data.guid, "search", 1, query)
  end,
  EditBoxOnEscapePressed = function(input) input:GetParent():Hide() end,
  timeout = 0, whileDead = true, hideOnEscape = true,
}

function S.Copy(guid, memoryID)
  if InCombatLockdown() then return false end
  local excerpt = M.Excerpt(guid, memoryID)
  if not excerpt then return false end
  if not S.copyFrame then
    local f = CreateFrame("Frame", "CMJ_CopyMemory", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(460, 360); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); f:Hide()
    f.TitleText:SetText("Copy a memory")
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 20, -38); hint:SetWidth(420); hint:SetMaxLines(3)
    hint:SetJustifyH("LEFT"); hint:SetText("Only this memory is included. Edit this copy if you like, then use your usual copy shortcut. Nothing is sent.")
    local scroll = CreateFrame("ScrollFrame", "CMJ_CopyMemoryText", f, "InputScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -90); scroll:SetPoint("BOTTOMRIGHT", -36, 54)
    f.input = scroll.EditBox
    f.input:SetAutoFocus(false); f.input:SetMultiLine(true); f.input:SetMaxLetters(8192); f.input:SetFontObject(GameFontHighlightSmall)
    f.input:SetScript("OnEscapePressed", function() f:Hide() end)
    local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    close:SetSize(100, 22); close:SetPoint("BOTTOMRIGHT", -20, 16); close:SetText("Close")
    close:SetScript("OnClick", function() f:Hide() end)
    f:HookScript("OnHide", function() f.input:ClearFocus() end)
    S.copyFrame = f; table.insert(UISpecialFrames, "CMJ_CopyMemory")
  end
  local f = S.copyFrame
  -- Escape display markup in the editable preview as everywhere else in the journal.
  f.input:SetText(CMCompat.Display(excerpt)); f:Show(); f:Raise(); f.input:SetFocus(); f.input:HighlightText()
  return true
end

local function pages(guid, view, page, context, items, choose)
  local total = math.max(1, math.ceil(#items / PAGE))
  page = math.max(1, math.min(page, total))
  for i = (page - 1) * PAGE + 1, math.min(#items, page * PAGE) do
    local item = items[i]
    line(type(item) == "table" and item.title or item, function() choose(item) end)
  end
  if #items == 0 then line("No pages here yet", nil, true) end
  if page > 1 then line("< Previous page", function() S.Open(guid, view, page - 1, context) end) end
  if page < total then line("Next page >", function() S.Open(guid, view, page + 1, context) end) end
  line("Page " .. page .. " / " .. total, nil, true)
end

function S.Open(guid, view, page, context)
  local e = person(guid)
  if InCombatLockdown() or not e or guid == CMCompat.UnitGUID("player") then return false end
  view, page = view or "home", page or 1
  if not S.menu then S.menu = CreateFrame("Frame", "CMJ_StorybookMenu", UIParent, "UIDropDownMenuTemplate") end
  CloseDropDownMenus()
  UIDropDownMenu_Initialize(S.menu, function()
    line(e.name or "Our story", nil, true, true)
    if view == "home" then
      action("Read our story", function() J.Read(guid) end)
      action("Continue draft", function() J.Write(guid) end, not e.journalDraft)
      action("Keep a memory", function() J.Write(guid, false) end)
      for _, pair in ipairs({{"open", "Unfinished stories"}, {"resolved", "Finished stories"}, {"memories", "All memories"},
        {"pinned", "Pinned memories"}, {"keepsakes", "Memories with keepsakes"}, {"places", "Familiar places"}}) do
        local kind = pair[1]; line(pair[2], function() S.Open(guid, kind) end)
      end
      action("Find a memory or story...", function() StaticPopup_Show("CMJ_FIND_PAGE", nil, nil, {guid = guid}) end)
    elseif view == "memory" then
      local memory = M.Find(guid, "memories", context)
      if memory then
        line(memory.title, nil, true, true)
        action("Read memory", function() J.Read(guid, context) end)
        action("Edit memory", function() edit(guid, "memory", context) end)
        action(memory.pinned and "Unpin memory" or "Pin memory", function() M.Pin(guid, context); refreshReader(guid) end)
        action(memory.keepsake and "Change keepsake..." or "Keep a keepsake...", function() S.Keepsake(guid, context) end)
        if memory.keepsake then action("Remove keepsake", function() M.SetKeepsake(guid, context, ""); refreshReader(guid) end) end
        local seen = {}
        for _, id in pairs({memory.nextStoryID, memory.continuedStoryID, memory.resolvedStoryID}) do
          local story = M.Find(guid, "stories", id)
          if story and not seen[id] then
            seen[id] = true; line("Chapters: " .. story.title, function() J.ReadChapters(guid, id, context); CloseDropDownMenus() end)
          end
        end
        action("Copy this memory...", function() S.Copy(guid, context) end)
        action("Remove memory...", function() StaticPopup_Show("CMJ_CONFIRM_REMOVE_PAGE", nil, nil, {guid = guid, id = context}) end)
      else line("This memory was removed", nil, true) end
    elseif view == "story" then
      local story = M.Find(guid, "stories", context)
      if story then
        line(story.title, nil, true, true)
        action("Read story", function() J.ReadStory(guid, context) end)
        action("Read chapters", function() J.ReadChapters(guid, context) end)
        action("Continue story", function() J.Write(guid, context) end, story.state ~= "open")
        action("Edit story", function() edit(guid, "story", context) end)
        action(story.state == "open" and "Resolve thread" or "Reopen thread", function()
          local current = M.Find(guid, "stories", context)
          if current then
            M.UpdateStory(guid, context, current.title, current.note, current.state == "open" and "resolved" or "open")
            refreshReader(guid)
          end
        end)
      else line("This story was removed", nil, true) end
    elseif view == "places" then
      pages(guid, view, page, context, M.Places(guid), function(place) S.Open(guid, "place", 1, place) end)
    elseif view == "search" then
      line("Found: " .. context, nil, true, true)
      pages(guid, view, page, context, M.Search(guid, context), function(item) S.Open(guid, item.type, 1, item.id) end)
    elseif view == "open" or view == "resolved" then
      local items = {}
      for _, story in ipairs(M.StoryList(guid)) do if story.state == view then items[#items + 1] = story end end
      pages(guid, view, page, context, items, function(item) S.Open(guid, "story", 1, item.id) end)
    else
      local items = {}
      for _, memory in ipairs(M.List(guid)) do
        if view == "memories" or (view == "pinned" and memory.pinned) or (view == "keepsakes" and memory.keepsake)
          or (view == "place" and memory.where == context) then items[#items + 1] = memory end
      end
      pages(guid, view, page, context, items, function(item) S.Open(guid, "memory", 1, item.id) end)
    end
    if view ~= "home" then line("< Our story", function() S.Open(guid) end) end
    action("Close", function() end)
  end, "MENU")
  ToggleDropDownMenu(1, nil, S.menu, "cursor", 0, 0)
  return true
end

-- Extend behavior after the journal creates its original controls. No restyling.
local events = CreateFrame("Frame")
CMCompat.RegisterEvent(events, "ADDON_LOADED")
CMCompat.RegisterEvent(events, "PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function(_, event, name)
  if event == "PLAYER_REGEN_DISABLED" then
    CloseDropDownMenus()
    if S.copyFrame then S.copyFrame:Hide() end
    return
  end
  if name ~= "CharacterMemory" or not U.ourStory then return end
  U.ourStory:SetScript("OnClick", function() if U.guid then S.Open(U.guid) end end)
  U.ourStory:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Our story")
    GameTooltip:AddLine("Find your chapters, promises, places and keepsakes.", 1, 1, 1, true); GameTooltip:Show()
  end)
  U.ourStory:HookScript("OnLeave", function() GameTooltip:Hide() end)
  for _, row in ipairs(U.rows or {}) do
    local original = row:GetScript("OnClick")
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button)
      if button == "RightButton" and row.item and row.item.type ~= "candidate" then S.Open(U.guid, row.item.type, 1, row.item.id)
      elseif original then original(self, button) end
    end)
    row:HookScript("OnEnter", function(self)
      if not row.item or row.item.type == "candidate" then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(caption(row.item.title))
      GameTooltip:AddLine("Click to read. Right-click for page actions.", 1, 1, 1, true); GameTooltip:Show()
    end)
    row:HookScript("OnLeave", function() GameTooltip:Hide() end)
  end
end)

if not CMCompat or not CMCompat.supported then return end
-- Additive native controls inside the existing Notes page; the journal shell is unchanged.
CMChronicleUI = { mode = "notes", page = 1 }
local U = CMChronicleUI
local PAGE = 4
local function label(parent, font, text)
  local value = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
  value:SetText(text or ""); value:SetJustifyH("LEFT")
  return value
end
local function button(parent, text, width, fn)
  local value = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  value:SetSize(width or 70, 20); value:SetText(text); value:SetScript("OnClick", fn)
  return value
end
local function person(guid) return CharacterMemoryDB and CharacterMemoryDB.entries and CharacterMemoryDB.entries[guid] end
local function current() return U.selected end

local function copyItem(item, kind)
  if not item then return nil end
  local result = {}; for key, value in pairs(item) do result[key] = value end
  result.type = kind
  return result
end

function U.FlushDraft()
  local f = U.editor
  if not f or f.loading or f.committed or not f.guid then return end
  local e = person(f.guid); if not e then return end
  local title, note = f.titleInput:GetText() or "", f.bodyInput:GetText() or ""
  local nextThread = f.followup:IsShown() and f.followup:GetText() or ""
  local resolve = f.resolveID and f.resolve:GetChecked() or false
  local initial = f.initial or {}
  if title == initial.title and note == initial.note and nextThread == "" and not resolve then
    e.journalDraft = nil; return
  end
  e.journalDraft = { kind = f.kind, itemID = f.item and f.item.id, itemType = f.item and f.item.type,
    title = CMCompat.Text(title, 120), note = CMCompat.Text(note), nextThread = CMCompat.Text(nextThread, 120),
    resolve = resolve and true or false, resolveID = f.resolveID, continueID = f.continueID,
    moment = CMChronicle.Moment(f.moment), at = time() }
end

local function buildEditor(root)
  local editor = CreateFrame("Frame", "CMJ_ChronicleEditor", root, "BasicFrameTemplateWithInset")
  editor:SetSize(420, 420); editor:SetPoint("CENTER"); editor:SetFrameStrata("DIALOG"); editor:Hide()
  local titleLabel = label(editor, "GameFontNormal", "Title")
  titleLabel:SetPoint("TOPLEFT", 20, -38)
  local title = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
  title:SetSize(365, 22); title:SetPoint("TOPLEFT", 24, -58); title:SetAutoFocus(false); title:SetMaxLetters(120)
  local context = label(editor, "GameFontDisableSmall")
  context:SetPoint("TOPLEFT", 20, -88); context:SetWidth(365); context:SetMaxLines(2)
  local bodyLabel = label(editor, "GameFontNormal", "Your words")
  bodyLabel:SetPoint("TOPLEFT", 20, -118)
  local scroll = CreateFrame("ScrollFrame", "CMJ_ChronicleEditorBody", editor, "InputScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 20, -140); scroll:SetPoint("BOTTOMRIGHT", -36, 140)
  local body = scroll.EditBox
  if not body then editor:Hide(); return nil end
  body:SetAutoFocus(false); body:SetMultiLine(true); body:SetMaxLetters(2048); body:SetFontObject(GameFontHighlightSmall)
  local hint = label(scroll, "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", 6, -6); hint:SetWidth(335); hint:SetMaxLines(3)
  local nextLabel = label(editor, "GameFontNormal", "Next time… (optional)")
  nextLabel:SetPoint("BOTTOMLEFT", 20, 113)
  local followup = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
  followup:SetSize(365, 22); followup:SetPoint("BOTTOMLEFT", 24, 86); followup:SetMaxLetters(120); followup:SetAutoFocus(false)
  local resolve = CreateFrame("CheckButton", nil, editor, "UICheckButtonTemplate")
  resolve:SetSize(24, 24); resolve:SetPoint("BOTTOMLEFT", 16, 56)
  if resolve.Text then resolve.Text:SetWidth(345); resolve.Text:SetMaxLines(1) end
  local err = label(editor, "GameFontRedSmall")
  err:SetPoint("BOTTOMLEFT", 20, 34); err:SetWidth(370); err:SetMaxLines(2)
  editor.titleInput, editor.bodyInput, editor.errorText = title, body, err
  editor.followup, editor.nextLabel, editor.resolve, editor.context = followup, nextLabel, resolve, context
  editor.scroll, editor.hint, editor.bodyLabel = scroll, hint, bodyLabel
  editor.save = button(editor, "Keep memory", 100, function()
    if editor.committed or not editor:IsShown() then return end
    U.FlushDraft()
    local guid, item = editor.guid, editor.item
    local name, words = title:GetText() or "", body:GetText() or ""
    local ok, message
    if editor.kind == "story" then
      if item then ok = CMChronicle.UpdateStory(guid, item.id, name, words, item.state)
      else ok, message = CMChronicle.AddStory(guid, name, words) end
    elseif item and item.type == "memory" then ok = CMChronicle.Update(guid, item.id, name, words)
    else ok, message = CMChronicle.SaveMoment(guid, item and item.id, words, name, followup:GetText(), resolve:GetChecked() and editor.resolveID, editor.continueID, editor.moment) end
    if not ok then err:SetText(message or "Give this page a title and try again. Your draft is safe."); return end
    local e = person(guid); if e then e.journalDraft = nil end
    editor.committed = true; editor:Hide(); U.Refresh(U.guid)
    if editor.kind ~= "story" and (not item or item.type == "candidate") and CMJourney then CMJourney.Read(guid, ok) end
  end)
  editor.save:SetPoint("BOTTOMLEFT", 20, 12)
  editor.discard = button(editor, "Discard draft", 104, function()
    StaticPopup_Show("CMJ_DISCARD_DRAFT", nil, nil, { guid = editor.guid })
  end)
  editor.discard:SetPoint("LEFT", editor.save, "RIGHT", 8, 0)
  editor.cancel = button(editor, "Later", 84, function() editor:Hide() end)
  editor.cancel:SetPoint("BOTTOMRIGHT", -20, 12)
  for _, edit in ipairs({title, body, followup}) do
    edit:HookScript("OnTextChanged", function() hint:SetShown((body:GetText() or "") == ""); U.FlushDraft() end)
    edit:SetScript("OnEscapePressed", function() editor:Hide() end)
  end
  resolve:SetScript("OnClick", U.FlushDraft)
  editor:HookScript("OnHide", function()
    U.FlushDraft(); title:ClearFocus(); body:ClearFocus(); followup:ClearFocus()
  end)
  if UISpecialFrames then table.insert(UISpecialFrames, "CMJ_ChronicleEditor") end
  return editor
end

function U.ResumeDraft(guid)
  local e = person(guid); local draft = e and e.journalDraft
  if not draft then return end
  U.guid = guid
  local collection = draft.itemType == "story" and "stories" or draft.itemType == "memory" and "memories" or "memoryCandidates"
  local item = draft.itemID and CMChronicle.Find(guid, collection, draft.itemID)
  if not item and draft.itemType == "candidate" and draft.moment then
    item = CMChronicle.Moment(draft.moment)
    if item then item.id = nil end -- Keep its facts even if the pending suggestion was dismissed.
  end
  U.Edit(draft.kind, copyItem(item, draft.itemType), true)
end

function U.Edit(kind, item, resume, threadID)
  if InCombatLockdown() or not U.editor or not person(U.guid) then return end
  U.FlushDraft()
  local e, editor = person(U.guid), U.editor
  local draft = e.journalDraft
  if draft and not resume and (draft.kind ~= kind or draft.itemID ~= (item and item.id)) then
    StaticPopup_Show("CMJ_RESUME_DRAFT", nil, nil, { guid = U.guid }); return
  end
  editor.loading, editor.committed = true, false
  editor.kind, editor.guid, editor.item = kind, U.guid, item
  editor.initial = { title = item and item.type ~= "candidate" and item.title or "", note = item and item.note or "" }
  editor.titleInput:SetText(draft and draft.title or editor.initial.title)
  editor.bodyInput:SetText(draft and draft.note or editor.initial.note)
  editor.followup:SetText(draft and draft.nextThread or "")
  local isNewMemory = kind ~= "story" and (not item or item.type == "candidate")
  editor.moment = isNewMemory and CMChronicle.Moment(draft and draft.moment or item) or nil
  editor.followup:SetShown(isNewMemory); editor.nextLabel:SetShown(isNewMemory)
  local _, story = CMChronicle.Highlights(U.guid)
  local contextID = draft and (draft.continueID or draft.resolveID) or threadID or (item and item.storyID)
  if contextID then story = CMChronicle.Find(U.guid, "stories", contextID) end
  if threadID == false and not draft then story, contextID = nil, nil end
  editor.continueID = isNewMemory and (contextID or (story and story.id)) or nil
  editor.resolveID = isNewMemory and story and story.state == "open" and story.id or nil
  editor.resolve:SetShown(editor.resolveID ~= nil); editor.resolve:SetChecked(draft and draft.resolve or false)
  if editor.resolve.Text then editor.resolve.Text:SetText("Finish: " .. CMCompat.Display(story and story.title or "", 100)) end
  editor.scroll:ClearAllPoints(); editor.scroll:SetPoint("TOPLEFT", 20, -140)
  editor.scroll:SetPoint("BOTTOMRIGHT", -36, isNewMemory and 140 or 68)
  editor.bodyLabel:SetText(kind == "story" and "What do you want to pick up next time?" or "One detail worth keeping")
  local prompts = { meeting = "A kindness, a curious detail, the way your paths crossed…",
    reunion = "What happened when you met again? Did you keep that promise?" }
  editor.hint:SetText(kind == "story" and "A plan, a promise, a reason to cross paths again…"
    or (prompts[item and item.kind] or "One sentence is enough. These words are yours alone.") .. "\nA title is optional.")
  editor.hint:SetShown((editor.bodyInput:GetText() or "") == "")
  local stamp = item and item.at or time()
  local context = date("%b %d, %Y", stamp) .. " · " .. CMCompat.Display(item and item.where or e.lastSeenWhere, 46)
  if isNewMemory and story then context = context .. "\nPicking up: " .. CMCompat.Display(story.title, 56) end
  editor.context:SetText(context)
  editor.errorText:SetText("")
  editor.save:SetText(kind == "story" and "Save thread" or item and item.type == "memory" and "Save changes" or "Keep memory")
  if editor.TitleText then editor.TitleText:SetText((kind == "story" and "Story with " or "Memory of ") .. CMCompat.Display(e.name or "this person", 70)) end
  editor.loading = false
  editor:Show(); editor:Raise()
  if isNewMemory then editor.bodyInput:SetFocus() else editor.titleInput:SetFocus() end
end

StaticPopupDialogs["CMJ_RESUME_DRAFT"] = {
  text = "You have an unfinished page for this person. Continue where you left off?", button1 = "Continue", button2 = "Cancel",
  OnAccept = function(_, data) if data then U.ResumeDraft(data.guid) end end,
  timeout = 0, whileDead = true, hideOnEscape = true,
}
StaticPopupDialogs["CMJ_DISCARD_DRAFT"] = {
  text = "Discard the words on this unfinished page? Saved memories and stories will stay.", button1 = "Discard", button2 = "Cancel",
  OnAccept = function(_, data)
    local e = data and person(data.guid); if e then e.journalDraft = nil end
    if U.editor and U.editor.guid == (data and data.guid) then U.editor.committed = true; U.editor:Hide() end
  end,
  timeout = 0, whileDead = true, hideOnEscape = true,
}

function U.SetMode(mode)
  if mode ~= "notes" and mode ~= "memories" and mode ~= "stories" then return end
  U.mode, U.page, U.selected = mode, 1, nil
  local R = CMJ.refs
  if R.noteEdit then R.noteEdit:SetShown(mode == "notes") end
  if _G.CMJ_RootXMLPageRNotesScroll then _G.CMJ_RootXMLPageRNotesScroll:SetShown(mode == "notes") end
  if _G.CMJ_RootXMLPageRNotesShare then _G.CMJ_RootXMLPageRNotesShare:SetShown(mode == "notes") end
  U.panel:SetShown(mode ~= "notes")
  for key, tab in pairs(U.tabs) do tab:SetEnabled(key ~= mode) end
  U.Refresh(U.guid)
end

function U.Open(item)
  if not item or not person(U.guid) or InCombatLockdown() then return end
  local collection = item.type == "story" and "stories" or item.type == "memory" and "memories" or "memoryCandidates"
  local actual = CMChronicle.Find(U.guid, collection, item.id)
  if not actual then U.Refresh(U.guid); return end
  U.selected = copyItem(actual, item.type); U.Refresh(U.guid)
  if item.type == "candidate" then
    if CMJourney.reader then CMJourney.reader:Hide() end
    U.Edit("memory", U.selected)
  elseif item.type == "story" then CMJourney.ReadStory(U.guid, item.id)
  else CMJourney.Read(U.guid, item.id) end
end

function U.Build(root)
  if U.panel then return end
  local notes = CMJ.refs.notes
  if not notes then return end
  U.tabs = {}
  for i, pair in ipairs({{"notes", "Notes"}, {"memories", "Memories"}, {"stories", "Stories"}}) do
    local mode = pair[1]
    local tab = button(notes, pair[2], 82, function() U.SetMode(mode) end)
    tab:SetPoint("TOPLEFT", (i - 1) * 88 + 4, -4); U.tabs[mode] = tab
  end
  local noteScroll = _G.CMJ_RootXMLPageRNotesScroll
  if noteScroll then
    noteScroll:ClearAllPoints(); noteScroll:SetPoint("TOPLEFT", 4, -34); noteScroll:SetPoint("BOTTOMRIGHT", -24, 32)
  end
  local panel = CreateFrame("Frame", nil, notes)
  panel:SetPoint("TOPLEFT", 4, -34); panel:SetPoint("BOTTOMRIGHT", -4, 0); panel:Hide(); U.panel = panel
  U.rows = {}
  for i = 1, PAGE do
    local row = CreateFrame("Button", nil, panel)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * 55); row:SetPoint("RIGHT", -4, 0); row:SetHeight(52)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.title = label(row, "GameFontNormal")
    row.title:SetPoint("TOPLEFT", 4, -3); row.title:SetPoint("RIGHT", -5, 0); row.title:SetMaxLines(1)
    row.detail = label(row, "GameFontHighlightSmall")
    row.detail:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3); row.detail:SetPoint("RIGHT", -5, 0); row.detail:SetMaxLines(1)
    row.context = label(row, "GameFontDisableSmall")
    row.context:SetPoint("TOPLEFT", row.detail, "BOTTOMLEFT", 0, -2); row.context:SetPoint("RIGHT", -5, 0); row.context:SetMaxLines(1)
    row:SetScript("OnClick", function()
      U.Open(row.item)
    end)
    U.rows[i] = row
  end
  U.empty = label(panel, "GameFontHighlightSmall")
  U.empty:SetPoint("TOPLEFT", 8, -40); U.empty:SetPoint("RIGHT", -8, 0)
  U.empty:SetText("Keep a moment, or start a story of your own.")
  U.add = button(panel, "New", 56, function() U.Edit(U.mode == "stories" and "story" or "memory") end)
  U.add:SetPoint("BOTTOMLEFT", 0, 7)
  U.edit = button(panel, "Edit", 56, function() if current() then U.Edit(U.mode == "stories" and "story" or "memory", current()) end end)
  U.edit:SetPoint("LEFT", U.add, "RIGHT", 4, 0)
  U.pin = button(panel, "Pin", 64, function()
    local item = current(); if not item then return end
    if U.mode == "stories" then
      CMChronicle.UpdateStory(U.guid, item.id, item.title, item.note, item.state == "open" and "resolved" or "open")
    else CMChronicle.Pin(U.guid, item.id) end
    U.Refresh(U.guid)
  end)
  U.pin:SetPoint("LEFT", U.edit, "RIGHT", 4, 0)
  U.remove = button(panel, "Remove", 64, function()
    local item = current(); if not item then return end
    if item.type == "candidate" then CMChronicle.Dismiss(U.guid, item.id); U.selected = nil; U.Refresh(U.guid); return end
    StaticPopup_Show("CMJ_CONFIRM_REMOVE_PAGE", nil, nil, { guid = U.guid, id = item.id, story = U.mode == "stories" })
  end)
  U.remove:SetPoint("LEFT", U.pin, "RIGHT", 4, 0)
  U.prev = button(panel, "<", 26, function() U.page = math.max(1, U.page - 1); U.Refresh(U.guid) end)
  U.prev:SetPoint("BOTTOMRIGHT", -34, 7)
  U.next = button(panel, ">", 26, function() U.page = U.page + 1; U.Refresh(U.guid) end)
  U.next:SetPoint("BOTTOMRIGHT", -4, 7)
  U.editor = buildEditor(root)
  local overview = CMJ.refs.overview
  if overview then
    U.favorite = button(overview, "Favorite", 90, function()
      local e = person(U.guid); if not e then return end
      e.favorite = not e.favorite; CMJ.NotifyDataChanged(); U.Refresh(U.guid)
    end)
    U.favorite:SetPoint("BOTTOMLEFT", 8, -4)
    U.ourStory = button(overview, "Our story", 100, function() if U.guid and CMJourney then CMJourney.Read(U.guid) end end)
    U.ourStory:SetPoint("LEFT", U.favorite, "RIGHT", 8, 0)
  end
  U.SetMode("notes")
end

function U.Refresh(guid)
  if not U.panel then return end
  if U.guid ~= guid then U.selected, U.page = nil, 1 end
  U.guid = guid
  local e = person(guid)
  if U.favorite then U.favorite:SetText(e and e.favorite and "Unfavorite" or "Favorite"); U.favorite:SetEnabled(e ~= nil) end
  if U.profileFrame and U.profileFrame:IsShown() and U.profileGUID == guid then U.ShowProfile(guid, true) end
  if U.ourStory then U.ourStory:SetEnabled(e ~= nil) end
  if U.mode == "notes" then return end
  local items = {}
  if e then
    if U.mode == "stories" then
      for _, story in ipairs(CMChronicle.StoryList(guid)) do
        local item = {}; for key, value in pairs(story) do item[key] = value end
        item.type = "story"; items[#items + 1] = item
      end
    else
      for _, candidate in ipairs(e.memoryCandidates or {}) do
        local item = {}; for key, value in pairs(candidate) do item[key] = value end
        item.type = "candidate"; items[#items + 1] = item
      end
      for _, memory in ipairs(CMChronicle.List(guid)) do
        local item = {}; for key, value in pairs(memory) do item[key] = value end
        item.type = "memory"; items[#items + 1] = item
      end
    end
  end
  local selectedID = U.selected and U.selected.id
  U.selected = nil
  for _, item in ipairs(items) do if item.id == selectedID then U.selected = item; break end end
  U.page = math.max(1, math.min(U.page, math.max(1, math.ceil(#items / PAGE))))
  for i, row in ipairs(U.rows) do
    local item = items[(U.page - 1) * PAGE + i]
    row.item = item; row:SetShown(item ~= nil)
    if item then
      row.title:SetText((item.type == "candidate" and "New moment: " or item.pinned and "* " or "") .. CMCompat.Display(item.title, 120))
      row.detail:SetText(CMCompat.Display(item.note and item.note ~= "" and item.note or (item.type == "candidate" and "Select to remember or let it pass." or ""), 100))
      row.context:SetText((item.state == "resolved" and "Resolved · " or "") .. date("%b %d", item.at) .. " · " .. CMCompat.Display(item.where, 120))
      if U.selected and U.selected.id == item.id then row:LockHighlight() else row:UnlockHighlight() end
    end
  end
  U.empty:SetShown(#items == 0)
  U.add:SetEnabled(e ~= nil)
  U.edit:SetEnabled(U.selected ~= nil)
  U.edit:SetText(U.selected and U.selected.type == "candidate" and "Keep" or "Edit")
  U.pin:SetEnabled(U.selected ~= nil and U.selected.type ~= "candidate")
  U.pin:SetText(U.mode == "stories" and (U.selected and U.selected.state == "resolved" and "Reopen" or "Resolve") or (U.selected and U.selected.pinned and "Unpin" or "Pin"))
  U.remove:SetEnabled(U.selected ~= nil)
  U.remove:SetText(U.selected and U.selected.type == "candidate" and "Pass" or "Remove")
  U.prev:SetEnabled(U.page > 1); U.next:SetEnabled(U.page < math.ceil(#items / PAGE))
end

function U.ShowProfile(guid, refreshOnly)
  local e = person(guid)
  if not e or guid == CMCompat.UnitGUID("player") then CharacterMemory_OpenCharacterSheet(); return end
  if not U.profileFrame then
    local frame = CreateFrame("Frame", "CMJ_PublicProfile", CMJ.refs.root, "BasicFrameTemplateWithInset")
    frame:SetSize(420, 360); frame:SetPoint("CENTER"); frame:SetFrameStrata("DIALOG"); frame:Hide()
    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -40); scroll:SetPoint("BOTTOMRIGHT", -36, 54)
    local content = CreateFrame("Frame", nil, scroll); content:SetSize(350, 280); scroll:SetScrollChild(content)
    frame.content = content
    frame.body = label(content, "GameFontHighlightSmall")
    frame.body:SetPoint("TOPLEFT"); frame.body:SetWidth(340); frame.body:SetJustifyV("TOP")
    frame.request = button(frame, "Request profile", 120, function()
      local target = person(U.profileGUID)
      if target then
        local requested = CharacterMemory_RequestBioFrom(target.name, U.profileGUID)
        frame.request:SetText(requested and "Requested" or "Try again shortly")
      end
    end)
    frame.request:SetPoint("BOTTOMLEFT", 20, 15)
    local close = button(frame, "Close", 84, function() frame:Hide() end); close:SetPoint("BOTTOMRIGHT", -20, 15)
    U.profileFrame = frame
    if UISpecialFrames then table.insert(UISpecialFrames, "CMJ_PublicProfile") end
  end
  local frame = U.profileFrame
  U.profileGUID = guid
  if frame.TitleText then frame.TitleText:SetText(CMCompat.Display(e.name or "Public profile", 70)) end
  local f = e.publicProfile
  local text
  if f then
    local sections = {{"Title",2},{"Pronouns",3},{"Aliases",5},{"Bio",1},{"Traits",4},{"Alignment",6},
      {"Languages",7},{"Hobbies",8},{"Height",10},{"Build",11},{"Eyes",12},{"Hair",13},
      {"Features",14},{"Attire",15},{"Occupation",16},{"RP hooks",17}}
    local lines = {}
    for _, section in ipairs(sections) do
      if f[section[2]] and f[section[2]] ~= "" then lines[#lines + 1] = section[1] .. "\n" .. CMCompat.Display(f[section[2]], 500) end
    end
    text = #lines > 0 and table.concat(lines, "\n\n") or "This player has shared an empty public profile."
  else text = "No public profile has been shared yet. Both players need RP Journal, and the other player must enable public-profile sharing." end
  frame.body:SetText(text); frame.content:SetHeight(math.max(280, frame.body:GetStringHeight() + 12))
  if not refreshOnly then frame.request:SetText("Request profile"); frame:Show(); frame:Raise() end
end

StaticPopupDialogs["CMJ_CONFIRM_REMOVE_PAGE"] = {
  text = "Remove this page from your private journal?", button1 = "Remove", button2 = "Cancel",
  OnAccept = function(_, data)
    if not data then return end
    if data.story then CMChronicle.RemoveStory(data.guid, data.id) else CMChronicle.Remove(data.guid, data.id) end
    U.selected = nil; U.Refresh(U.guid)
  end,
  timeout = 0, whileDead = true, hideOnEscape = true,
}

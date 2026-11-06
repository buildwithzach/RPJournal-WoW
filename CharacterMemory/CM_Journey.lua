if not CMCompat or not CMCompat.supported then return end
-- Encounter-to-recollection flow. All words and prompts remain local to this character.
CMJourney = { REUNION_AFTER = 1800, DWELL = 2, NOTICE_COOLDOWN = 30, NOTICE_LIFETIME = 18 }
local J = CMJourney
local ticket, lastNotice = 0, -math.huge
local function entry(guid) return CharacterMemoryDB and CharacterMemoryDB.entries and CharacterMemoryDB.entries[guid] end
local function text(value, limit) return CMCompat.Display(value or "", limit) end
local function snippet(value, limit)
  local words = CMCompat.Text(value):gsub("%s+", " "):match("^%s*(.-)%s*$")
  if #words > limit then words = CMCompat.Text(words, limit - 3) .. "…" end
  return text(words)
end
local function shortName(e) return (e.name or "Someone"):match("^[^-]+") end

function J.Elapsed(seconds)
  seconds = math.max(0, tonumber(seconds) or 0)
  if seconds < 3600 then local n = math.max(1, math.floor(seconds / 60)); return n .. (n == 1 and " minute" or " minutes") end
  if seconds < 86400 then local n = math.floor(seconds / 3600); return n .. (n == 1 and " hour" or " hours") end
  local n = math.floor(seconds / 86400); return n .. (n == 1 and " day" or " days")
end

function J.Candidate(guid)
  local e = entry(guid)
  local candidates = e and e.memoryCandidates or {}
  for i = #candidates, 1, -1 do
    local candidate = candidates[i]
    if (candidate.kind == "reunion" or candidate.kind == "meeting")
      and (not e.journey or (candidate.at == e.journey.at and candidate.kind == e.journey.kind)) then return candidate end
  end
end

function J.CancelNotice()
  ticket = ticket + 1
  if J.notice then J.notice:Hide() end
end

function J.Reveal(guid)
  if not entry(guid) or InCombatLockdown() then return false end
  local root = CMJ and CMJ.refs and CMJ.refs.root
  if not root then return false end
  local visible = false
  for _, id in ipairs(CMJ.Model.order) do if id == guid then visible = true; break end end
  if not visible then
    CMJ.Model.filter = "all"
    if CMJ.refs.search then CMJ.refs.search:SetText("") end
    if _G.CMJ_RootXMLPageLFilterMenu then UIDropDownMenu_SetText(_G.CMJ_RootXMLPageLFilterMenu, "All people") end
  end
  if not root:IsShown() then root:Show() end
  CMJ.NotifyDataChanged(); CMUI.Select(guid)
  return true
end

local function selected(guid)
  local u = CMChronicleUI
  return u and u.guid == guid and u.selected or nil
end

function J.Write(guid, threadID)
  local choice = selected(guid)
  local reading = J.reader and J.reader:IsShown() and J.reader.guid == guid
  if threadID == nil and reading then threadID = J.reader.threadID or false end
  if threadID == nil and not reading and choice and choice.type == "story" and choice.state == "open" then threadID = choice.id end
  if not J.Reveal(guid) then return end
  J.CancelNotice()
  if J.reader then J.reader:Hide() end
  CMUI.TabSwap("Notes"); CMChronicleUI.SetMode("memories")
  if entry(guid).journalDraft then CMChronicleUI.ResumeDraft(guid)
  else
    local item = J.Candidate(guid)
    if item then local copy = {}; for key, value in pairs(item) do copy[key] = value end; copy.type = "candidate"; item = copy end
    CMChronicleUI.Edit("memory", item, nil, threadID)
  end
end

local function label(parent, font)
  local value = parent:CreateFontString(nil, "OVERLAY", font)
  value:SetJustifyH("LEFT"); value:SetJustifyV("TOP")
  return value
end
local function button(parent, title, width, fn)
  local value = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  value:SetSize(width, 22); value:SetText(title); value:SetScript("OnClick", fn)
  return value
end

-- Navigation belongs to the existing reader, not the main journal pages.
local function buildNavigation(f)
  if f.older then return end
  f.scroll = f.content:GetParent()
  f.scroll:SetPoint("BOTTOMRIGHT", -36, 88)
  f.older = button(f, "< Older", 86, function() J.Browse(f.guid, "older", f.mode == "stories") end)
  f.older:SetPoint("BOTTOMLEFT", 18, 50)
  f.newer = button(f, "Newer >", 86, function() J.Browse(f.guid, "newer", f.mode == "stories") end)
  f.newer:SetPoint("LEFT", f.older, "RIGHT", 6, 0)
  f.pageCount = label(f, "GameFontDisableSmall")
  f.pageCount:SetPoint("BOTTOMRIGHT", -18, 54); f.pageCount:SetSize(190, 14); f.pageCount:SetJustifyH("RIGHT")
  f.all:SetScript("OnClick", J.EditReadPage)
end

local function updateNavigation(f)
  local stories = f.mode == "stories"
  local items = stories and CMChronicle.StoryList(f.guid) or CMChronicle.List(f.guid)
  if f.chapterStoryID then items = CMChronicle.Chapters(f.guid, f.chapterStoryID) end
  local currentID = stories and f.storyID or f.memoryID
  local index = 0
  for i, item in ipairs(items) do if item.id == currentID then index = i; break end end
  f.older:SetText(stories and "< Previous" or "< Older"); f.newer:SetText(stories and "Next >" or "Newer >")
  f.older:SetEnabled(index > 0 and index < #items); f.newer:SetEnabled(index > 1)
  f.pageCount:SetText(index > 0 and (f.chapterStoryID and "Chapter " or stories and "Story " or "Memory ") .. (#items - index + 1) .. " / " .. #items or "Your first page")
end
-- End reader navigation.

function J.Read(guid, memoryID, storyID, chapterStoryID)
  if not J.Reveal(guid) then return end
  J.CancelNotice()
  if not J.reader then
    local f = CreateFrame("Frame", "CMJ_OurStory", CMJ.refs.root, "BasicFrameTemplateWithInset")
    f:SetSize(420, 400); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); f:Hide()
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -42); scroll:SetPoint("BOTTOMRIGHT", -36, 55)
    local content = CreateFrame("Frame", nil, scroll); content:SetSize(350, 280); scroll:SetScrollChild(content)
    f.body = label(content, "GameFontHighlightSmall"); f.body:SetPoint("TOPLEFT"); f.body:SetWidth(350)
    f.content = content
    f.write = button(f, "Keep a memory", 130, function() J.Write(f.guid) end); f.write:SetPoint("BOTTOMLEFT", 18, 16)
    f.all = button(f, "All memories", 110, function()
      if not J.Reveal(f.guid) then return end
      f:Hide(); CMUI.TabSwap("Notes"); CMChronicleUI.SetMode("memories")
    end); f.all:SetPoint("LEFT", f.write, "RIGHT", 6, 0)
    local close = button(f, "Close", 84, function() f:Hide() end); close:SetPoint("BOTTOMRIGHT", -18, 16)
    table.insert(UISpecialFrames, "CMJ_OurStory"); J.reader = f
  end
  local e, f = entry(guid), J.reader
  f.guid = guid
  if f.TitleText then f.TitleText:SetText((chapterStoryID and "Story chapters · " or memoryID and "Memory kept · " or "Our story · ") .. text(shortName(e), 60)) end
  local memory, story = CMChronicle.Recollection(guid)
  local choice = selected(guid)
  if not memoryID and not storyID and choice then
    if choice.type == "memory" then memoryID = choice.id
    elseif choice.type == "story" then storyID = choice.id end
  end
  memory = memoryID and CMChronicle.Find(guid, "memories", memoryID) or memory
  if storyID then
    story = CMChronicle.Find(guid, "stories", storyID)
    memory = CMChronicle.StoryMemory(guid, story)
  elseif memoryID and memory then
    local link = memory.nextStoryID or memory.resolvedStoryID or memory.continuedStoryID
    story = link and CMChronicle.Find(guid, "stories", link) or nil
  end
  if chapterStoryID then story = CMChronicle.Find(guid, "stories", chapterStoryID) end
  f.chapterStoryID = chapterStoryID
  f.mode, f.storyID = storyID and "stories" or "memories", storyID
  f.memoryID, f.threadID = memory and memory.id, story and story.state == "open" and story.id
  local lines = {"|cffffd100Our paths first crossed|r", text(e.firstMetWhere ~= "" and e.firstMetWhere or "A place yet to be recorded", 200), text(e.firstMetAt, 60)}
  if memory then
    lines[#lines + 1] = "\n|cffffd100" .. (memory.pinned and "A memory you pinned" or "A memory you kept") .. "|r"
    if memory.note ~= "" and memory.note:sub(1, #memory.title) == memory.title then
      lines[#lines + 1] = text(memory.note, 2048)
    else
      lines[#lines + 1] = text(memory.title, 120)
      if memory.note ~= "" then lines[#lines + 1] = text(memory.note, 2048) end
    end
    lines[#lines + 1] = date("%b %d, %Y", memory.at) .. " · " .. text(memory.where, 200)
    if memory.keepsake then
      lines[#lines + 1] = "\n|cffffd100A keepsake|r"
      lines[#lines + 1] = text(memory.keepsake.label, 160)
    end
  elseif not story then lines[#lines + 1] = "\nYou have met. A few words can turn this encounter into a memory." end
  local finished = memory and memory.resolvedStoryID and CMChronicle.Find(guid, "stories", memory.resolvedStoryID)
  if finished then
    lines[#lines + 1] = "\n|cffffd100A thread brought full circle|r"
    lines[#lines + 1] = text(finished.title, 120)
  end
  if story and not (finished and finished.id == story.id) then
    lines[#lines + 1] = story.state == "resolved" and "\n|cffffd100A thread brought full circle|r" or "\n|cffffd100Next time…|r"; lines[#lines + 1] = text(story.title, 120)
    if story.note ~= "" then lines[#lines + 1] = text(story.note, 2048) end
  end
  f.body:SetText(table.concat(lines, "\n")); f.content:SetHeight(math.max(280, f.body:GetStringHeight() + 16))
  buildNavigation(f); updateNavigation(f); f.scroll:SetVerticalScroll(0)
  f.write:SetText(e.journalDraft and "Continue draft" or f.threadID and "Continue story" or "Keep a memory")
  f.all:SetText((storyID or memory) and (storyID and "Edit story" or "Edit memory") or "All memories")
  f:Show(); f:Raise()
end

function J.ReadChapters(guid, storyID, memoryID)
  if InCombatLockdown() or not CMChronicle.Find(guid, "stories", storyID) then return false end
  local chapters = CMChronicle.Chapters(guid, storyID)
  if #chapters == 0 then return J.ReadStory(guid, storyID) end
  local found
  for _, chapter in ipairs(chapters) do if chapter.id == memoryID then found = chapter.id; break end end
  J.Read(guid, found or chapters[1].id, nil, storyID)
  return true
end

function J.ReadStory(guid, storyID)
  if not CMChronicle.Find(guid, "stories", storyID) then return false end
  J.Read(guid, nil, storyID)
  return true
end

function J.EncounterStory(guid)
  local moment = J.Candidate(guid)
  if moment and moment.storyID and CMChronicle.Find(guid, "stories", moment.storyID) then J.ReadStory(guid, moment.storyID)
  else J.Read(guid, moment and moment.fromMemoryID) end
end

function J.EditReadPage()
  local f = J.reader
  if not f or not J.Reveal(f.guid) then return end
  local stories = f.mode == "stories"
  local item = CMChronicle.Find(f.guid, stories and "stories" or "memories", stories and f.storyID or f.memoryID)
  f:Hide(); CMUI.TabSwap("Notes"); CMChronicleUI.SetMode(stories and "stories" or "memories")
  if item then
    local copy = {}; for key, value in pairs(item) do copy[key] = value end; copy.type = stories and "story" or "memory"
    CMChronicleUI.Edit(stories and "story" or "memory", copy)
  end
end

function J.Browse(guid, direction, stories)
  local memories = stories and CMChronicle.StoryList(guid) or CMChronicle.List(guid)
  local chapterStoryID = J.reader and J.reader.guid == guid and J.reader.chapterStoryID
  if chapterStoryID then memories = CMChronicle.Chapters(guid, chapterStoryID) end
  local index = 1
  local currentID = J.reader and J.reader.guid == guid and (stories and J.reader.storyID or J.reader.memoryID)
  for i, memory in ipairs(memories) do if memory.id == currentID then index = i; break end end
  if direction == "first" then index = #memories
  elseif direction == "latest" then index = 1
  elseif direction == "older" then index = math.min(#memories, index + 1)
  elseif direction == "newer" then index = math.max(1, index - 1)
  else return false end
  if chapterStoryID then J.ReadChapters(guid, chapterStoryID, memories[index] and memories[index].id)
  elseif stories then J.ReadStory(guid, memories[index] and memories[index].id)
  else J.Read(guid, memories[index] and memories[index].id) end
  return true
end

function J.Continue(guid)
  if InCombatLockdown() then return false, "Continue your story after combat." end
  local choice = selected(guid)
  local _, story = CMChronicle.Highlights(guid)
  if choice and choice.type == "story" then story = CMChronicle.Find(guid, "stories", choice.id) end
  if not story or story.state ~= "open" then return false, "Choose an unfinished story to continue." end
  J.Write(guid, story.id)
  return true
end

local function showNotice(guid, kind, previousAt)
  local e = entry(guid)
  if not e then return end
  if not J.notice then
    local f = CreateFrame("Frame", "CMJ_EncounterNotice", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(360, 195); f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -40, 160); f:SetFrameStrata("DIALOG"); f:Hide()
    f.person = label(f, "GameFontNormalLarge"); f.person:SetPoint("TOPLEFT", 18, -36); f.person:SetWidth(320); f.person:SetMaxLines(1)
    f.context = label(f, "GameFontDisableSmall"); f.context:SetPoint("TOPLEFT", 18, -60); f.context:SetWidth(320); f.context:SetMaxLines(1)
    f.words = label(f, "GameFontHighlightSmall"); f.words:SetPoint("TOPLEFT", 18, -82); f.words:SetWidth(320); f.words:SetMaxLines(4)
    f.keep = button(f, "Keep a memory", 135, function() J.Write(f.guid) end); f.keep:SetPoint("BOTTOMLEFT", 16, 14)
    f.story = button(f, "Our story", 100, function() J.Read(f.guid) end); f.story:SetPoint("LEFT", f.keep, "RIGHT", 6, 0)
    -- Close button and timeout dismiss only this prompt; the moment stays in the journal.
    if f.CloseButton then f.CloseButton:SetScript("OnClick", J.CancelNotice) end
    table.insert(UISpecialFrames, "CMJ_EncounterNotice"); J.notice = f
  end
  local f = J.notice
  f.guid, f.kind = guid, kind
  f.keep:SetScript("OnClick", function()
    local moment = J.Candidate(f.guid)
    J.Write(f.guid, moment and (moment.storyID or false))
  end)
  f.story:SetScript("OnClick", function()
    if f.kind == "meeting" then J.CancelNotice() else J.EncounterStory(f.guid) end
  end)
  f.story:SetText(kind == "meeting" and "Not now" or "Our story")
  if f.TitleText then f.TitleText:SetText(kind == "meeting" and "Our paths cross" or "A familiar face") end
  f.person:SetText(text(shortName(e), 80))
  local memory, story = CMChronicle.Recollection(guid)
  if kind == "meeting" then
    f.context:SetText(text(e.firstMetWhere, 180))
    f.words:SetText("One detail is enough to remember them.\nA kindness, a curious habit, a reason to meet again.")
  else
    local moment = J.Candidate(guid)
    if moment then
      memory = CMChronicle.Find(guid, "memories", moment.fromMemoryID)
      story = CMChronicle.Find(guid, "stories", moment.storyID)
    end
    if story and story.state ~= "open" then story = nil end
    f.context:SetText("Your paths cross again after " .. J.Elapsed(time() - previousAt) .. ".")
    local lines = {}
    if e.journalDraft then
      lines[#lines + 1] = "Your unfinished page is waiting."
      local words = e.journalDraft.note
      if words and words:match("%S") then lines[#lines + 1] = "You began: " .. snippet(words, 100) end
    else
      if story then lines[#lines + 1] = "You meant to: " .. snippet(story.title, 64) end
      if memory then lines[#lines + 1] = "Last time: " .. snippet(memory.note ~= "" and memory.note or memory.title, 84) end
    end
    f.words:SetText(#lines > 0 and table.concat(lines, "\n") or "A familiar face. What happens in this next chapter?")
  end
  f.keep:SetText(e.journalDraft and "Continue draft" or kind == "meeting" and "Remember them" or story and "Pick up story" or "Keep a memory")
  e.lastJourneyNoticeAt, lastNotice = time(), GetTime()
  f:Show()
  local shownTicket = ticket
  C_Timer.After(J.NOTICE_LIFETIME, function() if ticket == shownTicket then f:Hide() end end)
end

function J.OnTarget(guid, previousAt, firstMeet)
  J.CancelNotice()
  if not guid or guid == CMCompat.UnitGUID("player") then return end
  local e = entry(guid)
  if not e or not e.isPlayer then return end
  local kind
  if firstMeet then kind = "meeting"
  elseif previousAt and time() - previousAt >= J.REUNION_AFTER then kind = "reunion"
  elseif not e.lastJourneyNoticeAt and #(e.memories or {}) == 0 then
    local candidate = J.Candidate(guid)
    if candidate and candidate.kind == "meeting" then kind = "meeting" end
  end
  if not kind then return end
  local pending = kind == "meeting" and J.Candidate(guid)
  e.journey = { kind = kind, at = pending and pending.at or time(), previousAt = previousAt }
  if kind == "reunion" then
    local candidateID = CMChronicle.Offer(guid, kind, e.lastSeenWhere)
    local candidate = candidateID and CMChronicle.Find(guid, "memoryCandidates", candidateID)
    if candidate then candidate.previousSeenAt = previousAt end
  end
  if CharacterMemoryDB.settings.showOnTarget == false then return end
  if e.lastJourneyNoticeAt and time() - e.lastJourneyNoticeAt < J.REUNION_AFTER then return end
  local expected = ticket
  C_Timer.After(J.DWELL, function()
    if ticket ~= expected or InCombatLockdown() or CMCompat.UnitGUID("target") ~= guid then return end
    if CharacterMemoryDB.settings.showOnTarget == false then return end
    if GetTime() - lastNotice < J.NOTICE_COOLDOWN then return end
    -- A visible journal or character sheet already has the player's attention.
    if (CMJ.refs.root and CMJ.refs.root:IsShown()) or (RPBioFrame and RPBioFrame:IsShown()) then return end
    showNotice(guid, kind, previousAt)
  end)
end

local events = CreateFrame("Frame")
for _, event in ipairs({"PLAYER_REGEN_DISABLED", "PLAYER_LOGOUT"}) do CMCompat.RegisterEvent(events, event) end
events:SetScript("OnEvent", J.CancelNotice)

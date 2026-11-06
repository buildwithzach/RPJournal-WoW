if not CMCompat or not CMCompat.supported then return end
-- Local, player-authored memories and unfinished stories. No chat transcripts.
CMChronicle = {}
local M = CMChronicle
M.LIMITS = { memories = 100, candidates = 12, stories = 32, text = 2048 }
local kinds = { meeting = "Our paths first crossed", reunion = "A familiar face",
  conversation = "A conversation", shared_rest = "A quiet moment together",
  adventure = "An adventure together", manual = "A memory", legacy = "Earlier notes" }

local function text(value, limit) return CMCompat.Text(value, limit) end
local function entry(guid)
  local db = CharacterMemoryDB
  return db and db.entries and db.entries[guid]
end
local function changed()
  if CMJ and CMJ.NotifyDataChanged then CMJ.NotifyDataChanged() end
end
local function id(prefix)
  CharacterMemoryDB.nextJournalID = (tonumber(CharacterMemoryDB.nextJournalID) or 0) + 1
  return prefix .. CharacterMemoryDB.nextJournalID
end
local function activity(item)
  return tonumber((item.latestMemoryID or item.id or ""):match("%d+$")) or 0
end

function M.Prepare(e, guid)
  e.guid = guid
  e.memories = type(e.memories) == "table" and e.memories or {}
  e.memoryCandidates = type(e.memoryCandidates) == "table" and e.memoryCandidates or {}
  e.stories = type(e.stories) == "table" and e.stories or {}
  e.memoryCooldowns = type(e.memoryCooldowns) == "table" and e.memoryCooldowns or {}
  if not e.chronicleMigrated then
    if type(e.notes) == "string" and e.notes ~= "" and #e.memories < M.LIMITS.memories then
      e.memories[#e.memories + 1] = { id = id("m"), kind = "legacy", title = kinds.legacy,
        note = e.notes, at = time(), where = e.lastSeenWhere or "", pinned = true }
    end
    e.chronicleMigrated = true
  end
end

function M.Initialize(db)
  db.nextJournalID = tonumber(db.nextJournalID) or 0
  for guid, e in pairs(db.entries) do
    if type(e) == "table" then M.Prepare(e, guid) end
  end
end

function M.Offer(guid, kind, where)
  local e = entry(guid)
  if not e or not kinds[kind] or kind == "legacy" then return false end
  M.Prepare(e, guid)
  local stamp = time()
  local previous = e.memoryCooldowns[kind]
  if previous and stamp >= previous and stamp - previous < 1200 then return false end
  if #e.memoryCandidates >= M.LIMITS.candidates then return false end
  e.memoryCooldowns[kind] = stamp
  local candidate = { id = id("c"), kind = kind, title = kinds[kind], at = stamp, where = text(where, 200) }
  if kind == "reunion" then
    local memory, story = M.Recollection(guid)
    candidate.fromMemoryID, candidate.storyID = memory and memory.id, story and story.id
  end
  e.memoryCandidates[#e.memoryCandidates + 1] = candidate
  changed()
  return candidate.id
end

-- Use the player's own first sentence when they leave the optional title blank.
function M.MemoryTitle(title, note)
  title = text(title, 120):match("^%s*(.-)%s*$")
  if title ~= "" then return title end
  local words = text(note):match("^%s*(.-)%s*$"):gsub("%s+", " ")
  if words == "" then return nil, "Keep one detail about them, or give this memory a title. Your draft stays here." end
  local first = words:match("^(.-[.!?])%s") or words
  return text(first, 96)
end

-- A draft keeps only encounter context, never a chat transcript or another profile.
function M.Moment(item)
  if type(item) ~= "table" or not kinds[item.kind] or item.kind == "legacy" then return nil end
  return { id = item.id, kind = item.kind, title = text(item.title, 120),
    at = tonumber(item.at) or time(), where = text(item.where, 200),
    fromMemoryID = item.fromMemoryID, storyID = item.storyID, previousSeenAt = item.previousSeenAt }
end

function M.Remember(guid, candidateID, note, title, where, moment)
  local e = entry(guid)
  if not e then return nil, "Choose someone in your journal first." end
  M.Prepare(e, guid)
  if #e.memories >= M.LIMITS.memories then return nil, "This journal has 100 memories. Remove one before adding another." end
  local candidate, index
  if candidateID then
    for i, item in ipairs(e.memoryCandidates) do if item.id == candidateID then candidate, index = item, i; break end end
    if not candidate then return nil, "That moment is no longer waiting to be remembered." end
  elseif text(note):match("^%s*$") and text(title, 120):match("^%s*$") then
    return nil, "Give this memory a title or a few words." 
  end
  local context = candidate or M.Moment(moment)
  if context and context.id then
    for _, saved in ipairs(e.memories) do
      if saved.fromMomentID == context.id then return nil, "This moment already has a saved memory. Your draft is still here." end
    end
  end
  local memory = { id = id("m"), kind = candidate and candidate.kind or "manual",
    title = text(title, 120), note = text(note), at = candidate and candidate.at or time(),
    where = candidate and candidate.where or text(where or e.lastSeenWhere, 200), pinned = false }
  if context then
    memory.kind, memory.at, memory.where = context.kind, context.at, context.where
    memory.fromMomentID = context.id
    memory.fromMemoryID, memory.continuedStoryID = context.fromMemoryID, context.storyID
    memory.previousSeenAt = context.previousSeenAt
  end
  if memory.title == "" then memory.title = context and context.title ~= "" and context.title or kinds[memory.kind] end
  e.memories[#e.memories + 1] = memory
  if index then table.remove(e.memoryCandidates, index) end
  changed()
  return memory.id
end

function M.Dismiss(guid, candidateID)
  local e = entry(guid)
  if not e then return false end
  for i, item in ipairs(e.memoryCandidates or {}) do
    if item.id == candidateID then table.remove(e.memoryCandidates, i); changed(); return true end
  end
  return false
end

function M.Pin(guid, memoryID)
  local e = entry(guid)
  for _, memory in ipairs(e and e.memories or {}) do
    if memory.id == memoryID then memory.pinned = not memory.pinned; changed(); return true end
  end
  return false
end

function M.Remove(guid, memoryID)
  local e = entry(guid)
  for i, memory in ipairs(e and e.memories or {}) do
    if memory.id == memoryID then table.remove(e.memories, i); changed(); return true end
  end
  return false
end

function M.Update(guid, memoryID, title, note)
  local e = entry(guid)
  title = M.MemoryTitle(title, note)
  if not title then return false end
  for _, memory in ipairs(e and e.memories or {}) do
    if memory.id == memoryID then
      memory.title, memory.note = title, text(note)
      changed(); return true
    end
  end
  return false
end

function M.List(guid)
  local e = entry(guid)
  local result = {}
  for _, memory in ipairs(e and e.memories or {}) do result[#result + 1] = memory end
  table.sort(result, function(a, b)
    if a.at == b.at then return (tonumber(a.id:match("%d+$")) or 0) > (tonumber(b.id:match("%d+$")) or 0) end
    return a.at > b.at
  end)
  return result
end

function M.StoryList(guid)
  local e, result = entry(guid), {}
  for _, story in ipairs(e and e.stories or {}) do result[#result + 1] = story end
  table.sort(result, function(a, b)
    if a.state ~= b.state then return a.state == "open" end
    if a.updatedAt ~= b.updatedAt then return a.updatedAt > b.updatedAt end
    return activity(a) > activity(b)
  end)
  return result
end

function M.AddStory(guid, title, note, where)
  local e = entry(guid)
  if not e then return nil, "Choose someone in your journal first." end
  M.Prepare(e, guid)
  title = text(title, 120)
  if title:match("^%s*$") then return nil, "Give your story a title." end
  if #e.stories >= M.LIMITS.stories then return nil, "This journal has 32 story threads. Remove one before adding another." end
  local story = { id = id("s"), title = title, note = text(note), state = "open",
    at = time(), updatedAt = time(), where = text(where or e.lastSeenWhere, 200) }
  e.stories[#e.stories + 1] = story
  changed()
  return story.id
end

function M.UpdateStory(guid, storyID, title, note, state)
  local e = entry(guid)
  if state ~= "open" and state ~= "resolved" then return false end
  title = text(title, 120)
  if title:match("^%s*$") then return false end
  for _, story in ipairs(e and e.stories or {}) do
    if story.id == storyID then
      story.title, story.note, story.state, story.updatedAt = title, text(note), state, time()
      changed(); return true
    end
  end
  return false
end

function M.RemoveStory(guid, storyID)
  local e = entry(guid)
  for i, story in ipairs(e and e.stories or {}) do
    if story.id == storyID then table.remove(e.stories, i); changed(); return true end
  end
  return false
end

-- A pinned recollection gets preference; unfinished threads use their latest update.
function M.Highlights(guid)
  local e = entry(guid)
  if not e then return nil, nil end
  local openStory
  for _, story in ipairs(e.stories or {}) do
    if story.state == "open" and (not openStory or story.updatedAt > openStory.updatedAt
      or (story.updatedAt == openStory.updatedAt and activity(story) > activity(openStory))) then openStory = story end
  end
  local memories = M.List(guid)
  local highlight = memories[1]
  for _, memory in ipairs(memories) do if memory.pinned then highlight = memory; break end end
  return highlight, openStory
end

function M.Recollection(guid)
  local memory, story = M.Highlights(guid)
  if story then
    local chapter = M.StoryMemory(guid, story)
    if chapter then memory = chapter end
  end
  return memory, story
end

function M.StoryMemory(guid, story)
  if not story then return nil end
  return M.Find(guid, "memories", story.latestMemoryID) or M.Chapters(guid, story.id)[1]
end

-- A page can close one promise and begin another; it belongs to both trails.
-- Derive the trail from saved links, so older journals need no migration.
function M.Chapters(guid, storyID)
  local story, result = M.Find(guid, "stories", storyID), {}
  if not story then return result end
  for _, memory in ipairs(M.List(guid)) do
    if memory.id == story.fromMemoryID or memory.id == story.latestMemoryID
      or memory.nextStoryID == storyID or memory.continuedStoryID == storyID or memory.resolvedStoryID == storyID then
      result[#result + 1] = memory
    end
  end
  return result
end

function M.Places(guid)
  local result, seen = {}, {}
  for _, memory in ipairs(M.List(guid)) do
    if memory.where and memory.where ~= "" and not seen[memory.where] then
      seen[memory.where] = true; result[#result + 1] = memory.where
    end
  end
  table.sort(result)
  return result
end

function M.Search(guid, query)
  local result = {}
  query = text(query, 120):match("^%s*(.-)%s*$"):lower()
  if query == "" then return result end
  for _, kind in ipairs({"memory", "story"}) do
    local list = kind == "memory" and M.List(guid) or M.StoryList(guid)
    for _, item in ipairs(list) do
      local words = table.concat({item.title or "", item.note or "", item.where or "", item.keepsake and item.keepsake.label or ""}, "\n")
      if words:lower():find(query, 1, true) then result[#result + 1] = {id = item.id, title = item.title, type = kind} end
    end
  end
  return result
end

-- These are private references, never inventory objects. Accept only a short
-- authored description or one structurally valid native item link.
function M.SetKeepsake(guid, memoryID, value)
  local memory = M.Find(guid, "memories", memoryID)
  if not memory then return false, "That memory is no longer in your journal." end
  if type(value) ~= "string" or #value > 512 or value:find("[%c]") then
    return false, "Use one line: a short description or a single item link."
  end
  value = value:match("^%s*(.-)%s*$")
  local keepsake
  if value ~= "" then
    if value:find("|", 1, true) then
      local link = value
      if value:sub(1, 2) == "|c" then link = value:match("^|c%x%x%x%x%x%x%x%x(.+)|r$") end
      if not link then return false, "Use a complete item link, or a short description." end
      local payload, label = link:match("^|H(item:%d+[:%d%-]*)|h(%[[^|]+%])|h$")
      local itemID = payload and tonumber(payload:match("^item:(%d+)"))
      if not itemID or itemID <= 0 or itemID > 2147483647 or #payload > 240 or #label > 160 then
        return false, "Use a single item link, or describe your keepsake in your own words."
      end
      for field in (payload:sub(6) .. ":"):gmatch("(.-):") do
        if field ~= "" and not field:match("^%-?%d+$") then return false, "That item link is incomplete." end
      end
      keepsake = {label = label, itemID = itemID, link = value}
    elseif #value <= 160 then keepsake = {label = value}
    else return false, "Keep the description within 160 bytes. Your words are still here." end
  end
  memory.keepsake = keepsake
  changed(); return true
end

function M.Excerpt(guid, memoryID)
  local e, memory = entry(guid), M.Find(guid, "memories", memoryID)
  if not memory then return nil end
  local lines = {"RP Journal · " .. text(e.name, 100)}
  if memory.note ~= "" and memory.note:sub(1, #memory.title) == memory.title then lines[#lines + 1] = text(memory.note, 2048)
  else
    lines[#lines + 1] = text(memory.title, 120)
    if memory.note ~= "" then lines[#lines + 1] = text(memory.note, 2048) end
  end
  lines[#lines + 1] = date("%b %d, %Y", memory.at) .. " · " .. text(memory.where, 200)
  if memory.keepsake then lines[#lines + 1] = "Keepsake: " .. text(memory.keepsake.label, 160) end
  return table.concat(lines, "\n\n")
end

function M.Find(guid, collection, itemID)
  local e = entry(guid)
  if collection ~= "memories" and collection ~= "stories" and collection ~= "memoryCandidates" then return nil end
  for _, item in ipairs(e and e[collection] or {}) do if item.id == itemID then return item end end
end

-- Preflight both capacities before saving so a full story list never loses the words.
function M.SaveMoment(guid, candidateID, note, title, nextThread, resolveID, continueID, moment)
  local e = entry(guid)
  if not e then return nil, "Choose someone in your journal first." end
  M.Prepare(e, guid)
  local named, titleError = M.MemoryTitle(title, note)
  if not named then return nil, titleError end
  nextThread = text(nextThread, 120)
  local hasThread = not nextThread:match("^%s*$")
  if hasThread and #e.stories >= M.LIMITS.stories then return nil, "Your story pages are full. Your draft is safe; remove a thread first." end
  local resolving = resolveID and M.Find(guid, "stories", resolveID)
  if resolveID and (not resolving or resolving.state ~= "open") then return nil, "That thread has changed. Reopen this page before resolving it." end
  if resolveID and continueID and resolveID ~= continueID then return nil, "This page refers to a different thread. Your draft is safe." end
  local continuing = continueID and M.Find(guid, "stories", continueID)
  local previousChapter = M.StoryMemory(guid, continuing)
  local memoryID, err = M.Remember(guid, candidateID, note, named, nil, moment)
  if not memoryID then return nil, err end
  local memory = M.Find(guid, "memories", memoryID)
  if continueID then
    local capturedThread = memory.continuedStoryID
    memory.continuedStoryID = continueID
    if continuing then
      if capturedThread ~= continueID or not memory.fromMemoryID then
        memory.fromMemoryID = previousChapter and previousChapter.id
      end
      continuing.latestMemoryID, continuing.updatedAt = memoryID, time()
    end
  end
  if resolving then
    memory.resolvedStoryID = resolveID
    M.UpdateStory(guid, resolveID, resolving.title, resolving.note, "resolved")
  end
  if hasThread then
    local storyID = M.AddStory(guid, nextThread, "")
    memory.nextStoryID = storyID
    local nextStory = M.Find(guid, "stories", storyID)
    nextStory.fromMemoryID, nextStory.latestMemoryID = memoryID, memoryID
  end
  changed()
  return memoryID
end

function M.Recall(guid)
  local memory, story = M.Highlights(guid)
  return story and "Unfinished story: " .. story.title or memory and memory.title or nil
end

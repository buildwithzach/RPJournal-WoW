-- Isolated prototype. Not loaded by CharacterMemory.toc.
-- The adapter supplies observed facts; the player chooses what becomes a memory.
local Chronicle = {}
local titles = {
  meeting = "Our paths first crossed",
  conversation = "A conversation worth remembering",
  shared_rest = "A quiet moment together",
  reunion = "A familiar face",
}

function Chronicle.Open(saved)
  saved = saved or {}
  saved.version = saved.version or 1
  assert(saved.version == 1, "Unsupported experimental chronicle version")
  saved.candidates = saved.candidates or {}
  saved.memories = saved.memories or {}
  return saved
end

function Chronicle.Offer(saved, event)
  assert(type(event.id) == "string" and event.id ~= "", "A stable event ID is required")
  assert(type(event.guid) == "string" and event.guid:match("^Player%-"), "A player GUID is required")
  assert(titles[event.kind], "Unsupported memory kind")
  assert(type(event.at) == "number" and event.at >= 0, "An observed timestamp is required")
  if saved.candidates[event.id] or saved.memories[event.id] then return false end
  -- Copy only the declared facts. Never copy chat bodies or another player's bio.
  saved.candidates[event.id] = {
    id = event.id, guid = event.guid, kind = event.kind, at = event.at,
    name = event.name, where = event.where, title = titles[event.kind], status = "offered",
  }
  return true
end

function Chronicle.Remember(saved, id, authoredNote)
  local candidate = saved.candidates[id]
  if not candidate or candidate.status ~= "offered" then return false end
  assert(authoredNote == nil or type(authoredNote) == "string", "A note must be text")
  local memory = {}
  for key, value in pairs(candidate) do memory[key] = value end
  memory.status = nil
  memory.note = authoredNote or ""
  memory.pinned = false
  saved.memories[id] = memory
  candidate.status = "remembered"
  return true
end

function Chronicle.Dismiss(saved, id)
  local candidate = saved.candidates[id]
  if not candidate or candidate.status ~= "offered" then return false end
  candidate.status = "dismissed"
  return true
end

function Chronicle.Pin(saved, id)
  local memory = saved.memories[id]
  if not memory then return false end
  memory.pinned = not memory.pinned
  return true
end

function Chronicle.Timeline(saved, guid)
  local result = {}
  for _, memory in pairs(saved.memories) do
    if memory.guid == guid then
      local copy = {}
      for key, value in pairs(memory) do copy[key] = value end
      result[#result + 1] = copy
    end
  end
  table.sort(result, function(a, b)
    if a.at == b.at then return a.id < b.id end
    return a.at < b.at
  end)
  return result
end

function Chronicle.Recall(saved, guid)
  local timeline = Chronicle.Timeline(saved, guid)
  local last = timeline[#timeline]
  if not last then return nil end
  return { id = last.id, name = last.name, where = last.where, at = last.at, note = last.note }
end

return Chronicle

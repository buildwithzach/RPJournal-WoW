if not CMCompat or not CMCompat.supported then return end
-- Bounded, versioned, solicited public-profile exchange. Never sends notes or story data.
CMProtocol = { PREFIX = "RPJ2", pending = {}, queue = {}, incoming = {} }
local P = CMProtocol
local replies, sent, tokenID = {}, {}, 0
local MAX_PARTS, CHUNK, MAX_PENDING = 32, 140, 16
local pumping, generation = false, 0
local function clock() return GetTime() end
local function count(map) local n = 0; for _ in pairs(map) do n = n + 1 end; return n end
local function cleanup()
  local now = clock()
  for key, value in pairs(P.pending) do if value.expires < now then P.pending[key] = nil; P.incoming[key] = nil end end
  for key, value in pairs(replies) do if value < now - 30 then replies[key] = nil end end
  for key, value in pairs(sent) do if value < now - 30 then sent[key] = nil end end
end

local function pump(epoch)
  if epoch ~= generation then return end
  if #P.queue == 0 then pumping = false; return end
  local packet = table.remove(P.queue, 1)
  local ok, result = pcall(C_ChatInfo.SendAddonMessage, P.PREFIX, packet.message, "WHISPER", packet.target)
  local success = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success
  local failed = not ok or result == false or (type(result) == "number" and success and result ~= success)
  if failed and (packet.attempts or 0) < 2 then
    packet.attempts = (packet.attempts or 0) + 1
    table.insert(P.queue, 1, packet)
  end
  if #P.queue > 0 then C_Timer.After(failed and 1 or 0.15, function() pump(epoch) end) else pumping = false end
end

local function enqueue(target, messages)
  if not C_ChatInfo or type(C_ChatInfo.SendAddonMessage) ~= "function" or not C_Timer or not C_Timer.After then return false end
  if #P.queue + #messages > 128 then return false end
  for _, message in ipairs(messages) do if #message > 250 then return false end end
  for _, message in ipairs(messages) do P.queue[#P.queue + 1] = { target = target, message = message } end
  if not pumping then pumping = true; pump(generation) end
  return true
end

function P.Encode(fields)
  local parts = {}
  for i = 1, 17 do
    local value = fields[i] or ""
    parts[#parts + 1] = #value .. ":" .. value
  end
  local payload = table.concat(parts)
  if #payload > MAX_PARTS * CHUNK / 2 then return nil end
  return (payload:gsub(".", function(char) return string.format("%02x", char:byte()) end))
end

function P.Decode(hex)
  if type(hex) ~= "string" or #hex > MAX_PARTS * CHUNK or #hex % 2 ~= 0 or hex:find("[^%x]") then return nil end
  local payload = hex:gsub("..", function(pair) return string.char(tonumber(pair, 16)) end)
  local fields, offset = {}, 1
  for i = 1, 17 do
    local startAt, endAt, digits = payload:find("^(%d+):", offset)
    if not startAt or #digits > 4 then return nil end
    local length = tonumber(digits)
    if not length or length > 500 or endAt + length > #payload then return nil end
    fields[i] = payload:sub(endAt + 1, endAt + length)
    offset = endAt + length + 1
  end
  return offset == #payload + 1 and fields or nil
end

function P.Request(name, guid)
  cleanup()
  local key = CMCompat.NameKey(name)
  local selfGUID = CMCompat.UnitGUID("player")
  if not key or guid == selfGUID then return false end
  local e = guid and CharacterMemoryDB and CharacterMemoryDB.entries and CharacterMemoryDB.entries[guid]
  if not e or CMCompat.NameKey(e.name) ~= key or not guid:match("^Player%-") then return false end
  if sent[key] or count(sent) >= 64 or count(P.pending) >= MAX_PENDING then return false end
  tokenID = tokenID + 1
  local token = string.format("%x-%x", math.floor(clock() * 1000), tokenID)
  P.pending[key] = { guid = guid, token = token, expires = clock() + 30 }
  sent[key] = clock()
  if enqueue(name, { "REQ|" .. token }) then return true end
  P.pending[key], sent[key] = nil, nil
  return false
end

function P.Receive(prefix, message, channel, sender)
  if prefix ~= P.PREFIX or channel ~= "WHISPER" or CMCompat.IsSecret(message) or type(message) ~= "string" or #message > 250 then return false end
  local key = CMCompat.NameKey(sender)
  if not key then return false end
  cleanup()
  local token = message:match("^REQ|([%x%-]+)$")
  if token and #token <= 32 then
    if not CharacterMemoryDB or not CharacterMemoryDB.settings or CharacterMemoryDB.settings.bioSharing ~= true or replies[key] or count(replies) >= 64 then return false end
    local guid = CMCompat.UnitGUID("player")
    if not guid or #guid > 64 then return false end
    local hex = P.Encode(CMProfile.PublicFields())
    if not hex then return false end
    local total, packets = math.ceil(#hex / CHUNK), {}
    for i = 1, total do
      packets[i] = table.concat({ "BIO", token, i, total, guid, hex:sub((i - 1) * CHUNK + 1, i * CHUNK) }, "|")
    end
    if enqueue(sender, packets) then replies[key] = clock(); return true end
    return false
  end
  local receipt, index, total, guid, data = message:match("^BIO|([%x%-]+)|(%d+)|(%d+)|([^|]+)|([%x]*)$")
  local pending = P.pending[key]
  index, total = tonumber(index), tonumber(total)
  if not pending or receipt ~= pending.token or guid ~= pending.guid or not index or not total
    or total < 1 or total > MAX_PARTS or index < 1 or index > total or #data > CHUNK or #data % 2 ~= 0 then return false end
  local assembly = P.incoming[key]
  if not assembly then assembly = { total = total, parts = {}, count = 0 }; P.incoming[key] = assembly end
  if assembly.total ~= total then return false end
  if assembly.parts[index] and assembly.parts[index] ~= data then return false end
  if not assembly.parts[index] then assembly.parts[index] = data; assembly.count = assembly.count + 1 end
  if assembly.count ~= total then return true end
  local fields = P.Decode(table.concat(assembly.parts))
  P.pending[key], P.incoming[key] = nil, nil
  return fields and CMProfile.Import(guid, fields) or false
end

function P.Stop()
  generation = generation + 1
  pumping = false
  wipe(P.queue); wipe(P.pending); wipe(P.incoming)
end

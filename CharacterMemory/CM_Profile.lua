if not CMCompat or not CMCompat.supported then return end
-- One authored character sheet, with an explicit public-field projection.
CMProfile = {}
local P = CMProfile
local sections = { "identity", "appearance", "lore", "personality", "skills", "relationships", "rpPrefs", "notes" }

function P.Ensure()
  RPJournalDB = type(RPJournalDB) == "table" and RPJournalDB or {}
  RPJournalDB.bio = type(RPJournalDB.bio) == "table" and RPJournalDB.bio or {}
  local b = RPJournalDB.bio
  for _, section in ipairs(sections) do b[section] = type(b[section]) == "table" and b[section] or {} end
  if not b.migrated then
    local guid = CMCompat.UnitGUID("player")
    local e = guid and CharacterMemoryDB and CharacterMemoryDB.entries and CharacterMemoryDB.entries[guid]
    local p = e and e.profile or {}
    local a = p.appearance or {}
    b.identity.title = b.identity.title or p.title or ""
    b.identity.pronouns = b.identity.pronouns or p.pronouns or ""
    b.identity.nicknames = b.identity.nicknames or (p.alias and p.alias ~= "" and { p.alias } or {})
    b.lore.shortBio = b.lore.shortBio or p.publicBio or p.background or ""
    b.lore.alignment = b.lore.alignment or p.alignment or ""
    for _, key in ipairs({ "height", "eyes", "hair" }) do b.appearance[key] = b.appearance[key] or a[key] or "" end
    b.migrated = true
  end
  return b
end

local function list(value)
  if type(value) == "table" then return table.concat(value, ", ") end
  return type(value) == "string" and value or ""
end

function P.PublicFields()
  local b = P.Ensure()
  local values = { b.lore.shortBio, b.identity.title, b.identity.pronouns, list(b.personality.traits),
    list(b.identity.nicknames), b.lore.alignment, list(b.skills.languages), list(b.skills.hobbies),
    "", b.appearance.height, b.appearance.build, b.appearance.eyes, b.appearance.hair,
    b.appearance.features, b.appearance.attire, b.skills.occupation, b.personality.hooks }
  local fields = {}
  for i = 1, 17 do fields[i] = CMCompat.Text(values[i], i == 1 and 500 or (i == 17 and 256 or 64)) end
  return fields
end

function P.SyncLegacy()
  local guid = CMCompat.UnitGUID("player")
  local e = guid and CharacterMemory_GetOrCreateEntry and CharacterMemory_GetOrCreateEntry(guid)
  if not e then return end
  local f = P.PublicFields()
  e.isPlayer = true
  local name, realm = CMCompat.UnitName("player")
  e.name = name and (realm and name .. "-" .. realm or name) or e.name
  e.profile = e.profile or {}
  local p = e.profile
  p.publicBio, p.background, p.title, p.pronouns, p.tags, p.alias, p.alignment = f[1], f[1], f[2], f[3], f[4], f[5], f[6]
  p.languages, p.proficiencies = f[7], f[8]
  p.appearance = p.appearance or {}
  p.appearance.age, p.appearance.height, p.appearance.weight = f[9], f[10], f[11]
  p.appearance.eyes, p.appearance.hair = f[12], f[13]
end

function P.FromLegacy(p)
  local b = P.Ensure()
  b.identity.title, b.identity.pronouns = p.title or "", p.pronouns or ""
  b.identity.nicknames = p.alias and p.alias ~= "" and { p.alias } or {}
  b.lore.shortBio, b.lore.alignment = p.publicBio or p.background or "", p.alignment or ""
  b.personality.traits = p.tags and p.tags ~= "" and { p.tags } or {}
  b.skills.languages, b.skills.hobbies = p.languages or "", p.proficiencies or ""
  local a = p.appearance or {}
  b.appearance.height, b.appearance.eyes, b.appearance.hair = a.height or "", a.eyes or "", a.hair or ""
end

function P.Import(guid, fields)
  local e = CharacterMemoryDB and CharacterMemoryDB.entries and CharacterMemoryDB.entries[guid]
  if not e or #fields ~= 17 then return false end
  e.publicProfile = {}
  for i = 1, 17 do e.publicProfile[i] = CMCompat.Text(fields[i], i == 1 and 500 or (i == 17 and 256 or 64)) end
  e.profile = e.profile or {}
  e.profile.publicBio = e.publicProfile[1]
  e.bioUpdatedAt = time()
  if CMJ and CMJ.NotifyDataChanged then CMJ.NotifyDataChanged() end
  return true
end

if not CMCompat or not CMCompat.supported then return end
BINDING_HEADER_RPJOURNAL = "RP Journal"
BINDING_NAME_RPJOURNAL_TOGGLE = "Open your journal"
BINDING_NAME_RPJOURNAL_REMEMBER = "Remember the current target"

function CharacterMemory_RememberTarget()
  if InCombatLockdown() then return end
  local guid = CMCompat.UnitGUID("target")
  if guid == CMCompat.UnitGUID("player") then CharacterMemory_OpenCharacterSheet(); return end
  local e = guid and CharacterMemory_GetOrCreateEntry(guid)
  if not e then return end
  if not e.name or e.name == "" then
    local name, realm = CMCompat.UnitName("target")
    if name then e.name = realm and name .. "-" .. realm or name end
  end
  if CMJourney then CMJourney.Write(guid) end
end

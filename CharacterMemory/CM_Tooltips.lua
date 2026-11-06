if not CMCompat or not CMCompat.supported then return end
-- Local recollections on native unit tooltips; never broadcasts journal data.
local function annotate(tooltip)
  if InCombatLockdown() or not tooltip.GetUnit then return end
  local _, unit = tooltip:GetUnit()
  local guid = unit and CMCompat.UnitGUID(unit)
  local e = guid and CharacterMemoryDB and CharacterMemoryDB.entries and CharacterMemoryDB.entries[guid]
  if not e then return end
  local memory, story = CMChronicle.Highlights(guid)
  if not memory and not story then return end
  tooltip:AddLine("RP Journal", 1, 0.82, 0)
  if story then tooltip:AddLine("Next time: " .. CMCompat.Display(story.title, 120), 1, 0.82, 0, true) end
  if memory then tooltip:AddLine(CMCompat.Display(memory.note ~= "" and memory.note or memory.title, 140), 1, 1, 1, true) end
end
local events = CreateFrame("Frame")
CMCompat.RegisterEvent(events, "PLAYER_LOGIN")
events:SetScript("OnEvent", function()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, annotate)
  elseif GameTooltip and GameTooltip.HookScript then
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", annotate)
  end
end)

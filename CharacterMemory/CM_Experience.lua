if not CMCompat or not CMCompat.supported then return end
-- Clear, quiet achievement feedback using the journal's existing native rows.
CMExperience = { page = 1 }
local E, PAGE_SIZE = CMExperience, 5
local function selected()
  local id = CMJ.Model.selected
  local e = id and CharacterMemoryDB and CharacterMemoryDB.entries[id]
  return id, e
end
local function build()
  if E.title then return true end
  local R = CMJ.refs
  if not R or not R.achievements or not R.achRows then return false end
  local parent = R.achievements
  E.title = CMForms.Label(parent, "", 0, 0, 416, 20, "GameFontNormal")
  E.hint = CMForms.Label(parent, "", 0, 22, 416, 36, "GameFontHighlightSmall")
  E.empty = CMForms.Label(parent, "", 12, 100, 392, 110, "GameFontHighlight")
  E.previous = CMForms.Button(parent, nil, "Previous", 0, 306, 80, function()
    E.page = math.max(1, E.page - 1); CMJ.RefreshAchievements()
  end)
  E.next = CMForms.Button(parent, nil, "Next", 336, 306, 80, function()
    E.page = E.page + 1; CMJ.RefreshAchievements()
  end)
  E.pageLabel = CMForms.Label(parent, "", 88, 310, 240, 20, "GameFontHighlightSmall")
  E.pageLabel:SetJustifyH("CENTER")
  local share = _G.CMJ_RootXMLPageRNotesShare
  if share then
    share:SetText("Post…")
    share:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText("Preview a public encounter summary")
      GameTooltip:AddLine("Choose Post summary in the preview to send it to your group or nearby chat. Your writing stays private.", 1, 1, 1, true)
      GameTooltip:Show()
    end)
    share:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  E.title:SetMaxLines(1)
  E.title:SetTextColor(0.25, 0.12, 0.04)
  E.hint:SetTextColor(0.30, 0.16, 0.06)
  E.empty:SetTextColor(0.30, 0.16, 0.06)
  if R.search then R.search:HookScript("OnTextChanged", function() CMJ.RefreshAchievements() end) end
  if R.achFaux then R.achFaux:Hide(); R.achFaux:SetScript("OnVerticalScroll", nil) end
  for i, row in ipairs(R.achRows) do
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -64 - (i - 1) * 44)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    if row.title then row.title:SetWidth(244); row.title:SetMaxLines(1); row.title:SetJustifyH("LEFT") end
    if row.desc then row.desc:SetWidth(244); row.desc:SetMaxLines(1); row.desc:SetJustifyH("LEFT") end
    if row.progress then row.progress:SetWidth(90); row.progress:SetJustifyH("RIGHT") end
  end
  return true
end

function CMJ.RefreshAchievements()
  if not build() then return end
  local id, person = selected()
  if id ~= E.guid then E.guid, E.page, E.feedback = id, 1, nil end
  local list = person and CharacterMemory_GetAchievements(id) or {}
  local pages = math.max(1, math.ceil(#list / PAGE_SIZE))
  E.page = math.max(1, math.min(E.page, pages))
  E.empty:SetShown(not person)
  E.empty:SetText("Meet someone to begin.\n\nTarget another player, then choose their name on the left. Achievements belong to each relationship, not your whole character.")
  if not person and (CMJ.Model.search or "") ~= "" then
    E.empty:SetText("No people match your search.\n\nClear the search on the left to return to your journal.")
  elseif not person and CMJ.Model.filter ~= "all" then
    E.empty:SetText("No people match this filter yet.\n\nChoose All people on the left to see everyone you have met.")
  end
  E.previous:SetShown(person ~= nil); E.next:SetShown(person ~= nil); E.pageLabel:SetShown(person ~= nil)
  E.previous:SetEnabled(E.page > 1); E.next:SetEnabled(E.page < pages)
  E.pageLabel:SetText(string.format("%d / %d", E.page, pages))
  if person then
    local summary = CharacterMemory_GetAchievementSummary(id)
    E.title:SetText(CMCompat.Display(person.name or "This person", 36) .. string.format(" · %d/%d completed", summary.done, summary.total))
    local guidance = person.relationshipUnlocked and "Keep spending time together to grow your relationship."
      or string.format("Complete 3 achievements to unlock Acquaintance (%d/3).", math.min(3, summary.done))
    E.hint:SetText(E.feedback or (summary.claimable > 0 and string.format("%d ready to claim. ", summary.claimable) or "") .. guidance)
  else
    E.title:SetText("Achievements grow with your friendships")
    E.hint:SetText("Small shared moments become milestones.")
  end
  for i, row in ipairs(CMJ.refs.achRows) do
    local item = i <= PAGE_SIZE and list[(E.page - 1) * PAGE_SIZE + i]
    row:SetShown(item ~= nil and item ~= false)
    if item then
      row.title:SetText(item.name)
      row.desc:SetText(item.desc)
      row.progress:SetText(item.done and "Complete" or (item.valueIsSeconds
        and string.format("%dm / %dm", math.floor(item.cur / 60), math.floor(item.goal / 60))
        or string.format("%d / %d", item.cur, item.goal)))
      row.claim:Show(); row.claim:SetEnabled(item.claimable)
      row.claim:SetText(item.claimable and "Claim" or (item.claimedAt and "Claimed" or "Locked"))
      row.claim:SetScript("OnClick", function()
        -- Reject callbacks from a page/person that is no longer displayed.
        if CMJ.Model.selected ~= id then return end
        if CharacterMemory_ClaimAchievement(id, item.id) then
          E.feedback = item.name .. " claimed. +" .. item.rewardXP .. " relationship XP."
        end
        CMJ.RefreshAchievements()
      end)
      row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(item.name)
        GameTooltip:AddLine(item.desc, 1, 1, 1, true)
        GameTooltip:AddLine("Reward: " .. item.rewardXP .. " relationship XP", 1, 0.82, 0)
        if item.repeatable then GameTooltip:AddLine("Repeatable every 7 days; progress uses the last 7 days.", 1, 1, 1, true) end
        GameTooltip:Show()
      end)
      row:EnableMouse(true)
      row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
  end
end

-- Detail refresh covers list clicks, keyboard selection, filtering and reopen.
local populate = CMJ.PopulateDetail
function CMJ.PopulateDetail(id)
  populate(id)
  CMJ.RefreshAchievements()
end
local notify = CMJ.NotifyDataChanged
function CMJ.NotifyDataChanged()
  E.feedback = nil
  notify()
end

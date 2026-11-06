if not CMCompat or not CMCompat.supported then return end
-- Consistent native controls and spacing for the sheet, settings and journal.
CMForms = {}
local F = CMForms
function F.Label(parent, text, x, y, width, height, font)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
  fs:SetPoint("TOPLEFT", x, -y); fs:SetSize(width, height or 16); fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP"); fs:SetText(text or "")
  fs._cmY = y
  return fs
end
function F.Button(parent, name, text, x, y, width, fn)
  local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
  b:SetPoint("TOPLEFT", x, -y); b:SetSize(width, 24); b:SetText(text); b:SetScript("OnClick", fn)
  return b
end
function F.Field(parent, name, title, x, y, width, multiline, limit)
  local caption = F.Label(parent, title, x, y, width, 16)
  local box = CreateFrame(multiline and "ScrollFrame" or "EditBox", name, parent, multiline and "InputScrollFrameTemplate" or "InputBoxTemplate")
  box:SetPoint("TOPLEFT", x + (multiline and 0 or 4), -(y + 21)); box:SetSize(width - (multiline and 0 or 8), multiline or 24)
  local edit = multiline and box.EditBox or box
  edit:SetAutoFocus(false); edit:SetMaxLetters(limit or 256)
  if multiline then edit:SetFontObject(GameFontHighlightSmall) end
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  box.caption, box.edit = caption, edit
  return box
end
function F.Dropdown(parent, name, title, x, y, width)
  local caption = F.Label(parent, title, x, y, width, 16)
  local box = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
  box:SetPoint("TOPLEFT", x - 16, -(y + 18)); box:SetSize(width + 24, 32)
  box.fieldWidth, box.caption = width, caption
  UIDropDownMenu_SetWidth(box, width - 28)
  return box
end
function F.Fit(frame, width, height)
  local scale = math.min(1, (UIParent:GetWidth() - 40) / width, (UIParent:GetHeight() - 40) / height)
  frame:SetScale(math.max(0.4, scale))
end

function F.DialogTitle(frame)
  if not frame.TitleText then return end
  local title = frame.TitleText
  title:ClearAllPoints(); title:SetPoint("TOPLEFT", 14, -4); title:SetPoint("TOPRIGHT", -34, -4)
  title:SetHeight(16); title:SetJustifyH("LEFT"); title:SetMaxLines(1)
end

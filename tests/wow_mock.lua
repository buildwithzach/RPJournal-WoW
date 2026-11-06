-- Deliberately synthetic API boundary; this does not emulate or render WoW.
MOCK = { secret={}, epoch=1792231200, elapsed=100, frames={}, timers={}, messages={}, chat={}, combat=false,
  units={player={guid='Player-1-SELF',name='Rowan',realm='FictionalRealm'}, target={guid='Player-1-ELARA',name='Elara',realm='FictionalRealm'}},
  instance=false, instanceType='none', grouped=false, resting=false, invalidEvents={} }
function GetTime() return MOCK.elapsed end
function time() return MOCK.epoch end
function date(fmt, stamp) return os.date(fmt, stamp or MOCK.epoch) end
function GetBuildInfo() return '1.60.1','70450','Oct 2026',16001 end
function GetRealmName() return 'FictionalRealm' end
GetNormalizedRealmName=GetRealmName
function issecretvalue(value) return value == MOCK.secret end
function InCombatLockdown() return MOCK.combat end
function UnitExists(unit) return MOCK.units[unit] ~= nil end
function UnitIsPlayer(unit) return UnitExists(unit) end
function UnitGUID(unit) return MOCK.secretGUID and MOCK.secret or (MOCK.units[unit] and MOCK.units[unit].guid) end
function UnitName(unit) local a=MOCK.units[unit]; if a then return a.name,a.realm end end
function UnitClass() return 'Mage','MAGE' end
function UnitRace() return 'Human','Human' end
function UnitLevel() return 12 end
function UnitFactionGroup() return 'Alliance' end
function UnitSex() return 3 end
function UnitIsUnit(a,b) return UnitGUID(a)==UnitGUID(b) end
function UnitIsFriend() return true end
function IsInGroup() return MOCK.grouped end
function IsInRaid() return false end
function IsInInstance() return MOCK.instance,MOCK.instanceType end
function IsResting() return MOCK.resting end
function GetNumGroupMembers() return MOCK.grouped and 2 or 0 end
function GetNumSubgroupMembers() return MOCK.grouped and 1 or 0 end
function GetZoneText() return 'Elwynn Forest' end
function GetSubZoneText() return 'Goldshire' end
function GetInstanceInfo() return 'Deadmines',MOCK.instanceType,1,'Normal',5,0,false,36 end
function GetAverageItemLevel() return 15,15 end
function GetFileIDFromPath() return nil end
function IsAltKeyDown() return false end
function GetCurrentKeyBoardFocus() return MOCK.focus end
function SetPortraitTexture(frame,unit) frame.unit=unit end
function wipe(t) for k in pairs(t) do t[k]=nil end end
function GetCursorPosition() return 0,0 end
function NotifyInspect() end
function CanInspect() return false end
ERR_TRADE_COMPLETE='Trade complete.'
SlashCmdList,StaticPopupDialogs,UISpecialFrames={},{},{}
GameFontHighlightSmall,GameFontNormal={},{ }
Enum={SendAddonMessageResult={Success=0},TooltipDataType={Unit=2}}
C_EventUtils={IsEventValid=function(event) return not MOCK.invalidEvents[event] end}
C_Map={GetBestMapForUnit=function() return 37 end,GetMapInfo=function() return {name='Elwynn Forest'} end}
C_FriendList={IsFriend=function() return false end}
C_GuildInfo={GetGuildInfo=function() return nil end}
C_ChatInfo={RegisterAddonMessagePrefix=function() return 0 end,SendAddonMessage=function(prefix,message,channel,target)
  MOCK.messages[#MOCK.messages+1]={prefix=prefix,message=message,channel=channel,target=target}
  return MOCK.sendResult or 0
end,SendChatMessage=function(text,channel) MOCK.chat[#MOCK.chat+1]={text=text,channel=channel} end}
SendChatMessage=C_ChatInfo.SendChatMessage
function print(text) MOCK.chat[#MOCK.chat+1]={text=tostring(text)} end
DEFAULT_CHAT_FRAME={AddMessage=function(_,text) print(text) end}
RAID_CLASS_COLORS={MAGE={r=.4,g=.8,b=1}}
local methods={}
function methods:Run(script,...) if self.scripts[script] then self.scripts[script](self,...) end; for _,fn in ipairs(self.hooks[script] or {}) do fn(self,...) end end
function methods:RegisterEvent(event) assert(not MOCK.invalidEvents[event]); self.events[event]=true end
function methods:SetScript(event,fn) self.scripts[event]=fn end
function methods:GetScript(event) return self.scripts[event] end
function methods:HookScript(event,fn) self.hooks[event]=self.hooks[event] or {}; table.insert(self.hooks[event],fn) end
function methods:Show() if not self.shown then self.shown=true; self:Run('OnShow') end end
function methods:Hide() if self.shown then self.shown=false; self:Run('OnHide') end end
function methods:SetShown(value) if value then self:Show() else self:Hide() end end
function methods:IsShown() return self.shown end
function methods:SetText(value) self.textValue=tostring(value or ''); if self.kind=='EditBox' then self:Run('OnTextChanged',false) end end
function methods:GetText() return self.textValue or '' end
function methods:SetChecked(value) self.checked=value end
function methods:GetChecked() return self.checked or false end
function methods:SetFocus() MOCK.focus=self end
function methods:ClearFocus() if MOCK.focus==self then MOCK.focus=nil end end
function methods:HasFocus() return MOCK.focus==self end
function methods:GetName() return self.frameName end
function methods:GetParent() return self.parent end
function methods:GetEditBox() return self.editBox end
function methods:HighlightText() self.highlightedText=true end
function methods:IsObjectType(kind) return self.kind==kind end
function methods:SetSize(w,h) self.width,self.height=w,h end
function methods:SetWidth(w) self.width=w end
function methods:SetHeight(h) self.height=h end
function methods:GetWidth() return self.width or (self.parent and self.parent:GetWidth()) or 400 end
function methods:GetHeight() return self.height or 350 end
function methods:GetScale() return self.scale or 1 end
function methods:GetEffectiveScale() return self:GetScale() end
function methods:SetScale(value) self.scale=value end
function methods:GetFrameLevel() return 1 end
function methods:SetPoint(...)
  local point={...}; self.points=self.points or {}
  for i,old in ipairs(self.points) do if old[1]==point[1] then self.points[i]=point; self.point=self.points[1]; return end end
  table.insert(self.points,point); self.point=self.points[1]
end
function methods:GetPoint(index) return unpack(self.points and self.points[index or 1] or {'CENTER',UIParent,'CENTER',0,0}) end
function methods:ClearAllPoints() self.points={}; self.point=nil end
function methods:SetAllPoints(parent) self:ClearAllPoints(); self:SetPoint('TOPLEFT',parent or self.parent,'TOPLEFT'); self:SetPoint('BOTTOMRIGHT',parent or self.parent,'BOTTOMRIGHT') end
function methods:SetTextColor(...) self.color={...} end
function methods:SetMaxLines(value) self.maxLines=value end
function methods:SetVerticalScroll(value) self.verticalScroll=value end
function methods:SetTexture(value) self.texture=value end
function methods:GetTexture() return self.texture end
function methods:GetStringHeight() return 80 end
function methods:SetEnabled(value) self.enabled=value end
function methods:Enable() self.enabled=true end
function methods:Disable() self.enabled=false end
function methods:IsEnabled() return self.enabled~=false end
function methods:LockHighlight() self.highlighted=true end
function methods:UnlockHighlight() self.highlighted=false end
function methods:SetScrollChild(frame) self.scrollChild=frame; frame:SetPoint('TOPLEFT',self,'TOPLEFT',0,0) end
function methods:GetUnit() return UnitName('target'),'target' end
function methods:AddLine(text) self.lines=self.lines or {}; table.insert(self.lines,text) end
function methods:CreateFontString(name,layer,font) local f=CreateFrame('FontString',name,self); f.font=font; return f end
function methods:CreateTexture(name) return CreateFrame('Texture',name,self) end
-- Explicit no-op surface for layout only; unlisted methods remain errors.
for _,key in ipairs({'EnableKeyboard','EnableMouse','RegisterForClicks','RegisterForDrag','SetAltArrowKeyMode',
'SetAutoFocus','SetClipsChildren','SetColorTexture','SetFontObject','SetFrameStrata','SetHighlightTexture','SetJustifyH','SetJustifyV',
'SetMaxLetters','SetMinMaxValues','SetMovable','SetMultiLine','SetOwner','SetPropagateKeyboardInput','SetTexCoord',
'SetClampedToScreen','SetToplevel','SetValue','StartMoving','StopMovingOrSizing','Raise','SetFrameLevel','SetAlpha','SetBackdrop','SetBackdropColor',
'SetBackdropBorderColor','SetNormalTexture','SetPushedTexture','SetDisabledTexture','SetHitRectInsets'}) do methods[key]=function() end end
function CreateFrame(kind,name,parent,template)
  local f=setmetatable({kind=kind,frameName=name,parent=parent,events={},scripts={},hooks={},shown=true,template=template}, {__index=methods})
  table.insert(MOCK.frames,f); f.mockID=#MOCK.frames; if name then _G[name]=f end
  if template then
    if template:find('BasicFrameTemplate') then f.TitleText=f:CreateFontString(nil,'OVERLAY','GameFontNormal'); f.TitleText:SetPoint('TOPLEFT',12,-4); f.TitleText:SetPoint('TOPRIGHT',-28,-4); f.TitleText:SetHeight(16); f.CloseButton=CreateFrame('Button',nil,f); f.CloseButton:SetSize(24,24); f.CloseButton:SetPoint('TOPRIGHT',0,0) end
    if template:find('InputScrollFrameTemplate') then f.EditBox=CreateFrame('EditBox',nil,f); f.EditBox:SetPoint('TOPLEFT',6,-6); f.EditBox:SetPoint('BOTTOMRIGHT',-18,6) end
    if template:find('UICheckButtonTemplate') or template:find('InterfaceOptionsCheckButtonTemplate') then f.Text=f:CreateFontString(name and name..'Text'); f.text=f.Text; f.Text.font='GameFontNormalSmall'; f.Text:SetPoint('LEFT',f,'RIGHT',0,0) end
  end
  return f
end
UIParent=CreateFrame('Frame','UIParent'); UIParent:SetSize(1920,1080)
GameTooltip=CreateFrame('GameTooltip','GameTooltip'); GameTooltip:Hide()
function StaticPopup_Show(which,_,__,data)
  local p=CreateFrame('Frame',nil,UIParent);p.which,p.data=which,data
  local info=StaticPopupDialogs[which]
  if info.hasEditBox then p.editBox=CreateFrame('EditBox',nil,p) end
  MOCK.popup=p;if info.OnShow then info.OnShow(p) end;return p
end
function MOCK.AcceptPopup()
  local p=MOCK.popup;MOCK.popup=nil
  if StaticPopupDialogs[p.which].OnAccept(p,p.data) then MOCK.popup=p end
end
function CloseDropDownMenus() MOCK.menu={} end
function ToggleDropDownMenu(_,__,frame) MOCK.menu={};frame.initialize(frame,1) end
function UIDropDownMenu_Initialize(frame,fn) frame.initialize=fn end
function UIDropDownMenu_SetWidth(frame,w) frame:SetWidth(w) end
function UIDropDownMenu_SetText(frame,value) frame.label=value end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info) MOCK.menu=MOCK.menu or {}; table.insert(MOCK.menu,info) end
function UIDropDownMenu_SetSelectedName(frame,name) frame.selectedName=name end
function UIDropDownMenu_GetSelectedName(frame) return frame.selectedName end
function UIDropDownMenu_SetSelectedID(frame,id) frame.selectedID=id end
function FauxScrollFrame_GetOffset(frame) return frame.offset or 0 end
function FauxScrollFrame_Update() end
function FauxScrollFrame_OnVerticalScroll(frame,offset,height,fn) frame.offset=math.floor(offset/height); fn() end
TooltipDataProcessor={AddTooltipPostCall=function(_,fn) MOCK.tooltip=fn end}
local function timer(seconds,fn,repeating)
  local t={at=MOCK.elapsed+seconds,seconds=seconds,callback=fn,repeating=repeating}; function t:Cancel() self.cancelled=true end
  table.insert(MOCK.timers,t); return t
end
C_Timer={After=function(s,fn) return timer(s,fn) end,NewTimer=function(s,fn) return timer(s,fn) end,NewTicker=function(s,fn) return timer(s,fn,true) end}
function MOCK.Advance(seconds)
  local target=MOCK.elapsed+seconds; local loops=0
  while true do
    local nextTimer
    for _,t in ipairs(MOCK.timers) do if not t.cancelled and t.at<=target and (not nextTimer or t.at<nextTimer.at) then nextTimer=t end end
    if not nextTimer then break end
    MOCK.epoch=MOCK.epoch+(nextTimer.at-MOCK.elapsed); MOCK.elapsed=nextTimer.at
    if nextTimer.repeating then nextTimer.at=nextTimer.at+nextTimer.seconds else nextTimer.cancelled=true end
    nextTimer.callback(); loops=loops+1; assert(loops<10000,'timer loop')
  end
  MOCK.epoch=MOCK.epoch+target-MOCK.elapsed; MOCK.elapsed=target
end
function MOCK.Emit(event,...)
  local list={}; for _,f in ipairs(MOCK.frames) do list[#list+1]=f end
  for _,f in ipairs(list) do if f.events[event] then f:Run('OnEvent',event,...) end end
end
function MOCK.Type(frame,text) frame.textValue=text; frame:Run('OnTextChanged',true) end
function MOCK.Click(frame) assert(frame:IsEnabled(),'disabled button'); frame:Run('OnClick','LeftButton') end

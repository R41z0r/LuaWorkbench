local _, addon = ...
local O, W, UI, L = {}, addon.Workspace, addon.UI, addon.L
addon.OutputWindow = O
local modes = { embedded = true, floating = true, left = true, right = true, top = true, bottom = true }

function O:Mode()
 local mode = W.db.options.outputWindowMode
 return modes[mode] and mode or 'embedded'
end

function O:Save()
 if not self.frame then return end
 local frame = self.frame
 local data = W.db.outputWindow or {}
 data.width, data.height = frame:GetWidth(), frame:GetHeight()
 if self:Mode() == 'floating' then
  local x, y = frame:GetCenter()
  if x and y then
   local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
   data.x, data.y = x * ratio - UIParent:GetWidth() / 2, y * ratio - UIParent:GetHeight() / 2
  end
 end
 W.db.outputWindow = data
end

function O:SetMode(mode)
 if not modes[mode] then return false end
 if self:Mode() ~= 'embedded' then self:Save() end
 W.db.options.outputWindowMode = mode
 if W.window and W.output then W:Layout() end
 return true
end

function O:Menu(owner)
 local entries = {}
 for _, item in ipairs({ {'embedded', L.outputEmbedded}, {'floating', L.outputFloating}, {'left', L.outputLeft},
  {'right', L.outputRight}, {'top', L.outputTop}, {'bottom', L.outputBottom} }) do
  local mode = item[1]
  entries[#entries + 1] = { text = item[2], selected = mode == self:Mode(), action = function() self:SetMode(mode) end }
 end
 W:OpenMenu(owner, entries)
end

function O:Create()
 local frame = CreateFrame('Frame', nil, W.window)
 self.frame = frame
 frame:SetFrameStrata('DIALOG'); frame:SetMovable(true); frame:SetResizable(true); frame:SetClampedToScreen(true)
 UI:Background(frame, UI.colors.panel); UI:Border(frame, { 0.28, 0.34, 0.43, 1 })
 local header = CreateFrame('Frame', nil, frame)
 self.header = header
 header:SetPoint('TOPLEFT'); header:SetPoint('TOPRIGHT'); header:SetHeight(28)
 UI:Background(header, { 0.11, 0.12, 0.15, 1 })
 local title = UI:Text(header, L.queryLuaOutput, 12); title:SetPoint('LEFT', 12, 0)
 header:EnableMouse(true); header:RegisterForDrag('LeftButton')
 header:SetScript('OnDragStart', function()
  if self:Mode() ~= 'floating' then return end
  self:Save()
  local x, y = frame:GetCenter()
  if x and y then
   frame:ClearAllPoints(); frame:SetPoint('CENTER', UIParent, 'BOTTOMLEFT', x * frame:GetEffectiveScale() / UIParent:GetEffectiveScale(), y * frame:GetEffectiveScale() / UIParent:GetEffectiveScale())
  end
  frame.moving = true; frame:StartMoving()
 end)
 header:SetScript('OnDragStop', function() if not frame.moving then return end; frame.moving = nil; frame:StopMovingOrSizing(); self:Save() end)
 local embed = UI:Button(header, 'minimize', L.outputEmbedded, function() self:SetMode('embedded') end)
 embed:SetPoint('TOPRIGHT', -3, -1)
 local grip = CreateFrame('Button', nil, frame)
 self.grip = grip
 grip:SetSize(18, 18); grip:SetPoint('BOTTOMRIGHT'); grip:EnableMouse(true)
 local mark = UI:Text(grip, '//', 12); mark:SetPoint('CENTER')
 grip:SetScript('OnMouseDown', function(_, button) if button == 'LeftButton' then frame.sizing = true; frame:StartSizing('BOTTOMRIGHT') end end)
 local function stop()
  if frame.sizing or frame.moving then
   frame.sizing, frame.moving = nil, nil; frame:StopMovingOrSizing(); self:Save()
   if W.window:IsShown() then self:Apply() end
  end
 end
 grip:SetScript('OnMouseUp', stop)
 frame:SetScript('OnHide', stop)
 frame:SetScript('OnSizeChanged', function() if frame.sizing then self:Save() end end)
 W.window:HookScript('OnHide', function() frame:Hide() end)
 W.window:HookScript('OnShow', function() self:Apply() end)
 self.button = UI:Button(W.output.frame, 'windowOptions', L.outputWindow, function() self:Menu(self.button) end)
 self.button:SetPoint('TOPRIGHT', -5, -2)
 frame:Hide()
end

function O:Apply()
 if self.applying or not W.output then return end
 self.applying = true
 if not self.frame then self:Create() end
 local frame, output, mode = self.frame, W.output.frame, self:Mode()
 output:ClearAllPoints()
 if mode == 'embedded' then
  output:SetParent(W.window)
  local code = addon.Query.Console.input.frame
  local available = math.max(140, W.window:GetHeight() - 74)
  output:SetPoint('TOPLEFT', code, 'BOTTOMLEFT', 0, -8)
  output:SetSize(code:GetWidth(), math.max(50, available - code:GetHeight() - 8))
  output:SetShown(not W.codeOnly)
  frame:Hide()
 else
  local data = W.db.outputWindow or {}
  local ratio = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
  local maxWidth, maxHeight = math.max(1, UIParent:GetWidth() * ratio - 24), math.max(1, UIParent:GetHeight() * ratio - 24)
  local minWidth, minHeight = math.min(420, maxWidth), math.min(180, maxHeight)
  frame:SetResizeBounds(minWidth, minHeight, maxWidth, maxHeight)
  frame:SetSize(math.max(minWidth, math.min(maxWidth, data.width or 560)), math.max(minHeight, math.min(maxHeight, data.height or 260)))
  frame:ClearAllPoints()
  if mode == 'floating' then
   frame:SetPoint('CENTER', UIParent, 'CENTER', (data.x or 0) * ratio, (data.y or 0) * ratio)
  elseif mode == 'left' then frame:SetPoint('TOPRIGHT', W.window, 'TOPLEFT', -8, 0)
  elseif mode == 'right' then frame:SetPoint('TOPLEFT', W.window, 'TOPRIGHT', 8, 0)
  elseif mode == 'top' then frame:SetPoint('BOTTOMLEFT', W.window, 'TOPLEFT', 0, 8)
  else frame:SetPoint('TOPLEFT', W.window, 'BOTTOMLEFT', 0, -8) end
  output:SetParent(frame); output:SetPoint('TOPLEFT', 1, -28); output:SetPoint('BOTTOMRIGHT', -1, 14)
  output:Show(); frame:SetShown(W.window:IsShown())
 end
 self.applying = nil
end
